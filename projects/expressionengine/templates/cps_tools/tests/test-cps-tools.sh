#!/usr/bin/env bash
# test-cps-tools.sh — integration tests for cps_tools. Run from a site repo root:
#   bash <config-repo>/projects/expressionengine/templates/cps_tools/tests/test-cps-tools.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sub=""; [[ -d ee/system/user ]] && sub="ee/"
MIG="${sub}system/user/database/migrations"
if [[ -n "${LOCAL_EECLI:-}" ]]; then :; elif [[ -n "$sub" ]]; then LOCAL_EECLI="ddev ee"; else LOCAL_EECLI="ddev exec php system/ee/eecli.php"; fi
EE() { $LOCAL_EECLI "$@" 2>&1; }
PASS=0; FAIL=0
ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL $1 :: $2"; FAIL=$((FAIL+1)); }
FIXTURES=(
  2099_01_01_000000_cps_tools_status_fixture
  2099_01_01_000001_cps_tools_verify_pass
  2099_01_01_000002_cps_tools_verify_fail
  2099_01_01_000003_cps_tools_no_verify
)
cleanup() { for f in "${FIXTURES[@]}"; do rm -f "${MIG:?}/${f:?}.php"; done; }
trap cleanup EXIT

# --- migrate-status ---------------------------------------------------------
STATUS_FIXTURE=${FIXTURES[0]}
out=$(EE cps:migrate-status --json)
echo "$out" | jq -e '.pending and .missing_files and .counts.tables and .counts.channel_titles and .counts.channel_fields' >/dev/null \
  && ok "status json has pending/missing_files/counts" || bad "status json shape" "$out"

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

echo "---"; echo "$PASS passed, $FAIL failed"; [[ $FAIL -eq 0 ]]
