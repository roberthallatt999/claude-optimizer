#!/usr/bin/env bash
# test-gitignore-safety.sh — the .gitignore rules ai-config adds must never leave out a file
# an app needs. Each stack's real core, add-on, plugin and config files stay addable on a
# fresh repo; old rules that hid them are removed on refresh; a stack rule that matches
# tracked files is not added; --doctor reports one that does.
#
# Usage: ./test-gitignore-safety.sh
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
command -v git >/dev/null 2>&1 || { echo "git is required to run these tests"; exit 1; }

export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"
export AI_CONFIG_SKIP_GLOBAL_SKILLS=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

PROJECTS=()
cleanup_all() { local d; for d in "${PROJECTS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
assert_true()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
assert_false() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

new_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config core.ignorecase true   # as on macOS, where Database.php matches database.php
  PROJECTS+=("$dir")
  echo "$dir"
}
mk() { local dir="$1"; shift; local f; for f in "$@"; do mkdir -p "$dir/$(dirname "$f")"; : > "$dir/$f"; done; }
deploy() { local d="$1"; shift; "$SETUP_SCRIPT" --project="$d" --force --skip-vscode --no-superpowers --skip-superpowers-update "$@" >/dev/null 2>&1; }
ignored() { git -C "$1" check-ignore -q --no-index "$2"; }

# The paths each stack must never hide. A fresh repo (nothing committed) is the case that
# breaks sites: the first `git add` after a CMS upgrade or a new add-on.
keep()   { local d="$1" label="$2"; shift 2; local f; for f in "$@"; do assert_false "$label keeps $f" ignored "$d" "$f"; done; }
hide()   { local d="$1" label="$2"; shift 2; local f; for f in "$@"; do assert_true  "$label ignores $f" ignored "$d" "$f"; done; }

# ============================================================================
echo -e "\n${CYAN}=== Templates ship no retired rule ===${NC}\n"
# ============================================================================

