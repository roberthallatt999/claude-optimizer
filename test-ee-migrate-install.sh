#!/usr/bin/env bash
# Tests for ee-migrate-install.sh (config-block preservation, cleanup, gitignore).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$HERE/ee-migrate-install.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tpl="$work/tpl"
mkdir -p "$tpl/cps_tools/tests" "$tpl/ee-migrate"
echo "<?php return ['version' => '9.9.9'];" > "$tpl/cps_tools/addon.setup.php"
echo "t" > "$tpl/cps_tools/tests/t.sh"
cat > "$tpl/ee-migrate/ee-migrate.sh" <<'EOT'
#!/usr/bin/env bash
# >>> site config
SITE=""
# <<< site config
echo logic
EOT

repo="$work/repo"
mkdir -p "$repo/system/user/addons/cps_logs" "$repo/.admin-scripts"
git init -q "$repo"
cat > "$repo/.admin-scripts/ee-migrate.sh" <<'EOT'
#!/usr/bin/env bash
# >>> site config
SITE="kept-value"
# <<< site config
echo old logic
EOT

export EE_MIGRATE_TEMPLATES="$tpl"
"$INSTALL" "$repo" >/dev/null 2>&1
"$INSTALL" "$repo" >/dev/null 2>&1
runner="$repo/.admin-scripts/ee-migrate.sh"

check "cps_logs removed" '[[ ! -d "$repo/system/user/addons/cps_logs" ]]'
check "cps_tools installed" '[[ -f "$repo/system/user/addons/cps_tools/addon.setup.php" ]]'
check "cps_tools has no tests/" '[[ ! -d "$repo/system/user/addons/cps_tools/tests" ]]'
check "runner keeps SITE once" '[[ $(grep -c "SITE=\"kept-value\"" "$runner") -eq 1 ]]'
check "runner has no empty SITE" '! grep -q "SITE=\"\"" "$runner"'
check "runner uses template logic" 'grep -q "echo logic" "$runner"'
check "gitignore entry once" '[[ $(grep -c "^\.admin-scripts/\.ee-migrate/" "$repo/.gitignore") -eq 1 ]]'

# Existing runner without markers: exit 2, unchanged.
repo2="$work/repo2"
mkdir -p "$repo2/system/user/addons" "$repo2/.admin-scripts"
git init -q "$repo2"
echo "no markers here" > "$repo2/.admin-scripts/ee-migrate.sh"
"$INSTALL" "$repo2" >/dev/null 2>&1
rc=$?
check "no-marker runner exits 2" '[[ $rc -eq 2 ]]'
check "no-marker runner unchanged" '[[ "$(cat "$repo2/.admin-scripts/ee-migrate.sh")" == "no markers here" ]]'

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
