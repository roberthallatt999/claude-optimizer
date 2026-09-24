#!/usr/bin/env bash
# test-frontend-detection.sh — projects/common/detect-frontend.sh and how setup-project.sh uses it:
# scan summary, library references, and the Front-End Stack block in CLAUDE.md.
#
# Usage: ./test-frontend-detection.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
DETECT="$SCRIPT_DIR/projects/common/detect-frontend.sh"
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

# lib <records> <id>  →  "category|version|evidence"  (empty when not detected)
lib() { printf '%s\n' "$1" | awk -F'\t' -v id="$2" '$1 == "lib" && $2 == id { print $4 "|" $5 "|" $6; exit }'; }
# custom <records> <js|css>  →  "count|folder"
custom() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == "custom" && $2 == k { print $3 "|" $4; exit }'; }

run() { local d="$1"; shift; "$SETUP_SCRIPT" --project="$d" --skip-vscode --no-superpowers "$@" 2>&1; }
backup_count() { find "$1/.claude/ai-config/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

# ============================================================================
# Fixtures
# ============================================================================

make_ee_cdn() {
  local d t; d=$(tmp_dir); t="$d/system/user/templates"
  mkdir -p "$d/system/ee" "$t/site.group" "$d/public/assets/js" "$d/public/themes/ee/cp/js" "$d/system/user/addons/slider/js"
  cat > "$t/site.group/index.html" <<'EOF'
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css">
<script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
<div x-data="{ open: false }"></div>
EOF
  echo 'document.body.classList.add("js");' > "$d/public/assets/js/site.js"
  echo 'export function menu() {}' > "$d/public/assets/js/menu.js"
  echo '/* EE control panel */' > "$d/public/themes/ee/cp/js/jquery-3.4.1.min.js"
  echo '/* third-party add-on */' > "$d/system/user/addons/slider/js/swiper-bundle.min.js"
  echo "$d"
}

make_wp_theme() {
  local d th; d=$(tmp_dir); th="$d/wp-content/themes/acme"
  mkdir -p "$th/src/scss" "$th/assets/js" "$d/wp-content/plugins/slider/js" "$d/wp-includes/js/jquery"
  echo '{"name":"acme","devDependencies":{"sass":"^1.69.0","foundation-sites":"~6.8.1","webpack":"^5.89.0"}}' > "$th/package.json"
  cat > "$th/functions.php" <<'EOF'
<?php
wp_enqueue_script('acme', get_template_directory_uri() . '/assets/js/app.js', array('jquery'), '1.0', true);
EOF
  echo '.site { color: red; }' > "$th/src/scss/main.scss"
  echo 'jQuery(function ($) {});' > "$th/assets/js/app.js"
  echo '/* plugin */' > "$d/wp-content/plugins/slider/js/slick.min.js"
  echo '/* core */' > "$d/wp-includes/js/jquery/jquery.min.js"
  echo "$d"
}

make_sage() {
  local d th; d=$(tmp_dir); th="$d/web/app/themes/sage"
  mkdir -p "$d/web/app/plugins" "$th/resources/scripts" "$th/resources/views"
  echo '{"devDependencies":{"@roots/bud":"6.16.1","tailwindcss":"3.4.0"},"dependencies":{"alpinejs":"^3.13.3"}}' > "$th/package.json"
  echo 'export default async (bud) => {}' > "$th/bud.config.js"
  echo 'import Alpine from "alpinejs";' > "$th/resources/scripts/app.js"
  echo '<div class="p-4">@yield("content")</div>' > "$th/resources/views/app.blade.php"
  echo "$d"
}

make_craft_htmx() {
  local d; d=$(tmp_dir)
  touch "$d/craft"; echo '{"require":{"craftcms/cms":"^5.0"}}' > "$d/composer.json"
  mkdir -p "$d/templates/_layouts" "$d/web/cpresources/abc123" "$d/src/css"
  cat > "$d/templates/_layouts/base.twig" <<'EOF'
<script src="https://unpkg.com/htmx.org@1.9.10"></script>
<button hx-get="/search">Search</button>
EOF
  echo '/* Craft control panel */' > "$d/web/cpresources/abc123/jquery.js"
  echo 'body { margin: 0; }' > "$d/src/css/site.css"
  echo "$d"
}

# ============================================================================
echo -e "\n${CYAN}=== detect-frontend.sh ===${NC}\n"
# ============================================================================

out=$(bash "$DETECT" "$(make_ee_cdn)")
assert_eq "EE: Bootstrap from CDN with version" "css|5.3.2|CDN in system/user/templates/site.group/index.html" "$(lib "$out" bootstrap)"
assert_eq "EE: jQuery from CDN with version" "js-lib|3.7.1|CDN in system/user/templates/site.group/index.html" "$(lib "$out" jquery)"
assert_eq "EE: Alpine from x-data markup" "js-framework||markup in system/user/templates/site.group/index.html" "$(lib "$out" alpine)"
assert_eq "EE: control-panel and add-on libraries ignored" "|" "$(lib "$out" swiper)|$(printf '%s\n' "$out" | grep -c 'jquery-3.4.1' | sed 's/^0$//')"
assert_eq "EE: first-party scripts counted" "2|public/assets/js" "$(custom "$out" js)"

out=$(bash "$DETECT" "$(make_wp_theme)")
assert_eq "WP: Foundation from theme package.json" "css|6.8.1|wp-content/themes/acme/package.json" "$(lib "$out" foundation)"
assert_eq "WP: Sass from theme package.json" "css-tool|1.69.0|wp-content/themes/acme/package.json" "$(lib "$out" scss)"
assert_eq "WP: webpack build tool" "build|5.89.0|wp-content/themes/acme/package.json" "$(lib "$out" webpack)"
assert_eq "WP: jQuery from wp_enqueue dependency" "js-lib||enqueued in wp-content/themes/acme/functions.php" "$(lib "$out" jquery)"
assert_eq "WP: plugin and core libraries ignored" "" "$(lib "$out" slick)"
assert_eq "WP: first-party stylesheet counted" "1|wp-content/themes/acme/src/scss" "$(custom "$out" css)"

out=$(bash "$DETECT" "$(make_sage)")
assert_eq "Sage: Bud build tool" "build|6.16.1|web/app/themes/sage/package.json" "$(lib "$out" bud)"
assert_eq "Sage: Tailwind" "css|3.4.0|web/app/themes/sage/package.json" "$(lib "$out" tailwind)"
assert_eq "Sage: Alpine" "js-framework|3.13.3|web/app/themes/sage/package.json" "$(lib "$out" alpine)"
assert_eq "Sage: bud.config.js is not first-party code" "1|web/app/themes/sage/resources/scripts" "$(custom "$out" js)"

out=$(bash "$DETECT" "$(make_craft_htmx)")
assert_eq "Craft: htmx from CDN with version" "js-framework|1.9.10|CDN in templates/_layouts/base.twig" "$(lib "$out" htmx)"
assert_eq "Craft: cpresources jQuery ignored" "" "$(lib "$out" jquery)"
assert_eq "Craft: custom CSS counted" "1|src/css" "$(custom "$out" css)"

d=$(tmp_dir)
echo '{"dependencies":{"react":"18.2.0","next":"14.1.0","@mui/material":"^5.15.0","styled-components":"^6.1.0"},"devDependencies":{"typescript":"^5.3.3"}}' > "$d/package.json"
echo '{}' > "$d/tsconfig.json"
out=$(bash "$DETECT" "$d")
assert_eq "React" "js-framework|18.2.0|package.json" "$(lib "$out" react)"
assert_eq "Material UI" "ui|5.15.0|package.json" "$(lib "$out" mui)"
assert_eq "styled-components" "css-tool|6.1.0|package.json" "$(lib "$out" styled-components)"
assert_eq "TypeScript" "lang|5.3.3|package.json" "$(lib "$out" typescript)"

d=$(tmp_dir)
mkdir -p "$d/assets/js/vendor" "$d/assets/css"
echo 'console.log(1);' > "$d/assets/js/app.js"
echo 'body{}' > "$d/assets/css/app.css"
echo '/* some library */' > "$d/assets/js/vendor/lib.min.js"
out=$(bash "$DETECT" "$d")
assert_eq "custom only: no libraries" "0" "$(printf '%s\n' "$out" | grep -c '^lib')"
assert_eq "custom only: minified files not counted as first-party" "1|assets/js" "$(custom "$out" js)"
assert_eq "custom only: CSS counted" "1|assets/css" "$(custom "$out" css)"

d=$(tmp_dir)
mkdir -p "$d/assets/js"
echo '/* jQuery */' > "$d/assets/js/jquery-3.6.0.min.js"
echo '$(function () {});' > "$d/assets/js/main.js"
out=$(bash "$DETECT" "$d")
assert_eq "vendored jQuery file with version" "js-lib|3.6.0|assets/js/jquery-3.6.0.min.js" "$(lib "$out" jquery)"
assert_eq "vendored library not counted as first-party" "1|assets/js" "$(custom "$out" js)"

# Installed version (node_modules beside the package.json) wins over the declared range
d=$(tmp_dir)
mkdir -p "$d/theme/node_modules/tailwindcss" "$d/theme/node_modules/alpinejs/node_modules/nested"
echo '{"devDependencies":{"tailwindcss":"^3.4.1","vite":"^5.1.0"},"dependencies":{"alpinejs":"^3.13.5"}}' > "$d/theme/package.json"
echo '{"name":"tailwindcss","version":"3.4.19"}' > "$d/theme/node_modules/tailwindcss/package.json"
echo '{"name":"alpinejs","version":"3.16.2"}' > "$d/theme/node_modules/alpinejs/package.json"
out=$(bash "$DETECT" "$d")
assert_eq "installed Tailwind version beats range" "css|3.4.19|theme/package.json" "$(lib "$out" tailwind)"
assert_eq "installed Alpine version beats range" "js-framework|3.16.2|theme/package.json" "$(lib "$out" alpine)"
assert_eq "no node_modules entry → range version" "build|5.1.0|theme/package.json" "$(lib "$out" vite)"

assert_eq "empty project → no output" "" "$(bash "$DETECT" "$(tmp_dir)")"

# ============================================================================
echo -e "\n${CYAN}=== setup-project.sh ===${NC}\n"
# ============================================================================

ee=$(make_ee_cdn)
out=$(run "$ee" --force)
assert_true "scan summary names Bootstrap with version" contains "$out" "CSS: Bootstrap 5.3.2 (CDN in system/user/templates/site.group/index.html)"
assert_true "scan summary names jQuery and Alpine" contains "$out" "JavaScript: Alpine.js (markup in"
assert_false "old per-framework lines are gone" contains "$out" "No Foundation detected"
assert_eq "Front-End Stack block present once" "1" "$(grep -c '<!-- BEGIN FRONTEND STACK' "$ee/CLAUDE.md")"
assert_true "block lists Bootstrap" grep -qF -- "- **CSS:** Bootstrap 5.3.2" "$ee/CLAUDE.md"
assert_true "block lists jQuery with version" grep -qF "jQuery 3.7.1" "$ee/CLAUDE.md"
assert_true "Bootstrap library reference added" grep -qF '.claude/libraries/bootstrap.md' "$ee/CLAUDE.md"
assert_true "jQuery library reference added" grep -qF '.claude/libraries/jquery.md' "$ee/CLAUDE.md"
sha=$(shasum -a 256 "$ee/CLAUDE.md" | cut -d' ' -f1); backups=$(backup_count "$ee")
run "$ee" --refresh >/dev/null
assert_eq "unchanged stack → CLAUDE.md untouched on refresh" "$sha" "$(shasum -a 256 "$ee/CLAUDE.md" | cut -d' ' -f1)"
assert_eq "unchanged stack → no new backup" "$backups" "$(backup_count "$ee")"
echo '<script src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js"></script>' >> "$ee/system/user/templates/site.group/index.html"
run "$ee" --refresh >/dev/null
assert_true "new library → block updated on refresh" grep -qF "GSAP 3.12.5" "$ee/CLAUDE.md"
assert_eq "block still present once after update" "1" "$(grep -c '<!-- BEGIN FRONTEND STACK' "$ee/CLAUDE.md")"

d=$(tmp_dir)
mkdir -p "$d/system/ee" "$d/system/user/templates/site.group" "$d/public/assets/js" "$d/public/assets/css"
echo '<p>{title}</p>' > "$d/system/user/templates/site.group/index.html"
echo 'console.log(1);' > "$d/public/assets/js/app.js"
echo 'body{}' > "$d/public/assets/css/site.css"
out=$(run "$d" --force)
assert_true "custom JS reported plainly" contains "$out" "JavaScript: custom JavaScript, no framework detected (1 file(s), mainly in public/assets/js/)"
assert_true "custom CSS reported plainly" contains "$out" "CSS: custom CSS, no framework detected (1 file(s), mainly in public/assets/css/)"
assert_true "block says custom JavaScript" grep -qF "custom JavaScript, no framework detected" "$d/CLAUDE.md"
assert_true "vanilla-js library reference kept for custom JS" grep -qF '.claude/libraries/vanilla-js.md' "$d/CLAUDE.md"

sage=$(make_sage)
run "$sage" --force >/dev/null
assert_true "Tailwind in a theme folder still deploys the Tailwind rule" test -f "$sage/.claude/rules/tailwind-css.md"

empty=$(tmp_dir)
mkdir -p "$empty/system/ee" "$empty/system/user/templates/site.group"
echo '<p>{title}</p>' > "$empty/system/user/templates/site.group/index.html"
out=$(run "$empty" --force)
assert_true "no front-end code → says so" contains "$out" "No front-end CSS or JavaScript found"
assert_eq "no front-end code → no Front-End Stack block" "0" "$(grep -c '<!-- BEGIN FRONTEND STACK' "$empty/CLAUDE.md")"

printf '# KEEP\n' | cat - "$ee/CLAUDE.md" > "$ee/c.md" && mv "$ee/c.md" "$ee/CLAUDE.md"
run "$ee" --uninstall >/dev/null
assert_eq "uninstall strips the Front-End Stack block" "0" "$(grep -c '<!-- BEGIN FRONTEND STACK' "$ee/CLAUDE.md")"

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
