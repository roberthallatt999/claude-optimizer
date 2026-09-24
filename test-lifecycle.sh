#!/usr/bin/env bash
# test-lifecycle.sh — superpowers skill layout + migration, placeholder rendering, version stamp,
# hook matcher updates, --shared-policy, --uninstall, and @import health checks.
#
# Usage: ./test-lifecycle.sh
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
export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"

TMPS=()
tmp_dir() { local d; d="$(mktemp -d)"; TMPS+=("$d"); echo "$d"; }
cleanup_all() { local d; for d in "${TMPS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"; FAIL=$((FAIL + 1)); fi
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
contains() { grep -qF -- "$2" <<< "$1"; }

run() { local d="$1"; shift; "$SETUP_SCRIPT" --project="$d" --skip-vscode "$@" 2>&1; }
make_nuxt() { local d; d=$(tmp_dir); touch "$d/nuxt.config.ts"; echo '{"dependencies":{"nuxt":"3"}}' > "$d/package.json"; echo "$d"; }
make_ee() {
  local d; d=$(tmp_dir)
  mkdir -p "$d/system/ee" "$d/system/user/templates/site.group"
  echo '{"devDependencies":{"tailwindcss":"3"}}' > "$d/package.json"
  echo '{embed="site/_x"}' > "$d/system/user/templates/site.group/index.html"
  echo "$d"
}
tree_sha() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1); }

# ============================================================================
echo -e "\n${CYAN}=== Superpowers skills layout ===${NC}\n"
# ============================================================================

p=$(make_nuxt)
run "$p" --force --superpowers-minimal --skip-superpowers-update >/dev/null
S="$p/.claude/settings.local.json"
assert_true "skill deployed one level deep" test -f "$p/.claude/skills/using-superpowers/SKILL.md"
assert_false "no nested .claude/skills/superpowers/" test -e "$p/.claude/skills/superpowers"
cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$S")
assert_true "SessionStart registration sets CLAUDE_PLUGIN_ROOT" contains "$cmd" 'CLAUDE_PLUGIN_ROOT='
out=$(cd "$p" && CLAUDE_PROJECT_DIR="$p" bash -c "$cmd" 2>&1)
assert_true "registered hook emits hookSpecificOutput.additionalContext" contains "$out" '"additionalContext"'
assert_false "registered hook no longer errors reading the skill" contains "$out" 'Error reading'
assert_true "hook injects the real skill content" contains "$out" 'using-superpowers'
assert_eq "--doctor passes" "0" "$("$SETUP_SCRIPT" --project="$p" --doctor >/dev/null 2>&1; echo $?)"

p=$(make_nuxt)
run "$p" --force --no-superpowers >/dev/null
mkdir -p "$p/.claude/skills/superpowers/brainstorming" "$p/.claude/hooks"
echo "KEEP-SKILL-EDIT" > "$p/.claude/skills/superpowers/brainstorming/SKILL.md"
printf '.claude/skills/superpowers/brainstorming/SKILL.md\tdeadbeef\n' >> "$p/.claude/ai-config/manifest.tsv"
jq '.hooks.SessionStart = [{"hooks":[{"type":"command","command":".claude/hooks/session-start"}]}]' "$p/.claude/settings.local.json" > "$p/s.json" && mv "$p/s.json" "$p/.claude/settings.local.json"
run "$p" --refresh --superpowers-minimal --skip-superpowers-update >/dev/null
assert_true "legacy nested skill moved up a level" test -f "$p/.claude/skills/brainstorming/SKILL.md"
assert_true "moved skill keeps its edits" grep -q KEEP-SKILL-EDIT "$p/.claude/skills/brainstorming/SKILL.md"
assert_false "nested folder removed after the move" test -e "$p/.claude/skills/superpowers"
assert_true "manifest path follows the move" grep -q '^\.claude/skills/brainstorming/SKILL\.md' "$p/.claude/ai-config/manifest.tsv"
assert_eq "legacy SessionStart registration updated, not duplicated" "1|true" \
  "$(jq -r '[.hooks.SessionStart[].hooks[]] | "\(length)|\(.[0].command | test("CLAUDE_PLUGIN_ROOT"))"' "$p/.claude/settings.local.json")"

# ============================================================================
echo -e "\n${CYAN}=== Placeholders in copied stack files ===${NC}\n"
# ============================================================================

ee=$(make_ee)
run "$ee" --force --no-superpowers >/dev/null
assert_eq "no raw {{PLACEHOLDERS}} in deployed agents/rules/commands/skills" "" \
  "$(grep -rlE '\{\{[A-Z][A-Z0-9_]*\}\}' "$ee/.claude/agents" "$ee/.claude/rules" "$ee/.claude/commands" "$ee/.claude/skills" "$ee/CLAUDE.md" 2>/dev/null)"
