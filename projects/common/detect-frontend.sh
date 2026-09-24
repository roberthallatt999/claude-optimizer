#!/usr/bin/env bash
#
# detect-frontend.sh — detect a web project's front-end stack: CSS frameworks and tooling, UI
# component libraries, JS frameworks and libraries, build tools — and the project's own
# first-party CSS/JS, so "custom code, no framework" can be reported plainly.
#
# Usage:  bash detect-frontend.sh <project-dir>
# Output: tab-separated records on stdout, in catalog order (deterministic)
#   lib     <id>  <label>  <category>  <version>  <evidence>
#   custom  js|css  <file-count>  <main-folder>
# Categories: css, css-tool, ui, js-framework, js-lib, build, lang
#
# Signals, strongest first: dependencies in any package.json (theme folders included), vendored
# asset file names (jquery-3.7.1.min.js), CDN <script>/<link> URLs and wp_enqueue calls in
# templates, and markup attributes (x-data, hx-get). CMS core and third-party folders are skipped
# so the libraries they bundle aren't mistaken for the site's own: node_modules, vendor, EE
# system/ee, themes/ee|user and add-ons, Craft cpresources, WordPress core and plugins, build
# output, uploads, and caches. Only file names, package.json, and markup are read.
#
# Source of truth: claude-optimizer/projects/common/detect-frontend.sh
# Tests:           claude-optimizer/test-frontend-detection.sh

set -uo pipefail

project="${1:?usage: detect-frontend.sh <project-dir>}"
project="${project%/}"
[[ -d "$project" ]] || exit 0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
US=$'\037'

# find(1) over the project, skipping dependencies, CMS core, third-party code, build output, caches.
project_find() {
  find "$project" -maxdepth 9 \( -type d \( -name node_modules -o -name vendor -o -name .git -o -name .ddev \
      -o -name .next -o -name .nuxt -o -name .output -o -name .svelte-kit -o -name .astro -o -name .cache \
      -o -name cache -o -name dist -o -name build -o -name coverage -o -name storage -o -name uploads \
      -o -name cpresources -o -name wp-admin -o -name wp-includes -o -name plugins -o -name mu-plugins \
      -o -name addons -o -name tmp -o -name logs -o -path '*/system/ee' -o -path '*/themes/ee' \
      -o -path '*/themes/user' -o -path '*/web/wp' \) -prune \) -o "$@"
}

relative() { awk -v p="$project/" 'index($0, p) == 1 { print substr($0, length(p) + 1) }'; }

# --- Gather signals -----------------------------------------------------------------------------

deps="$work/deps.tsv"          # name \t version \t package.json
files="$work/files.txt"        # scripts, styles, build configs (relative paths)
templates="$work/templates.txt" # markup files (absolute paths)
refs="$work/refs.txt"          # file:<script src… | <link href… | wp_enqueue_…(…>
: > "$deps"; : > "$refs"

if command -v jq >/dev/null 2>&1; then
  while IFS= read -r pkg; do
    rel="${pkg#"$project"/}"
    jq -r --arg f "$rel" '[(.dependencies // {}), (.devDependencies // {}), (.peerDependencies // {})]
      | add // {} | to_entries[] | "\(.key)\t\(.value)\t\($f)"' "$pkg" 2>/dev/null >> "$deps"
  done < <(project_find -type f -name package.json -print 2>/dev/null | LC_ALL=C sort)
fi

project_find -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' -o -name '*.jsx' \
  -o -name '*.tsx' -o -name '*.vue' -o -name '*.svelte' -o -name '*.css' -o -name '*.scss' -o -name '*.sass' \
  -o -name '*.less' -o -name '*.styl' -o -name '*.pcss' -o -name tsconfig.json \) -print 2>/dev/null \
  | relative | LC_ALL=C sort | head -n 20000 > "$files"

project_find -type f \( -name '*.html' -o -name '*.htm' -o -name '*.twig' -o -name '*.php' -o -name '*.astro' \
  -o -name '*.vue' -o -name '*.svelte' -o -name '*.liquid' -o -name '*.njk' -o -name '*.hbs' -o -name '*.ejs' \
  -o -name '*.jsx' -o -name '*.tsx' \) -print 2>/dev/null | LC_ALL=C sort | head -n 5000 > "$templates"

if [[ -s "$templates" ]]; then
  tr '\n' '\0' < "$templates" \
    | xargs -0 grep -HoE "<script[^>]*src=[\"'][^\"']+|<link[^>]*href=[\"'][^\"']+|wp_(enqueue|register)_(script|style)[[:space:]]*\([^;]+" 2>/dev/null \
    | head -n 20000 | relative > "$refs"
