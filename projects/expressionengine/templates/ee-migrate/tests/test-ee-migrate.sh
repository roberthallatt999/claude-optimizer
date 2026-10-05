#!/usr/bin/env bash
# Unit tests for ee-migrate.sh. Never uses real ssh/ddev: stubs come first on PATH.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/../ee-migrate.sh"
STUBS="$HERE/stubs"
pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1 [$2]"; fi; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export STUB_DIR="$work/stub" STUB_LOG="$work/stub.log"
export EE_MIGRATE_FUNCTIONS="$STUBS/functions-websavers.sh"
chmod +x "$STUBS/ssh" "$STUBS/ddev"

# make_runner <name> [VAR=value ...] — copy the template with the site config block replaced.
make_runner() {
  local name="$1"
  shift
  local cfg="$work/cfg.$name"
  cat > "$cfg" <<'CFG'
# >>> site config (preserved by ee-migrate-install.sh)
SITE="testsite"
SSH_HOST="stub-host"
REMOTE_PHP="/usr/bin/php"
PROD_PATH="/srv/prod/httpdocs/current"
STAGING_PATH="/srv/stg/httpdocs/current"
PROD_DB="proddb"
STAGING_DB="stgdb"
PROD_MYSQL_DEFAULTS="/srv/prod/defaults"
STAGING_MYSQL_DEFAULTS="/srv/stg/defaults"
PROD_BACKUP_DIR="/srv/prod/db-backups"
STAGING_BACKUP_DIR="/srv/stg/db-backups"
LOCAL_DB="localdb"
EE_SUBDIR=""
LOCAL_EECLI="ddev exec php system/ee/eecli.php"
HAS_STAGING="yes"
# <<< site config
CFG
  local override var val
  for override in "$@"; do
    var="${override%%=*}"
    val="${override#*=}"
    sed -i.bak "s|^${var}=.*|${var}=\"${val}\"|" "$cfg" && rm -f "$cfg.bak"
  done
  sed -e "/^# >>> site config/r $cfg" -e '/^# >>> site config/,/^# <<< site config/d' \
    "$TEMPLATE" > "$work/$name.sh"
  chmod +x "$work/$name.sh"
  echo "$work/$name.sh"
}

reset_stub() {
  rm -rf "$STUB_DIR"
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
  cat > "$STUB_DIR/migrate-status.json" <<'JSON'
{"pending":["a","b"],"missing_files":[],"migrations_table":true,"commit":"abc123",
 "counts":{"tables":10,"channel_titles":5,"channel_fields":3}}
JSON
}

# run <runner> args... — sets OUT and RC.
run() {
  local runner="$1"
  shift
  OUT="$(PATH="$STUBS:$PATH" "$runner" "$@" 2>&1)"
  RC=$?
}

# Ordered list of subcommands the stub saw. The multi-line backup script is logged as one
# entry whose first line is the cd-or-exit guard, shown here as "backup".
calls() {
  grep '^ssh ' "$STUB_LOG" | sed -E \
    -e "s/.*\|\| exit 11$/backup/" \
    -e 's/^ssh [^ ]+ .*eecli\.php //'
}
calls_backup() {
  grep -q '|| exit 11' "$STUB_LOG" && echo backup
}

RUNNER="$(make_runner base)"

# ---- Task 10: skeleton, config, arguments ----
reset_stub
run "$RUNNER"
check "no args -> usage, exit 2" '[[ $RC -eq 2 && "$OUT" == *usage* ]]'
run "$RUNNER" bogus status
check "unknown mode -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"unknown mode"* ]]'
run "$RUNNER" prod frobnicate
check "unknown action -> exit 2" '[[ $RC -eq 2 ]]'
run "$RUNNER" prod apply
check "apply without --expect -> exit 2" '[[ $RC -eq 2 ]]'
run "$RUNNER" prod apply "--expect=a;rm"
check "unsafe migration name -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"invalid migration name"* ]]'

NOSTG="$(make_runner nostg HAS_STAGING=no)"
run "$NOSTG" staging status
check "HAS_STAGING=no rejects staging" '[[ $RC -eq 2 && "$OUT" == *"has no staging"* ]]'

INREL="$(make_runner inrel PROD_BACKUP_DIR=/srv/prod/httpdocs/current/backups)"
run "$INREL" prod status
check "backup dir inside current -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"outside the release tree"* ]]'
INREL2="$(make_runner inrel2 PROD_BACKUP_DIR=/srv/prod/releases/20260101)"
run "$INREL2" prod status
check "backup dir inside releases -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"outside the release tree"* ]]'
EQREL="$(make_runner eqrel PROD_BACKUP_DIR=/srv/prod/httpdocs/current)"
run "$EQREL" prod status
check "backup dir equal to release path -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"outside the release tree"* ]]'
grep -q '^EE_MIGRATE_VERSION="1.0.0"' "$TEMPLATE" && ok "EE_MIGRATE_VERSION present" || ko "EE_MIGRATE_VERSION present"
EMPTY="$(make_runner empty SSH_HOST=)"
run "$EMPTY" prod status
check "empty config -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"SSH_HOST is empty"* ]]'

