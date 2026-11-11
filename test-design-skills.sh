#!/usr/bin/env bash
# test-design-skills.sh — vendor/skills.conf, scripts/vendor-skills.sh, and how setup-project.sh
# deploys the pinned design skills per project (JS stacks by default, CMS opt-in, GSAP gated).
#
# Usage: ./test-design-skills.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/setup-project.sh"
VENDOR="$SCRIPT_DIR/scripts/vendor-skills.sh"
CONF="$SCRIPT_DIR/vendor/skills.conf"
export AI_CONFIG_SKIP_GLOBAL_SKILLS=1 AI_CONFIG_USER_SETTINGS=/nonexistent
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

conf_rows() { awk '!/^[[:space:]]*(#|$)/' "$CONF"; }
run_setup() { "$SETUP" --force --no-superpowers --skip-vscode "$@" >/dev/null 2>&1; }

# --- The committed copies match the manifest ---------------------------------
assert_true "conf: every commit is a full SHA" test -z "$(conf_rows | awk '$4 !~ /^[0-9a-f]{40}$/')"
while IFS= read -r name; do
  case "$(conf_rows | awk -v n="$name" '$1 == n { print $2; exit }')" in
    global) dir="$SCRIPT_DIR/global-skills/$name" ;;
    *)      dir="$SCRIPT_DIR/design-skills/$name" ;;
  esac
  assert_true "$name: SKILL.md names the skill" grep -qx "name: $name" "$dir/SKILL.md"
  assert_true "$name: SOURCE records the pinned commit" \
    grep -qx "commit=$(conf_rows | awk -v n="$name" '$1 == n { print $4; exit }')" "$dir/upstream/SOURCE"
  assert_false "$name: no nested SKILL.md" bash -c 'find "$1" -mindepth 2 -name SKILL.md | grep -q .' _ "$dir"
  if [[ -f "$SCRIPT_DIR/vendor/patches/$name.patch" ]]; then
    assert_true "$name: SOURCE records its patch" grep -qx "patch=vendor/patches/$name.patch" "$dir/upstream/SOURCE"
  fi
done < <(conf_rows | awk '!seen[$1]++ { print $1 }')

# Vetting decisions the patches carry.
assert_false "gsap: no 'recommend GSAP' left in any skill" grep -qi 'recommend GSAP' "$SCRIPT_DIR"/design-skills/gsap-*/SKILL.md
assert_false "web-design-guidelines: never fetches its rules" grep -q 'raw.githubusercontent.com' "$SCRIPT_DIR/design-skills/web-design-guidelines/SKILL.md"
assert_true  "web-design-guidelines: rules pinned beside it" test -s "$SCRIPT_DIR/design-skills/web-design-guidelines/guidelines.md"
assert_false "impeccable: no engine binary vendored" test -e "$SCRIPT_DIR/design-skills/impeccable/scripts/bin"
assert_false "impeccable: no hooks file vendored" bash -c 'find "$1" -name hooks.json | grep -q .' _ "$SCRIPT_DIR/design-skills/impeccable"
assert_true  "impeccable: launcher is executable" test -x "$SCRIPT_DIR/design-skills/impeccable/scripts/impeccable"

# --- vendor-skills.sh against a local repo (no network) ----------------------
up=$(tmp_dir)
git -C "$up" init -q
mkdir -p "$up/skills/demo"
printf -- '---\nname: demo\ndescription: Demo. Recommend Demo always.\n---\n\nBody one.\n' > "$up/skills/demo/SKILL.md"
echo "MIT demo" > "$up/LICENSE"
git -C "$up" add -A && git -C "$up" -c user.name=t -c user.email=t@t commit -qm one
c1=$(git -C "$up" rev-parse HEAD)
out=$(tmp_dir)
mkdir -p "$out/vendor/patches"
printf 'demo design:gsap file://%s %s skills/demo\n' "$up" "$c1" > "$out/vendor/skills.conf"
cat > "$out/vendor/patches/demo.patch" <<'EOF'
--- a/SKILL.md
+++ b/SKILL.md
@@ -1,6 +1,6 @@
 ---
 name: demo
-description: Demo. Recommend Demo always.
+description: Demo.
 ---

 Body one.
