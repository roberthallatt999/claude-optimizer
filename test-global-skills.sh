#!/usr/bin/env bash
# test-global-skills.sh — global-skills/: every skill has valid frontmatter, and the noslop skill
# is built from its profile overlay plus the verbatim upstream copy (scripts/sync-noslop.sh).
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
overrides_line="$(grep -n '^# Profile overrides' "$built" | cut -d: -f1)"
upstream_line="$(grep -n '^# No slop\.' "$built" | cut -d: -f1)"
assert_true  "build: profile overrides come before the upstream rules" test "${overrides_line:-0}" -gt 0 -a "${overrides_line:-0}" -lt "${upstream_line:-0}"
assert_true  "build: upstream body carried over verbatim" cmp -s \
  <(sed -n "${upstream_line},\$p" "$built") \
  <(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;s=1;next} f{next} s&&$0==""{next} {s=0;print}' "$NOSLOP/upstream/noslop.md")

# --check reports drift without writing.
echo "drift" >> "$work/noslop/overlay.md"
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

# profile.sh: the active profile comes from AI_CONFIG_PROFILE, then the nearest ai-config.conf,
# then the machine default. cloudflare.sh takes its share domain from it.
PROFILE="$NOSLOP/scripts/profile.sh"
cfg_home=$(tmp_dir)
export AI_CONFIG_HOME="$cfg_home"
mkdir -p "$cfg_home/profiles"
assert_true  "profile: none configured says so" grep -qx 'profile=none' <<< "$(cd "$(tmp_dir)" && "$PROFILE")"
assert_false "cloudflare: no profile, no share domain" "$CF" url some-page-0a1b2c3d
printf 'name = Robert Hallatt\norganization = Canadian Paediatric Society\nshare_domain = share.cps.ca   # work\n' > "$cfg_home/profiles/work.conf"
printf 'name = Robert Hallatt\norganization =\nshare_domain = share.example.org\n' > "$cfg_home/profiles/home.conf"
echo work > "$cfg_home/profile"
proj_dir=$(tmp_dir)
assert_true  "profile: machine default applies" grep -qx 'profile=work' <<< "$(cd "$proj_dir" && "$PROFILE")"
assert_true  "profile: value lookup strips comments" test "$(cd "$proj_dir" && "$PROFILE" share_domain)" = share.cps.ca
assert_true  "profile: empty value kept as empty" grep -qx 'organization=' <<< "$(AI_CONFIG_PROFILE=home "$PROFILE")"
mkdir -p "$proj_dir/sub"
printf '[options]\nstack = custom\nprofile = home  # side work\n' > "$proj_dir/ai-config.conf"
assert_true  "profile: nearest ai-config.conf wins over the machine default" \
  test "$(cd "$proj_dir/sub" && "$PROFILE" share_domain)" = share.example.org
assert_true  "profile: AI_CONFIG_PROFILE wins over ai-config.conf" \
  test "$(cd "$proj_dir" && AI_CONFIG_PROFILE=work "$PROFILE" share_domain)" = share.cps.ca
assert_true  "profile: unknown name reports the missing file" grep -q '^missing=' <<< "$(AI_CONFIG_PROFILE=nope "$PROFILE")"
assert_false "profile: a path in the name is refused" grep -q '^share_domain=' <<< "$(AI_CONFIG_PROFILE=../profiles/work "$PROFILE")"

# The folders map: everything under a folder uses its profile, the longest match wins, and a
# project's ai-config.conf that names no profile (only [remote], say) doesn't stop the search.
tree=$(tmp_dir)
mkdir -p "$tree/studio/client-a/site" "$tree/studio/homelab" "$tree/gig/forge/site-b"
printf 'name = R\nshare_domain = share.studio.example\n' > "$cfg_home/profiles/studio.conf"
printf 'name = R\nshare_domain = share.gig.example\n' > "$cfg_home/profiles/gig.conf"
printf '%s = studio\n%s = home   # nested: longest wins\n%s = gig\n' "$tree/studio" "$tree/studio/homelab" "$tree/gig" > "$cfg_home/folders"
printf '[remote]\nproduction = site-b-prod\n' > "$tree/gig/forge/site-b/ai-config.conf"
assert_true  "folders: a project under a mapped folder uses its profile" \
  test "$(cd "$tree/studio/client-a/site" && "$PROFILE" share_domain)" = share.studio.example
