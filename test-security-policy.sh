#!/usr/bin/env bash
# test-security-policy.sh — Integration tests for the shared safety policy, managed
# CLAUDE.md blocks, token-saving defaults, and template hygiene.
#
# Usage: ./test-security-policy.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
POLICY_FILE="$SCRIPT_DIR/projects/common/security.settings.local.json"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

# Keep runs independent of the developer's real ~/.claude/settings.json.
export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"

# ============================================================================
# Helpers
# ============================================================================

PROJECTS=()
make_nuxt_project() {
  local dir
  dir="$(mktemp -d)"
  touch "$dir/nuxt.config.ts"
  echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$dir/package.json"
  PROJECTS+=("$dir")
  echo "$dir"
}

cleanup_all() { local d; for d in "${PROJECTS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

# Non-interactive deploy; extra args pass through.
deploy() {
  local project_dir="$1"
  shift
  "$SETUP_SCRIPT" --project="$project_dir" --force --skip-vscode --no-superpowers "$@" >/dev/null 2>&1
}

settings() { echo "$1/.claude/settings.local.json"; }
jqs() { jq -r "$2" "$(settings "$1")" 2>/dev/null; }
block_count() { grep -c "<!-- BEGIN $2" "$1/CLAUDE.md" 2>/dev/null || true; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name"
    FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${RED}FAIL${NC} $name"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  fi
}

EXPECTED_ASK=$(jq '.permissions.ask | length' "$POLICY_FILE")

# The deployed deny list is the shared policy plus the stack's protected paths, so assert
# on coverage rather than a fixed count (test-protected-paths.sh covers the stack layer).
# Prints how many shared policy deny rules are missing from the project's settings.
missing_policy_deny() {
  jq -n --slurpfile s "$(settings "$1")" --slurpfile p "$POLICY_FILE" \
    '[($p[0].permissions.deny // [])[] | select(. as $r | (($s[0].permissions.deny // []) | index([$r])) == null)] | length'
}

# ============================================================================
echo -e "\n${CYAN}=== Fresh deploy (stack with no deny rules of its own) ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p"
assert_eq "every shared deny rule applied" "0" "$(missing_policy_deny "$p")"
assert_eq "ask rules applied" "$EXPECTED_ASK" "$(jqs "$p" '.permissions.ask | length')"
assert_eq "git push is not auto-allowed" "false" "$(jqs "$p" '.permissions.allow | index("Bash(git push:*)") != null')"
assert_eq "safety-guard hook registered once" "1" "$(jqs "$p" '[.hooks.PreToolUse[]?.hooks[]? | select(.command | test("safety-guard.sh"))] | length')"
assert_true "safety-guard.sh installed and executable" test -x "$p/.claude/hooks/safety-guard.sh"
assert_eq "project MCP servers not auto-enabled" "false" "$(jqs "$p" '.enableAllProjectMcpServers')"
assert_eq "\$schema set" "true" "$(jqs "$p" 'has("$schema")')"
assert_false "policy file not copied under its own name" test -e "$p/.claude/security.settings.local.json"
assert_true "deployment-safety rule deployed for stack without rules/" test -f "$p/.claude/rules/deployment-safety.md"
assert_true "sensitive-files rule deployed for stack without rules/" test -f "$p/.claude/rules/sensitive-files.md"
assert_eq "Safety Guardrails block present once" "1" "$(block_count "$p" "SAFETY GUARDRAILS")"
assert_eq "Memory Protocol block present once" "1" "$(block_count "$p" "MEMORY PROTOCOL")"
assert_eq "Response Style block present once" "1" "$(block_count "$p" "RESPONSE STYLE")"
assert_eq "no eager library @imports" "0" "$(grep -cE '^@(\./)?\.claude/libraries/' "$p/CLAUDE.md" || true)"
assert_true "library kept as on-demand reference" grep -qF '`.claude/libraries/vue.md`' "$p/CLAUDE.md"
assert_eq "no SessionStart hook without superpowers" "null" "$(jqs "$p" '.hooks.SessionStart')"

# ============================================================================
echo -e "\n${CYAN}=== Idempotency ===${NC}\n"
# ============================================================================

deny_before=$(jqs "$p" '.permissions.deny | length')
deploy "$p"
deploy "$p" --refresh
assert_eq "deny count stable after redeploy + refresh" "$deny_before" "$(jqs "$p" '.permissions.deny | length')"
assert_eq "hook still registered once" "1" "$(jqs "$p" '.hooks.PreToolUse | length')"
assert_eq "Safety block still once" "1" "$(block_count "$p" "SAFETY GUARDRAILS")"
assert_eq "Response Style block still once" "1" "$(block_count "$p" "RESPONSE STYLE")"

# ============================================================================
echo -e "\n${CYAN}=== Refresh of a legacy project ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
mkdir -p "$p/.claude"
cat > "$(settings "$p")" <<'JSON'
{
  "enableAllProjectMcpServers": true,
  "permissions": {
    "allow": ["Bash(git push:*)", "Bash(rm:*)", "Bash(my-custom-command:*)"],
    "deny": ["Read(**/super-secret-project-file.txt)"]
  },
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": ".claude/hooks/session-start"}]}],
    "PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "npx prettier --write"}]}]
  }
}
JSON
deploy "$p" --refresh --stack=nuxt
assert_eq "existing git push allow kept (additive)" "true" "$(jqs "$p" '.permissions.allow | index("Bash(git push:*)") != null')"
assert_eq "git push ask rule added (ask beats allow)" "true" "$(jqs "$p" '.permissions.ask | index("Bash(git push:*)") != null')"
assert_eq "rm ask rule added (ask beats allow)" "true" "$(jqs "$p" '.permissions.ask | index("Bash(rm:*)") != null')"
assert_eq "project allow rule kept" "true" "$(jqs "$p" '.permissions.allow | index("Bash(my-custom-command:*)") != null')"
assert_eq "project allow rules keep their order" '["Bash(git push:*)","Bash(rm:*)","Bash(my-custom-command:*)"]' \
  "$(jqs "$p" '[.permissions.allow[] | select(. == "Bash(git push:*)" or . == "Bash(rm:*)" or . == "Bash(my-custom-command:*)")] | tojson')"
