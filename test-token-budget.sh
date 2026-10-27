#!/usr/bin/env bash
# test-token-budget.sh — what loads into every request stays small, and a refresh can't put
# it back: orchestrator = false sticks, the superpowers bootstrap is opt-in, edited rules get
# their shipped paths: scoping, and library @imports in an edited CLAUDE.md become references.
#
# Usage: ./test-token-budget.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }
export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"

PROJECTS=()
make_next_project() {
  local dir
  dir="$(mktemp -d)"
  touch "$dir/next.config.js"
  echo '{"name":"test","dependencies":{"next":"14.0.0","react":"18.0.0"}}' > "$dir/package.json"
  printf 'node_modules\n.env\n' > "$dir/.gitignore"
  PROJECTS+=("$dir")
  echo "$dir"
}
cleanup_all() { local d; for d in "${PROJECTS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

run() {
  local project_dir="$1"
  shift
  "$SETUP_SCRIPT" --project="$project_dir" --skip-vscode --skip-superpowers-update "$@" >/dev/null 2>&1
}

session_hook_count() {
  jq '[.hooks.SessionStart[]?.hooks[]?.command | select(test("hooks/session-start"))] | length' \
    "$1/.claude/settings.local.json"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"; FAIL=$((FAIL + 1))
  fi
}
assert_true() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1)); fi
}
assert_false() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1))
  else echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1)); fi
}

# ============================================================================
echo -e "\n${CYAN}=== orchestrator = false removes the pattern and sticks ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force --no-superpowers --orchestrator
assert_eq "orchestrator pins opus" "opus" "$(jq -r '.model // empty' "$p/.claude/settings.local.json")"
assert_true "implementer agent deployed" test -f "$p/.claude/agents/implementer.md"

printf '[options]\norchestrator = false\n' > "$p/ai-config.conf"
run "$p" --refresh --no-superpowers
assert_eq "opus pin removed" "" "$(jq -r '.model // empty' "$p/.claude/settings.local.json")"
assert_eq "subagent model removed" "" "$(jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL // empty' "$p/.claude/settings.local.json")"
assert_false "implementer agent removed" test -f "$p/.claude/agents/implementer.md"
assert_false "policy block removed from CLAUDE.md" grep -q 'ORCHESTRATOR POLICY' "$p/CLAUDE.md"

run "$p" --refresh --no-superpowers
assert_eq "second refresh keeps opus off" "" "$(jq -r '.model // empty' "$p/.claude/settings.local.json")"
assert_false "second refresh doesn't restore the block" grep -q 'ORCHESTRATOR POLICY' "$p/CLAUDE.md"

p=$(make_next_project)
run "$p" --force --no-superpowers --orchestrator
jq '.model = "sonnet[1m]"' "$p/.claude/settings.local.json" > "$p/s.json" && mv "$p/s.json" "$p/.claude/settings.local.json"
printf '[options]\norchestrator = false\n' > "$p/ai-config.conf"
run "$p" --refresh --no-superpowers
assert_eq "a model the developer chose is kept" "sonnet[1m]" "$(jq -r '.model // empty' "$p/.claude/settings.local.json")"

# ============================================================================
echo -e "\n${CYAN}=== Superpowers bootstrap is opt-in ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force --superpowers-core
assert_true "skills still deploy" test -f "$p/.claude/skills/brainstorming/SKILL.md"
assert_eq "no SessionStart hook by default" "0" "$(session_hook_count "$p")"
assert_false "no Superpowers section in CLAUDE.md" grep -q 'Workflow Skills (Superpowers)' "$p/CLAUDE.md"

p=$(make_next_project)
run "$p" --force --superpowers-core --superpowers-bootstrap
assert_eq "--superpowers-bootstrap registers the hook" "1" "$(session_hook_count "$p")"
assert_true "--superpowers-bootstrap keeps the section" grep -q 'Workflow Skills (Superpowers)' "$p/CLAUDE.md"

jq '.hooks.SessionStart += [{hooks: [{type: "command", command: "echo keep-me"}]}]' "$p/.claude/settings.local.json" > "$p/s.json" \
  && mv "$p/s.json" "$p/.claude/settings.local.json"
run "$p" --refresh --superpowers-core
assert_eq "refresh without the flag unregisters it" "0" "$(session_hook_count "$p")"
assert_eq "other SessionStart hooks survive" "echo keep-me" \
  "$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command] | join(",")' "$p/.claude/settings.local.json")"

p=$(make_next_project)
run "$p" --force --superpowers-core
printf '[options]\nsuperpowers-bootstrap = true\n' > "$p/ai-config.conf"
run "$p" --refresh --superpowers-core
assert_eq "superpowers-bootstrap = true in ai-config.conf registers it" "1" "$(session_hook_count "$p")"

# ============================================================================
echo -e "\n${CYAN}=== Edited rules get their shipped paths: ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force --no-superpowers
rule="$p/.claude/rules/accessibility.md"
awk 'NR == 1 && /^---$/ { skip = 1; next } skip && /^---$/ { skip = 0; next } !skip' "$rule" > "$rule.tmp"
echo "LOCAL-EDIT-KEEP" >> "$rule.tmp"
mv "$rule.tmp" "$rule"
assert_false "precondition: rule unscoped" grep -q '^paths:' "$rule"

run "$p" --refresh --no-superpowers
assert_eq "frontmatter starts the file" "---" "$(head -1 "$rule")"
assert_true "shipped paths: added" grep -q '^paths:' "$rule"
assert_true "local edit kept" grep -q 'LOCAL-EDIT-KEEP' "$rule"
assert_true "unscoped copy backed up" grep -rqs 'LOCAL-EDIT-KEEP' "$p/.claude/ai-config/backups/"

before=$(shasum "$rule")
run "$p" --refresh --no-superpowers
assert_eq "scoping is idempotent" "$before" "$(shasum "$rule")"

# ============================================================================
echo -e "\n${CYAN}=== Library @imports in an edited CLAUDE.md become references ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force --no-superpowers
{
  cat "$p/CLAUDE.md"
  echo "## Team notes KEEP-NOTES"
  echo "@~/.claude/libraries/html5.md"
  echo "@./.claude/libraries/tailwind.md"
  echo "@.claude/libraries/tailwind.md"
} > "$p/CLAUDE.md.tmp" && mv "$p/CLAUDE.md.tmp" "$p/CLAUDE.md"

run "$p" --refresh --no-superpowers
assert_eq "no library @imports left" "0" "$(grep -cE '^@(\./|~/)?\.claude/libraries/' "$p/CLAUDE.md")"
assert_eq "user-level library kept as a reference" "1" "$(grep -cF -- '- `~/.claude/libraries/html5.md`' "$p/CLAUDE.md")"
assert_eq "duplicate imports collapse to one reference" "1" "$(grep -cF -- '- `.claude/libraries/tailwind.md`' "$p/CLAUDE.md")"
assert_true "edits kept" grep -q 'KEEP-NOTES' "$p/CLAUDE.md"

# ============================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
