#!/usr/bin/env bash
# test-cms-intelligence.sh — template map (ExpressionEngine / Craft / Sage), php-lsp enablement,
# the required-tool preflight, and the --doctor health check.
#
# Usage: ./test-cms-intelligence.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
MAP="$SCRIPT_DIR/projects/common/okf/template-map.sh"
CHECKER="$SCRIPT_DIR/projects/common/okf/okf-check.sh"
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

run() { local d="$1"; shift; "$SETUP_SCRIPT" --project="$d" --skip-vscode --no-superpowers "$@" >/dev/null 2>&1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
backup_count() { find "$1/.claude/ai-config/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

# ============================================================================
# Fixtures
# ============================================================================

make_ee() {
  local d t
  d=$(tmp_dir)
  t="$d/system/user/templates"
  mkdir -p "$d/system/ee" "$t/site.group" "$t/layouts.group" "$t/_partials"
  cat > "$t/site.group/index.html" <<'EOF'
{layout="layouts/_main"}
{embed="site/_card" title="Hello"}
{embed="site/_missing"}
{exp:channel:entries
    channel="news|blog"
    limit="3"}
  <h2>{title}</h2>
{/exp:channel:entries}
{exp:stash:get name="nav"}
{p_footer}
EOF
  echo '<main>{layout:contents}</main>' > "$t/layouts.group/_main.html"
  echo '<div>{embed:title}</div>' > "$t/site.group/_card.html"
  echo '<footer></footer>' > "$t/_partials/p_footer.html"
  echo "$d"
}

make_craft() {
  local d
  d=$(tmp_dir)
  touch "$d/craft"
  echo '{"require":{"craftcms/cms":"^5.0"}}' > "$d/composer.json"
  mkdir -p "$d/templates/_layouts" "$d/templates/news" "$d/templates/_partials" "$d/config/project/sections"
  echo '<html>{% block content %}{% endblock %}</html>' > "$d/templates/_layouts/base.twig"
  cat > "$d/templates/news/_entry.twig" <<'EOF'
{% extends "_layouts/base" %}
{% block content %}
  {% include '_partials/card' with { entry: entry } %}
  {{ include("_partials/meta") }}
  {% set related = craft.entries
       .section('news')
       .limit(3)
       .all() %}
{% endblock %}
EOF
  echo '<article></article>' > "$d/templates/_partials/card.twig"
  cat > "$d/config/project/sections/news--0f1e.yaml" <<'EOF'
handle: news
name: News
siteSettings:
  1a2b3c:
    hasUrls: true
    template: news/_entry
    uriFormat: 'news/{slug}'
type: channel
EOF
  echo "$d"
}

make_sage() {
  local d v
  d=$(tmp_dir)
  v="$d/web/app/themes/sage/resources/views"
  mkdir -p "$d/web/app/plugins" "$v/layouts" "$v/partials" "$v/components"
  cat > "$v/index.blade.php" <<'EOF'
@extends('layouts.app')

@section('content')
  @include('partials.header')
  <x-alert type="info">Hi</x-alert>
  @includeWhen($showFooter, 'partials.footer')
@endsection
EOF
  echo "<body>@yield('content')</body>" > "$v/layouts/app.blade.php"
  echo '<header></header>' > "$v/partials/header.blade.php"
  echo '<div class="alert"></div>' > "$v/components/alert.blade.php"
  echo "$d"
}

# ============================================================================
echo -e "\n${CYAN}=== template-map.sh ===${NC}\n"
# ============================================================================

ee=$(make_ee)
out=$(bash "$MAP" "$ee")
assert_true "EE: template row" contains "$out" '| `site/index` |'
assert_true "EE: layout" contains "$out" 'layout `layouts/_main`'
assert_true "EE: embed resolved" contains "$out" 'embed `site/_card`;'
assert_true "EE: missing embed marked ?" contains "$out" 'embed `site/_missing` ?'
assert_true "EE: partial" contains "$out" 'partial `_partials/p_footer`'
assert_true "EE: multi-line channel tag" contains "$out" 'channels: blog, news'
assert_true "EE: add-on tags" contains "$out" 'add-ons: stash'
assert_true "EE: reverse index" contains "$out" '- `site/_card` ← `site/index`'

craft=$(make_craft)
out=$(bash "$MAP" "$craft")
assert_true "Craft: extends" contains "$out" 'extends `_layouts/base`'
assert_true "Craft: include tag" contains "$out" 'include `_partials/card`'
assert_true "Craft: include() function, missing target" contains "$out" 'include `_partials/meta` ?'
assert_true "Craft: multi-line section query" contains "$out" 'sections: news'
assert_true "Craft: section route from project config" contains "$out" '| `news` | `news/_entry` |'

sage=$(make_sage)
out=$(bash "$MAP" "$sage")
assert_true "Sage: @extends dot notation" contains "$out" 'extends `layouts/app`'
assert_true "Sage: @include" contains "$out" 'include `partials/header`'
assert_true "Sage: @includeWhen, missing target" contains "$out" 'include `partials/footer` ?'
assert_true "Sage: <x-component>" contains "$out" 'component `components/alert`'
assert_false "Sage: @section is not a Craft section" contains "$out" 'sections:'

empty=$(tmp_dir)
assert_eq "no templates → no output" "" "$(bash "$MAP" "$empty")"
vend=$(tmp_dir)
mkdir -p "$vend/vendor/pkg/system/user/templates/x.group"
echo '{embed="x/y"}' > "$vend/vendor/pkg/system/user/templates/x.group/a.html"
assert_eq "vendor templates ignored" "" "$(bash "$MAP" "$vend")"

# ============================================================================
echo -e "\n${CYAN}=== Template map in the OKF bundle ===${NC}\n"
# ============================================================================

ee=$(make_ee)
MAP_FILE="$ee/.okf/architecture/templates.md"
run "$ee" --force --okf-memory
assert_true "EE --okf-memory writes .okf/architecture/templates.md" test -f "$MAP_FILE"
assert_true "bundle with template map is conformant" bash "$CHECKER" "$ee/.okf"
assert_eq "index.md links the map once" "1" "$(grep -c '/architecture/templates.md' "$ee/.okf/index.md")"

map_sha=$(sha "$MAP_FILE"); backups=$(backup_count "$ee")
run "$ee" --refresh
assert_eq "unchanged templates → map untouched (timestamp ignored)" "$map_sha" "$(sha "$MAP_FILE")"
assert_eq "unchanged templates → no new backup" "$backups" "$(backup_count "$ee")"

echo '{embed="site/_new"}' >> "$ee/system/user/templates/site.group/index.html"
run "$ee" --refresh
assert_true "template change → map updated" grep -qF 'embed `site/_new` ?' "$MAP_FILE"
assert_true "previous map backed up" test -n "$(find "$ee/.claude/ai-config/backups" -path '*/.okf/architecture/templates.md' 2>/dev/null)"
assert_eq "index.md still links the map once" "1" "$(grep -c '/architecture/templates.md' "$ee/.okf/index.md")"

echo "KEEP-MAP-NOTE" >> "$MAP_FILE"
echo '{embed="site/_newer"}' >> "$ee/system/user/templates/site.group/index.html"
run "$ee" --refresh
assert_true "edited map kept" grep -q KEEP-MAP-NOTE "$MAP_FILE"
assert_true "new map staged for review" grep -qF 'site/_newer' "$ee/.claude/ai-config/pending/.okf/architecture/templates.md"

ee2=$(make_ee)
run "$ee2" --force
assert_false "no --okf-memory → no template map" test -e "$ee2/.okf"

next=$(tmp_dir)
touch "$next/next.config.js"; echo '{"dependencies":{"next":"14","react":"18"}}' > "$next/package.json"
run "$next" --force --okf-memory
assert_false "JS stack → no template map" test -e "$next/.okf/architecture/templates.md"

# ============================================================================
echo -e "\n${CYAN}=== php-lsp ===${NC}\n"
# ============================================================================

bin=$(tmp_dir)
export FAKE_CLAUDE_LOG="$bin/claude.log"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/intelephense"
cat > "$bin/claude" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CLAUDE_LOG"
if [[ "$1 $2" == "plugin install" ]]; then
  f="$PWD/.claude/settings.local.json"
  [[ -f "$f" ]] || echo '{}' > "$f"
  jq --arg p "$3" '.enabledPlugins[$p] = true' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi
[[ "$1 $2" == "mcp get" ]] && exit 1
exit 0
SH
chmod +x "$bin/intelephense" "$bin/claude"
nobin=$(tmp_dir)
cp "$bin/claude" "$nobin/claude"
installs() { if [[ -f "$FAKE_CLAUDE_LOG" ]]; then grep -c '^plugin install php-lsp@claude-plugins-official --scope local$' "$FAKE_CLAUDE_LOG"; else echo 0; fi; }

wp=$(tmp_dir); mkdir -p "$wp/wp-content/themes"
PATH="$bin:$PATH" run "$wp" --force
assert_eq "WordPress + intelephense → php-lsp installed at local scope" "1" "$(installs)"
assert_eq "enabledPlugins recorded in settings.local.json" "true" \
  "$(jq -r '.enabledPlugins["php-lsp@claude-plugins-official"]' "$wp/.claude/settings.local.json")"
PATH="$bin:$PATH" run "$wp" --refresh
assert_eq "already enabled → not installed again" "1" "$(installs)"

rm -f "$FAKE_CLAUDE_LOG"
wp2=$(tmp_dir); mkdir -p "$wp2/wp-content" "$wp2/.claude"
echo '{"enabledPlugins":{"php-lsp@claude-plugins-official":false}}' > "$wp2/.claude/settings.local.json"
PATH="$bin:$PATH" run "$wp2" --force
assert_eq "explicit false in project settings respected" "0|false" \
  "$(installs)|$(jq -r '.enabledPlugins["php-lsp@claude-plugins-official"]' "$wp2/.claude/settings.local.json")"

wp3=$(tmp_dir); mkdir -p "$wp3/wp-content"
PATH="$nobin:$PATH" run "$wp3" --force
assert_eq "no intelephense → nothing installed" "0" "$(installs)"

user=$(tmp_dir); echo '{"enabledPlugins":{"php-lsp@claude-plugins-official":true}}' > "$user/settings.json"
wp4=$(tmp_dir); mkdir -p "$wp4/wp-content"
AI_CONFIG_USER_SETTINGS="$user/settings.json" PATH="$bin:$PATH" run "$wp4" --force
assert_eq "enabled in user settings → not installed per project" "0" "$(installs)"

next2=$(tmp_dir)
touch "$next2/next.config.js"; echo '{"dependencies":{"next":"14","react":"18"}}' > "$next2/package.json"
PATH="$bin:$PATH" run "$next2" --force
assert_eq "JS stack → php-lsp never installed" "0" "$(installs)"

# ============================================================================
echo -e "\n${CYAN}=== Preflight and --doctor ===${NC}\n"
# ============================================================================

nuxt=$(tmp_dir)
touch "$nuxt/nuxt.config.ts"; echo '{"dependencies":{"nuxt":"3"}}' > "$nuxt/package.json"
run "$nuxt" --force
assert_eq "healthy deploy exits 0" "0" "$?"
out=$("$SETUP_SCRIPT" --project="$nuxt" --doctor 2>&1); status=$?
assert_eq "--doctor on a healthy project exits 0" "0" "$status"
assert_true "--doctor runs a live safety-hook test" contains "$out" "blocks a test secret read"

chmod -x "$nuxt/.claude/hooks/safety-guard.sh"
out=$("$SETUP_SCRIPT" --project="$nuxt" --doctor 2>&1); status=$?
assert_eq "--doctor fails when the hook isn't executable" "1" "$status"
assert_true "--doctor names the broken hook" contains "$out" "safety-guard.sh missing or not executable"
chmod +x "$nuxt/.claude/hooks/safety-guard.sh"

jq '.permissions.deny = []' "$nuxt/.claude/settings.local.json" > "$nuxt/s.json" && mv "$nuxt/s.json" "$nuxt/.claude/settings.local.json"
out=$("$SETUP_SCRIPT" --project="$nuxt" --doctor 2>&1); status=$?
assert_eq "--doctor fails when deny rules are missing" "1" "$status"
assert_true "--doctor reports the missing rules" contains "$out" "rule(s) missing from settings.local.json"
snapshot=$(cd "$nuxt" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256)
"$SETUP_SCRIPT" --project="$nuxt" --doctor >/dev/null 2>&1
assert_eq "--doctor changes nothing" "$snapshot" "$(cd "$nuxt" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256)"

farm=$(tmp_dir)
for dir in /usr/bin /bin /usr/sbin /sbin; do
  for tool in "$dir"/*; do
    name="${tool##*/}"
    [[ "$name" == "jq" || -e "$farm/$name" ]] && continue
    ln -s "$tool" "$farm/$name"
  done
done
bare=$(tmp_dir)
touch "$bare/nuxt.config.ts"; echo '{"dependencies":{"nuxt":"3"}}' > "$bare/package.json"
out=$(PATH="$farm" /bin/bash "$SETUP_SCRIPT" --project="$bare" --force --skip-vscode --no-superpowers 2>&1); status=$?
assert_eq "missing jq → run exits 1" "1" "$status"
assert_true "missing jq → named in the error" contains "$out" "Missing required tools: jq"
assert_false "missing jq → nothing written" test -e "$bare/.claude"

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