assert_true  "folders: the longest matching folder wins" \
  test "$(cd "$tree/studio/homelab" && "$PROFILE" share_domain)" = share.example.org
assert_true  "folders: an ai-config.conf without a profile doesn't stop the search" \
  test "$(cd "$tree/gig/forge/site-b" && "$PROFILE" share_domain)" = share.gig.example
assert_true  "folders: an unmapped folder falls back to the machine default" \
  grep -qx 'profile=work' <<< "$(cd "$(tmp_dir)" && "$PROFILE")"
printf '[options]\nprofile = work\n' > "$tree/gig/forge/site-b/ai-config.conf"
assert_true  "folders: a project's own profile beats the folder" \
  test "$(cd "$tree/gig/forge/site-b" && "$PROFILE" share_domain)" = share.cps.ca
CFCMD="$NOSLOP/scripts/cloudflare.sh"
assert_true  "cloudflare: each profile has its own config and Keychain entry" \
  grep -q "ai-config-cloudflare/gig/config" <<< "$(cd "$tree/gig/forge" && env -u CLOUDFLARE_CONFIG -u CLOUDFLARE_TOKEN_FILE -u CLOUDFLARE_KEYCHAIN_SERVICE "$CFCMD" config 2>&1)"
printf 'name = R\n' > "$cfg_home/profiles/cps.conf"
assert_true  "cloudflare: the cps profile keeps the original location" \
  grep -q "cps-cloudflare/config" <<< "$(cd "$(tmp_dir)" && AI_CONFIG_PROFILE=cps env -u CLOUDFLARE_CONFIG -u CLOUDFLARE_TOKEN_FILE -u CLOUDFLARE_KEYCHAIN_SERVICE "$CFCMD" config 2>&1)"
printf 'name = R\ncloudflare = studio\n' > "$cfg_home/profiles/gig.conf"
assert_true  "cloudflare: a profile can share another's Cloudflare setup" \
  grep -q "ai-config-cloudflare/studio/config" <<< "$(cd "$tree/gig" && env -u CLOUDFLARE_CONFIG -u CLOUDFLARE_TOKEN_FILE -u CLOUDFLARE_KEYCHAIN_SERVICE "$CFCMD" config 2>&1)"
rm -f "$cfg_home/folders"
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
record="$cfdir/pages/$name.json"
assert_true  "cloudflare: new records the page" test -f "$record"
# ls -l reads the same on macOS and Linux; `stat -f` means different things on the two.
assert_true  "cloudflare: the record is private" test "$(ls -l "$record" | cut -c1-10)" = "-rw-------"
assert_true  "cloudflare: the record keeps the folder and address" \
  jq -e --arg f "$(cd "$site" && pwd)" --arg a "https://share.cps.ca/$name/" '.folder == $f and .address == $a' "$record"
assert_true  "cloudflare: describe works offline from the record" \
  grep -q "^folder: *$(cd "$site" && pwd)$" <<< "$("$CF" describe "$name" 2>&1)"
assert_true  "cloudflare: describe says when Cloudflare can't be reached" \
  grep -q "can't reach Cloudflare" <<< "$("$CF" describe "$name" 2>&1)"
assert_true  "cloudflare: describe offers a new passcode when none is recorded" \
  grep -q "passcode: *not recorded" <<< "$("$CF" describe "$name" 2>&1)"
assert_false "cloudflare: passcode needs a deployed page" "$CF" passcode "$name"
passcodes=$(bash -c 'eval "$(sed -n "/^WORDS=/,/^}/p" "$1")"; for _ in 1 2 3 4 5; do make_passcode; echo; done' _ "$CF")
assert_true  "cloudflare: passcodes are three words and two digits" \
  test "$(grep -cE '^[a-z]+-[a-z]+-[a-z]+-[0-9]{2}$' <<< "$passcodes")" -eq 5
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

# humanizer: pinned through vendor/skills.conf (commit and SOURCE checked in test-design-skills.sh).
HUMANIZER="$SCRIPT_DIR/global-skills/humanizer"
assert_true  "humanizer: upstream licence kept (MIT notice)" grep -q 'Copyright (c) 2025 Siqi Chen' "$HUMANIZER/upstream/LICENSE"
assert_false "humanizer: no nested SKILL.md" test -e "$HUMANIZER/upstream/SKILL.md"

