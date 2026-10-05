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
export EE_MIGRATE_REPO_ROOT="$work/repo"
STAMPS="$EE_MIGRATE_REPO_ROOT/.admin-scripts/.ee-migrate/stamps"
chmod +x "$STUBS/ssh" "$STUBS/ddev"

iso_ago() { # iso_ago <seconds>
  if [[ "$(uname)" == "Darwin" ]]; then date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ; else date -u -d "$1 seconds ago" +%Y-%m-%dT%H:%M:%SZ; fi
}
# write_stamp <target> <commit> <pending-json> <rehearsed_at> <rehearsal> <apply> [pending_hash]
HASH=aaaa1111bbbb
write_stamp() {
  mkdir -p "$STAMPS"
  jq -n --arg t "$1" --arg c "$2" --argjson p "$3" --arg at "$4" --arg r "$5" --arg a "$6" --arg h "${7:-$HASH}" \
    '{target:$t, commit:$c, pending_hash:$h, pending:$p, rehearsed_at:$at, rehearsal:(if $r=="" then null else $r end),
      applied_at:null, apply:(if $a=="" then null else $a end), backup:null}' > "$STAMPS/$1.json"
}
seed_stamps() {
  write_stamp staging abc123 '["a","b"]' "$(iso_ago 60)" pass pass
  write_stamp prod abc123 '["a","b"]' "$(iso_ago 60)" pass ""
}

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
REMOTE_EECLI=''
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
    if [[ "$var" == "REMOTE_EECLI" ]]; then   # stored single-quoted, as in a real config block
      sed -i.bak "s|^${var}=.*|${var}='${val}'|" "$cfg" && rm -f "$cfg.bak"
    else
      sed -i.bak "s|^${var}=.*|${var}=\"${val}\"|" "$cfg" && rm -f "$cfg.bak"
    fi
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
  rm -rf "$EE_MIGRATE_REPO_ROOT"
  mkdir -p "$EE_MIGRATE_REPO_ROOT/.admin-scripts"
  seed_stamps
  echo '{"pending":["a"],"counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/local-status.json"
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
    -e 's/^ssh [^ ]+ .*--baseline=.*/schema-baseline/' \
    -e 's/ --compare=.*/ --compare/' \
    -e "s/.*\\|\\| exit 13$/pending-hash/" \
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
grep -q '^EE_MIGRATE_VERSION="1.1.0"' "$TEMPLATE" && ok "EE_MIGRATE_VERSION present" || ko "EE_MIGRATE_VERSION present"
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
expected="$(printf '%s\n' 'cps:migrate-status --json' pending-hash backup schema-baseline 'migrate --core --steps=1' \
  'cps:migrate-verify a' 'migrate --core --steps=1' 'cps:migrate-verify b' \
  'cps:schema-check --no-smoke --json --compare')"
check "happy path exits 0" '[[ $RC -eq 0 ]]'
check "happy path order exactly as spec" '[[ "$(calls)" == "$expected" ]]'
check "success prints rollback and restore" '[[ "$OUT" == *"rollback:"* && "$OUT" == *"restore (Robert runs this):"* ]]'

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
  '[[ "$OUT" == *"rollback:"*"migrate:rollback --steps=1"* && "$OUT" == *"restore (Robert runs this):"* ]]'
check "no post-check after failed verify" '! grep -q -- "--compare" "$STUB_LOG"'
check "a ran fully before b failed" '[[ "$(calls | grep -c "migrate --core")" -eq 2 ]]'

reset_stub
echo 1 > "$STUB_DIR/migrate-exit"
run "$RUNNER" prod apply --expect=a,b
check "migrate step fails -> exit 1, stops at first, recovery printed" \
  '[[ $RC -eq 1 && "$(calls | grep -c "migrate --core")" -eq 1 && "$OUT" == *"rollback:"* ]]'

