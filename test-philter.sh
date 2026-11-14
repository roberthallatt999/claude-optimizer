#!/usr/bin/env bash
# test-philter.sh — `philter = <set>` in ai-config.conf writes a committed .philter file.
#
# The file names one Philter policy set for philter-guard to use. ai-config only writes the bare
# name: it never calls Philter, never reads philter-guard's key, and works without it installed.
# .philter is committed in client repos, so it is never gitignored and never deleted.
#
# Usage: ./test-philter.sh
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

MARKER='# Philter policy set, written by ai-config from ai-config.conf (philter = …). See philter-guard.'

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

conf() { printf '[options]\nstack = craftcms\nphilter = %s\n' "$2" > "$1/ai-config.conf"; }

# A fake `claude` on PATH so the doctor's `claude mcp get philter` is hermetic.
# fake_claude <dir> <registered:yes|no>
fake_claude() {
  local bin="$1/bin"
  mkdir -p "$bin"
  if [[ "$2" == yes ]]; then
    printf '#!/bin/sh\n[ "$1 $2 $3" = "mcp get philter" ] && exit 0\nexit 1\n' > "$bin/claude"
  else
    printf '#!/bin/sh\nexit 1\n' > "$bin/claude"
  fi
  chmod +x "$bin/claude"
  echo "$bin"
}

# ============================================================================
echo -e "\n${CYAN}=== philter = <set> writes .philter ===${NC}\n"
# ============================================================================

p=$(make_craft)
conf "$p" acme
out=$(run "$p" --force)
assert_true "no unknown-key warning" bash -c '! grep -q "unknown key .philter" <<< "$1"' _ "$out"
assert_true ".philter exists" test -f "$p/.philter"
assert_eq   "first line is the marker" "$MARKER" "$(sed -n 1p "$p/.philter")"
assert_eq   "second line is the set name" "acme" "$(sed -n 2p "$p/.philter")"
assert_eq   "nothing else in the file" "2" "$(wc -l < "$p/.philter" | tr -d ' ')"
assert_false ".gitignore has no line matching .philter" grep -q 'philter' "$p/.gitignore"

# ============================================================================
echo -e "\n${CYAN}=== --refresh follows a changed value ===${NC}\n"
# ============================================================================

conf "$p" beta
out=$(run "$p" --refresh)
assert_eq   "file now holds beta" "beta" "$(sed -n 2p "$p/.philter")"
assert_eq   "marker kept" "$MARKER" "$(sed -n 1p "$p/.philter")"
assert_true "output mentions acme to beta" contains "$out" "acme → beta"
out=$(run "$p" --refresh)
assert_eq   "an unchanged value is left alone" "beta" "$(sed -n 2p "$p/.philter")"
assert_false "no change message the second time" contains "$out" "→ beta"
assert_false ".gitignore still has no .philter line" grep -q 'philter' "$p/.gitignore"

# ============================================================================
echo -e "\n${CYAN}=== a hand-written .philter is left alone ===${NC}\n"
# ============================================================================

p=$(make_craft)
printf '# mine\nclient-x\n' > "$p/.philter"
cp "$p/.philter" "$p/.philter.orig"
printf '[options]\nstack = craftcms\n' > "$p/ai-config.conf"
run "$p" --force >/dev/null
assert_true "setup without the option leaves it byte-identical" cmp -s "$p/.philter" "$p/.philter.orig"
run "$p" --refresh >/dev/null
assert_true "refresh without the option leaves it byte-identical" cmp -s "$p/.philter" "$p/.philter.orig"
conf "$p" other
out=$(run "$p" --refresh)
assert_true "even with the option, an unmarked file is not overwritten" cmp -s "$p/.philter" "$p/.philter.orig"
assert_true "and the run says so" contains "$out" "not written by ai-config"

# ============================================================================
echo -e "\n${CYAN}=== an invalid value is refused ===${NC}\n"
# ============================================================================

p=$(make_craft)
conf "$p" "Acme Corp"
out=$(run "$p" --force)
assert_true  "warns about the value" contains "$out" "philter"
assert_true  "warning names the rule" contains "$out" "lowercase"
assert_false ".philter is not written" test -e "$p/.philter"

# ============================================================================
echo -e "\n${CYAN}=== --clean and --uninstall keep .philter ===${NC}\n"
# ============================================================================

p=$(make_craft)
conf "$p" acme
run "$p" --force >/dev/null
out=$(run "$p" --clean --force)
assert_true "--clean keeps .philter" test -f "$p/.philter"
assert_true "--clean notes it" contains "$out" ".philter"
assert_eq   "--clean keeps its content" "acme" "$(sed -n 2p "$p/.philter")"
out=$(run "$p" --uninstall --force)
assert_true "--uninstall keeps .philter" test -f "$p/.philter"
assert_true "--uninstall notes it" contains "$out" ".philter"