# ---- Task 11: backup ----
MB=$((1024 * 1024))
backup_case() { # backup_case <desc> <new> <prev|none> <expect_rc> <pattern> [mode]
  reset_stub
  echo "$2" > "$STUB_DIR/backup-size"
  [[ "$3" == none ]] || echo "$3" > "$STUB_DIR/prev-size"
  [[ -z "${6:-}" ]] || echo "$6" > "$STUB_DIR/backup-mode"
  run "$RUNNER" prod apply --expect=a,b
  check "$1: exit" "[[ \$RC -eq $4 ]]"
  PAT="$5"
  [[ -z "$PAT" ]] || check "$1: message" '[[ "$OUT" == *"$PAT"* ]]'
  if [[ "$4" -ne 0 ]]; then
    check "$1: no migrate call" '! grep -q "migrate --core\|migrate:rollback" "$STUB_LOG"'
  fi
}
backup_case "95MB vs 100MB previous" $((95 * MB)) $((100 * MB)) 0 "backup OK"
backup_case "80MB vs 100MB previous" $((80 * MB)) $((100 * MB)) 1 "backup too small"
backup_case "0.5MB, no previous" $((MB / 2)) none 1 "< 1 MB"
backup_case "2MB, no previous" $((2 * MB)) none 0 "backup OK"
backup_case "mode 644" $((95 * MB)) $((100 * MB)) 1 "expected 600" 644

reset_stub
touch "$STUB_DIR/backup-nofile"
run "$RUNNER" prod apply --expect=a,b
check "backup cmd ok but no file -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"no backup file"* ]]'
check "no-file: no migrate call" '! grep -q "migrate --core" "$STUB_LOG"'
reset_stub
touch "$STUB_DIR/backup-fail"
run "$RUNNER" prod apply --expect=a,b
check "backup command fails -> FAIL, no migrate" '[[ $RC -eq 1 ]] && ! grep -q "migrate --core" "$STUB_LOG"'

reset_stub
run "$RUNNER" prod apply --expect=a,b
check "backup name pre_migrate_<UTC> + suffix, chmod 600" \
  'grep -Eq "pre_migrate_[0-9]{8}_[0-9]{6}\.sql" "$STUB_LOG" && grep -q "chmod 600" "$STUB_LOG"'
check "backup uses absolute_path in out-of-release dir" 'grep -q "absolute_path=./srv/prod/db-backups/." "$STUB_LOG"'

# ---- Task 12: pending-set guard + loop ----
reset_stub
run "$RUNNER" prod apply --expect=a,b
expected="$(printf '%s\n' 'cps:migrate-status --json' backup 'migrate --core --steps=1' 'cps:migrate-verify a' \
  'migrate --core --steps=1' 'cps:migrate-verify b' 'cps:schema-check --no-smoke --json')"
check "happy path exits 0" '[[ $RC -eq 0 ]]'
check "happy path order exactly as spec" '[[ "$(calls)" == "$expected" ]]'
check "success prints rollback and restore" '[[ "$OUT" == *"rollback:"* && "$OUT" == *"restore:"* ]]'

reset_stub
run "$RUNNER" prod apply --expect=a
check "extra pending -> FAIL pending set differs" '[[ $RC -eq 1 && "$OUT" == *"pending set differs"* ]]'
check "extra pending: no backup, no migrate" '! calls_backup >/dev/null && ! grep -q "migrate --core" "$STUB_LOG"'

reset_stub
run "$RUNNER" prod apply --expect=b,a
check "wrong order -> FAIL pending set differs" '[[ $RC -eq 1 && "$OUT" == *"pending set differs"* ]]'
check "wrong order: no backup" '! calls_backup >/dev/null'

reset_stub
echo '{"pending":["a","b"],"missing_files":["gone"],"counts":{}}' > "$STUB_DIR/migrate-status.json"
run "$RUNNER" prod apply --expect=a,b
check "recorded migration with missing file -> FAIL, no backup" '[[ $RC -eq 1 ]] && ! calls_backup >/dev/null'

reset_stub
touch "$STUB_DIR/status-missing"
run "$RUNNER" prod apply --expect=a,b
check "cps_tools missing -> exit 2 with message" \
  '[[ $RC -eq 2 && "$OUT" == *"cps_tools is not deployed on prod — deploy it first"* ]]'
check "cps_tools missing: no backup" '! calls_backup >/dev/null'
run "$RUNNER" staging status
check "status on missing cps_tools -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"not deployed on staging"* ]]'

reset_stub
echo 1 > "$STUB_DIR/verify-exit-b"
run "$RUNNER" prod apply --expect=a,b
check "verify b fails -> exit 1" '[[ $RC -eq 1 && "$OUT" == *"verify for b"* ]]'
check "verify failure prints rollback + restore" \
  '[[ "$OUT" == *"rollback:"*"migrate:rollback --steps=1"* && "$OUT" == *"restore:"* ]]'
check "no schema-check after failed verify" '! grep -q "cps:schema-check" "$STUB_LOG"'
check "a ran fully before b failed" '[[ "$(calls | grep -c "migrate --core")" -eq 2 ]]'

reset_stub
echo 1 > "$STUB_DIR/migrate-exit"
run "$RUNNER" prod apply --expect=a,b
check "migrate step fails -> exit 1, stops at first, recovery printed" \
  '[[ $RC -eq 1 && "$(calls | grep -c "migrate --core")" -eq 1 && "$OUT" == *"rollback:"* ]]'

reset_stub
echo 2 > "$STUB_DIR/schema-exit"
run "$RUNNER" prod apply --expect=a,b
check "post-check could-not-run -> exit 1 with recovery" '[[ $RC -eq 1 && "$OUT" == *"restore:"* ]]'

reset_stub
run "$RUNNER" staging apply --expect=a,b
check "staging apply targets staging path and dir" \
  'grep -q "/srv/stg/httpdocs/current" "$STUB_LOG" && grep -q "/srv/stg/db-backups" "$STUB_LOG"'

reset_stub
EE="$(make_runner eesub EE_SUBDIR=ee/)"
run "$EE" prod status
check "EE_SUBDIR applied to eecli path" 'grep -q "ee/system/ee/eecli.php" "$STUB_LOG"'

echo
echo "Passed: $pass  Failed: $fail"
[[ $fail -eq 0 ]]