reset_stub
echo 2 > "$STUB_DIR/compare-exit"
run "$RUNNER" prod apply --expect=a,b
check "post-check could-not-run -> exit 1 with recovery" '[[ $RC -eq 1 && "$OUT" == *"restore (Robert runs this):"* ]]'
reset_stub
echo 1 > "$STUB_DIR/compare-exit"
run "$RUNNER" prod apply --expect=a,b
check "post-check new failures -> exit 1, rollback+restore" \
  '[[ $RC -eq 1 && "$OUT" == *"new failures"* && "$OUT" == *"rollback:"* && "$OUT" == *"restore (Robert runs this):"* ]]'
check "failed post-check does not record apply" '[[ "$(jq -r .apply "$STAMPS/prod.json")" == "null" ]]'
reset_stub
echo 2 > "$STUB_DIR/baseline-exit"
run "$RUNNER" prod apply --expect=a,b
check "baseline failure -> exit 1 before any migrate" '[[ $RC -eq 1 ]] && ! grep -q "migrate --core" "$STUB_LOG"'
reset_stub
run "$RUNNER" prod apply --expect=a,b
check "baseline file named from backup ts, outside pre_ size glob" \
  'grep -Eq "baseline=./srv/prod/db-backups/pre_migrate_[0-9]{8}_[0-9]{6}\.baseline\.json" "$STUB_LOG" && grep -q "baseline.json" "$STUB_LOG"'
check "baseline chmod 600 in same ssh call" 'grep "baseline=" "$STUB_LOG" | grep -q "chmod 600"'
check "previous-dump lookup ignores baseline files" 'grep -qF "baseline" "$STUB_LOG" && grep -F "ls -t" "$STUB_LOG" | grep -qF "json"'

reset_stub
run "$RUNNER" staging apply --expect=a,b
check "staging apply targets staging path and dir" \
  'grep -q "/srv/stg/httpdocs/current" "$STUB_LOG" && grep -q "/srv/stg/db-backups" "$STUB_LOG"'

reset_stub
EE="$(make_runner eesub EE_SUBDIR=ee/)"
run "$EE" prod status
check "EE_SUBDIR applied to eecli path" 'grep -q "ee/system/ee/eecli.php" "$STUB_LOG"'

# ---- Task 13: stamps and production gate ----
reset_stub
rm -f "$STAMPS/staging.json"
run "$RUNNER" staging apply --expect=a,b
check "staging apply without stamp -> FAIL no rehearsal" '[[ $RC -eq 1 && "$OUT" == *"no rehearsal"* ]]'
check "no stamp: no backup, no migrate" '! calls_backup >/dev/null && ! grep -q "migrate --core" "$STUB_LOG"'

reset_stub
write_stamp staging other '["a","b"]' "$(iso_ago 60)" pass ""
run "$RUNNER" staging apply --expect=a,b
check "merge scenario: other commit, same files -> allowed" '[[ $RC -eq 0 ]]'
reset_stub
write_stamp staging abc123 '["a","b"]' "$(iso_ago 60)" pass "" deadbeef0000
run "$RUNNER" staging apply --expect=a,b
check "same names, one file content differs -> FAIL naming pending_hash" \
  '[[ $RC -eq 1 && "$OUT" == *"pending_hash differs"* ]]'
check "pending_hash mismatch: no backup, no migrate" '! calls_backup >/dev/null && ! grep -q "migrate --core" "$STUB_LOG"'
reset_stub
touch "$STUB_DIR/hash-missing"
run "$RUNNER" staging apply --expect=a,b
check "migration file missing on target -> FAIL before backup" '[[ $RC -eq 1 && "$OUT" == *"could not hash"* ]] && ! calls_backup >/dev/null'
reset_stub
write_stamp staging abc123 '["a","b"]' "$(iso_ago 60)" pass ""
write_stamp staging abc123 '["a"]' "$(iso_ago 60)" pass ""
run "$RUNNER" staging apply --expect=a,b
check "stamp for other pending set -> FAIL names set" '[[ $RC -eq 1 && "$OUT" == *"different pending set"* ]]'
write_stamp staging abc123 '["a","b"]' "$(iso_ago 90000)" pass ""
run "$RUNNER" staging apply --expect=a,b
check "stamp older than 24h -> FAIL names age" '[[ $RC -eq 1 && "$OUT" == *"older than 24 h"* ]]'
write_stamp staging abc123 '["a","b"]' "$(iso_ago 60)" "" ""
run "$RUNNER" staging apply --expect=a,b
check "stamp without rehearsal pass -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"no rehearsal"* ]]'
check "all stamp failures: no migrate" '! grep -q "migrate --core" "$STUB_LOG"'