eval "$(sed -n '/^GITIGNORE_RETIRED=(/,/^)/p' "$SETUP_SCRIPT")"
assert_true "GITIGNORE_RETIRED parsed" test "${#GITIGNORE_RETIRED[@]}" -gt 10
bad=""
for t in "$SCRIPT_DIR"/projects/*/gitignore-security.txt; do
  for r in "${GITIGNORE_RETIRED[@]}"; do
    grep -qxF -- "$r" "$t" && bad+="$(basename "$(dirname "$t")"):$r "
  done
done
assert_true "no template ships a retired rule${bad:+ ($bad)}" test -z "$bad"

# ============================================================================
echo -e "\n${CYAN}=== ExpressionEngine (renamed system folder) ===${NC}\n"
# ============================================================================

ee=$(new_repo)
mk "$ee" ermin/ee/ExpressionEngine/Core/Core.php ermin/user/config/config.php
printf "<?php\n\$system_path = './ermin';\n" > "$ee/admin.php"
# config.php as EE's installer writes it: literal credentials
printf "<?php\n\$config['encryption_key'] = 'fake0enc1key2for3tests';\n\$config['database'] = array('expressionengine' => array('username' => 'ee', 'password' => 'fake-pass-1234'));\n" \
  > "$ee/ermin/user/config/config.php"
deploy "$ee"
keep "$ee" EE \
  ermin/ee/ExpressionEngine/Service/Database/Database.php \
  ermin/ee/legacy/libraries/csrf/Database.php \
  ermin/ee/ExpressionEngine/Controller/Logs/Cp.php \
  ermin/ee/ExpressionEngine/Model/Log/CpLog.php \
  ermin/ee/ExpressionEngine/Library/Cache/FileDriver.php \
  ermin/user/addons/freeform/vendor/symfony/cache/Adapter/ArrayAdapter.php \
  ermin/user/addons/freeform_next/db.freeform_next.sql \
  ermin/user/addons/calendar/db.calendar.sql \
  ermin/user/config/license.key \
  ermin/user/cache/index.html \
  ermin/ee/legacy/libraries/cacert.pem \
  themes/ee/cp/js/build/vendor/codemirror/codemirror.js \
  themes/ee/asset/javascript/compressed/vendor/focus-visible.js \
  ermin/user/addons/myaddon/Service/ApiKey.php \
  ermin/user/addons/myaddon/Library/csrf_token.php \
  .npmrc
hide "$ee" EE \
  ermin/user/config/config.php \
  ermin/user/cache/default_site/page.php \
  ermin/user/logs/error.log \
  .env \
  backup.sql \
  vendor/autoload.php
before=$(cat "$ee/.gitignore")
deploy "$ee" --refresh
assert_true "EE: a second run leaves .gitignore unchanged" test "$before" == "$(cat "$ee/.gitignore")"

# The same site moves its secrets to .env.php: config.php must now be committable
printf "<?php\n\$config['encryption_key'] = \$_ENV['EE_ENCRYPTION_KEY'];\n\$config['database'] = array('expressionengine' => array('username' => getenv('DB_USER'), 'password' => getenv('DB_PASSWORD')));\n" \
  > "$ee/ermin/user/config/config.php"
deploy "$ee" --refresh
keep "$ee" "EE (env-based config)" ermin/user/config/config.php
hide "$ee" "EE (env-based config)" .env.php ermin/user/cache/default_site/page.php

# A fresh install with no config.php yet: ignored by default (the installer writes literals)
ee2=$(new_repo)
mk "$ee2" system/ee/ExpressionEngine/Core/Core.php
deploy "$ee2" --stack=expressionengine
hide "$ee2" "EE (no config yet)" system/user/config/config.php

# Literal credentials, committed: reported, not hidden from git's view
ee3=$(new_repo)
mk "$ee3" system/ee/ExpressionEngine/Core/Core.php system/user/config/config.php
printf "<?php\n\$config['database'] = array('expressionengine' => array('password' => 'fake-pass-1234'));\n" > "$ee3/system/user/config/config.php"
git -C "$ee3" add -A >/dev/null 2>&1 && git -C "$ee3" commit -qm init >/dev/null 2>&1
out=$("$SETUP_SCRIPT" --project="$ee3" --stack=expressionengine --force --skip-vscode --no-superpowers --skip-superpowers-update 2>&1)
assert_true "EE: committed config.php with a literal password is reported" grep -q "holds a literal password (password) and is committed" <<< "$out"
out=$("$SETUP_SCRIPT" --doctor --project="$ee3" 2>&1)
assert_true "--doctor reports it too" grep -q "holds a literal password and is committed" <<< "$out"

# The common layout: config.php committed with EE's app keys, the database login in an
# uncommitted config.local.php (each server and DDEV has its own)
ee4=$(new_repo)
mk "$ee4" system/ee/ExpressionEngine/Core/Core.php system/user/config/config.php
printf "<?php\n\$config['encryption_key'] = 'fake0enc1key2for3tests';\n\$config['session_crypt_key'] = 'fake4sess5key6';\nif (file_exists(__DIR__.'/config.local.php')) { require __DIR__.'/config.local.php'; }\n" \
  > "$ee4/system/user/config/config.php"
printf "<?php\n\$config['database'] = array('expressionengine' => array('password' => 'fake-pass-1234'));\n" \
  > "$ee4/system/user/config/config.local.php"
git -C "$ee4" add system/user/config/config.php system/ee >/dev/null 2>&1 && git -C "$ee4" commit -qm init >/dev/null 2>&1
out=$("$SETUP_SCRIPT" --project="$ee4" --stack=expressionengine --force --skip-vscode --no-superpowers --skip-superpowers-update 2>&1)
keep "$ee4" "EE (keys only, DB in config.local.php)" system/user/config/config.php
hide "$ee4" "EE (keys only, DB in config.local.php)" system/user/config/config.local.php system/user/config/local.config.php
assert_false "keys-only config.php is not called a password leak" grep -q "holds a literal password" <<< "$out"
out=$("$SETUP_SCRIPT" --doctor --project="$ee4" 2>&1)
assert_false "--doctor: no warning for keys-only config.php" grep -q "holds a literal password" <<< "$out"
assert_true "--doctor names the app keys (not their values)" grep -q "app keys written in it (encryption_key session_crypt_key)" <<< "$out"
assert_false "--doctor never prints a value" grep -q "fake0enc1key2for3tests" <<< "$out"

# ============================================================================
echo -e "\n${CYAN}=== Old rules are retired on refresh ===${NC}\n"
# ============================================================================

old=$(new_repo)
mk "$old" system/ee/ExpressionEngine/Core/Core.php system/user/config/config.php
cat > "$old/.gitignore" <<'EOF'
# The site's own rules
cache/
images/uploads/

# =============================================================================
# Security: Custom
# (Added by ai-config — do not remove section header)
# =============================================================================
*.log
logs/
log/
node_modules/
vendor/

# =============================================================================
# Security: ExpressionEngine
# (Added by ai-config — do not remove section header)
# =============================================================================
system/user/cache/
cache/
database.php
.npmrc
*apikey*
EOF
deploy "$old" --stack=expressionengine
for r in logs/ log/ vendor/ system/user/cache/ database.php .npmrc '*apikey*'; do
  assert_false "retired: $r removed" grep -qxF -- "$r" "$old/.gitignore"
done
assert_true "the site's own cache/ rule (above ai-config's header) is kept" \
  test "$(grep -cxF 'cache/' "$old/.gitignore")" -eq 1
assert_true "the site's own cache/ rule is still first" \
  test "$(grep -nxF 'cache/' "$old/.gitignore" | cut -d: -f1)" -eq 2
assert_true "harmless leftovers stay (*.log, node_modules/)" \
  grep -qxF 'node_modules/' "$old/.gitignore"
assert_true "a backup of .gitignore was taken" \
  bash -c "ls '$old'/.claude/ai-config/backups/*/.gitignore"