# link-global-skills.sh: links missing skills, never repoints for a project run, never
# replaces a real directory, and install mode repoints a link to another checkout.
# shellcheck source=scripts/link-global-skills.sh
source "$SCRIPT_DIR/scripts/link-global-skills.sh"
home=$(tmp_dir)
other_checkout=$(tmp_dir)
mkdir -p "$home/skills" "$other_checkout/humanizer" "$home/skills/noslop"
echo mine > "$home/skills/noslop/SKILL.md"
ln -s "$other_checkout/humanizer" "$home/skills/humanizer"
dry=$(tmp_dir)
link_global_skills "$SCRIPT_DIR" "$dry" true >/dev/null
assert_false "link: dry run writes nothing" test -e "$dry/skills"
out=$(link_global_skills "$SCRIPT_DIR" "$home")
assert_true  "link: a real directory is left alone" grep -qx mine "$home/skills/noslop/SKILL.md"
assert_true  "link: says why it left the directory" grep -q "Left ~/.claude/skills/noslop alone" <<< "$out"
assert_true  "link: project run doesn't repoint another checkout's link" _gs_links_to "$home/skills/humanizer" "$other_checkout/humanizer"
assert_true  "link: unlinked skills are listed" test "$(global_skills_unlinked "$SCRIPT_DIR" "$home" | tr '\n' ' ')" = "humanizer noslop "
link_global_skills "$SCRIPT_DIR" "$home" false true >/dev/null
assert_true  "link: install mode repoints the link" _gs_links_to "$home/skills/humanizer" "$HUMANIZER"
rm -rf "$home/skills/noslop"
ln -s "$home/gone" "$home/skills/noslop"
link_global_skills "$SCRIPT_DIR" "$home" >/dev/null
assert_true  "link: a broken link is replaced" _gs_links_to "$home/skills/noslop" "$NOSLOP"
assert_true  "link: silent when current" test -z "$(link_global_skills "$SCRIPT_DIR" "$home")"
assert_true  "link: nothing left unlinked" test -z "$(global_skills_unlinked "$SCRIPT_DIR" "$home")"
mkdir -p "$cfg_home/skills/mine" "$cfg_home/skills/noslop"
printf -- '---\nname: mine\ndescription: Private.\n---\n' > "$cfg_home/skills/mine/SKILL.md"
printf -- '---\nname: noslop\ndescription: Shadow.\n---\n' > "$cfg_home/skills/noslop/SKILL.md"
assert_true  "link: private skills are listed as unlinked" grep -qx mine <<< "$(global_skills_unlinked "$SCRIPT_DIR" "$home")"
link_global_skills "$SCRIPT_DIR" "$home" >/dev/null
assert_true  "link: a private skill is linked from the profiles repo" _gs_links_to "$home/skills/mine" "$cfg_home/skills/mine"
assert_true  "link: the repo's skill wins a name clash" _gs_links_to "$home/skills/noslop" "$NOSLOP"
rm -rf "$cfg_home/skills"

# setup-project.sh links them on a run, and AI_CONFIG_SKIP_GLOBAL_SKILLS=1 opts out.
proj=$(tmp_dir)
home2=$(tmp_dir)
AI_CONFIG_USER_SETTINGS=/nonexistent AI_CONFIG_CLAUDE_DIR="$home2" \
  "$SCRIPT_DIR/setup-project.sh" --stack=custom --project="$proj" --force --no-superpowers --skip-vscode >/dev/null 2>&1
assert_true  "setup: deploy links humanizer" _gs_links_to "$home2/skills/humanizer" "$HUMANIZER"
assert_true  "setup: deploy links noslop" _gs_links_to "$home2/skills/noslop" "$NOSLOP"
home3=$(tmp_dir)
AI_CONFIG_SKIP_GLOBAL_SKILLS=1 AI_CONFIG_USER_SETTINGS=/nonexistent AI_CONFIG_CLAUDE_DIR="$home3" \
  "$SCRIPT_DIR/setup-project.sh" --stack=custom --refresh --project="$proj" --force --no-superpowers --skip-vscode >/dev/null 2>&1
assert_false "setup: opt-out links nothing" test -e "$home3/skills/humanizer"
out=$(AI_CONFIG_USER_SETTINGS=/nonexistent AI_CONFIG_CLAUDE_DIR="$home3" "$SCRIPT_DIR/setup-project.sh" --stack=custom --doctor --project="$proj" 2>&1)
assert_true  "doctor: warns about unlinked global skills" grep -q "Global skill(s) not linked to this repo: humanizer noslop" <<< "$out"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