reset_stub
rm -f "$STAMPS/staging.json"
run "$RUNNER" prod apply --expect=a,b
check "prod apply (has staging) without staging stamp -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"staging apply"* ]]'
write_stamp staging abc123 '["a","b"]' "$(iso_ago 60)" pass ""
run "$RUNNER" prod apply --expect=a,b
check "prod apply with staging rehearsal only (no apply) -> FAIL" '[[ $RC -eq 1 ]]'
write_stamp staging other '["a","b"]' "$(iso_ago 60)" pass pass
run "$RUNNER" prod apply --expect=a,b
check "prod apply: staging apply with other commit, same files -> allowed" '[[ $RC -eq 0 ]]'
reset_stub
write_stamp staging abc123 '["a","b"]' "$(iso_ago 60)" pass pass deadbeef0000
run "$RUNNER" prod apply --expect=a,b
check "prod apply: staging apply for different file contents -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"pending_hash differs"* ]]'
reset_stub
run "$RUNNER" prod apply --expect=a,b
check "prod apply with staging apply pass -> OK" '[[ $RC -eq 0 ]]'
check "apply records applied_at, apply, backup" \
  '[[ "$(jq -r .apply "$STAMPS/prod.json")" == "pass" && "$(jq -r .applied_at "$STAMPS/prod.json")" != "null" && "$(jq -r .backup "$STAMPS/prod.json")" == */srv/prod/db-backups/pre_migrate_* ]]'
check "recorded stamp keeps rehearsal fields" '[[ "$(jq -r .rehearsal "$STAMPS/prod.json")" == "pass" ]]'

reset_stub
run "$NOSTG" prod apply --expect=a,b
check "HAS_STAGING=no: prod rehearsal stamp suffices" '[[ $RC -eq 0 ]]'
reset_stub
rm -f "$STAMPS/prod.json"
run "$NOSTG" prod apply --expect=a,b
check "HAS_STAGING=no: no prod rehearsal -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"no rehearsal"* ]]'
reset_stub
run "$NOSTG" prod apply --expect=a,b
check "stamp file written for success even w/o prior apply" '[[ -f "$STAMPS/prod.json" ]]'

# rehearse
reset_stub
rm -f "$STAMPS/prod.json" "$STAMPS/staging.json"
echo '{"pending":["a","b"],"missing_files":[],"commit":"abc123","counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' \
  > "$STUB_DIR/migrate-status.json"
echo '{"pending":["a","b"],"counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/local-status.json"
run "$RUNNER" staging rehearse
check "rehearse passes" '[[ $RC -eq 0 && "$OUT" == *"rehearsal PASS"* ]]'
check "rehearse uses export/download/import only" \
  'grep -q "^export_db " "$STUB_LOG" && grep -q "^download_db " "$STUB_LOG" && grep -q "^import_db " "$STUB_LOG"'
check "rehearse never calls dev_*" '! grep -q "^dev_" "$STUB_LOG"'
check "rehearse never calls sync.sh" '! grep -q "sync\.sh" "$STUB_LOG"'
check "export_db gets defaults file, no login args" \
  'grep "^export_db " "$STUB_LOG" | grep -q "stub-host   stgdb /srv/stg/httpdocs/current MYSQL_DEFAULTS_FILE=/srv/stg/defaults"'
check "import_db targets the local DB" 'grep -q "^import_db stgdb localdb" "$STUB_LOG"'
check "snapshot before import, restore after" \
  '[[ "$(grep -n "ddev snapshot --name ee-migrate-" "$STUB_LOG" | cut -d: -f1)" -lt "$(grep -n "^import_db" "$STUB_LOG" | cut -d: -f1)" && "$(grep -n "^import_db" "$STUB_LOG" | cut -d: -f1)" -lt "$(grep -n "ddev snapshot restore ee-migrate-" "$STUB_LOG" | cut -d: -f1)" ]]'
