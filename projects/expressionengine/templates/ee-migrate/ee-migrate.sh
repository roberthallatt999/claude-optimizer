#!/usr/bin/env bash
# ee-migrate.sh — the only path an EE migration takes to a server. See the EE Migrate spec.
#   local test <migration>
#   <staging|prod> status | rehearse | apply --expect=<m1,m2,…>
# Note: the remote backup verification script (stat -c, ls -t, chmod) and the server-side
# schema-check baseline are first exercised against a real server on the first real staging run.
set -uo pipefail
EE_MIGRATE_VERSION="1.1.0"
# >>> site config (preserved by ee-migrate-install.sh)
SITE=""                 # e.g. cps
SSH_HOST=""             # e.g. websvr-cps
REMOTE_PHP=""           # e.g. /opt/plesk/php/8.2/bin/php
REMOTE_EECLI=''         # empty = "$REMOTE_PHP" ${EE_SUBDIR}system/ee/eecli.php; Coilpack sites: "$REMOTE_PHP" artisan eecli
PROD_PATH=""            # release symlink, e.g. /var/www/vhosts/cps.ca/httpdocs/current
STAGING_PATH=""         # empty when HAS_STAGING=no
PROD_DB=""              # database name (for export_db)
STAGING_DB=""
PROD_MYSQL_DEFAULTS=""  # server-side defaults file path, same value sync.sh uses
STAGING_MYSQL_DEFAULTS=""
PROD_BACKUP_DIR=""      # outside the release tree, e.g. /var/www/vhosts/cps.ca/db-backups
STAGING_BACKUP_DIR=""
LOCAL_DB=""             # DDEV database, e.g. admin_cps
EE_SUBDIR=""            # "ee/" for diabetes and intranet-backend
LOCAL_EECLI="ddev exec php system/ee/eecli.php"   # Coilpack sites: "ddev exec php artisan eecli" (their "ddev ee" wrapper may drop arguments)
HAS_STAGING="yes"
# <<< site config

# Same file suffix EE's own backup:database files use (EE adds none when --file_name is given).
DUMP_SUFFIX=".sql"
MIN_FIRST_BACKUP_BYTES=1048576

MODE=""        # local | remote
TARGET=""      # staging | prod
ACTION=""      # test | status | rehearse | apply
EXPECT=""
LOCAL_MIGRATION=""
BACKUP_NAME=""
BACKUP_FILE=""
STATUS_JSON=""
PENDING_HASH=""
BASELINE_FILE=""
SNAPSHOT=""
REPO_ROOT="${EE_MIGRATE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
EM_DIR="$REPO_ROOT/.admin-scripts/.ee-migrate"
EM_REL=".admin-scripts/.ee-migrate"    # same dir as seen from the DDEV project root
STAMP_DIR="$EM_DIR/stamps"
STAMP_MAX_AGE=86400

die() { echo "ee-migrate: $*" >&2; exit 2; }
fail() { echo "ee-migrate: FAIL $*" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
usage:
  ee-migrate.sh local test <migration>
  ee-migrate.sh <staging|prod> status
  ee-migrate.sh <staging|prod> rehearse
  ee-migrate.sh <staging|prod> apply --expect=<m1,m2,...>
USAGE
  exit 2
}

valid_name() { [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]; }