agent_src=$(grep -rlF '{{PROJECT_NAME}}' "$SCRIPT_DIR/projects/expressionengine/agents" | head -n 1)
agent_dest="$ee/.claude/agents/$(basename "$agent_src")"
assert_true "{{PROJECT_NAME}} rendered with the project name" grep -qF "$(basename "$ee")" "$agent_dest"
brand_src=$(grep -rlF '{{BRAND_GREEN}}' "$SCRIPT_DIR/projects/expressionengine/rules" 2>/dev/null | head -n 1)
if [[ -n "$brand_src" && -f "$ee/.claude/rules/$(basename "$brand_src")" ]]; then
  assert_true "unknown brand color becomes readable text" grep -qF "(brand green: not set)" "$ee/.claude/rules/$(basename "$brand_src")"
  assert_false "brand color is not faked as #000000" grep -qF "#000000" "$ee/.claude/rules/$(basename "$brand_src")"
fi

cp "$agent_src" "$agent_dest"
grep -v "^\.claude/agents/$(basename "$agent_src")	" "$ee/.claude/ai-config/manifest.tsv" > "$ee/m.tsv"; mv "$ee/m.tsv" "$ee/.claude/ai-config/manifest.tsv"
run "$ee" --force --no-superpowers >/dev/null
assert_false "legacy raw copy (unedited) is re-rendered on redeploy" grep -qF '{{PROJECT_NAME}}' "$agent_dest"
echo "KEEP-AGENT" >> "$agent_dest"
printf '.claude/agents/%s\tdeadbeef\n' "$(basename "$agent_src")" >> "$ee/.claude/ai-config/manifest.tsv"
run "$ee" --force --no-superpowers >/dev/null
assert_true "edited rendered agent kept on redeploy" grep -q KEEP-AGENT "$agent_dest"

# ============================================================================
echo -e "\n${CYAN}=== Version stamp, hook matcher ===${NC}\n"
# ============================================================================

p=$(make_nuxt)
run "$p" --force --no-superpowers >/dev/null
V="$p/.claude/ai-config/version"
assert_true "version stamp records the commit" grep -qE '^commit=[0-9a-f]+' "$V"
assert_eq "version stamp records stack and mode" "nuxt|deploy" "$(sed -n 's/^stack=//p' "$V")|$(sed -n 's/^mode=//p' "$V")"
jq '(.hooks.PreToolUse[] | select(.hooks[0].command | test("safety-guard"))).matcher = "Bash|Read"' "$p/.claude/settings.local.json" > "$p/s.json" && mv "$p/s.json" "$p/.claude/settings.local.json"
run "$p" --refresh --no-superpowers >/dev/null
assert_eq "refresh records mode=refresh" "refresh" "$(sed -n 's/^mode=//p' "$V")"
assert_eq "managed safety hook matcher follows the policy" "$(jq -r '.hooks.PreToolUse[0].matcher' "$POLICY_FILE")" \
  "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[0].command | test("safety-guard"))][0].matcher' "$p/.claude/settings.local.json")"
assert_eq "matcher update doesn't duplicate the hook" "1" "$(jq '.hooks.PreToolUse | length' "$p/.claude/settings.local.json")"

# ============================================================================
echo -e "\n${CYAN}=== --shared-policy ===${NC}\n"
# ============================================================================

p=$(make_nuxt)
git -C "$p" init -q
printf 'node_modules\n.claude/\n' > "$p/.gitignore"
run "$p" --force --no-superpowers --shared-policy >/dev/null
SH="$p/.claude/settings.json"
assert_true "shared settings.json carries the safety hook" jq -e '[.hooks.PreToolUse[].hooks[].command | select(test("safety-guard"))] | length == 1' "$SH"
assert_eq "shared settings.json carries every deny rule" "0" \
  "$(jq -n --slurpfile s "$SH" --slurpfile p "$POLICY_FILE" '[($p[0].permissions.deny // [])[] | select(. as $r | (($s[0].permissions.deny // []) | index([$r])) == null)] | length')"
assert_false "'.claude/' directory rule replaced" grep -qxF '.claude/' "$p/.gitignore"
assert_false ".claude/settings.json can be committed" git -C "$p" check-ignore -q .claude/settings.json
assert_false ".claude/hooks/safety-guard.sh can be committed" git -C "$p" check-ignore -q .claude/hooks/safety-guard.sh
assert_true ".claude/settings.local.json stays ignored" git -C "$p" check-ignore -q .claude/settings.local.json
assert_true ".claude/ai-config/ stays ignored" git -C "$p" check-ignore -q .claude/ai-config/manifest.tsv
assert_true "previous .gitignore backed up" test -n "$(find "$p/.claude/ai-config/backups" -name .gitignore 2>/dev/null)"
run "$p" --refresh --no-superpowers >/dev/null
assert_false "refresh without the flag stays shared (no .claude/ re-added)" grep -qxF '.claude/' "$p/.gitignore"
out=$("$SETUP_SCRIPT" --project="$p" --doctor 2>&1); status=$?
assert_eq "--doctor passes in shared mode" "0" "$status"
assert_true "--doctor reports the shared policy" contains "$out" "Shared safety policy present"

