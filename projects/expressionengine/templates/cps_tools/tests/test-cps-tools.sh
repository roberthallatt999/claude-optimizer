#!/usr/bin/env bash
# test-cps-tools.sh — integration tests for cps_tools. Run from a site repo root:
#   bash <config-repo>/projects/expressionengine/templates/cps_tools/tests/test-cps-tools.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sub=""; [[ -d ee/system/user ]] && sub="ee/"
MIG="${sub}system/user/database/migrations"
if [[ -n "${LOCAL_EECLI:-}" ]]; then :; elif [[ -n "$sub" ]]; then LOCAL_EECLI="ddev ee"; else LOCAL_EECLI="ddev exec php system/ee/eecli.php"; fi
EE() { $LOCAL_EECLI "$@" 2>&1; }
EEJ() { $LOCAL_EECLI "$@" 2>/dev/null; }   # stdout only: JSON stays parseable when the command exits non-zero
STATE=".admin-scripts/.ee-migrate"
BASE="$STATE/cpstools-base.json"
PASS=0; FAIL=0
ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL $1 :: $2"; FAIL=$((FAIL+1)); }
FIXTURES=(
  2099_01_01_000000_cps_tools_status_fixture
  2099_01_01_000001_cps_tools_verify_pass
  2099_01_01_000002_cps_tools_verify_fail
  2099_01_01_000003_cps_tools_no_verify
  2099_01_01_000010_cpstools_fx_url_missing_schemes
  2099_01_01_000011_cpstools_fx_relationship_bad_shape
  2099_01_01_000020_cpstools_fx_grid_orphan_column
  2099_01_01_000021_cpstools_fx_grid_missing_data_column
  2099_01_01_000030_cpstools_fx_layout_stale_field
  2099_01_01_000031_cpstools_fx_bad_relationship_target
  2099_01_01_000032_cpstools_fx_missing_cat_group
)
cleanup() { for f in "${FIXTURES[@]}"; do rm -f "${MIG:?}/${f:?}.php"; done; rm -f "$BASE"; }
trap cleanup EXIT

# --- migrate-status ---------------------------------------------------------
STATUS_FIXTURE=${FIXTURES[0]}
out=$(EE cps:migrate-status --json)
echo "$out" | jq -e '.pending and .missing_files and .counts.tables and .counts.channel_titles and .counts.channel_fields' >/dev/null \
  && ok "status json has pending/missing_files/counts" || bad "status json shape" "$out"

[[ "$(echo "$out" | jq -r '.migrations_table')" == "true" ]] \
  && ok "status reports migrations_table true" || bad "migrations_table flag" "$out"

cp "$HERE/fixtures/$STATUS_FIXTURE.php" "$MIG/"
out=$(EE cps:migrate-status --json)
[[ "$(echo "$out" | jq -r '.pending[-1]')" == "$STATUS_FIXTURE" ]] \
  && ok "fixture is last pending (EE order)" || bad "fixture last pending" "$out"
cleanup

# --- migrate-verify ---------------------------------------------------------
verify_case() { # <fixture> <expected exit> <expected output substring> <label>
  cp "$HERE/fixtures/$1.php" "$MIG/"
  out=$(EE cps:migrate-verify "$1"); code=$?
  cleanup
  if [[ $code -eq $2 && "$out" == *"$3"* ]]; then ok "$4"; else bad "$4" "exit=$code out=$out"; fi
}
verify_case "${FIXTURES[1]}" 0 "PASS" "verify pass -> exit 0 + PASS"
verify_case "${FIXTURES[2]}" 1 "expected 4 events, found 0" "verify fail -> exit 1 + message"
verify_case "${FIXTURES[3]}" 0 "no verify()" "no verify() -> exit 0"

out=$(EE cps:migrate-verify 2099_01_01_999999_does_not_exist); code=$?
[[ $code -eq 2 && "$out" == *"not found"* ]] \
  && ok "unknown name -> exit 2 + not found" || bad "unknown name" "exit=$code out=$out"

for bad_name in ../../index foo; do
  out=$(EE cps:migrate-verify "$bad_name"); code=$?
  [[ $code -eq 2 && "$out" == *"Invalid migration name"* ]] \
    && ok "invalid name '$bad_name' -> exit 2" || bad "invalid name $bad_name" "exit=$code out=$out"
