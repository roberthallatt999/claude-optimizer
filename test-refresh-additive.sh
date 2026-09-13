#!/usr/bin/env bash
# test-refresh-additive.sh — --refresh, --force redeploys and --clean must be additive:
# developer edits, memory and settings are never lost; every modification is backed up.
#
# Usage: ./test-refresh-additive.sh
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

# ============================================================================
# Helpers
# ============================================================================

PROJECTS=()
make_next_project() {
  local dir
  dir="$(mktemp -d)"
  touch "$dir/next.config.js"
  echo '{"name":"test","dependencies":{"next":"14.0.0","react":"18.0.0"}}' > "$dir/package.json"
  printf 'node_modules\n.env\n# team entry\n' > "$dir/.gitignore"
  PROJECTS+=("$dir")
  echo "$dir"
}
cleanup_all() { local d; for d in "${PROJECTS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

run() {
  local project_dir="$1"
  shift
  "$SETUP_SCRIPT" --project="$project_dir" --skip-vscode --no-superpowers "$@" >/dev/null 2>&1
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
tree_sha() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1); }
backup_count() { find "$1/.claude/ai-config/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
latest_backup_has() { grep -rqs -- "$3" "$1/.claude/ai-config/backups/"*/"$2"; }

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
echo -e "\n${CYAN}=== Developer edits survive --refresh ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force
assert_true "manifest recorded on deploy" test -s "$p/.claude/ai-config/manifest.tsv"

{ echo "# Local header KEEP-TOP"; cat "$p/CLAUDE.md"; echo "## Team notes"; echo "KEEP-CLAUDE"; } > "$p/CLAUDE.md.tmp" && mv "$p/CLAUDE.md.tmp" "$p/CLAUDE.md"
# Simulate a managed block written by an older ai-config version, so refresh must change it in place.
perl -0pi -e 's/(<!-- BEGIN SAFETY GUARDRAILS[^\n]*\n)/$1OLD-BLOCK-LINE\n/' "$p/CLAUDE.md"
cp "$p/.gitignore" "$p/gitignore.before"
echo "KEEP-RULE" >> "$p/.claude/rules/token-optimization.md"
echo "KEEP-LIB" >> "$p/.claude/libraries/react.md"
echo "KEEP-AGENT" >> "$p/.claude/agents/security-expert.md"
echo "| 2026-01-01 | KEEP-MEMORY-HISTORY | x |" >> "$p/MEMORY.md"
memory_sha=$(sha "$p/MEMORY.md")
orig_allow=$(jq -c '["Bash(zzz-team:*)"] + .permissions.allow' "$p/.claude/settings.local.json")
jq --argjson a "$orig_allow" '.permissions.allow = $a | .permissions.deny += ["Read(**/team-secret.txt)"]
  | .enableAllProjectMcpServers = true | .env = {"TEAM_FLAG": "1"}' "$p/.claude/settings.local.json" > "$p/s.json"
mv "$p/s.json" "$p/.claude/settings.local.json"

run "$p" --refresh
assert_eq "CLAUDE.md top line kept" "# Local header KEEP-TOP" "$(head -1 "$p/CLAUDE.md")"
assert_true "CLAUDE.md team notes kept" grep -q KEEP-CLAUDE "$p/CLAUDE.md"
assert_eq "managed Safety block present exactly once" "1" "$(grep -c '<!-- BEGIN SAFETY GUARDRAILS' "$p/CLAUDE.md")"
assert_eq "managed Response Style block present exactly once" "1" "$(grep -c '<!-- BEGIN RESPONSE STYLE' "$p/CLAUDE.md")"
assert_true "new CLAUDE.md render staged for review" test -f "$p/.claude/ai-config/pending/CLAUDE.md"
assert_false "stale managed block refreshed in place" grep -q OLD-BLOCK-LINE "$p/CLAUDE.md"
assert_true "pre-refresh CLAUDE.md backed up (with edits and old block)" latest_backup_has "$p" CLAUDE.md OLD-BLOCK-LINE
assert_true "edited rule kept" grep -q KEEP-RULE "$p/.claude/rules/token-optimization.md"
assert_true "edited library kept" grep -q KEEP-LIB "$p/.claude/libraries/react.md"
assert_true "edited agent kept" grep -q KEEP-AGENT "$p/.claude/agents/security-expert.md"
assert_eq "MEMORY.md byte-identical" "$memory_sha" "$(sha "$p/MEMORY.md")"
assert_true ".gitignore only appended to" cmp -n "$(wc -c < "$p/gitignore.before")" "$p/gitignore.before" "$p/.gitignore"
S="$p/.claude/settings.local.json"
assert_eq "every original allow entry kept, in order" "$orig_allow" \
  "$(jq -c --argjson o "$orig_allow" '[.permissions.allow[] | select(. as $x | $o | index([$x]) != null)]' "$S")"
assert_eq "project deny entry kept" "true" "$(jq '.permissions.deny | index("Read(**/team-secret.txt)") != null' "$S")"
assert_eq "enableAllProjectMcpServers left as set" "true" "$(jq '.enableAllProjectMcpServers' "$S")"
assert_eq "custom env kept" "1" "$(jq -r '.env.TEAM_FLAG' "$S")"
assert_eq "git push still gated by ask rule" "true" "$(jq '.permissions.ask | index("Bash(git push:*)") != null' "$S")"

backups_before=$(backup_count "$p")
run "$p" --refresh
assert_eq "no-op refresh creates no new backup" "$backups_before" "$(backup_count "$p")"
assert_true "edits still kept after second refresh" grep -q KEEP-CLAUDE "$p/CLAUDE.md"

# ============================================================================
echo -e "\n${CYAN}=== Unedited files are still updated (with backup) ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force
printf 'OLD GENERATED CLAUDE.md\n' > "$p/CLAUDE.md"
printf 'CLAUDE.md\t%s\n' "$(sha "$p/CLAUDE.md")" >> "$p/.claude/ai-config/manifest.tsv"
run "$p" --refresh
assert_false "unedited CLAUDE.md regenerated" grep -q "OLD GENERATED" "$p/CLAUDE.md"
assert_true "regenerated CLAUDE.md has managed blocks" grep -q "BEGIN SAFETY GUARDRAILS" "$p/CLAUDE.md"
assert_true "previous generated CLAUDE.md backed up" latest_backup_has "$p" CLAUDE.md "OLD GENERATED"
assert_false "nothing staged for an unedited file" test -f "$p/.claude/ai-config/pending/CLAUDE.md"

# Legacy project (no manifest entry): a library matching an older committed version is updated.
old_lib="" old_commit=""
for f in "$SCRIPT_DIR"/libraries/*.md; do
  [[ "$(basename "$f")" == "README.md" ]] && continue   # never deployed
  rel="libraries/$(basename "$f")"
  cur=$(git -C "$SCRIPT_DIR" hash-object "$f")
  c=$(git -C "$SCRIPT_DIR" log --format=%H -- "$rel" | while read -r h; do
        b=$(git -C "$SCRIPT_DIR" rev-parse "$h:$rel" 2>/dev/null) || continue
        if [[ "$b" != "$cur" ]]; then echo "$h"; break; fi
      done)
  if [[ -n "$c" ]]; then old_lib=$(basename "$f"); old_commit=$c; break; fi
done
if [[ -n "$old_lib" ]]; then
  git -C "$SCRIPT_DIR" show "$old_commit:libraries/$old_lib" > "$p/.claude/libraries/$old_lib"
  grep -v "^\.claude/libraries/$old_lib	" "$p/.claude/ai-config/manifest.tsv" > "$p/m.tsv"; mv "$p/m.tsv" "$p/.claude/ai-config/manifest.tsv"
  run "$p" --refresh
  assert_true "legacy unedited library ($old_lib) updated from git history match" cmp -s "$SCRIPT_DIR/libraries/$old_lib" "$p/.claude/libraries/$old_lib"
else
  echo "SKIP legacy library history test (no library with an older committed version)"
fi

# ============================================================================
echo -e "\n${CYAN}=== --force redeploy, --dry-run, --clean, --apply-pending ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force
echo "KEEP-AGENT" >> "$p/.claude/agents/security-expert.md"
echo "KEEP-CLAUDE" >> "$p/CLAUDE.md"
memory_sha=$(sha "$p/MEMORY.md")
run "$p" --force
assert_true "--force redeploy keeps edited agent" grep -q KEEP-AGENT "$p/.claude/agents/security-expert.md"
assert_true "--force redeploy keeps edited CLAUDE.md" grep -q KEEP-CLAUDE "$p/CLAUDE.md"
assert_eq "--force redeploy keeps MEMORY.md" "$memory_sha" "$(sha "$p/MEMORY.md")"

snapshot=$(tree_sha "$p")
run "$p" --refresh --dry-run
assert_eq "--dry-run refresh changes nothing" "$snapshot" "$(tree_sha "$p")"

run "$p" --refresh --apply-pending
assert_false "--apply-pending adopts the staged CLAUDE.md" grep -q KEEP-CLAUDE "$p/CLAUDE.md"
assert_true "--apply-pending backed up the edited CLAUDE.md" latest_backup_has "$p" CLAUDE.md KEEP-CLAUDE
assert_eq "--apply-pending empties pending/" "0" "$(find "$p/.claude/ai-config/pending" -type f 2>/dev/null | wc -l | tr -d ' ')"
assert_true "agent edit kept until adopted, now backed up" latest_backup_has "$p" .claude/agents/security-expert.md KEEP-AGENT

p=$(make_next_project)
run "$p" --force
echo "team rule KEEP-CUSTOM-RULE" > "$p/.claude/rules/my-team-rule.md"
run "$p" --force
backups_before=$(backup_count "$p")
run "$p" --force --clean
assert_false "--clean starts fresh" test -f "$p/.claude/rules/my-team-rule.md"
assert_true "--clean moved the old .claude into a backup" latest_backup_has "$p" .claude/rules/my-team-rule.md KEEP-CUSTOM-RULE
assert_eq "--clean keeps earlier backups" "true" "$([[ $(backup_count "$p") -gt $backups_before ]] && echo true || echo false)"
assert_true "MEMORY.md untouched by --clean" test -f "$p/MEMORY.md"

# ============================================================================
echo -e "\n${CYAN}=== Orchestrator stays sticky without overwriting choices ===${NC}\n"
# ============================================================================

p=$(make_next_project)
run "$p" --force --orchestrator
jq '.model = "fable"' "$p/.claude/settings.local.json" > "$p/s.json" && mv "$p/s.json" "$p/.claude/settings.local.json"
echo "KEEP-IMPL" >> "$p/.claude/agents/implementer.md"
run "$p" --refresh
assert_eq "sticky refresh keeps a changed model" "fable" "$(jq -r '.model' "$p/.claude/settings.local.json")"
assert_true "sticky refresh keeps edited implementer" grep -q KEEP-IMPL "$p/.claude/agents/implementer.md"
assert_eq "orchestrator block still present once" "1" "$(grep -c '<!-- BEGIN ORCHESTRATOR POLICY' "$p/CLAUDE.md")"
run "$p" --refresh --orchestrator
assert_eq "explicit --orchestrator re-pins opus" "opus" "$(jq -r '.model' "$p/.claude/settings.local.json")"

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