assert_eq "shared deny rules all present beside the project's own" "0" "$(missing_policy_deny "$p")"
assert_eq "project deny rule kept beside shared rules" "true" \
  "$(jqs "$p" '.permissions.deny | index("Read(**/super-secret-project-file.txt)") != null')"
assert_eq "existing SessionStart hook preserved" "1" "$(jqs "$p" '.hooks.SessionStart | length')"
assert_eq "existing PostToolUse hook preserved" "npx prettier --write" "$(jqs "$p" '.hooks.PostToolUse[0].hooks[0].command')"
assert_eq "safety-guard hook added" "1" "$(jqs "$p" '.hooks.PreToolUse | length')"
assert_eq "enableAllProjectMcpServers left as the project set it" "true" "$(jqs "$p" '.enableAllProjectMcpServers')"

# ============================================================================
echo -e "\n${CYAN}=== Superpowers hook merge ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
"$SETUP_SCRIPT" --project="$p" --force --skip-vscode --superpowers-minimal --skip-superpowers-update >/dev/null 2>&1
"$SETUP_SCRIPT" --project="$p" --force --skip-vscode --superpowers-minimal --skip-superpowers-update >/dev/null 2>&1
assert_eq "SessionStart hook registered once" "1" "$(jqs "$p" '.hooks.SessionStart | length')"
assert_eq "SessionStart registration keeps the safety hook" "1" "$(jqs "$p" '.hooks.PreToolUse | length')"

p=$(make_nuxt_project)
plugin_settings="$p/user-settings.json"
echo '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}' > "$plugin_settings"
AI_CONFIG_USER_SETTINGS="$plugin_settings" "$SETUP_SCRIPT" --project="$p" --force --skip-vscode --skip-superpowers-update >/dev/null 2>&1
assert_false "global superpowers plugin → no duplicate project copy" test -d "$p/.claude/skills/using-superpowers"
assert_eq "global superpowers plugin → no duplicate SessionStart hook" "null" "$(jqs "$p" '.hooks.SessionStart')"

# ============================================================================
echo -e "\n${CYAN}=== Flags & dry-run ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p" --dry-run
assert_false "dry-run writes no settings.local.json" test -e "$(settings "$p")"
assert_false "dry-run installs no hook" test -e "$p/.claude/hooks/safety-guard.sh"

p=$(make_nuxt_project)
deploy "$p" --no-response-style --eager-libraries --effort=medium
assert_eq "--no-response-style omits the block" "0" "$(block_count "$p" "RESPONSE STYLE")"
assert_true "--eager-libraries keeps @imports" grep -qE '^@\.claude/libraries/vue\.md' "$p/CLAUDE.md"
assert_eq "--effort sets effortLevel" "medium" "$(jqs "$p" '.effortLevel')"

p=$(make_nuxt_project)
assert_false "--effort rejects unknown levels" deploy "$p" --effort=turbo

# ============================================================================
echo -e "\n${CYAN}=== Template hygiene ===${NC}\n"
# ============================================================================

missing=""
for f in "$SCRIPT_DIR"/projects/*/agents/*.md; do
  head -1 "$f" | grep -q '^---$' && grep -q '^name: ' "$f" && grep -q '^description: ' "$f" || missing="$missing ${f#"$SCRIPT_DIR"/projects/}"
done
assert_eq "every subagent has name + description frontmatter" "" "$missing"

bad=""
for f in "$SCRIPT_DIR"/projects/*/settings.local.json; do
  jq -e '(.permissions.deny // [] | length) == 0 and .hooks == null and ((.permissions.allow // []) | index("Bash(git push:*)") == null)' "$f" >/dev/null || bad="$bad $(basename "$(dirname "$f")")"
done
assert_eq "stack settings carry no deny list, hooks, or git push allow" "" "$bad"

unscoped=""
for f in "$SCRIPT_DIR"/projects/*/rules/*.md; do
  case "$f" in */common/rules/token-optimization.md|*/custom/rules/coding-standards.md) continue ;; esac
  head -1 "$f" | grep -q '^---$' || unscoped="$unscoped ${f#"$SCRIPT_DIR"/projects/}"
done
assert_eq "stack rules are path-scoped" "" "$unscoped"

# ============================================================================
echo ""
echo -e "${CYAN}================================${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  FAIL: $FAIL"
echo -e "${CYAN}================================${NC}"
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}✗ $FAIL test(s) failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ All $PASS tests passed${NC}"