EOF
venv() { VENDOR_SKILLS_CONF="$out/vendor/skills.conf" VENDOR_SKILLS_PATCHES="$out/vendor/patches" VENDOR_SKILLS_OUT="$out" "$VENDOR" "$@"; }
assert_true  "vendor: fetch builds the skill" venv --fetch demo
assert_true  "vendor: design tier lands in design-skills/" test -f "$out/design-skills/demo/SKILL.md"
assert_true  "vendor: patch applied" grep -qx 'description: Demo.' "$out/design-skills/demo/SKILL.md"
assert_true  "vendor: licence kept" grep -qx 'MIT demo' "$out/design-skills/demo/upstream/LICENSE"
assert_false "vendor: no patch leftovers" bash -c 'find "$1" -name "*.orig" -o -name "*.rej" | grep -q .' _ "$out/design-skills/demo"
printf -- '---\nname: demo\ndescription: Changed upstream.\n---\n\nBody two.\n' > "$up/skills/demo/SKILL.md"
git -C "$up" -c user.name=t -c user.email=t@t commit -qam two
assert_false "vendor: bump stops when the patch no longer applies" venv --bump demo
assert_true  "vendor: failed bump keeps the old copy" grep -qx 'Body one.' "$out/design-skills/demo/SKILL.md"
rm "$out/vendor/patches/demo.patch"
assert_true  "vendor: bump without a patch succeeds" venv --bump demo
assert_true  "vendor: bump records the new commit" grep -q "$(git -C "$up" rev-parse HEAD)" "$out/vendor/skills.conf"
assert_true  "vendor: bump rebuilt the copy" grep -qx 'Body two.' "$out/design-skills/demo/SKILL.md"
assert_false "vendor: unknown skill fails" venv --fetch nope

# --- Deployment -----------------------------------------------------------------
next=$(tmp_dir)
echo '{"dependencies":{"next":"14.2.0","react":"18.3.1","gsap":"3.12.5"}}' > "$next/package.json"
run_setup --stack=nextjs --project="$next"
assert_true  "nextjs: impeccable deployed" test -f "$next/.claude/skills/impeccable/SKILL.md"
assert_true  "nextjs: impeccable agents go to .claude/agents" test -f "$next/.claude/agents/impeccable-documenter.md"
assert_false "nextjs: agents folder not left inside the skill" test -e "$next/.claude/skills/impeccable/agents"
assert_true  "nextjs: web-design-guidelines deployed" test -f "$next/.claude/skills/web-design-guidelines/guidelines.md"
assert_true  "nextjs: gsap-core deployed (gsap detected)" test -f "$next/.claude/skills/gsap-core/SKILL.md"
assert_true  "nextjs: gsap-react deployed (gsap + react)" test -f "$next/.claude/skills/gsap-react/SKILL.md"
assert_false "nextjs: gsap-frameworks skipped (no vue/svelte)" test -e "$next/.claude/skills/gsap-frameworks"
assert_true  "nextjs: impeccable telemetry off" test "$(jq -r '.env.IMPECCABLE_NO_TELEMETRY' "$next/.claude/settings.local.json")" = 1
assert_true  "nextjs: launcher keeps its execute bit" test -x "$next/.claude/skills/impeccable/scripts/impeccable"
assert_false "nextjs: no impeccable hook registered" grep -q 'impeccable' <<< "$(jq -c '.hooks // {}' "$next/.claude/settings.local.json")"

plain=$(tmp_dir)
echo '{"dependencies":{"next":"14.2.0","react":"18.3.1"}}' > "$plain/package.json"
run_setup --stack=nextjs --project="$plain"
assert_false "no gsap: no GSAP skills" bash -c 'ls -d "$1"/.claude/skills/gsap-* 2>/dev/null | grep -q .' _ "$plain"

ee=$(tmp_dir)
run_setup --stack=expressionengine --project="$ee"
assert_false "ee: no design skills by default" test -e "$ee/.claude/skills/impeccable"
assert_false "ee: no design-system rule by default" test -e "$ee/.claude/rules/design-system.md"
run_setup --stack=expressionengine --project="$ee" --refresh --design-skills
assert_true  "ee --design-skills: impeccable on refresh" test -f "$ee/.claude/skills/impeccable/SKILL.md"
assert_true  "ee --design-skills: design-system rule" test -f "$ee/.claude/rules/design-system.md"

ee2=$(tmp_dir)
printf '[options]\nstack = expressionengine\ndesign-skills = true\n' > "$ee2/ai-config.conf"
run_setup --project="$ee2"
assert_true  "policy design-skills = true: deployed" test -f "$ee2/.claude/skills/web-design-guidelines/SKILL.md"
"$SETUP" --project="$ee2" --save-policy >/dev/null 2>&1
assert_true  "save-policy keeps design-skills" grep -qx 'design-skills = true' "$ee2/ai-config.conf"

off=$(tmp_dir)
echo '{"dependencies":{"next":"14.2.0","react":"18.3.1"}}' > "$off/package.json"
run_setup --stack=nextjs --project="$off" --no-design-skills
assert_false "--no-design-skills: nothing deployed" test -e "$off/.claude/skills/impeccable"

# A skill removed on purpose stays removed on refresh; an edited one is kept.
rm -rf "$next/.claude/skills/gsap-utils"
printf "\nmy note\n" >> "$next/.claude/skills/impeccable/SKILL.md"
run_setup --stack=nextjs --project="$next" --refresh
assert_false "refresh: removed skill stays removed" test -e "$next/.claude/skills/gsap-utils"
assert_true  "refresh: edited skill kept" grep -qx 'my note' "$next/.claude/skills/impeccable/SKILL.md"
assert_true  "refresh: new version staged" test -f "$next/.claude/ai-config/pending/.claude/skills/impeccable/SKILL.md"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