done

# --- schema-check: report + baseline/compare ---------------------------------
mkdir -p "$STATE"
out=$(EEJ cps:schema-check --no-smoke --json); code=$?
echo "$out" | jq -e '(.results|type)=="array" and (.results[0]|has("check","subject","subject_type","status","message")) and (.summary|has("pass","warn","fail"))' >/dev/null \
  && ok "schema-check json shape" || bad "schema-check json shape" "exit=$code ${out:0:300}"

EE cps:schema-check --no-smoke --json --baseline="$BASE" >/dev/null
[[ -s "$BASE" ]] && ok "schema-check --baseline writes file" || bad "baseline file" "missing $BASE"

out=$(EEJ cps:schema-check --no-smoke --json --compare="$BASE"); code=$?
[[ $code -eq 0 && "$(echo "$out" | jq -r '.new_failures')" == "0" ]] \
  && ok "compare on unchanged DB -> exit 0, new_failures 0" || bad "compare unchanged" "exit=$code ${out:0:300}"

EE cps:schema-check --no-smoke --compare=/nonexistent/baseline.json >/dev/null; code=$?
[[ $code -eq 2 ]] && ok "compare with missing baseline -> exit 2" || bad "missing baseline exit" "exit=$code"

# --- schema-check: settings contract is DDEV-only ----------------------------
if [[ "$LOCAL_EECLI" == "ddev exec "* ]]; then
  out=$(${LOCAL_EECLI/ddev exec /ddev exec env -u IS_DDEV_PROJECT } cps:schema-check --no-smoke --json 2>/dev/null)
  n=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract")]|length')
  w=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract" and .subject=="*" and .status=="warn" and .message=="settings contract skipped: not DDEV")]|length')
  [[ "$n" == 1 && "$w" == 1 ]] && ok "non-DDEV -> single skipped warn" || bad "non-DDEV skip" "n=$n w=$w ${out:0:200}"
fi

# --- schema-check: settings contract (spec defects 1 and 2) -------------------
run_fixture() {  # run_fixture <name>: copy in, migrate exactly one step
  cp "$HERE/fixtures/$1.php" "$MIG/"
  local pend; pend=$(EEJ cps:migrate-status --json)
  [[ "$(echo "$pend" | jq -r '.pending|length')" == 1 ]] \
    || { echo "ABORT: other migrations pending locally - resolve first"; rm -f "$MIG/$1.php"; exit 3; }
  EE migrate --core --steps=1 >/dev/null
}
undo_fixture() { EE migrate:rollback --steps=1 >/dev/null; rm -f "$MIG/$1.php"; }

FX_URL=${FIXTURES[4]}
FX_REL=${FIXTURES[5]}

EE cps:schema-check --no-smoke --json --baseline="$BASE" >/dev/null
run_fixture "$FX_URL"
out=$(EEJ cps:schema-check --no-smoke --json --compare="$BASE"); code=$?
[[ $code -eq 1 ]] && ok "url fixture -> compare exits 1" || bad "url fixture exit" "exit=$code"
n=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract" and .status=="fail" and .subject=="cpstools_fx_url" and (.message|test("allowed_url_schemes")))]|length')
[[ "$n" -ge 1 ]] && ok "url field failure names allowed_url_schemes (no smoke test)" || bad "url field failure" "n=$n"
n=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract" and .status=="fail" and .subject=="cpstools_fx_grid.cpstools_fx_link" and (.message|test("allowed_url_schemes")))]|length')
[[ "$n" -ge 1 ]] && ok "grid column failure names allowed_url_schemes (no smoke test)" || bad "grid column failure" "n=$n"
n=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract" and .status=="warn" and .message=="contract unavailable" and (.subject_type|IN("text","textarea","rte","number","date","duration","email_address","file","filepicker","checkboxes","radio","select","multi_select","selectable_buttons","toggle","url","relationship","grid","file_grid","fluid_field","colorpicker","slider","hidden","markdown","notes","member","emoji")))]|length')
[[ "$n" -eq 0 ]] && ok "no core fieldtype falls back to 'contract unavailable'" || bad "core type fell back to warn" "n=$n"
undo_fixture "$FX_URL"
out=$(EEJ cps:schema-check --no-smoke --json --compare="$BASE"); code=$?
[[ $code -eq 0 ]] && ok "url fixture removed -> compare exits 0" || bad "url fixture cleanup" "exit=$code"

