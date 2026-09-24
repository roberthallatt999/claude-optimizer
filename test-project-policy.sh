#!/usr/bin/env bash
# test-project-policy.sh — ai-config.conf: the project's committed say over its own config.
#
# Covers the three things that used to revert on the next run because the evidence for them
# lived in gitignored files: a curated library set, a relocated decision log, and a rule the
# project has taken over. Each case is checked against a simulated fresh clone — .claude/,
# CLAUDE.md, MEMORY.md and .okf/ deleted, ai-config.conf kept — which is the state that
# actually loses them.
#
# Usage: ./test-project-policy.sh
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

run() { local d="$1"; shift; "$SETUP_SCRIPT" --project="$d" --skip-vscode --no-superpowers --skip-superpowers-update "$@" 2>&1; }

make_craft() {
  local d; d=$(tmp_dir)
  touch "$d/craft"
  echo '{"require":{"craftcms/cms":"5.0"}}' > "$d/composer.json"
  echo '{"devDependencies":{"tailwindcss":"3"}}' > "$d/package.json"
  printf 'vendor/\n' > "$d/.gitignore"
  git -C "$d" init -q .
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
  echo "$d"
}

# Everything ai-config normally writes is gitignored, so this is what a teammate — or Robert on
# a new machine — actually starts from.
simulate_fresh_clone() { rm -rf "$1/.claude" "$1/CLAUDE.md" "$1/MEMORY.md" "$1/AGENTS.md" "$1/.okf"; }

lib_count() { ls "$1/.claude/libraries" 2>/dev/null | wc -l | tr -d ' '; }

# ============================================================================
echo -e "\n${CYAN}=== --save-policy captures a tuned project ===${NC}\n"
# ============================================================================

p=$(make_craft)
run "$p" --force >/dev/null
before=$(lib_count "$p")
rm -f "$p"/.claude/libraries/{react,vue,nextjs,nuxt,svelte,angular}.md
out=$(run "$p" --save-policy)

assert_true "ai-config.conf written at the project root" test -f "$p/ai-config.conf"
assert_true "records the stack" grep -qx "stack = craftcms" "$p/ai-config.conf"
assert_true "records the removed libraries" grep -qx ".claude/libraries/react.md" "$p/ai-config.conf"
assert_eq  "records every removal" "6" "$(sed -n '/^\[exclude\]/,$p' "$p/ai-config.conf" | grep -c '^\.claude/libraries/')"
assert_true "says how to commit it" contains "$out" "git add ai-config.conf"
assert_false "does not record files that are still present" grep -qx ".claude/libraries/tailwind.md" "$p/ai-config.conf"

# ============================================================================
echo -e "\n${CYAN}=== [exclude] survives a fresh clone (was: 12 libraries returned) ===${NC}\n"
# ============================================================================

simulate_fresh_clone "$p"
out=$(run "$p" --force)
assert_eq "pruned libraries are not re-added" "$((before - 6))" "$(lib_count "$p")"
assert_false "react.md stays gone" test -f "$p/.claude/libraries/react.md"
assert_true  "unexcluded libraries still deploy" test -f "$p/.claude/libraries/tailwind.md"
assert_true  "the run says why" contains "$out" "[exclude] covers them"

# Without the policy file the same fresh clone rebuilds the full set — the old behaviour.
q=$(make_craft)
run "$q" --force >/dev/null
rm -f "$q"/.claude/libraries/{react,vue,nextjs,nuxt,svelte,angular}.md
simulate_fresh_clone "$q"
run "$q" --force >/dev/null
assert_eq "no policy file → pruning is lost (regression guard)" "$before" "$(lib_count "$q")"

# ============================================================================
echo -e "\n${CYAN}=== [decisions] path redirects the managed protocol block ===${NC}\n"
# ============================================================================

p=$(make_craft)
mkdir -p "$p/docs" && printf '# Decisions\n' > "$p/docs/decisions.md"
printf '[options]\nstack = craftcms\n\n[decisions]\npath = docs/decisions.md\n' > "$p/ai-config.conf"
run "$p" --force >/dev/null
block=$(sed -n '/BEGIN MEMORY PROTOCOL/,/END MEMORY PROTOCOL/p' "$p/CLAUDE.md")
assert_true "protocol block points at the tracked file" contains "$block" 'record it in `docs/decisions.md`'
assert_true "protocol block warns off project memory"  contains "$block" 'Do not put decisions in project memory'
assert_true "memory rule agrees" grep -q 'Architectural decisions go in `docs/decisions.md`' "$p/.claude/rules/memory-management.md"
assert_true "memory rule is scoped to load there" grep -q '"docs/decisions.md"' "$p/.claude/rules/memory-management.md"

# The block is regenerated from the template every run, so this is the case that used to revert.
run "$p" --refresh >/dev/null
block=$(sed -n '/BEGIN MEMORY PROTOCOL/,/END MEMORY PROTOCOL/p' "$p/CLAUDE.md")
assert_true "refresh keeps the redirect" contains "$block" 'record it in `docs/decisions.md`'

# ============================================================================
echo -e "\n${CYAN}=== Defaults are unchanged when there is no policy file ===${NC}\n"
# ============================================================================