check "snapshot deleted afterwards" 'grep -q "ddev snapshot --cleanup --name ee-migrate-" "$STUB_LOG"'
check "local loop runs migrate+verify per file with schema-check" \
  '[[ "$(grep -c "ddev .*migrate --core --steps=1" "$STUB_LOG")" -eq 2 ]] && grep -q "migrate-verify a" "$STUB_LOG" && grep -q "migrate-verify b" "$STUB_LOG" && grep -q "schema-check --json --compare" "$STUB_LOG"'
check "rehearsal stamp stores target-computed pending_hash" '[[ "$(jq -r .pending_hash "$STAMPS/staging.json")" == "aaaa1111bbbb" ]]'
check "rehearsal hashes the target release files (ssh), not local" 'grep -q "sha256sum" "$STUB_LOG"'
check "rehearsal stamp written" \
  '[[ "$(jq -r .rehearsal "$STAMPS/staging.json")" == "pass" && "$(jq -r .commit "$STAMPS/staging.json")" == "abc123" && "$(jq -c .pending "$STAMPS/staging.json")" == "[\"a\",\"b\"]" && "$(jq -r .apply "$STAMPS/staging.json")" == "null" ]]'
run "$RUNNER" staging apply --expect=a,b
check "rehearse stamp then satisfies staging apply" '[[ $RC -eq 0 ]]'

reset_stub
rm -f "$STAMPS/staging.json"
echo '{"pending":["a"],"commit":"abc123","counts":{"tables":11,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/migrate-status.json"
echo '{"pending":["a"],"counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/local-status.json"
run "$RUNNER" staging rehearse
check "count mismatch -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"import verification failed"* ]]'
check "count mismatch: snapshot still restored" 'grep -q "ddev snapshot restore ee-migrate-" "$STUB_LOG"'
check "count mismatch: no stamp, no local migrate" '[[ ! -f "$STAMPS/staging.json" ]] && ! grep -q "migrate --core" "$STUB_LOG"'

for case_ in "5 5 ok" "6 5 ok" "105 5 ok" "4 5 fail" "106 5 fail"; do
  read -r l_titles r_titles want <<<"$case_"
  reset_stub
  rm -f "$STAMPS/staging.json"
  echo "{\"pending\":[\"a\"],\"commit\":\"abc123\",\"counts\":{\"tables\":10,\"channel_titles\":$r_titles,\"channel_fields\":3}}" > "$STUB_DIR/migrate-status.json"
  echo "{\"pending\":[\"a\"],\"counts\":{\"tables\":10,\"channel_titles\":$l_titles,\"channel_fields\":3}}" > "$STUB_DIR/local-status.json"
  run "$RUNNER" staging rehearse
  if [[ $want == ok ]]; then check "titles local $l_titles vs remote $r_titles -> accepted" '[[ $RC -eq 0 ]]'
  else check "titles local $l_titles vs remote $r_titles -> rejected" '[[ $RC -eq 1 && "$OUT" == *"channel_titles"* ]]'; fi
done
reset_stub
rm -f "$STAMPS/staging.json"
echo '{"pending":["a"],"commit":"abc123","counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/migrate-status.json"
echo '{"pending":["a"],"counts":{"tables":10,"channel_titles":5,"channel_fields":4}}' > "$STUB_DIR/local-status.json"
run "$RUNNER" staging rehearse
check "channel_fields must match exactly" '[[ $RC -eq 1 && "$OUT" == *"channel_fields differ"* ]]'

reset_stub
rm -f "$STAMPS/staging.json"
touch "$STUB_DIR/import-fail"
run "$RUNNER" staging rehearse
check "import failure -> FAIL, snapshot restored" '[[ $RC -eq 1 ]] && grep -q "ddev snapshot restore ee-migrate-" "$STUB_LOG"'