# ============================================================================
echo -e "\n${CYAN}=== Craft CMS ===${NC}\n"
# ============================================================================

craft=$(new_repo)
: > "$craft/craft"
echo '{"require":{"craftcms/cms":"^5.0"}}' > "$craft/composer.json"
deploy "$craft"
keep "$craft" Craft config/general.php config/db.php config/app.php \
  web/assets/lib/swiper/dist/swiper.min.js web/js/vendor/alpine.js \
  modules/sitemodule/backups/BackupService.php
hide "$craft" Craft storage/backups/site.sql.gz storage/logs/web.log storage/runtime/x vendor/autoload.php .env

# ============================================================================
echo -e "\n${CYAN}=== WordPress and Bedrock ===${NC}\n"
# ============================================================================

wp=$(new_repo)
mk "$wp" wp-config.php wp-content/themes/x/style.css
printf "<?php\ndefine( 'DB_PASSWORD', 'fake-pass-1234' );\n" > "$wp/wp-config.php"
deploy "$wp" --stack=wordpress
keep "$wp" WordPress wp-includes/certificates/ca-bundle.crt \
  wp-content/plugins/woocommerce/vendor/autoload.php \
  wp-content/plugins/someplugin/install/schema.sql \
  wp-content/plugins/someplugin/includes/class-api-key.php
hide "$wp" WordPress wp-config.php vendor/autoload.php wp-content/cache/page.html dump.sql

wp2=$(new_repo)
mk "$wp2" wp-content/themes/x/style.css
printf "<?php\ndefine( 'DB_PASSWORD', getenv('DB_PASSWORD') );\ndefine( 'AUTH_KEY', \$_ENV['AUTH_KEY'] );\n" > "$wp2/wp-config.php"
deploy "$wp2" --stack=wordpress
keep "$wp2" "WordPress (env-based config)" wp-config.php

bedrock=$(new_repo)
deploy "$bedrock" --stack=wordpress-roots
keep "$bedrock" Bedrock config/application.php web/wp-config.php config/environments/staging.php
hide "$bedrock" Bedrock web/wp/wp-load.php vendor/autoload.php web/app/cache/x .env

# ============================================================================
echo -e "\n${CYAN}=== Laravel-based stacks (Coilpack) ===${NC}\n"
# ============================================================================

cp_=$(new_repo)
deploy "$cp_" --stack=coilpack
keep "$cp_" Coilpack bootstrap/cache/.gitignore storage/framework/views/.gitignore \
  storage/framework/cache/.gitignore storage/app/public/.gitignore storage/logs/.gitignore \
  storage/framework/sessions/.gitignore
hide "$cp_" Coilpack bootstrap/cache/config.php storage/logs/laravel.log \
  storage/framework/sessions/abc storage/oauth-private.key

# ============================================================================
echo -e "\n${CYAN}=== Custom and JS stacks ===${NC}\n"
# ============================================================================

cu=$(new_repo)
deploy "$cu" --stack=custom
keep "$cu" Custom src/log/Logger.php app/Http/Controllers/Logs/Index.php public/js/vendor/jquery.js
hide "$cu" Custom logs/app.log vendor/autoload.php node_modules/x/index.js

st=$(new_repo)
deploy "$st" --stack=astro-strapi
keep "$st" "Astro+Strapi" backend/database/migrations/2024-add-field.js src/lib/vendor/dist/lib.js \
  backend/public/uploads/.gitkeep
