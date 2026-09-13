#!/usr/bin/env bash
#
# run-tests.sh
# Run the repository's test suites (test-*.sh in the repo root) and print one line per suite.
#
# Usage:
#   ./run-tests.sh                        # every test-*.sh, sorted
#   ./run-tests.sh test-fleet.sh safety-guard   # only these (test- prefix and .sh optional)
#   ./run-tests.sh --list                 # list the suites
#
# Note: test-stack-detection.sh and the setup-project.sh integration suites take up to a
# few minutes each.
#
# Exit codes:
#   0  every suite passed
#   1  at least one suite failed
#   2  usage error
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAIL_LINES=30

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

ESC="$(printf '\033')"

usage() {
  cat <<'EOF'
Usage: run-tests.sh [--list] [SUITE...]

Run every test-*.sh in the repository root (sorted), or only the named suites.
A suite name may omit the test- prefix and the .sh suffix (fleet = test-fleet.sh).

Each suite runs with the same bash as this script; its output is captured to a log.
One line is printed per suite, then totals. A failing suite also shows the last
30 lines of its log, and the log folder is kept (it is removed when all pass).

Options:
  --list      List the available suites and exit
  -h, --help  Show this help

Exit codes: 0 = all suites passed, 1 = a suite failed, 2 = usage error

Note: test-stack-detection.sh and the setup-project.sh integration suites take up to a
few minutes each.
EOF
}

all_suites() {
  local f
  for f in "$SCRIPT_DIR"/test-*.sh; do
    [[ -f "$f" ]] && echo "${f##*/}"
  done | LC_ALL=C sort
}

# ============================================================================
# Arguments
# ============================================================================

SUITES=()
LIST=false
for arg in "$@"; do
  case "$arg" in
    --list) LIST=true ;;
    -h|--help) usage; exit 0 ;;
    -*) echo -e "${RED}✗${NC} Unknown option: $arg (see --help)" >&2; exit 2 ;;
    *)
      name="${arg##*/}"
      name="${name%.sh}"
      name="test-${name#test-}.sh"
      if [[ ! -f "$SCRIPT_DIR/$name" ]]; then
        echo -e "${RED}✗${NC} No such suite: $arg (see --list)" >&2
        exit 2
      fi
      SUITES+=("$name")
      ;;
  esac
done

if [[ "$LIST" == true ]]; then
  all_suites
  exit 0
fi

if [[ ${#SUITES[@]} -eq 0 ]]; then
  while IFS= read -r suite; do SUITES+=("$suite"); done < <(all_suites)
fi
if [[ ${#SUITES[@]} -eq 0 ]]; then
  echo -e "${RED}✗${NC} No test-*.sh suites found in $SCRIPT_DIR" >&2
  exit 2
fi

# ============================================================================
# Run
# ============================================================================

tmp_base="${TMPDIR:-/tmp}"
LOG_DIR="$(mktemp -d "${tmp_base%/}/ai-config-tests.XXXXXX")" || {
  echo -e "${RED}✗${NC} Could not create a log folder in $tmp_base" >&2
  exit 2
}

echo -e "${CYAN}Running ${#SUITES[@]} test suite(s)${NC} with $BASH"
echo ""

SUITES_PASSED=0
SUITES_FAILED=0
TESTS_PASSED=0
TESTS_FAILED=0
STARTED=$SECONDS

for suite in "${SUITES[@]}"; do
  log="$LOG_DIR/${suite%.sh}.log"
  [[ -t 1 ]] && printf '  … %s' "$suite"
  suite_start=$SECONDS
  (cd "$SCRIPT_DIR" && "$BASH" "./$suite") > "$log" 2>&1 < /dev/null
  status=$?
  secs=$((SECONDS - suite_start))
  [[ -t 1 ]] && printf '\r\033[K'

  plain="$(LC_ALL=C sed "s/${ESC}\\[[0-9;]*m//g" "$log")"
  passed="$(LC_ALL=C sed -nE 's/.*All ([0-9]+) tests passed.*/\1/p' <<< "$plain" | tail -n 1)"
  [[ -n "$passed" ]] || passed="$(LC_ALL=C sed -nE 's/^[[:space:]]*PASS: ([0-9]+)[[:space:]]*$/\1/p' <<< "$plain" | tail -n 1)"
  failed="$(LC_ALL=C sed -nE 's/^[[:space:]]*FAIL: ([0-9]+)[[:space:]]*$/\1/p' <<< "$plain" | tail -n 1)"

  [[ -n "$passed" ]] && TESTS_PASSED=$((TESTS_PASSED + passed))
  [[ -n "$failed" ]] && TESTS_FAILED=$((TESTS_FAILED + failed))

  if [[ $status -eq 0 && "${failed:-0}" -eq 0 ]]; then
    SUITES_PASSED=$((SUITES_PASSED + 1))
    echo -e "  ${GREEN}✓${NC} $suite — ${passed:-?} passed (${secs}s)"
  else
    SUITES_FAILED=$((SUITES_FAILED + 1))
    if [[ -n "$failed" && "$failed" -gt 0 ]]; then
      detail="$failed failed"
    else
      detail="exit $status"
    fi
    echo -e "  ${RED}✗${NC} $suite — $detail (${secs}s), see $log"
    if [[ -n "$plain" ]]; then
      echo -e "    ${YELLOW}last $TAIL_LINES lines:${NC}"
      tail -n "$TAIL_LINES" <<< "$plain" | sed 's/^/    │ /'
    else
      echo -e "    ${YELLOW}(no output)${NC}"
    fi
    echo ""
  fi
done

# ============================================================================
# Totals
# ============================================================================

echo ""
echo -e "${CYAN}================================${NC}"
echo "  Suites: $SUITES_PASSED passed, $SUITES_FAILED failed"
echo "  Tests:  $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "  Time:   $((SECONDS - STARTED))s"
echo -e "${CYAN}================================${NC}"

if [[ $SUITES_FAILED -gt 0 ]]; then
  echo -e "${RED}✗ $SUITES_FAILED suite(s) failed${NC} — logs: $LOG_DIR"
  exit 1
fi
rm -rf "$LOG_DIR"
echo -e "${GREEN}✓ All ${#SUITES[@]} suite(s) passed${NC}"
exit 0