q=$(make_craft)
run "$q" --force >/dev/null
block=$(sed -n '/BEGIN MEMORY PROTOCOL/,/END MEMORY PROTOCOL/p' "$q/CLAUDE.md")
assert_true  "decisions default to MEMORY.md" contains "$block" 'add a short **Decision Log** entry to `MEMORY.md`'
assert_false "no placeholder leaks into CLAUDE.md" grep -q '{{DECISION' "$q/CLAUDE.md"
assert_false "no placeholder leaks into the rules" grep -rq '{{DECISION' "$q/.claude/rules/"
assert_eq    "no stray paths: entry" "2" "$(sed -n '/^paths:/,/^---$/p' "$q/.claude/rules/memory-management.md" | grep -c '^  - ')"

# ============================================================================
echo -e "\n${CYAN}=== [options] restores stickiness a fresh clone loses ===${NC}\n"
# ============================================================================

p=$(make_craft)
run "$p" --force --okf-memory >/dev/null
run "$p" --save-policy >/dev/null
assert_true "okf-memory captured" grep -qx "okf-memory = true" "$p/ai-config.conf"

simulate_fresh_clone "$p"
run "$p" --force >/dev/null
assert_true "OKF protocol block returns without the flag" grep -q "BEGIN OKF MEMORY PROTOCOL" "$p/CLAUDE.md"
assert_false "and the MEMORY.md block does not" grep -q "BEGIN MEMORY PROTOCOL" "$p/CLAUDE.md"

# OKF + a tracked decision log: conventions stay in the bundle, decisions move out.
printf '\n[decisions]\npath = docs/decisions.md\n' >> "$p/ai-config.conf"
run "$p" --refresh >/dev/null
block=$(sed -n '/BEGIN OKF MEMORY PROTOCOL/,/END OKF MEMORY PROTOCOL/p' "$p/CLAUDE.md")
assert_true "OKF decisions redirect" contains "$block" 'record it in `docs/decisions.md`'
assert_true "OKF durable knowledge still goes to the bundle" contains "$block" 'link it from `.okf/index.md`'

# ============================================================================
echo -e "\n${CYAN}=== An explicit flag beats the file ===${NC}\n"
# ============================================================================

p=$(make_craft)
printf '[options]\nstack = craftcms\nokf-memory = true\n' > "$p/ai-config.conf"
out=$(run "$p" --stack=custom --dry-run)
assert_true "--stack overrides [options] stack" contains "$out" "Stack:"
assert_eq "…with the command-line value" "custom" "$(grep -a 'Stack:' <<< "$out" | head -1 | sed 's/.*Stack:[[:space:]]*//' | sed 's/\x1b\[[0-9;]*m//g' | tr -d ' ')"

# ============================================================================
echo -e "\n${CYAN}=== Malformed files are reported, never fatal ===${NC}\n"
# ============================================================================

p=$(make_craft)
printf '[nope]\nstray\n[options]\nbadline\nstack = craftcms\nunknownkey = 1\n' > "$p/ai-config.conf"
out=$(run "$p" --dry-run); rc=$?
assert_eq "still exits 0" "0" "$rc"
assert_true "unknown section reported" contains "$out" "Unknown section '[nope]'"
assert_true "line outside a section reported" contains "$out" "'stray' appears before any section"
assert_true "non key=value line reported" contains "$out" "'badline' is not 'key = value'"
assert_true "unknown key reported" contains "$out" "unknown key 'unknownkey'"

# ============================================================================
echo -e "\n${CYAN}=== --doctor reports policy drift ===${NC}\n"
# ============================================================================

p=$(make_craft)
run "$p" --force >/dev/null
rm -f "$p/.claude/libraries/react.md"
out=$("$SETUP_SCRIPT" --project="$p" --doctor 2>&1)
assert_true "uncaptured removals are flagged" contains "$out" "removed on purpose but not recorded"
assert_true "and it names the fix" contains "$out" "--save-policy"

run "$p" --save-policy >/dev/null
out=$("$SETUP_SCRIPT" --project="$p" --doctor 2>&1)
assert_false "flag clears once captured" contains "$out" "removed on purpose but not recorded"
assert_true "uncommitted policy file is flagged" contains "$out" "is not committed"

git -C "$p" add ai-config.conf >/dev/null 2>&1
git -C "$p" -c user.email=t@t -c user.name=t commit -qm policy >/dev/null 2>&1
out=$("$SETUP_SCRIPT" --project="$p" --doctor 2>&1)
assert_false "…and clears once committed" contains "$out" "is not committed"

# ============================================================================
echo -e "\n${CYAN}=== --save-policy is safe to re-run ===${NC}\n"
# ============================================================================

printf '\n[decisions]\npath = docs/decisions.md\n' >> "$p/ai-config.conf"
rm -f "$p/.claude/libraries/vue.md"
run "$p" --save-policy >/dev/null
assert_true "hand-written decisions path is kept" grep -qx "path = docs/decisions.md" "$p/ai-config.conf"
assert_true "earlier exclusions are kept" grep -qx ".claude/libraries/react.md" "$p/ai-config.conf"
assert_true "new exclusions are added" grep -qx ".claude/libraries/vue.md" "$p/ai-config.conf"

out=$(run "$p" --save-policy)
assert_true "a second run is a no-op" contains "$out" "already current"

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