reset_stub
echo '{"pending":["a"],"commit":"abc123","counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/migrate-status.json"
rm -f "$STAMPS/staging.json"
echo 1 > "$STUB_DIR/local-verify-exit-a"
run "$RUNNER" staging rehearse
check "local verify failure -> FAIL, restored, no stamp" \
  '[[ $RC -eq 1 ]] && grep -q "ddev snapshot restore ee-migrate-" "$STUB_LOG" && [[ ! -f "$STAMPS/staging.json" || "$(jq -r .rehearsal "$STAMPS/staging.json")" != "pass" ]]'

reset_stub
touch "$STUB_DIR/restore-fail"
echo '{"pending":["a"],"commit":"abc123","counts":{"tables":10,"channel_titles":5,"channel_fields":3}}' > "$STUB_DIR/migrate-status.json"
run "$RUNNER" staging rehearse
check "restore failure is loud and exits 1" '[[ $RC -eq 1 && "$OUT" == *"could not restore local snapshot"* ]]'

# preflight
reset_stub
EE_MIGRATE_FUNCTIONS="$work/missing-lib.sh" run "$RUNNER" staging rehearse
check "missing library -> exit 2" '[[ $RC -eq 2 && "$OUT" == *"shared sync library not found"* ]]'
check "missing library: no snapshot" '! grep -q "ddev snapshot" "$STUB_LOG"'
printf 'export_db() { :; }\nimport_db() { :; }\n' > "$work/lib-partial.sh"
EE_MIGRATE_FUNCTIONS="$work/lib-partial.sh" run "$RUNNER" staging rehearse
check "library lacking download_db -> exit 2 naming it" '[[ $RC -eq 2 && "$OUT" == *"does not define download_db"* ]]'
check "partial library: no snapshot, no ssh" '! grep -q "ddev snapshot" "$STUB_LOG" && ! grep -q "^ssh" "$STUB_LOG"'
EMPTYDEF="$(make_runner emptydef STAGING_MYSQL_DEFAULTS=)"
run "$EMPTYDEF" staging rehearse
check "empty defaults path -> exit 2, no snapshot" '[[ $RC -eq 2 ]] && ! grep -q "ddev snapshot" "$STUB_LOG"'

# ---- Task 14: local test ----
LOCALMIG=a
reset_stub
run "$RUNNER" local test "$LOCALMIG"
check "local test passes" '[[ $RC -eq 0 && "$OUT" == *"local test PASS"* ]]'
lcalls() { grep '^ddev ' "$STUB_LOG" | sed -E -e 's/^ddev exec php system\/ee\/eecli\.php //' -e 's/^ddev mysql .*/mysql-dump/' \
  -e 's/ --baseline=.*/ --baseline/' -e 's/ --compare=.*/ --compare/'; }
expected_local="$(printf '%s\n' 'cps:migrate-status --json' backup:database 'cps:schema-check --json --baseline' mysql-dump \
  'migrate --core --steps=1' 'cps:migrate-verify a' 'cps:schema-check --json --compare' 'migrate:rollback --steps=1' \
  mysql-dump 'migrate --core --steps=1' 'cps:schema-check --json --compare')"
check "local test order per spec 7.1" '[[ "$(lcalls)" == "$expected_local" ]]'
check "local test: settings dumps under .admin-scripts/.ee-migrate" \
  '[[ -s "$EE_MIGRATE_REPO_ROOT/.admin-scripts/.ee-migrate/local-settings-before.txt" ]]'

reset_stub
echo '{"pending":["a","z"]}' > "$STUB_DIR/local-status.json"
run "$RUNNER" local test a
check "other pending locally -> FAIL listing them" '[[ $RC -eq 1 && "$OUT" == *"[a,z]"* ]]'
check "other pending: nothing run" '! grep -q "backup:database\|migrate --core" "$STUB_LOG"'

reset_stub
echo 100 > "$STUB_DIR/local-backup-size"
run "$RUNNER" local test a
check "tiny local backup -> FAIL before migrate" '[[ $RC -eq 1 && "$OUT" == *"backup too small"* ]] && ! grep -q "migrate --core" "$STUB_LOG"'

