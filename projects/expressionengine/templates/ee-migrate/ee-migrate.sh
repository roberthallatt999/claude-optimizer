#!/usr/bin/env bash
# ee-migrate.sh — the only path an EE migration takes to a server. See the EE Migrate spec.
#   local test <migration>
#   <staging|prod> status | rehearse | apply --expect=<m1,m2,…>
set -uo pipefail
EE_MIGRATE_VERSION="1.0.0"
# >>> site config (preserved by ee-migrate-install.sh)
SITE=""                 # e.g. cps
SSH_HOST=""             # e.g. websvr-cps
REMOTE_PHP=""           # e.g. /opt/plesk/php/8.2/bin/php
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
LOCAL_EECLI="ddev exec php system/ee/eecli.php"   # "ddev ee" for diabetes and intranet-backend
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

# Run an eecli command in the target release dir. Output goes to stdout, rc is ssh's.
remote_eecli() {
  ssh "$SSH_HOST" "cd '$(target_path)' && '$REMOTE_PHP' ${EE_SUBDIR}system/ee/eecli.php $*"
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

# Task 13: stamp + rehearsal gate (target, commit, pending set, age; staging.json for prod).
require_rehearsal_stamp() {
  return 0
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
  # POSIX sh on the server; every step prints a tagged line the checks below read.
  script="cd '$(target_path)' || exit 11
'$REMOTE_PHP' ${EE_SUBDIR}system/ee/eecli.php backup:database --absolute_path='${dir}/' --file_name='${BACKUP_NAME}${DUMP_SUFFIX}' || { echo BACKUP_CMD_FAILED; exit 0; }
[ -f '${file}' ] || { echo NEW_MISSING; exit 0; }
chmod 600 '${file}'
echo \"NEW \$(stat -c '%s %a' '${file}')\"
prev=\$(ls -t '${dir}'/pre_* 2>/dev/null | grep -vxF '${file}' | head -1)
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
  echo "  rollback: ssh $SSH_HOST \"cd '$(target_path)' && '$REMOTE_PHP' ${EE_SUBDIR}system/ee/eecli.php migrate:rollback --steps=1\"" >&2
  echo "  restore:  ssh $SSH_HOST \"mysql --defaults-extra-file='$(target_defaults)' '$(target_db)' < '${BACKUP_FILE}'\"" >&2
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

# Structural only (--no-smoke is forced on servers). No baseline exists on the server, so
# exit 1 (failures, possibly pre-existing) is reported, not fatal; exit 2 (could not run) is.
post_check() {
  local out rc
  out="$(remote_eecli cps:schema-check --no-smoke --json 2>&1)"
  rc=$?
  if [[ $rc -ge 2 ]]; then
    echo "ee-migrate: FAIL post-migration schema-check could not run (exit $rc)" >&2
    print_recovery
    exit 1
  fi
  echo "ee-migrate: schema-check exit $rc: $(jq -c '.summary' 2>/dev/null <<<"$out")"
  if [[ $rc -ne 0 ]]; then
    echo "ee-migrate: WARN schema-check reports failures; compare with 'status' output from before the run" >&2
  fi
}

cmd_apply() {
  remote_status
  assert_pending_equals
  require_rehearsal_stamp
  backup_remote
  apply_loop
  post_check
  echo "ee-migrate: apply OK on $TARGET"
  echo "  backup: $BACKUP_FILE"
  print_recovery
}

main() {
  parse_args "$@"
  require_config
  check_backup_dir
  case "$MODE/$ACTION" in
    remote/apply) cmd_apply ;;
    remote/status)
      remote_status
      echo "$STATUS_JSON"
      ;;
    *) die "$MODE $ACTION is not implemented yet" ;;
  esac
}

main "$@"