run_fixture "$FX_REL"
out=$(EEJ cps:schema-check --no-smoke --json --compare="$BASE"); code=$?
[[ $code -eq 1 ]] && ok "relationship fixture -> compare exits 1" || bad "rel fixture exit" "exit=$code"
n=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract" and .status=="fail" and .subject=="cpstools_fx_rel" and (.message|test("type mismatch")))]|length')
[[ "$n" -ge 1 ]] && ok "relationship channels type mismatch reported" || bad "rel channels type" "n=$n"
n=$(echo "$out" | jq '[.results[]|select(.check=="settings_contract" and .status=="fail" and .subject=="cpstools_fx_rel" and (.message|test("order_field")))]|length')
[[ "$n" -ge 1 ]] && ok "relationship invalid order_field reported" || bad "rel order_field" "n=$n"
n=$(echo "$out" | jq '[.results[]|select(.message=="order_field \"nonexistent\" is not title|entry_date")]|length')
[[ "$n" -ge 1 ]] && ok "double quote in message round-trips through jq" || bad "quote round-trip" "n=$n"
undo_fixture "$FX_REL"
out=$(EEJ cps:schema-check --no-smoke --json --compare="$BASE"); code=$?
[[ $code -eq 0 ]] && ok "relationship fixture removed -> compare exits 0" || bad "rel fixture cleanup" "exit=$code"

# --- schema-check: storage, orphans, layouts, references ----------------------
# fx_case <fixture> <expected exit> <label>: baseline, migrate, compare, leaves $out/$code set, then undoes.
fx_run() {  # fx_run <fixture>: sets out/code with the fixture applied
  EE cps:schema-check --no-smoke --json --baseline="$BASE" >/dev/null
  run_fixture "$1"
  out=$(EEJ cps:schema-check --no-smoke --json --compare="$BASE"); code=$?
}
fx_done() {  # fx_done <fixture> <label>: undo and assert a clean compare
  undo_fixture "$1"
  EEJ cps:schema-check --no-smoke --json --compare="$BASE" >/dev/null; local c=$?
  [[ $c -eq 0 ]] && ok "$2 removed -> compare exits 0" || bad "$2 cleanup" "exit=$c"
}
jcount() { echo "$out" | jq "[.results[]|select($1)]|length"; }

fx_run "${FIXTURES[6]}"
[[ $code -eq 1 ]] && ok "grid orphan fixture -> exit 1" || bad "orphan exit" "exit=$code"
n=$(jcount '.check=="orphans" and .status=="fail" and (.subject|test("grid_columns"))')
[[ "$n" -ge 1 ]] && ok "orphans: NULL/0 field_id Grid column fails" || bad "orphan fail" "n=$n"
n=$(jcount '.check=="orphans" and .status=="warn" and (.subject|test("relationships"))')
[[ "$n" -ge 1 ]] && ok "orphans: relationship row to missing entry warns" || bad "rel orphan warn" "n=$n"
fx_done "${FIXTURES[6]}" "grid orphan fixture"

fx_run "${FIXTURES[7]}"
[[ $code -eq 1 ]] && ok "grid missing-column fixture -> exit 1" || bad "missing col exit" "exit=$code"
n=$(jcount '.check=="storage" and .status=="fail" and (.message|test("col_id_"))')
[[ "$n" -ge 1 ]] && ok "storage: missing col_id_N reported" || bad "storage fail" "n=$n"
fx_done "${FIXTURES[7]}" "grid missing-column fixture"

fx_run "${FIXTURES[8]}"
[[ $code -eq 1 ]] && ok "stale layout fixture -> exit 1" || bad "layout exit" "exit=$code"
n=$(jcount '.check=="layouts" and .status=="fail" and (.message|test("cpstools_fx_b.*not attached"))')
[[ "$n" -ge 1 ]] && ok "layouts: detached field B fails" || bad "layout B" "n=$n"
n=$(jcount '.check=="layouts" and .status=="warn" and (.message|test("cpstools_fx_c.*not placed"))')
[[ "$n" -ge 1 ]] && ok "layouts: unplaced field C warns" || bad "layout C" "n=$n"
fx_done "${FIXTURES[8]}" "stale layout fixture"