reset_stub
echo 1 > "$STUB_DIR/local-verify-exit-a"
run "$RUNNER" local test a
check "verify failure -> FAIL with rollback+restore" \
  '[[ $RC -eq 1 && "$OUT" == *"rollback:"* && "$OUT" == *"restore (Robert runs this):"* ]] && ! grep -q "migrate:rollback --steps=1$" "$STUB_LOG"'

reset_stub
echo 1 > "$STUB_DIR/local-compare-exit"
run "$RUNNER" local test a
check "new schema failures -> FAIL" '[[ $RC -eq 1 && "$OUT" == *"new failures"* ]]'

reset_stub
echo "schema-state-2" > "$STUB_DIR/mysql-after"
run "$RUNNER" local test a
check "dump differs after rollback -> FAIL, no second migrate" \
  '[[ $RC -eq 1 && "$OUT" == *"differ after rollback"* && "$(grep -c "migrate --core" "$STUB_LOG")" -eq 1 ]]'

# ---- Coilpack: REMOTE_EECLI ----
COIL="$(make_runner coil 'REMOTE_EECLI="$REMOTE_PHP" artisan eecli')"
reset_stub
run "$COIL" prod apply --expect=a,b
check "REMOTE_EECLI: apply passes" '[[ $RC -eq 0 ]]'
check "REMOTE_EECLI: artisan eecli for status/migrate/backup/verify/schema" \
  'grep -q "\"/usr/bin/php\" artisan eecli cps:migrate-status --json" "$STUB_LOG" && grep -q "artisan eecli migrate --core --steps=1" "$STUB_LOG" && grep -q "artisan eecli backup:database" "$STUB_LOG" && grep -q "artisan eecli cps:migrate-verify a" "$STUB_LOG" && grep -q "artisan eecli cps:schema-check --no-smoke --json --baseline" "$STUB_LOG"'
check "REMOTE_EECLI: no system/ee/eecli.php anywhere" '! grep -q "system/ee/eecli.php" "$STUB_LOG"'
reset_stub
echo 1 > "$STUB_DIR/verify-exit-a"
run "$COIL" prod apply --expect=a,b
check "REMOTE_EECLI: rollback hint uses artisan" '[[ "$OUT" == *"artisan eecli migrate:rollback --steps=1"* ]]'
reset_stub
run "$RUNNER" prod apply --expect=a,b
check "REMOTE_EECLI empty: default eecli.php path unchanged" 'grep -q "/usr/bin/php. system/ee/eecli.php" "$STUB_LOG" && ! grep -q "artisan" "$STUB_LOG"'

# runner installed before REMOTE_EECLI existed: variable absent from the config block
sed '/^REMOTE_EECLI=/d' "$RUNNER" > "$work/old.sh"; chmod +x "$work/old.sh"
reset_stub
run "$work/old.sh" prod apply --expect=a,b
check "config block without REMOTE_EECLI still works" '[[ $RC -eq 0 ]]'

# pending hash: empty pending list never touches the migrations directory
reset_stub
echo '{"pending":[],"missing_files":[],"commit":"abc123","counts":{}}' > "$STUB_DIR/migrate-status.json"
run "$RUNNER" prod status
check "empty pending list: status ok, no hash call" '[[ $RC -eq 0 ]] && ! grep -q sha256sum "$STUB_LOG"'
check "empty pending: PENDING_HASH computed without ssh" \
  '(source <(sed -n "/^remote_pending_hash() {/,/^}/p" "$TEMPLATE"); target_path() { :; }; remote_pending_hash ""; [[ "$PENDING_HASH" == none ]])'
reset_stub
touch "$STUB_DIR/hash-missing"
run "$RUNNER" prod apply --expect=a,b
check "non-empty pending with missing file still fails" '[[ $RC -eq 1 && "$OUT" == *"could not hash"* ]]'

echo
echo "Passed: $pass  Failed: $fail"
[[ $fail -eq 0 ]]
