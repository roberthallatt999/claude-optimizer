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

# Cloudflare helper (web version): scaffolding, addresses, and no token ever printed.
CF="$NOSLOP/scripts/cloudflare.sh"
cfdir=$(tmp_dir)
export CLOUDFLARE_CONFIG="$cfdir/config" CLOUDFLARE_TOKEN_FILE="$cfdir/api-token"
export CLOUDFLARE_KEYCHAIN_SERVICE="noslop-test-$$-absent"
site=$(tmp_dir)
assert_true  "cloudflare: new scaffolds the gate" "$CF" new "$site" "Q3 Member Centre traffic!"
name=$(sed -n 's/^  "name": "\([^"]*\)".*/\1/p' "$site/wrangler.jsonc")
assert_true  "cloudflare: name is the topic plus an 8-character hash" grep -Eq '^q3-member-centre-traffic-[0-9a-f]{8}$' <<< "$name"
assert_true  "cloudflare: every request goes through the gate" grep -q '"run_worker_first": true' "$site/wrangler.jsonc"
assert_true  "cloudflare: the page gets its own path on share.cps.ca" \
  grep -q "\"pattern\": \"share.cps.ca/$name/\\*\", \"zone_name\": \"cps.ca\"" "$site/wrangler.jsonc"
assert_true  "cloudflare: the gate knows its path" grep -q "\"BASE_PATH\": \"/$name\"" "$site/wrangler.jsonc"
assert_true  "cloudflare: no workers.dev address" grep -q '"workers_dev": false' "$site/wrangler.jsonc"
assert_true  "cloudflare: a new page expires in 30 days by default" \
  grep -q "\"EXPIRES\": \"$(date -u -v+30d +%F 2>/dev/null || date -u -d '+30 days' +%F)\"" "$site/wrangler.jsonc"
assert_false "cloudflare: days must be a number" "$CF" new "$(tmp_dir)" topic soon
assert_true  "cloudflare: the gate refuses an expired page" grep -q 'expired on' "$NOSLOP/templates/cloudflare/worker.js"
assert_false "cloudflare: delete without a token deletes nothing" "$CF" delete q3-traffic-7f3a9c2e
other=$(tmp_dir)
"$CF" new "$other" "Q3 Member Centre traffic!" >/dev/null 2>&1
assert_false "cloudflare: the same topic twice gets two routes" \
  test "$(sed -n 's/^  "name": "\([^"]*\)".*/\1/p' "$other/wrangler.jsonc")" = "$name"
echo "// mine" > "$site/worker.js"
assert_true  "cloudflare: new in a page's folder keeps its name" grep -q "kept existing page $name" <<< "$("$CF" new "$site" other 2>&1)"
assert_true  "cloudflare: new never overwrites" grep -qx '// mine' "$site/worker.js"
assert_false "cloudflare: new refuses a topic with no letters" "$CF" new "$(tmp_dir)" '!!!'
assert_true  "cloudflare: url defaults to share.cps.ca" \
  test "$("$CF" url "$name")" = "https://share.cps.ca/$name/"
printf 'CLOUDFLARE_ACCOUNT_ID=abc\n' > "$CLOUDFLARE_CONFIG"
"$CF" domain share.example.org >/dev/null
assert_true  "cloudflare: domain sets the share domain" \
  test "$("$CF" url q3-traffic-0a1b2c3d)" = "https://share.example.org/q3-traffic-0a1b2c3d/"
assert_true  "cloudflare: domain keeps the account ID" grep -qx 'CLOUDFLARE_ACCOUNT_ID=abc' "$CLOUDFLARE_CONFIG"
assert_false "cloudflare: domain refuses a non-host" "$CF" domain 'not a host'
printf 'sekret-token-value\n' > "$CLOUDFLARE_TOKEN_FILE"
assert_false "cloudflare: config never prints the token" grep -q sekret-token-value <<< "$("$CF" config 2>&1)"
if command -v node >/dev/null 2>&1; then
  cp "$NOSLOP/templates/cloudflare/worker.js" "$cfdir/worker.mjs"
  assert_true "cloudflare: worker.js parses" node --check "$cfdir/worker.mjs"
fi
assert_true  "cloudflare: worker fails closed without PASSCODE" grep -q 'if (!env.PASSCODE)' "$NOSLOP/templates/cloudflare/worker.js"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