# ============================================================================
echo -e "\n${CYAN}=== --uninstall ===${NC}\n"
# ============================================================================

p=$(make_nuxt)
run "$p" --force --no-superpowers --okf-memory >/dev/null
echo "KEEP-RULE" >> "$p/.claude/rules/token-optimization.md"
jq '.permissions.allow += ["Bash(team-tool:*)"] | .permissions.deny += ["Read(**/team-secret.txt)"]
  | .hooks.PostToolUse = [{"matcher":"Edit","hooks":[{"type":"command","command":"npx prettier --write"}]}]' \
  "$p/.claude/settings.local.json" > "$p/s.json" && mv "$p/s.json" "$p/.claude/settings.local.json"
snapshot=$(tree_sha "$p")
run "$p" --uninstall --dry-run >/dev/null
assert_eq "--uninstall --dry-run changes nothing" "$snapshot" "$(tree_sha "$p")"

run "$p" --uninstall >/dev/null; status=$?
S="$p/.claude/settings.local.json"
assert_eq "--uninstall exits 0" "0" "$status"
assert_false "unedited shipped rule removed" test -f "$p/.claude/rules/deployment-safety.md"
assert_false "safety hook script removed" test -f "$p/.claude/hooks/safety-guard.sh"
assert_true "edited rule kept" grep -q KEEP-RULE "$p/.claude/rules/token-optimization.md"
assert_false "unedited generated CLAUDE.md removed" test -f "$p/CLAUDE.md"
assert_true "OKF bundle kept" test -f "$p/.okf/index.md"
assert_eq "only the project's own deny rule remains" '["Read(**/team-secret.txt)"]' "$(jq -c '.permissions.deny' "$S")"
assert_eq "policy ask rules removed" "0" "$(jq '(.permissions.ask // []) | length' "$S")"
assert_true "project allow rule kept" jq -e '.permissions.allow | index("Bash(team-tool:*)") != null' "$S"
assert_eq "policy ssh allow rule withdrawn" "false" "$(jq '(.permissions.allow // []) | index("Bash(ssh:*)") != null' "$S")"
assert_eq "safety hook registration removed, project hook kept" "null|npx prettier --write" \
  "$(jq -r '"\(.hooks.PreToolUse)|\(.hooks.PostToolUse[0].hooks[0].command)"' "$S")"
assert_true "removed files are in the backup" test -n "$(find "$p/.claude/ai-config/backups" -path '*/.claude/rules/deployment-safety.md' 2>/dev/null)"
assert_true "removed CLAUDE.md is in the backup" test -n "$(find "$p/.claude/ai-config/backups" -name CLAUDE.md 2>/dev/null)"
assert_eq "version stamp records the uninstall" "uninstall" "$(sed -n 's/^mode=//p' "$p/.claude/ai-config/version")"

p=$(make_nuxt)
run "$p" --force --no-superpowers >/dev/null
printf '# Team header KEEP-TOP\n' | cat - "$p/CLAUDE.md" > "$p/c.md" && mv "$p/c.md" "$p/CLAUDE.md"
run "$p" --uninstall >/dev/null
assert_true "edited CLAUDE.md kept" grep -q KEEP-TOP "$p/CLAUDE.md"
assert_eq "edited CLAUDE.md loses every managed block" "0" "$(grep -c '<!-- BEGIN ' "$p/CLAUDE.md")"
assert_true "MEMORY.md kept" test -f "$p/MEMORY.md"

# ============================================================================
echo -e "\n${CYAN}=== @import health check, context7 ===${NC}\n"
# ============================================================================

ee=$(make_ee)
run "$ee" --force --no-superpowers >/dev/null
home=$(tmp_dir)
out=$(HOME="$home" "$SETUP_SCRIPT" --project="$ee" --doctor 2>&1)
assert_true "missing ~/.claude/stacks import reported" contains "$out" "imports ~/.claude/stacks/expressionengine.md, which doesn't exist on this machine"
mkdir -p "$home/.claude/stacks"
cp "$SCRIPT_DIR/stacks/expressionengine.md" "$home/.claude/stacks/"
out=$(HOME="$home" "$SETUP_SCRIPT" --project="$ee" --doctor 2>&1)
assert_false "present, current stack import not reported" contains "$out" "stacks/expressionengine.md"
echo "stale" >> "$home/.claude/stacks/expressionengine.md"
out=$(HOME="$home" "$SETUP_SCRIPT" --project="$ee" --doctor 2>&1)
assert_true "stale stack import reported" contains "$out" "is out of date with claude-optimizer/stacks"

assert_eq "no stack template enables the undefined context7 server" "" \
  "$(grep -l '"context7"' "$SCRIPT_DIR"/projects/*/settings.local.json 2>/dev/null)"

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
