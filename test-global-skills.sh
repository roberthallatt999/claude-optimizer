#!/usr/bin/env bash
# test-global-skills.sh — global-skills/: every skill has valid frontmatter, and the noslop skill
# is built from its CPS overlay plus the verbatim upstream copy (scripts/sync-noslop.sh).
#
# Usage: ./test-global-skills.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$SCRIPT_DIR/scripts/sync-noslop.sh"
NOSLOP="$SCRIPT_DIR/global-skills/noslop"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TMPS=()
tmp_dir() { local d; d="$(mktemp -d)"; TMPS+=("$d"); echo "$d"; }
cleanup_all() { local d; for d in "${TMPS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

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

# Frontmatter: opens on line 1, closes, and names the skill after its folder with a description.
frontmatter_ok() {
  local file="$1" name="$2" fm
  [[ "$(head -1 "$file")" == "---" ]] || return 1
  fm="$(awk 'NR == 1 { next } $0 == "---" { exit } { print }' "$file")"
  grep -qx "name: $name" <<< "$fm" && grep -q '^description:' <<< "$fm"
}
frontmatter_count() { grep -c '^name: ' "$1"; }

for skill_dir in "$SCRIPT_DIR"/global-skills/*/; do
  name="$(basename "$skill_dir")"
  assert_true "$name: SKILL.md frontmatter names the skill" frontmatter_ok "${skill_dir}SKILL.md" "$name"
done

# Claude Code would load a nested SKILL.md as a second skill, so the upstream copy must not be one.
assert_false "noslop: no nested SKILL.md" test -e "$NOSLOP/upstream/SKILL.md"
assert_true  "noslop: upstream licence kept (MIT notice)" grep -q 'Copyright (c) 2026 Ruben Hassid' "$NOSLOP/upstream/LICENSE"
assert_true  "noslop: source commit recorded" grep -qE '^commit=[0-9a-f]{40}$' "$NOSLOP/upstream/SOURCE"
assert_true  "noslop: committed SKILL.md matches its sources" "$SYNC" --check

# Build into a scratch copy: overlay first, upstream frontmatter dropped, upstream body intact.
work=$(tmp_dir)
cp -R "$NOSLOP" "$work/noslop"
rm "$work/noslop/SKILL.md"
NOSLOP_SKILL_DIR="$work/noslop" "$SYNC" >/dev/null
built="$work/noslop/SKILL.md"
assert_true  "build: recreates a missing SKILL.md" test -f "$built"
assert_true  "build: identical to the committed file" cmp -s "$built" "$NOSLOP/SKILL.md"
assert_true  "build: exactly one frontmatter block" test "$(frontmatter_count "$built")" -eq 1
overrides_line="$(grep -n '^# CPS overrides' "$built" | cut -d: -f1)"
upstream_line="$(grep -n '^# No slop\.' "$built" | cut -d: -f1)"
assert_true  "build: CPS overrides come before the upstream rules" test "${overrides_line:-0}" -gt 0 -a "${overrides_line:-0}" -lt "${upstream_line:-0}"
assert_true  "build: upstream body carried over verbatim" cmp -s \
  <(sed -n "${upstream_line},\$p" "$built") \
  <(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;s=1;next} f{next} s&&$0==""{next} {s=0;print}' "$NOSLOP/upstream/noslop.md")

# --check reports drift without writing.
echo "drift" >> "$work/noslop/cps-overlay.md"
assert_false "check: fails when the overlay changed" env NOSLOP_SKILL_DIR="$work/noslop" "$SYNC" --check
assert_false "check: leaves SKILL.md untouched" grep -qx drift "$built"
NOSLOP_SKILL_DIR="$work/noslop" "$SYNC" >/dev/null
assert_true  "build: picks up the overlay change" grep -qx drift "$built"

# The overlay's contrast overrides are the ones that pass WCAG AA (checked by hand: 4.74:1, 5.1:1, 5.06:1).
assert_true  "overlay: light --text-3 override" grep -qF -- '--text-3: rgba(0,0,0,.55)' "$NOSLOP/SKILL.md"
assert_true  "overlay: --clay-strong override" grep -qF -- '--clay-strong: #b5502f' "$NOSLOP/SKILL.md"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
