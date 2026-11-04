#!/usr/bin/env bash
# Tests for devcontainer-kit/files/ddev-shim.sh: the arguments `ddev mysql` hands to mariadb.
# A stub mariadb on PATH prints its argv, one per line, so nothing connects anywhere.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$HERE/devcontainer-kit/files/ddev-shim.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
printf '#!/bin/sh\nfor a in "$@"; do echo "$a"; done\n' > "$work/bin/mariadb"
chmod +x "$work/bin/mariadb"

# shim ARGS… → mariadb's argv joined with spaces (exit status kept in $rc)
shim() { out=$(PATH="$work/bin:$PATH" DDEV_DB_NAME="${DB:-}" bash "$SHIM" "$@" 2>&1 | tr '\n' ' '); rc=${PIPESTATUS[0]}; }
expect() {
  local name="$1" want="$2"; shift 2
  shim "$@"
  if [[ "$out" == "$want " ]]; then ok "$name"; else ko "$name: got [$out] want [$want]"; fi
}

DB=admin_cps expect 'default database from DDEV_DB_NAME' \
  '-h db -u db -pdb --database=admin_cps -N -e SELECT 1' mysql -N -e 'SELECT 1'
DB= expect 'no DDEV_DB_NAME falls back to db' \
  '-h db -u db -pdb --database=db' mysql
# ee-migrate.sh form: the database as the first argument must reach mariadb as its only positional.
DB=admin_cps expect 'named database stays a single positional' \
  '-h db -u db -pdb --database=admin_cps admin_cps -N -e SELECT 1' mysql admin_cps -N -e 'SELECT 1'
DB=admin_cps expect 'mariadb alias' '-h db -u db -pdb --database=admin_cps' mariadb
DB=admin_cps expect '--project=NAME targets that project, default db' \
  '-h ddev-cfk-db -u db -pdb --database=db admin_cfk -e SELECT 1' mysql --project=cfk admin_cfk -e 'SELECT 1'
DB=admin_cps expect '--project NAME (two words)' \
  '-h ddev-members-db -u db -pdb --database=db cpsca_6' mysql --project members cpsca_6

DB= shim mysql '--project=../x'
[[ $rc -eq 2 && "$out" == *"needs a DDEV project name"* ]] && ok 'bad project name refused' || ko "bad project name: rc=$rc [$out]"
DB= shim mysql --project
[[ $rc -eq 2 ]] && ok 'missing project name refused' || ko "missing project name: rc=$rc [$out]"

# The mariadb client rejects two positionals; a real client proves the default is not one.
if command -v mariadb >/dev/null 2>&1; then
  real=$(mariadb -h 127.0.0.1 --database=a b --help 2>&1 | head -1)
  [[ "$real" != *"Too many arguments"* ]] && ok 'real client accepts --database plus a positional' \
    || ko 'real client rejected --database plus a positional'
fi

[[ $fail -eq 0 ]] && echo "All $pass tests passed" || echo "ddev-shim: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