hide "$st" "Astro+Strapi" dist/index.html backend/.tmp/data.db backend/public/uploads/photo.jpg

t3=$(new_repo)
deploy "$t3" --stack=t3-stack
keep "$t3" T3 prisma/schema.prisma prisma/migrations/20240101_init/migration.sql .env.example .env.test .env.encrypted
hide "$t3" T3 prisma/db.sqlite .env .env.local .next/server/x.js

ti=$(new_repo)
deploy "$ti" --stack=astro-tina
keep "$ti" Tina tina/tina-lock.json tina/config.ts content/posts/hello.md
hide "$ti" Tina tina/__generated__/client.ts dist/index.html

nx=$(new_repo)
deploy "$nx" --stack=nuxt
keep "$nx" Nuxt server/api/data/route.ts components/vendor/dist/x.js
hide "$nx" Nuxt .nuxt/app.js .output/server/index.mjs .data/kv/db.json

sv=$(new_repo)
deploy "$sv" --stack=sveltekit
keep "$sv" SvelteKit src/lib/build/helpers.ts .env.test
hide "$sv" SvelteKit .svelte-kit/output/x.js build/index.js vite.config.ts.timestamp-123.mjs

# ============================================================================
echo -e "\n${CYAN}=== Craft licence and Coilpack's ee/system/ ===${NC}\n"
# ============================================================================

keep "$craft" Craft config/license.key storage/rebrand/logo/logo.svg
hide "$craft" Craft storage/config-backups/project.yaml

cpe=$(new_repo)
mk "$cpe" ee/system/ee/ExpressionEngine/Core/Core.php
echo '{"require":{"laravel/framework":"^11.0","expressionengine/coilpack":"^1.0"}}' > "$cpe/composer.json"
deploy "$cpe"
assert_true "Coilpack detected with EE in ee/system/" grep -q 'stack=coilpack' "$cpe/.claude/ai-config/version"
keep "$cpe" Coilpack ee/system/user/config/license.key ee/system/user/addons/x/db.x.sql ee/system/user/cache/index.html
hide "$cpe" Coilpack ee/system/user/config/config.php ee/system/user/cache/default_site/x.php

# ============================================================================
echo -e "\n${CYAN}=== ai-config.conf [gitignore] skip ===${NC}\n"
# ============================================================================

sk=$(new_repo)
deploy "$sk" --stack=wordpress
assert_true "before: /vendor/ is added" grep -qxF '/vendor/' "$sk/.gitignore"
printf '[options]\nstack = wordpress\n\n[gitignore]\nskip = /vendor/, *.sql\n' > "$sk/ai-config.conf"
deploy "$sk" --refresh
assert_false "skip: /vendor/ removed from ai-config's part" grep -qxF '/vendor/' "$sk/.gitignore"
assert_false "skip: *.sql removed" grep -qxF '*.sql' "$sk/.gitignore"
keep "$sk" "skip" vendor/autoload.php site.sql
deploy "$sk" --refresh
assert_false "skip: a later refresh doesn't add it back" grep -qxF '/vendor/' "$sk/.gitignore"
"$SETUP_SCRIPT" --save-policy --project="$sk" --force >/dev/null 2>&1
assert_true "--save-policy keeps [gitignore] skip" grep -qxF 'skip = /vendor/' "$sk/ai-config.conf"

# ============================================================================
echo -e "\n${CYAN}=== Tracked files: rule skipped, doctor warns ===${NC}\n"
# ============================================================================

tr=$(new_repo)
mk "$tr" wp-config-sample.php wp-content/cache/advanced-cache-keep.php
git -C "$tr" add -A >/dev/null 2>&1 && git -C "$tr" commit -qm init >/dev/null 2>&1
out=$("$SETUP_SCRIPT" --project="$tr" --stack=wordpress --force --skip-vscode --no-superpowers --skip-superpowers-update 2>&1)
assert_false "a stack rule matching tracked files is not added" grep -qxF '/wp-content/cache/' "$tr/.gitignore"
assert_true "the skip is reported with the file" grep -q "advanced-cache-keep.php" <<< "$out"

printf '\ncache/\n' >> "$tr/.gitignore"   # as if an old ai-config run had added it
out=$("$SETUP_SCRIPT" --doctor --project="$tr" 2>&1)
assert_true "--doctor reports an ai-config rule that matches tracked files" \
  grep -q "match files this repo tracks" <<< "$out"

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
echo -e "${GREEN}✓ All tests passed${NC}"
