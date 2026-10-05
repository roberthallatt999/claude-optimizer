#!/usr/bin/env bash
# run-fixtures.sh <site-repo> [type...] — prove the fieldtype references against a site's DDEV.
#
# For each fixture (all, or the named types): copy fixture + helper into the migrations folder, migrate,
# cps:migrate-verify, cps:schema-check --compare, rollback, settings dump byte-identical to the baseline,
# remove the files. Takes ONE database backup first. Local DDEV only; never touches a server.
# Re-run after every EE upgrade. Exit 0 only when every fixture passed and nothing was left behind.
#
# Options: --fresh-backup   force a new database backup (default: see below)
#          --cleanup        run no fixture: back up, then remove every cpsref* leftover of an earlier failed run
#                           (the cleanup migration), and report what remains. Use when a run refuses to start
#                           with "cpsref rows already exist locally".
#
# Behaviours:
#  1. Cleans up after itself: if this run created the site's database/migrations folder (and/or its parent
#     database folder) it removes them again at exit when empty (rmdir only, never rm -r), on every exit path.
#  2. Reuses a recent backup: when the newest backup file in the site's EE cache dir is under 60 minutes old and
#     passes the size rule, it is reused ("reusing backup <name> (N min old)") instead of taking a new ~100 MB
#     one. Fixtures are self-cleaning; the backup is only the safety net. --fresh-backup forces a new one.
#  3. Skips what the site cannot run: a fixture whose fieldtype is not in the site's exp_fieldtypes prints
#     "SKIP <type> (fieldtype not installed on this site)"; a fixture whose reference front matter has
#     fixture_site: <other site> is skipped too, but only when the reference is origin: legacy or third-party
#     (core fixtures run everywhere). Skips never fail the run; the summary reads "N passed, M failed, K skipped".
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$HERE/fixtures"
MIN_FIRST_BACKUP_BYTES=1048576   # same rule as ee-migrate.sh: first backup >= 1 MB, else >= 90% of the previous

die() { echo "run-fixtures: $*" >&2; exit 2; }

[[ $# -ge 1 ]] || die "usage: run-fixtures.sh <site-repo> [type...]"
SITE_REPO="$(cd "$1" 2>/dev/null && pwd)" || die "site repo not found: $1"
shift
TYPES=()
FRESH_BACKUP=0
CLEANUP_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --fresh-backup) FRESH_BACKUP=1 ;;
    --cleanup) CLEANUP_ONLY=1; FRESH_BACKUP=1 ;;
    *) TYPES+=("$arg") ;;
  esac
done
SITE_NAME="$(basename "$SITE_REPO")"
MIG_CREATED=0
DB_DIR_CREATED=0

CONF="$SITE_REPO/.admin-scripts/ee-migrate.sh"
[[ -f "$CONF" ]] || die "no .admin-scripts/ee-migrate.sh in $SITE_REPO"
conf_value() { grep -m1 "^$1=" "$CONF" | sed -E 's/^[A-Z_]+=//; s/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"']$//'; }
LOCAL_EECLI="$(conf_value LOCAL_EECLI)"
LOCAL_DB="$(conf_value LOCAL_DB)"
EE_SUBDIR="$(conf_value EE_SUBDIR)"
[[ -n "$LOCAL_EECLI" && -n "$LOCAL_DB" ]] || die "LOCAL_EECLI / LOCAL_DB not set in $CONF"

cd "$SITE_REPO" || die "cannot cd to $SITE_REPO"
MIG_REL="${EE_SUBDIR}system/user/database/migrations"
MIG="$SITE_REPO/$MIG_REL"
EM_REL=".admin-scripts/.ee-migrate"
EM_DIR="$SITE_REPO/$EM_REL"
mkdir -p "$EM_DIR"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/run-fixtures.XXXXXX")"

eecli() { $LOCAL_EECLI "$@"; }
if ddev mutagen status 2>&1 | grep -qi 'not enabled'; then sync_files() { :; }; else sync_files() { ddev mutagen sync >/dev/null 2>&1; }; fi
file_bytes() { wc -c < "$1" | tr -d ' '; }