fx_run "${FIXTURES[9]}"
[[ $code -eq 0 ]] && ok "bad relationship target -> warn only, exit 0" || bad "bad target exit" "exit=$code"
n=$(jcount '.check=="references" and .status=="warn" and .subject=="cpstools_fx_badtarget" and (.message|test("999999"))')
[[ "$n" -ge 1 ]] && ok "references: deleted target channel warns once, names field and id" || bad "bad target warn" "n=$n"
n=$(jcount '.subject=="cpstools_fx_badtarget" and (.message|test("999999"))')
[[ "$n" -eq 1 ]] && ok "deleted target reported only once" || bad "bad target dup" "n=$n"
fx_done "${FIXTURES[9]}" "bad relationship target fixture"

fx_run "${FIXTURES[10]}"
[[ $code -eq 1 ]] && ok "missing cat group fixture -> exit 1" || bad "cat group exit" "exit=$code"
n=$(jcount '.check=="references" and .status=="fail" and .subject=="cpstools_fixture" and (.message|test("999999"))')
[[ "$n" -ge 1 ]] && ok "references: missing category group fails naming channel" || bad "cat group fail" "n=$n"
fx_done "${FIXTURES[10]}" "missing cat group fixture"

# --- schema-check: smoke test ---------------------------------------------------
count_rows() { ddev mysql admin_cps -N -e "SELECT CONCAT_WS(',',(SELECT COUNT(*) FROM exp_channel_titles),(SELECT COUNT(*) FROM exp_channel_data),(SELECT COUNT(*) FROM exp_relationships),(SELECT COUNT(*) FROM exp_grid_columns),(SELECT COUNT(*) FROM exp_channel_fields),(SELECT COUNT(*) FROM exp_migrations))" 2>&1; }

run_fixture "$FX_URL"
rows_before=$(count_rows)
out=$(EEJ cps:schema-check --json); code=$?
n=$(jcount '.check=="smoke" and .status=="fail" and .subject=="cpstools_fx_url" and (.message|test("in_array"))')
[[ "$n" -ge 1 ]] && ok "smoke: URL field in_array crash caught" || bad "smoke url field" "n=$n"
n=$(jcount '.check=="smoke" and .status=="fail" and .subject=="cpstools_fx_grid.cpstools_fx_link" and (.message|test("in_array"))')
[[ "$n" -ge 1 ]] && ok "smoke: Grid URL column in_array crash caught" || bad "smoke grid column" "n=$n"
EEJ cps:schema-check --json >/dev/null
rows_after=$(count_rows)
[[ "$rows_before" == "$rows_after" ]] && ok "smoke leaves row counts unchanged ($rows_after)" || bad "smoke changed rows" "$rows_before -> $rows_after"
out=$(ddev exec env -u IS_DDEV_PROJECT php system/ee/eecli.php cps:schema-check --json 2>/dev/null)
n=$(jcount '.check=="smoke" and .status=="warn" and .message=="smoke skipped: not DDEV"')
[[ "$n" -eq 1 ]] && ok "smoke refuses to run off DDEV" || bad "smoke off-DDEV warn" "n=$n"
out=$(EEJ cps:schema-check --no-smoke --json)
n=$(jcount '.check=="smoke"')
[[ "$n" -eq 0 ]] && ok "--no-smoke produces no smoke results" || bad "--no-smoke" "n=$n"
undo_fixture "$FX_URL"

left=$(ddev mysql admin_cps -N -e "SELECT (SELECT COUNT(*) FROM exp_channels WHERE channel_name LIKE 'cpstools%')+(SELECT COUNT(*) FROM exp_channel_fields WHERE field_name LIKE 'cpstools%')+(SELECT COUNT(*) FROM exp_grid_columns WHERE col_name LIKE 'cpstools%')+(SELECT COUNT(*) FROM exp_field_groups WHERE group_name LIKE 'cpstools%')+(SELECT COUNT(*) FROM exp_migrations WHERE migration LIKE '2099%')+(SELECT COUNT(*) FROM exp_layout_publish WHERE layout_name LIKE 'cpstools%')" 2>&1)
[[ "$left" == "0" ]] && ok "no cpstools_ rows left behind" || bad "leftover rows" "$left"

echo "---"; echo "$PASS passed, $FAIL failed"; [[ $FAIL -eq 0 ]]