parse_args() {
  [[ $# -ge 2 ]] || usage
  case "$1" in
    local)
      MODE="local"
      [[ "$2" == "test" && $# -eq 3 ]] || usage
      ACTION="test"
      LOCAL_MIGRATION="$3"
      valid_name "$LOCAL_MIGRATION" || die "invalid migration name: $LOCAL_MIGRATION"
      ;;
    staging | prod)
      MODE="remote"
      TARGET="$1"
      ACTION="$2"
      shift 2
      case "$ACTION" in
        status | rehearse)
          [[ $# -eq 0 ]] || usage
          ;;
        apply)
          [[ $# -eq 1 && "$1" == --expect=* ]] || usage
          EXPECT="${1#--expect=}"
          [[ -n "$EXPECT" ]] || die "apply needs --expect=<m1,m2,...>"
          local name
          while IFS= read -r name; do
            valid_name "$name" || die "invalid migration name in --expect: $name"
          done < <(tr ',' '\n' <<<"$EXPECT")
          ;;
        *) die "unknown action: $ACTION" ;;
      esac
      ;;
    *) die "unknown mode: $1" ;;
  esac
}

target_path() { if [[ "$TARGET" == "prod" ]]; then echo "$PROD_PATH"; else echo "$STAGING_PATH"; fi; }
target_db() { if [[ "$TARGET" == "prod" ]]; then echo "$PROD_DB"; else echo "$STAGING_DB"; fi; }
target_defaults() {
  if [[ "$TARGET" == "prod" ]]; then echo "$PROD_MYSQL_DEFAULTS"; else echo "$STAGING_MYSQL_DEFAULTS"; fi
}
target_backup_dir() {
  local dir
  if [[ "$TARGET" == "prod" ]]; then dir="$PROD_BACKUP_DIR"; else dir="$STAGING_BACKUP_DIR"; fi
  echo "${dir%/}"
}

require_config() {
  [[ "$MODE" == "remote" ]] || return 0
  if [[ "$TARGET" == "staging" && "$HAS_STAGING" != "yes" ]]; then
    die "${SITE:-this site} has no staging — use prod"
  fi
  local var
  for var in SSH_HOST REMOTE_PHP; do
    [[ -n "${!var}" ]] || die "config: $var is empty (edit the site config block)"
  done
  [[ -n "$(target_path)" ]] || die "config: $TARGET path is empty"
  [[ -n "$(target_backup_dir)" ]] || die "config: $TARGET backup dir is empty"
}

# Backups inside the release tree are deleted by the next deploy, so refuse them.
check_backup_dir() {
  [[ "$MODE" == "remote" ]] || return 0
  local dir path
  dir="$(target_backup_dir)"
  path="$(target_path)"
  path="${path%/}"
  [[ "$dir" == /* ]] || die "backup dir must be an absolute path: $dir"
  case "$dir/" in
    */httpdocs/current/* | */releases/*)
      die "backup dir must be outside the release tree: $dir"
      ;;
  esac
  if [[ "$dir" == "$path" || "$dir" == "$path"/* ]]; then
    die "backup dir must be outside the release tree: $dir"
  fi
  return 0
}

# --- remote helpers ---------------------------------------------------------

# The remote eecli prefix, run from the release root. REMOTE_EECLI comes from the config block;
# only the literal $REMOTE_PHP is substituted (string replace, never eval) so nothing else in the
# value is ever executed locally.
remote_eecli_cmd() {
  local cmd="${REMOTE_EECLI:-}"
  if [[ -z "$cmd" ]]; then
    echo "'$REMOTE_PHP' ${EE_SUBDIR}system/ee/eecli.php"
    return
  fi
  echo "${cmd//\$REMOTE_PHP/$REMOTE_PHP}"
}

# Run an eecli command in the target release dir. Output goes to stdout, rc is ssh's.
remote_eecli() {
  ssh "$SSH_HOST" "cd '$(target_path)' && $(remote_eecli_cmd) $*"
}

remote_status() {
  local out rc
  out="$(remote_eecli cps:migrate-status --json 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]] || ! jq -e '.pending | type == "array"' >/dev/null 2>&1 <<<"$out"; then
    if grep -qiE 'not found|not registered|unknown command|no such command|not defined' <<<"$out"; then
      die "cps_tools is not deployed on $TARGET — deploy it first"
    fi
    die "could not read migrate-status from $TARGET (exit $rc): $(head -c 300 <<<"$out")"
  fi
  STATUS_JSON="$out"
}

assert_pending_equals() {
  local actual missing
  actual="$(jq -r '.pending | join(",")' <<<"$STATUS_JSON")"
  if [[ "$actual" != "$EXPECT" ]]; then
    fail "pending set differs on $TARGET: expected [$EXPECT] but remote has [$actual]"
  fi
  missing="$(jq -r '(.missing_files // []) | join(",")' <<<"$STATUS_JSON")"
  [[ -z "$missing" ]] || fail "recorded migrations have no file on $TARGET: $missing"
}

# --- pending hash (binds stamps to the migration files, spec 7.0a) ----------

# sha256 over, in pending order, one line "<name> <sha256 of that file>" per migration, read from
# the TARGET release (the code that will actually run). Sets PENDING_HASH.
remote_pending_hash() {
  local names="${1//,/ }" script out rc
  if [[ -z "$names" ]]; then
    # Sites that have never had a migration have no directory; nothing to hash.
    PENDING_HASH="none"
    return 0
  fi
  script="cd '$(target_path)' || exit 13
dir='${EE_SUBDIR}system/user/database/migrations'
lines=''
for n in ${names}; do
  h=\$(sha256sum \"\$dir/\$n.php\" 2>/dev/null | cut -d' ' -f1)
  [ -n \"\$h\" ] || { echo \"MISSING \$n\"; exit 12; }
  lines=\"\$lines\$n \$h
\"
done
printf '%s' \"\$lines\" | sha256sum | cut -d' ' -f1"
  out="$(ssh "$SSH_HOST" "$script" 2>&1)"
  rc=$?
  [[ $rc -eq 0 && "$out" =~ ^[0-9a-f]{8,64}$ ]] \
    || fail "could not hash pending migration files on $TARGET (exit $rc): $(head -c 200 <<<"$out")"
  PENDING_HASH="$out"
}

# --- stamps (spec 7.0a) -----------------------------------------------------

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# iso_to_epoch <YYYY-MM-DDTHH:MM:SSZ> — UTC epoch seconds, BSD and GNU date.
iso_to_epoch() {
  if [[ "$(uname)" == "Darwin" ]]; then
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s
  else
    date -u -d "$1" +%s
  fi
}

stamp_file() { echo "$STAMP_DIR/$1.json"; }

pending_csv() { jq -r '.pending | join(",")' <<<"$STATUS_JSON"; }

write_rehearsal_stamp() {
  local commit
  commit="$(jq -r '.commit // ""' <<<"$STATUS_JSON")"
  mkdir -p "$STAMP_DIR"
  jq -n --arg target "$TARGET" --arg commit "$commit" --arg hash "$PENDING_HASH" --argjson pending "$(jq -c '.pending' <<<"$STATUS_JSON")" \
    --arg at "$(iso_now)" \
    '{target: $target, commit: $commit, pending_hash: $hash, pending: $pending, rehearsed_at: $at, rehearsal: "pass",
      applied_at: null, apply: null, backup: null}' > "$(stamp_file "$TARGET")" \
    || fail "could not write stamp for $TARGET"
}

record_apply() {
  local file base commit
  file="$(stamp_file "$TARGET")"
  mkdir -p "$STAMP_DIR"
  base='{}'
  [[ -f "$file" ]] && base="$(cat "$file")"
  commit="$(jq -r '.commit // ""' <<<"$STATUS_JSON")"
  jq --arg target "$TARGET" --arg commit "$commit" --arg expect "$EXPECT" --arg at "$(iso_now)" \
    --arg backup "$BACKUP_FILE" --arg hash "$PENDING_HASH" \
    '. + {target: $target, commit: $commit, pending_hash: $hash, pending: ($expect | split(",")), applied_at: $at,
          apply: "pass", backup: $backup}' <<<"$base" > "$file.new" \
    && mv "$file.new" "$file" || fail "could not record apply in $file"
}

# check_stamp <stamp-target> <rehearsal|apply> — same pending set and pending_hash (file contents)
# as the target release. The commit is informational only: a merge changes it without changing the files.
check_stamp() {
  local which="$1" kind="$2" file at age
  file="$(stamp_file "$which")"
  if [[ ! -f "$file" ]]; then
    if [[ "$kind" == "rehearsal" ]]; then
      fail "no rehearsal stamp for $which — run: ee-migrate.sh $which rehearse"
    fi
    fail "no recorded $which apply — apply on $which first ($file)"
  fi
  if [[ "$kind" == "rehearsal" ]]; then
    [[ "$(jq -r '.rehearsal // ""' "$file")" == "pass" ]] || fail "no rehearsal: $which stamp is not a pass"
  else
    [[ "$(jq -r '.apply // ""' "$file")" == "pass" ]] || fail "no recorded $which apply: stamp has apply != pass"
  fi
  [[ "$(jq -r '.pending | join(",")' "$file")" == "$EXPECT" ]] \
    || fail "$which stamp is for a different pending set ($(jq -r '.pending | join(",")' "$file"))"
  [[ "$(jq -r '.pending_hash // ""' "$file")" == "$PENDING_HASH" ]] \
    || fail "$which stamp pending_hash differs: the migration files changed since the stamp was written"
  if [[ "$kind" == "rehearsal" ]]; then
    at="$(jq -r '.rehearsed_at // ""' "$file")"
    age=$(($(date -u +%s) - $(iso_to_epoch "$at" 2>/dev/null || echo 0)))
    [[ $age -lt $STAMP_MAX_AGE ]] || fail "$which rehearsal stamp is older than 24 h ($at) — rehearse again"
  fi
}

# Staging sites: prod needs a recorded staging apply (spec 7.2). Everything else needs
# a rehearsal stamp for the target itself (spec 7.0a, 7.3).
require_rehearsal_stamp() {
  if [[ "$TARGET" == "prod" && "$HAS_STAGING" == "yes" ]]; then
    check_stamp staging apply
  else
    check_stamp "$TARGET" rehearsal
  fi
}

# --- backup (spec 7.1a) -----------------------------------------------------

# Pure size rule: size_ok <new_bytes> <prev_bytes|none>
size_ok() {
  local new="$1" prev="$2"
  [[ "$new" =~ ^[0-9]+$ ]] || return 1
  [[ "$new" -gt 0 ]] || return 1
  if [[ "$prev" == "none" ]]; then
    [[ "$new" -ge "$MIN_FIRST_BACKUP_BYTES" ]]
  else
    [[ "$prev" =~ ^[0-9]+$ ]] || return 1
    [[ $((new * 100)) -ge $((prev * 90)) ]]
  fi
}

backup_remote() {
  local dir stamp file script out rc new_size new_mode prev_size
  dir="$(target_backup_dir)"
  stamp="$(date -u +%Y%m%d_%H%M%S)"
  BACKUP_NAME="pre_migrate_${stamp}"
  file="${dir}/${BACKUP_NAME}${DUMP_SUFFIX}"
  BASELINE_FILE="${dir}/${BACKUP_NAME}.baseline.json"
  # POSIX sh on the server; every step prints a tagged line the checks below read.
  script="cd '$(target_path)' || exit 11
$(remote_eecli_cmd) backup:database --absolute_path='${dir}/' --file_name='${BACKUP_NAME}${DUMP_SUFFIX}' || { echo BACKUP_CMD_FAILED; exit 0; }
[ -f '${file}' ] || { echo NEW_MISSING; exit 0; }
chmod 600 '${file}'
echo \"NEW \$(stat -c '%s %a' '${file}')\"
prev=\$(ls -t '${dir}'/pre_* 2>/dev/null | grep -vxF '${file}' | grep -v '\\.baseline\\.json\$' | head -1)
if [ -n \"\$prev\" ]; then echo \"PREV \$(stat -c %s \"\$prev\")\"; else echo 'PREV none'; fi"
  out="$(ssh "$SSH_HOST" "$script" 2>&1)"
  rc=$?
  [[ $rc -eq 0 ]] || fail "backup aborted: ssh/backup step exited $rc: $(head -c 300 <<<"$out")"
  grep -q '^BACKUP_CMD_FAILED' <<<"$out" && fail "backup aborted: backup:database failed on $TARGET"
  grep -q '^NEW_MISSING' <<<"$out" && fail "backup aborted: no backup file was written at $file"

  read -r _ new_size new_mode < <(grep '^NEW ' <<<"$out" | head -1)
  prev_size="$(grep '^PREV ' <<<"$out" | head -1 | cut -d' ' -f2)"
  [[ -n "${new_size:-}" && -n "${prev_size:-}" ]] || fail "backup aborted: could not read backup details: $out"
  [[ "${new_mode:-}" == "600" ]] || fail "backup aborted: $file has mode ${new_mode:-?}, expected 600"
  if ! size_ok "$new_size" "$prev_size"; then
    if [[ "$prev_size" == "none" ]]; then
      fail "backup too small: $new_size bytes (< 1 MB, no previous file to compare) at $file"
    fi
    fail "backup too small: $new_size bytes is under 90% of previous file ($prev_size bytes) at $file"
  fi
  BACKUP_FILE="$file"
  echo "ee-migrate: backup OK $file ($new_size bytes, mode 600)"
}

# --- apply loop (spec 7.0) --------------------------------------------------

print_recovery() {
  echo "ee-migrate: recovery for $TARGET:" >&2
  echo "  rollback: ssh $SSH_HOST \"cd '$(target_path)' && $(remote_eecli_cmd) migrate:rollback --steps=1\"" >&2
  echo "  restore (Robert runs this): ssh $SSH_HOST \"mysql --defaults-extra-file='$(target_defaults)' '$(target_db)' < '${BACKUP_FILE}'\"" >&2
}

apply_loop() {
  local name
  while IFS= read -r name; do
    echo "ee-migrate: migrating $name"
    if ! remote_eecli migrate --core --steps=1; then
      echo "ee-migrate: FAIL migrate step for $name" >&2
      print_recovery
      exit 1
    fi
    if ! remote_eecli cps:migrate-verify "$name"; then
      echo "ee-migrate: FAIL verify for $name" >&2
      print_recovery
      exit 1
    fi
  done < <(tr ',' '\n' <<<"$EXPECT")
}

# Server-side structural baseline taken after the backup and before the first migrate, so the
# post-check can demand "no new failures". Kept out of pre_* size comparisons (see backup_remote).
baseline_remote() {
  local file="$BASELINE_FILE" out rc
  out="$(ssh "$SSH_HOST" "cd '$(target_path)' && $(remote_eecli_cmd) cps:schema-check --no-smoke --json --baseline='${file}' >/dev/null; rc=\$?; [ \$rc -ge 2 ] && exit \$rc; [ -s '${file}' ] || exit 12; chmod 600 '${file}'" 2>&1)"
  rc=$?
  [[ $rc -eq 0 ]] || fail "schema-check baseline failed on $TARGET (exit $rc), nothing migrated: $(head -c 200 <<<"$out")"
}

# Strict: any new failure versus the baseline, or a check that could not run, is a FAIL.
post_check() {
  local out rc
  out="$(remote_eecli cps:schema-check --no-smoke --json "--compare=${BASELINE_FILE}" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "ee-migrate: FAIL post-migration schema-check exit $rc (1 = new failures, 2 = could not run)" >&2
    head -c 2000 <<<"$out" >&2
    print_recovery
    exit 1
  fi
  echo "ee-migrate: schema-check OK: $(jq -c '.summary' 2>/dev/null <<<"$out")"
}

cmd_apply() {
  remote_status
  assert_pending_equals
  remote_pending_hash "$EXPECT"
  require_rehearsal_stamp
  backup_remote
  baseline_remote
  apply_loop
  post_check
  record_apply
  echo "ee-migrate: apply OK on $TARGET"
  echo "  backup: $BACKUP_FILE"
  print_recovery
}

# --- rehearsal (spec 7.0b) --------------------------------------------------

preflight_sync_library() {
  local lib fn
  lib="${EE_MIGRATE_FUNCTIONS:-$HOME/Web/code/_scripts/functions-websavers.sh}"
  [[ -f "$lib" ]] || die "shared sync library not found: $lib"
  # shellcheck disable=SC1090
  source "$lib"
  for fn in export_db download_db import_db; do
    declare -F "$fn" >/dev/null || die "shared sync library $lib does not define $fn"
  done
}

local_eecli() { $LOCAL_EECLI "$@"; }

# Always runs once the snapshot exists: restores it, removes the snapshot and any leftover dump.
rehearse_cleanup() {
  local rc=$?
  trap - EXIT
  rm -f "$REPO_ROOT/.admin-scripts/$(target_db).sql.gz" "$REPO_ROOT/.admin-scripts/$(target_db).sql"
  if [[ -n "$SNAPSHOT" ]]; then
    if ddev snapshot restore "$SNAPSHOT"; then
      ddev snapshot --cleanup --name "$SNAPSHOT" -y || echo "ee-migrate: WARN could not delete snapshot $SNAPSHOT" >&2
    else
      echo "ee-migrate: FAIL could not restore local snapshot — run: ddev snapshot restore $SNAPSHOT" >&2
      rc=1
    fi
  fi
  exit "$rc"
}

# Compare DDEV counts with the target's counts read just before the export (spec 7.0b).
verify_import_counts() {
  local local_out r_tables l_tables r_fields l_fields r_titles l_titles
  local_out="$(local_eecli cps:migrate-status --json 2>&1)"
  jq -e '.counts' >/dev/null 2>&1 <<<"$local_out" \
    || fail "import check: local cps:migrate-status unreadable: $(head -c 200 <<<"$local_out")"
  r_tables="$(jq -r '.counts.tables' <<<"$STATUS_JSON")"
  l_tables="$(jq -r '.counts.tables' <<<"$local_out")"
  r_fields="$(jq -r '.counts.channel_fields' <<<"$STATUS_JSON")"
  l_fields="$(jq -r '.counts.channel_fields' <<<"$local_out")"
  r_titles="$(jq -r '.counts.channel_titles' <<<"$STATUS_JSON")"
  l_titles="$(jq -r '.counts.channel_titles' <<<"$local_out")"
  [[ "$r_tables" == "$l_tables" ]] \
    || fail "import verification failed: tables differ (target $r_tables, DDEV $l_tables)"
  [[ "$r_fields" == "$l_fields" ]] \
    || fail "import verification failed: channel_fields differ (target $r_fields, DDEV $l_fields)"
  # Entries can be added on a live target between the status read and the export.
  [[ "$r_titles" =~ ^[0-9]+$ && "$l_titles" =~ ^[0-9]+$ ]] \
    || fail "import verification failed: channel_titles count unreadable"
  if [[ $l_titles -lt $r_titles || $l_titles -gt $((r_titles + 100)) ]]; then
    fail "import verification failed: channel_titles $l_titles outside $r_titles..$((r_titles + 100))"
  fi
  echo "ee-migrate: import verified (tables $l_tables, fields $l_fields, titles $l_titles)"
}

cmd_rehearse() {
  local name dump rc
  preflight_sync_library
  [[ -n "$(target_defaults)" ]] || die "config: $TARGET MySQL defaults path is empty (refusing the login fallback)"
  [[ -n "$(target_db)" && -n "$LOCAL_DB" ]] || die "config: target and local database names are required"
  remote_status
  [[ "$(jq -r '.pending | length' <<<"$STATUS_JSON")" -gt 0 ]] || die "nothing pending on $TARGET — nothing to rehearse"
  EXPECT="$(pending_csv)"
  remote_pending_hash "$EXPECT"
  dump="$REPO_ROOT/.admin-scripts/$(target_db)"
  [[ ! -e "$dump.sql.gz" && ! -e "$dump.sql" ]] || die "stale dump at $dump.* — remove it first"

  SNAPSHOT="ee-migrate-$(date -u +%Y%m%d_%H%M%S)"
  if ! ddev snapshot --name "$SNAPSHOT"; then
    SNAPSHOT=""
    fail "ddev snapshot failed, nothing imported"
  fi
  trap rehearse_cleanup EXIT
  trap 'exit 130' INT TERM

  # Only these three library functions are ever called; never sync.sh or any dev_* function.
  export MYSQL_DEFAULTS_FILE
  MYSQL_DEFAULTS_FILE="$(target_defaults)"
  SITE_NAME="${SITE}"
  export_db "$SSH_HOST" "" "" "$(target_db)" "$(target_path)" || fail "export_db failed"
  download_db "$SSH_HOST" "$(target_path)" "$(target_db)" "$(basename "$REPO_ROOT")" || fail "download_db failed"
  import_db "$(target_db)" "$LOCAL_DB" || fail "import_db failed"
  rm -f "$dump.sql.gz" "$dump.sql"
  verify_import_counts

  mkdir -p "$EM_DIR"
  local_eecli cps:schema-check --json "--baseline=$EM_REL/rehearse-baseline.json" >/dev/null
  rc=$?
  [[ $rc -lt 2 ]] || fail "local schema-check baseline could not run"
  while IFS= read -r name; do
    echo "ee-migrate: rehearsing $name locally"
    local_eecli migrate --core --steps=1 || fail "local migrate failed for $name"
    local_eecli cps:migrate-verify "$name" || fail "local verify failed for $name"
  done < <(tr ',' '\n' <<<"$EXPECT")
  local_eecli cps:schema-check --json "--compare=$EM_REL/rehearse-baseline.json" >/dev/null \
    || fail "rehearsal schema-check (smoke on) reports new failures or could not run"
  write_rehearsal_stamp
  echo "ee-migrate: rehearsal PASS for $TARGET ($EXPECT); local database will be restored from the snapshot"
}

# --- local round-trip gate (spec 7.1) ---------------------------------------

file_bytes() { wc -c < "$1" | tr -d ' '; }

print_local_recovery() {
  echo "ee-migrate: recovery (local):" >&2
  echo "  rollback: $LOCAL_EECLI migrate:rollback --steps=1" >&2
  [[ -z "$BACKUP_FILE" ]] || echo "  restore (Robert runs this): ddev import-db --database=$LOCAL_DB --file=$BACKUP_FILE" >&2
}

local_fail() {
  echo "ee-migrate: FAIL $*" >&2
  print_local_recovery
  exit 1
}

backup_local() {
  local cache before after new prev new_size prev_size
  cache="$REPO_ROOT/${EE_SUBDIR}system/user/cache"
  before="$(ls -t "$cache"/*"$DUMP_SUFFIX"* 2>/dev/null)"
  local_eecli backup:database || fail "local backup:database failed, nothing migrated"
  after="$(ls -t "$cache"/*"$DUMP_SUFFIX"* 2>/dev/null)"
  new="$(comm -13 <(sort <<<"$before") <(sort <<<"$after") | head -1)"
  [[ -n "$new" && -s "$new" ]] || fail "local backup produced no new file in $cache, nothing migrated"
  prev="$(head -1 <<<"$before")"
  new_size="$(file_bytes "$new")"
  prev_size="none"
  [[ -z "$prev" ]] || prev_size="$(file_bytes "$prev")"
  size_ok "$new_size" "$prev_size" \
    || fail "backup too small: $new_size bytes (previous: $prev_size) at $new, nothing migrated"
  BACKUP_FILE="$new"
  echo "ee-migrate: local backup OK $new ($new_size bytes)"
}

# Schema and settings snapshot written to $1 (spec 7.1: identical after rollback).
settings_dump() {
  local out="$1"
  ddev mysql "$LOCAL_DB" -N -e "SELECT field_id, field_name, field_type, field_settings FROM exp_channel_fields ORDER BY field_id; SELECT col_id, field_id, col_name, col_type, col_settings FROM exp_grid_columns ORDER BY col_id; SHOW TABLES;" > "$out" \
    || local_fail "settings snapshot failed"
  [[ -s "$out" ]] || local_fail "settings snapshot is empty"
}

cmd_local_test() {
  local out pending rc
  mkdir -p "$EM_DIR"
  out="$(local_eecli cps:migrate-status --json 2>&1)"
  jq -e '.pending | type == "array"' >/dev/null 2>&1 <<<"$out" \
    || die "local cps:migrate-status unreadable: $(head -c 200 <<<"$out")"
  pending="$(jq -r '.pending | join(",")' <<<"$out")"
  [[ "$pending" == "$LOCAL_MIGRATION" ]] \
    || fail "local pending set is [$pending], expected only [$LOCAL_MIGRATION] — resolve the others first"

  backup_local
  local_eecli cps:schema-check --json "--baseline=$EM_REL/local-baseline.json" >/dev/null
  rc=$?
  [[ $rc -lt 2 ]] || local_fail "baseline schema-check could not run"
  settings_dump "$EM_DIR/local-settings-before.txt"

  local_eecli migrate --core --steps=1 || local_fail "migrate failed"
  local_eecli cps:migrate-verify "$LOCAL_MIGRATION" || local_fail "verify failed"
  local_eecli cps:schema-check --json "--compare=$EM_REL/local-baseline.json" >/dev/null \
    || local_fail "schema-check (smoke on) reports new failures after migrate"
  local_eecli migrate:rollback --steps=1 || local_fail "rollback failed"
  settings_dump "$EM_DIR/local-settings-after.txt"
  cmp -s "$EM_DIR/local-settings-before.txt" "$EM_DIR/local-settings-after.txt" \
    || local_fail "schema/settings differ after rollback (compare $EM_DIR/local-settings-*.txt)"
  local_eecli migrate --core --steps=1 || local_fail "second migrate failed"
  local_eecli cps:schema-check --json "--compare=$EM_REL/local-baseline.json" >/dev/null \
    || local_fail "schema-check reports new failures after re-migrate"
  echo "ee-migrate: local test PASS for $LOCAL_MIGRATION (backup $BACKUP_FILE)"
}

main() {
  parse_args "$@"
  require_config
  check_backup_dir
  cd "$REPO_ROOT" || die "cannot enter $REPO_ROOT"
  case "$MODE/$ACTION" in
    remote/apply) cmd_apply ;;
    remote/rehearse) cmd_rehearse ;;
    remote/status)
      remote_status
      echo "$STATUS_JSON"
      ;;
    local/test) cmd_local_test ;;
    *) die "$MODE $ACTION is not implemented yet" ;;
  esac
}

main "$@"