fi

# --- Catalog: id %% Label %% category %% npm-name-regex %% asset-basename-regex %% markup-ref-regex %% attribute-regex
# Regexes are ERE; basename and markup matches are case-insensitive (write them in lowercase).

catalog() {
  cat <<'CATALOG'
tailwind%%Tailwind CSS%%css%%^tailwindcss$%%^tailwind\.config\.(js|cjs|mjs|ts)$%%cdn\.tailwindcss\.com|/tailwindcss(@[0-9][^/]*)?/%%
bootstrap%%Bootstrap%%css%%^bootstrap$%%^bootstrap([.-][0-9][0-9.]*)?(\.bundle)?(\.min)?\.(css|js)$%%bootstrapcdn|/bootstrap(@[0-9][^/]*)?/|bootstrap(\.bundle)?(\.min)?\.(css|js)%%
foundation%%Foundation%%css%%^foundation-sites$%%^foundation(\.min)?\.(css|js)$%%foundation-sites|foundation(\.min)?\.(css|js)%%
bulma%%Bulma%%css%%^bulma$%%^bulma(\.min)?\.css$%%/bulma(@[0-9][^/]*)?/|bulma(\.min)?\.css%%
uikit%%UIkit%%css%%^uikit$%%^uikit(-icons)?(\.min)?\.(css|js)$%%/uikit(@[0-9][^/]*)?/|uikit(-icons)?(\.min)?\.(css|js)%%
daisyui%%daisyUI%%css%%^daisyui$%%%%daisyui%%
pure%%Pure.css%%css%%^purecss$%%^pure(-min)?\.css$%%purecss|pure(-min)?\.css%%
materialize%%Materialize%%css%%^(materialize-css|@materializecss/materialize)$%%^materialize(\.min)?\.(css|js)$%%materialize(\.min)?\.(css|js)%%
semantic%%Fomantic / Semantic UI%%css%%^(fomantic-ui|semantic-ui)(-css)?$%%^semantic(\.min)?\.(css|js)$%%(fomantic|semantic)-ui|semantic(\.min)?\.(css|js)%%
unocss%%UnoCSS%%css%%^(unocss|@unocss/.+)$%%^uno\.config\.(js|ts|mjs)$%%%%
scss%%Sass/SCSS%%css-tool%%^(sass|node-sass|sass-embedded)$%%\.s[ac]ss$%%%%
less%%Less%%css-tool%%^less$%%\.less$%%%%
postcss%%PostCSS%%css-tool%%^postcss$%%^postcss\.config\.(js|cjs|mjs|ts)$%%%%
stylus%%Stylus%%css-tool%%^stylus$%%\.styl$%%%%
styled-components%%styled-components%%css-tool%%^styled-components$%%%%%%
emotion%%Emotion%%css-tool%%^@emotion/(react|styled|css)$%%%%%%
mui%%Material UI%%ui%%^(@mui/material|@mui/joy|@material-ui/core)$%%%%%%
chakra%%Chakra UI%%ui%%^@chakra-ui/react$%%%%%%
mantine%%Mantine%%ui%%^@mantine/core$%%%%%%
antd%%Ant Design%%ui%%^antd$%%%%%%
radix%%Radix UI%%ui%%^@radix-ui/.+%%%%%%
headlessui%%Headless UI%%ui%%^@headlessui/(react|vue)$%%%%%%
vuetify%%Vuetify%%ui%%^vuetify$%%%%%%
prime%%PrimeVue / PrimeReact%%ui%%^(primevue|primereact)$%%%%%%
react%%React%%js-framework%%^react$%%^react(\.production)?(\.min)?\.js$%%unpkg\.com/react@|/react(@[0-9][^/]*)?/umd/%%
vue%%Vue%%js-framework%%^vue$%%^vue(\.global)?(\.prod)?(\.min)?\.js$%%unpkg\.com/vue@|/vue(@[0-9][^/]*)?/dist/%%
svelte%%Svelte%%js-framework%%^svelte$%%%%%%
angular%%Angular%%js-framework%%^@angular/core$%%%%%%
preact%%Preact%%js-framework%%^preact$%%%%%%
solid%%SolidJS%%js-framework%%^solid-js$%%%%%%
lit%%Lit%%js-framework%%^(lit|lit-element)$%%%%%%
alpine%%Alpine.js%%js-framework%%^alpinejs$%%^alpine(js)?([.-][0-9][0-9.]*)?(\.min)?\.js$%%alpinejs|alpine(\.min)?\.js%%[[:space:]]x-data([[:space:]]|=|>)
htmx%%htmx%%js-framework%%^htmx\.org$%%^htmx(\.min)?\.js$%%htmx\.org|htmx(\.min)?\.js%%[[:space:]]hx-(get|post|put|patch|delete|boost|trigger|target)=
stimulus%%Stimulus%%js-framework%%^(@hotwired/stimulus|stimulus)$%%%%@hotwired/stimulus|stimulus(\.umd)?(\.min)?\.js%%
turbo%%Turbo%%js-framework%%^@hotwired/turbo$%%%%@hotwired/turbo%%
jquery%%jQuery%%js-lib%%^jquery$%%^jquery([.-][0-9][0-9.]*)?(\.slim)?(\.min)?\.js$%%code\.jquery\.com|/jquery(@[0-9][^/]*)?/|jquery([.-][0-9][0-9.]*)?(\.slim)?(\.min)?\.js|['"]jquery(-core)?['"]%%
gsap%%GSAP%%js-lib%%^gsap$%%^gsap(\.min)?\.js$%%/gsap(@[0-9][^/]*)?/|gsap(\.min)?\.js%%
swiper%%Swiper%%js-lib%%^swiper$%%^swiper(-bundle)?(\.min)?\.(js|css)$%%/swiper(@[0-9][^/]*)?/|swiper(-bundle)?(\.min)?\.(js|css)%%
slick%%Slick%%js-lib%%^slick-carousel$%%^slick(-theme)?(\.min)?\.(js|css)$%%slick-carousel|slick(\.min)?\.(js|css)%%
splide%%Splide%%js-lib%%^@splidejs/splide$%%^splide(\.min)?\.(js|css)$%%splidejs|splide(\.min)?\.(js|css)%%
chartjs%%Chart.js%%js-lib%%^chart\.js$%%^chart(\.umd)?(\.min)?\.js$%%/chart\.js(@[0-9][^/]*)?/|chart(\.umd)?(\.min)?\.js%%
three%%Three.js%%js-lib%%^three$%%^three(\.module)?(\.min)?\.js$%%/three(@[0-9][^/]*)?/build/|three(\.module)?(\.min)?\.js%%
aos%%AOS (Animate On Scroll)%%js-lib%%^aos$%%^aos(\.min)?\.(js|css)$%%/aos(@[0-9][^/]*)?/%%
vite%%Vite%%build%%^vite$%%^vite\.config\.(js|cjs|mjs|ts)$%%%%
webpack%%webpack%%build%%^webpack$%%^webpack\.config\.(js|cjs|mjs|ts)$%%%%
laravel-mix%%Laravel Mix%%build%%^laravel-mix$%%^webpack\.mix\.js$%%%%
bud%%Bud (Roots)%%build%%^@roots/bud$%%^bud\.config\.(js|cjs|mjs|ts)$%%%%
parcel%%Parcel%%build%%^parcel$%%%%%%
esbuild%%esbuild%%build%%^esbuild$%%%%%%
rollup%%Rollup%%build%%^rollup$%%^rollup\.config\.(js|cjs|mjs|ts)$%%%%
gulp%%Gulp%%build%%^gulp$%%^gulpfile\.(js|mjs|cjs|ts|babel\.js)$%%%%
grunt%%Grunt%%build%%^grunt$%%^gruntfile\.(js|coffee)$%%%%
typescript%%TypeScript%%lang%%^typescript$%%^tsconfig\.json$%%%%
CATALOG
}

# --- Match --------------------------------------------------------------------------------------

vendored="$work/vendored.txt"
: > "$vendored"

while IFS="$US" read -r id label category npm_re asset_re markup_re attr_re; do
  [[ -n "$id" ]] || continue
  version="" evidence=""

  if [[ -n "$npm_re" ]]; then
    hit=$(RE="$npm_re" awk -F'\t' '$1 ~ ENVIRON["RE"] { print; exit }' "$deps")
    if [[ -n "$hit" ]]; then
      version=$(printf '%s' "$hit" | awk -F'\t' '{ if (match($2, /[0-9]+(\.[0-9]+)*/)) print substr($2, RSTART, RLENGTH) }')
      evidence=$(printf '%s' "$hit" | awk -F'\t' '{ print $3 }')
      # A range like ^3.4.1 only names the floor; report what npm actually installed when we can.
      installed="$project/$(dirname "$evidence")/node_modules/${hit%%$'\t'*}/package.json"
      if [[ -f "$installed" ]]; then
        installed=$(jq -r '.version // empty' "$installed" 2>/dev/null)
        [[ -n "$installed" ]] && version="$installed"
      fi
    fi
  fi

  if [[ -n "$asset_re" ]]; then
    # Library files (not tooling/extension matches like *.scss) are excluded from first-party counts.
    case "$category" in
      css|ui|js-framework|js-lib)
        RE="$asset_re" awk '{ n = split($0, p, "/"); if (tolower(p[n]) ~ ENVIRON["RE"]) print }' "$files" >> "$vendored" ;;
    esac
    if [[ -z "$evidence" ]]; then
      hit=$(RE="$asset_re" awk '{ n = split($0, p, "/"); if (tolower(p[n]) ~ ENVIRON["RE"]) { print; exit } }' "$files")
      if [[ -n "$hit" ]]; then
        evidence="$hit"
        version=$(printf '%s' "${hit##*/}" | awk '{ if (match($0, /[0-9]+\.[0-9]+(\.[0-9]+)?/)) print substr($0, RSTART, RLENGTH) }')
      fi
    fi
  fi

  if [[ -z "$evidence" && -n "$markup_re" ]]; then
    hit=$(RE="$markup_re" awk '{ i = index($0, ":"); if (tolower(substr($0, i + 1)) ~ ENVIRON["RE"]) { print; exit } }' "$refs")
    if [[ -n "$hit" ]]; then
      file="${hit%%:*}"
      ref="${hit#*:}"
      case "$ref" in
        wp_*) evidence="enqueued in $file" ;;
        *)
          url=$(printf '%s' "$ref" | sed -E "s/^.*(src|href)=[\"']//; s/[?#].*$//")
          case "$url" in
            *//*) evidence="CDN in $file" ;;
            *)    evidence="linked in $file" ;;
          esac
          version=$(printf '%s' "$url" | awk '{ if (match($0, /[0-9]+\.[0-9]+(\.[0-9]+)?/)) print substr($0, RSTART, RLENGTH) }')
          ;;
      esac
    fi
  fi

  if [[ -z "$evidence" && -n "$attr_re" && -s "$templates" ]]; then
    hit=$(tr '\n' '\0' < "$templates" | xargs -0 grep -lE -e "$attr_re" 2>/dev/null | head -n 1)
    if [[ -n "$hit" ]]; then
      evidence="markup in $(printf '%s\n' "$hit" | relative)"
    fi
  fi

  if [[ -n "$evidence" ]]; then
    printf 'lib\t%s\t%s\t%s\t%s\t%s\n' "$id" "$label" "$category" "$version" "$evidence"
  fi