# ============================================================================
echo -e "\n${CYAN}=== --save-policy keeps philter ===${NC}\n"
# ============================================================================

p=$(make_craft)
conf "$p" acme
run "$p" --force >/dev/null
run "$p" --save-policy >/dev/null
assert_true "philter line survives --save-policy" grep -qx "philter = acme" "$p/ai-config.conf"

# ============================================================================
echo -e "\n${CYAN}=== --doctor ===${NC}\n"
# ============================================================================

p=$(make_craft)
conf "$p" acme
run "$p" --force >/dev/null

yes_bin=$(fake_claude "$(tmp_dir)" yes)
no_bin=$(fake_claude "$(tmp_dir)" no)

out=$(PATH="$yes_bin:$PATH" run "$p" --doctor); yes_status=$?
assert_true "installed: reports the set name" contains "$out" "acme"
assert_true "installed: points at /scrub" contains "$out" "/scrub"
assert_false "installed: no 'not installed' note" contains "$out" "Philter guard not installed"

out=$(PATH="$no_bin:$PATH" run "$p" --doctor); no_status=$?
assert_true "not installed: says so" contains "$out" "Philter guard not installed"
assert_eq   "same exit code with or without the server" "$yes_status" "$no_status"

q=$(make_craft)
printf '[options]\nstack = craftcms\n' > "$q/ai-config.conf"
run "$q" --force >/dev/null
out=$(PATH="$no_bin:$PATH" run "$q" --doctor); base_status=$?
assert_false "no .philter: doctor says nothing about Philter" contains "$out" "Philter"
assert_eq   "no .philter: same exit code" "$base_status" "$no_status"

# Only a validated name is ever printed (terminal escape injection), exit code unchanged.
bad_case() {  # bad_case <label> <file content, printf format> <forbidden text>
  local bp bout bstatus
  bp=$(make_craft)
  conf "$bp" acme
  run "$bp" --force >/dev/null
  printf "$2" > "$bp/.philter"
  bout=$(PATH="$no_bin:$PATH" run "$bp" --doctor); bstatus=$?
  assert_true  "$1: reports an invalid or empty name" contains "$bout" "invalid or empty set name in .philter"
  assert_false "$1: raw content is not printed" contains "$bout" "$3"
  assert_false "$1: no escape character in the output" contains "$bout" $'\033[31m'
  assert_eq    "$1: exit code unchanged" "$base_status" "$bstatus"
}
bad_case "empty .philter"        ''                         'zzzz-never'
bad_case "escape in the name"    '\033[31mevil\n'           'evil'
bad_case "uppercase and space"   'Acme Corp\n'              'Acme Corp'
bad_case "comment-only .philter" '# nothing here\n'         'nothing here'

# ============================================================================
echo -e "\n${CYAN}=== a symlinked .philter is never written through ===${NC}\n"
# ============================================================================

p=$(make_craft)
outside="$(tmp_dir)/outside.txt"
printf 'precious\n' > "$outside"
cp "$outside" "$outside.orig"
ln -s "$outside" "$p/.philter"
conf "$p" acme
out=$(run "$p" --force)
assert_true "setup: outside file byte-identical" cmp -s "$outside" "$outside.orig"
assert_true "setup: warns about the symlink" contains "$out" ".philter is a symlink"
out=$(run "$p" --refresh)
assert_true "refresh: outside file byte-identical" cmp -s "$outside" "$outside.orig"
assert_true "refresh: warns about the symlink" contains "$out" ".philter is a symlink"
assert_true "the symlink itself is left in place" test -L "$p/.philter"

# A symlink to a marked file would be read for its current value too; still skipped.
printf '%s\nbeta\n' "$MARKER" > "$outside"
cp "$outside" "$outside.orig"
run "$p" --refresh >/dev/null
assert_true "a symlink to a marked file is not rewritten either" cmp -s "$outside" "$outside.orig"

# ============================================================================
echo -e "\n${CYAN}=== unmarked file: warning names its set when valid ===${NC}\n"
# ============================================================================

p=$(make_craft)
printf '# mine\nclient-x\n' > "$p/.philter"
conf "$p" other
out=$(run "$p" --force)
assert_true "warning includes the current valid set name" contains "$out" "(set 'client-x')"
printf '\033[31mevil\n' > "$p/.philter"
out=$(run "$p" --refresh)
assert_false "an invalid current name is not echoed" contains "$out" "evil"

# ============================================================================
echo -e "\n${CYAN}=== no stack's .gitignore rules ignore .philter ===${NC}\n"
# ============================================================================

g=$(tmp_dir)
git -C "$g" init -q .
cat "$SCRIPT_DIR"/projects/*/gitignore-security.txt > "$g/.gitignore"
touch "$g/.philter"
assert_false "union of every stack's rules does not match .philter" git -C "$g" check-ignore -q .philter

# ============================================================================
echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
[[ $FAIL -eq 0 ]]