COPIED=()
cleanup_files() {
  local name
  for name in ${COPIED[@]+"${COPIED[@]}"}; do rm -f "${MIG:?}/${name:?}.php"; done
  rm -f "${MIG:?}/CpsRefFixture.php" "${MIG:?}/2099_02_01_999999_cpsref_cleanup.php"
  # Remove folders this run created, only when empty (rmdir never removes content).
  [[ $MIG_CREATED -eq 1 ]] && rmdir "$MIG" 2>/dev/null
  [[ $DB_DIR_CREATED -eq 1 ]] && rmdir "$(dirname "$MIG")" 2>/dev/null
  sync_files
}
trap cleanup_files EXIT
trap 'exit 130' INT TERM

# Fixtures to run
FIXTURES=()
if [[ ${#TYPES[@]} -eq 0 ]]; then
  for f in "$FIXTURE_DIR"/2099_02_01_*_cpsref_*.php; do
    [[ -e "$f" && "$f" != *_999999_cpsref_cleanup.php ]] && FIXTURES+=("$(basename "$f" .php)")
  done
else
  for t in "${TYPES[@]}"; do
    [[ "$t" =~ ^[a-z_]+$ ]] || die "invalid type: $t"
    match="$(ls "$FIXTURE_DIR"/2099_02_01_*_cpsref_"$t".php 2>/dev/null | head -1)"
    [[ -n "$match" ]] || die "no fixture for type: $t"
    FIXTURES+=("$(basename "$match" .php)")
  done
fi
[[ ${#FIXTURES[@]} -gt 0 ]] || die "no fixtures found in $FIXTURE_DIR"

# Refuse if anything is pending or a previous run left fixture rows
out="$(eecli cps:migrate-status --json 2>&1)"
jq -e '.pending | type == "array"' >/dev/null 2>&1 <<<"$out" || die "cps:migrate-status unreadable: $(head -c 200 <<<"$out")"
db_name="$(jq -r '.database // ""' <<<"$out")"
[[ -z "$db_name" || "$db_name" == "$LOCAL_DB" ]] \
  || die "LOCAL_DB is [$LOCAL_DB] but EE is connected to [$db_name] — fix LOCAL_DB in .admin-scripts/ee-migrate.sh"
[[ "$(jq -r '.pending | length' <<<"$out")" -eq 0 ]] || die "migrations are pending locally ($(jq -r '.pending | join(",")' <<<"$out")); resolve first"
[[ -d "$(dirname "$MIG")" ]] || DB_DIR_CREATED=1
[[ -d "$MIG" ]] || MIG_CREATED=1
mkdir -p "$MIG"

leftovers() {
  ddev mysql "$LOCAL_DB" -N -e "SELECT (SELECT COUNT(*) FROM exp_channels WHERE channel_name LIKE 'cpsref%')+(SELECT COUNT(*) FROM exp_channel_fields WHERE field_name LIKE 'cpsref%')+(SELECT COUNT(*) FROM exp_grid_columns WHERE col_name LIKE 'cpsref%')+(SELECT COUNT(*) FROM exp_field_groups WHERE group_name LIKE 'cpsref%')+(SELECT COUNT(*) FROM exp_channel_titles WHERE url_title LIKE 'cpsref%')+(SELECT COUNT(*) FROM exp_migrations WHERE migration LIKE '2099_02_01%')" 2>&1
}
[[ $CLEANUP_ONLY -eq 1 || "$(leftovers)" == "0" ]] \
  || die "cpsref rows already exist locally; remove them first (run-fixtures.sh <site-repo> --cleanup)"

# One backup (size-checked like the runner)
cache="$SITE_REPO/${EE_SUBDIR}system/user/cache"
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }
size_ok() { # size_ok <file> <previous-file-or-empty>
  local size prev_size
  size="$(file_bytes "$1")"
  if [[ -z "$2" ]]; then [[ "$size" -ge "$MIN_FIRST_BACKUP_BYTES" ]]; else
    prev_size="$(file_bytes "$2")"; [[ $((size * 100)) -ge $((prev_size * 90)) ]]
  fi
}
before="$(ls -t "$cache"/*.sql* 2>/dev/null)"
newest="$(head -1 <<<"$before")"
second="$(sed -n 2p <<<"$before")"
new=""
if [[ $FRESH_BACKUP -eq 0 && -n "$newest" && -s "$newest" ]]; then
  age_min=$(( ($(date +%s) - $(file_mtime "$newest")) / 60 ))
  if [[ $age_min -lt 60 ]] && size_ok "$newest" "$second"; then
    new="$newest"
    echo "run-fixtures: reusing backup $(basename "$new") ($age_min min old)"
  fi
fi
if [[ -z "$new" ]]; then
  eecli backup:database >/dev/null || die "backup:database failed, nothing run"
  after="$(ls -t "$cache"/*.sql* 2>/dev/null)"
  new="$(comm -13 <(sort <<<"$before") <(sort <<<"$after") | head -1)"
  [[ -n "$new" && -s "$new" ]] || die "backup produced no new file in $cache, nothing run"
  size_ok "$new" "$newest" || die "backup too small ($(file_bytes "$new") bytes), nothing run"
  echo "run-fixtures: backup OK $new ($(file_bytes "$new") bytes)"
fi
new_size="$(file_bytes "$new")"

settings_dump() {
  ddev mysql "$LOCAL_DB" -N -e "SELECT field_id, field_name, field_type, field_settings FROM exp_channel_fields ORDER BY field_id; SELECT col_id, field_id, col_name, col_type, col_settings FROM exp_grid_columns ORDER BY col_id; SHOW TABLES;" > "$1" \
    && [[ -s "$1" ]]
}

CLEANUP="2099_02_01_999999_cpsref_cleanup"
newest_migration() {
  ddev mysql "$LOCAL_DB" -N -e "SELECT migration FROM exp_migrations ORDER BY migration_id DESC LIMIT 1" 2>&1
}
ANCHOR="$(newest_migration)"   # the newest REAL migration; it must still be the newest after every fixture
ABORTED=0

if [[ $CLEANUP_ONLY -eq 1 ]]; then
  echo "run-fixtures: cleanup only; $(leftovers) cpsref/2099_02_01 rows before"
  cp "$FIXTURE_DIR/CpsRefFixture.php" "$FIXTURE_DIR/$CLEANUP.php" "$MIG/"
  sync_files
  eecli migrate --core --steps=1 2>&1 | tail -3
  if [[ "$(newest_migration)" == "$CLEANUP" ]]; then
    eecli migrate:rollback --steps=1 2>&1 | tail -2
  else
    echo "run-fixtures: cleanup migration was not recorded; nothing rolled back"
  fi
  rm -f "$MIG/$CLEANUP.php" "$MIG/CpsRefFixture.php"
  sync_files
  [[ "$(newest_migration)" == "$ANCHOR" ]] \
    || die "newest recorded migration is now '$(newest_migration)', was '$ANCHOR'; restore from $new"
  left="$(leftovers)"
  echo "run-fixtures: cleanup done; $left cpsref/2099_02_01 rows remain (backup $new)"
  [[ "$left" == "0" ]]
  exit $?
fi

BASELINE="$EM_REL/fixtures-baseline.json"
eecli cps:schema-check --json "--baseline=$BASELINE" >/dev/null
[[ $? -lt 2 ]] || die "baseline schema-check could not run"
settings_dump "$EM_DIR/fixtures-settings-before.txt" || die "settings snapshot failed"

PASSED=0
SKIPPED=0
INSTALLED_TYPES="$(ddev mysql "$LOCAL_DB" -N -e "SELECT name FROM exp_fieldtypes" 2>/dev/null)"
FAILED=0
FAILED_NAMES=()

run_fixture() {
  local name="$1" type="${1#*_cpsref_}" log="$LOG_DIR/fixture-$1.log"
  : > "$log"
  if ! grep -qx "$type" <<<"$INSTALLED_TYPES"; then
    echo "SKIP $type (fieldtype not installed on this site)"; SKIPPED=$((SKIPPED + 1)); return
  fi
  local ref="$HERE/$type.md" ref_origin ref_site
  if [[ -f "$ref" ]]; then
    ref_origin="$(sed -n '1,/^---$/{s/^origin:[[:space:]]*\([a-z-]*\).*/\1/p;}' "$ref" | head -1)"
    ref_site="$(sed -n '1,/^---$/{s/^fixture_site:[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p;}' "$ref" | head -1)"
    if [[ "$ref_origin" =~ ^(legacy|third-party)$ && -n "$ref_site" && "$ref_site" != "$SITE_NAME" ]]; then
      echo "SKIP $type (fixture is for site $ref_site)"; SKIPPED=$((SKIPPED + 1)); return
    fi
  fi
  cp "$FIXTURE_DIR/CpsRefFixture.php" "$FIXTURE_DIR/$name.php" "$MIG/"
  COPIED+=("$name")
  sync_files

  local ok=1 migrated=0
  # eecli exits 0 even after an uncaught fatal inside up(), so trust the migrations table, not the exit code.
  eecli migrate --core --steps=1 >>"$log" 2>&1
  if [[ "$(ddev mysql "$LOCAL_DB" -N -e "SELECT COUNT(*) FROM exp_migrations WHERE migration = '$name'" 2>&1)" != "1" ]]; then
    echo "  migrate failed"; ok=0
  else
    migrated=1
    eecli cps:migrate-verify "$name" >>"$log" 2>&1 || { echo "  verify failed"; ok=0; }
    if [[ $ok -eq 1 ]] && ! eecli cps:schema-check --json "--compare=$BASELINE" >>"$log" 2>&1; then
      echo "  schema-check (smoke on) reports new failures or could not run"; ok=0
    fi
  fi

  # Never roll back on an exit code: eecli migrate exits 0 when up() throws, and --steps=1 then undoes whatever
  # is newest, i.e. a real migration. Roll back only when the newest recorded migration is the one we just ran.
  if [[ $migrated -eq 1 ]]; then
    if [[ "$(newest_migration)" == "$name" ]]; then
      eecli migrate:rollback --steps=1 >>"$log" 2>&1 || { echo "  rollback failed"; ok=0; }
    else
      echo "  rollback refused: newest recorded migration is '$(newest_migration)', not the fixture"; ok=0
    fi
  else
    # A failed up() has no migration row, so it cannot be rolled back; a cleanup migration removes cpsref*.
    # The failed fixture must leave the folder first: it sorts before the cleanup, so --steps=1 would re-run it.
    rm -f "$MIG/$name.php"
    cp "$FIXTURE_DIR/$CLEANUP.php" "$MIG/"
    sync_files
    eecli migrate --core --steps=1 >>"$log" 2>&1
    if [[ "$(newest_migration)" == "$CLEANUP" ]]; then
      eecli migrate:rollback --steps=1 >>"$log" 2>&1 || echo "  cleanup rollback failed"
    else
      echo "  cleanup migration was not recorded; nothing rolled back"
    fi
    rm -f "$MIG/$CLEANUP.php"
  fi
  rm -f "$MIG/$name.php" "$MIG/CpsRefFixture.php"
  sync_files

  settings_dump "$EM_DIR/fixtures-settings-after.txt" || { echo "  settings snapshot failed"; ok=0; }
  if ! cmp -s "$EM_DIR/fixtures-settings-before.txt" "$EM_DIR/fixtures-settings-after.txt"; then
    echo "  schema/settings differ after rollback (diff $EM_DIR/fixtures-settings-before.txt $EM_DIR/fixtures-settings-after.txt)"
    ok=0
  fi

  if [[ "$(newest_migration)" != "$ANCHOR" ]]; then
    echo "  ABORT: newest recorded migration is now '$(newest_migration)', was '$ANCHOR' before the run."
    echo "  A real migration may have been rolled back. Restore from $new or re-apply it; no further fixtures run."
    ok=0; ABORTED=1
  fi

  if [[ $ok -eq 1 ]]; then
    echo "PASS $type"; PASSED=$((PASSED + 1))
  else
    echo "FAIL $type (log: $log)"; FAILED=$((FAILED + 1)); FAILED_NAMES+=("$type")
  fi
}

for name in "${FIXTURES[@]}"; do
  run_fixture "$name"
  [[ $ABORTED -eq 0 ]] || break
done

left="$(leftovers)"
if [[ "$left" != "0" ]]; then
  echo "FAIL leftovers: $left cpsref/2099_02_01 rows remain"
  FAILED=$((FAILED + 1))
fi

echo "run-fixtures: logs in $LOG_DIR"
echo "run-fixtures: $PASSED passed, $FAILED failed, $SKIPPED skipped (backup $new)"
[[ $FAILED -eq 0 ]]