done < <(catalog | awk -F'%%' -v us="$US" '{ print $1 us $2 us $3 us $4 us $5 us $6 us $7 }')

# --- First-party code ---------------------------------------------------------------------------
# Scripts and styles that aren't minified, vendored library files, build configs, or type stubs.

awk -v vendfile="$vendored" '
  BEGIN { while ((getline line < vendfile) > 0) vend[line] = 1 }
  {
    path = $0
    if (path in vend) next
    n = split(path, p, "/"); base = tolower(p[n])
    if (base ~ /\.min\.(js|css)$/ || base ~ /\.d\.ts$/ || base ~ /(^|[.-])config\.(js|cjs|mjs|ts)$/ \
        || base ~ /^(gulpfile|gruntfile|webpack\.mix)\./ || base ~ /-bundle\./ || base == "tsconfig.json") next
    dir = (n > 1) ? substr(path, 1, length(path) - length(p[n]) - 1) : "."
    if (base ~ /\.(js|mjs|cjs|ts|jsx|tsx|vue|svelte)$/) { js++; jsdir[dir]++ }
    else if (base ~ /\.(css|scss|sass|less|styl|pcss)$/) { css++; cssdir[dir]++ }
  }
  function top(arr,    d, best, bestdir) {
    best = 0; bestdir = ""
    for (d in arr) if (arr[d] > best || (arr[d] == best && d < bestdir)) { best = arr[d]; bestdir = d }
    return bestdir
  }
  END {
    if (js > 0) printf "custom\tjs\t%d\t%s\n", js, top(jsdir)
    if (css > 0) printf "custom\tcss\t%d\t%s\n", css, top(cssdir)
  }
' "$files"
