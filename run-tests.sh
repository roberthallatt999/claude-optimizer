#!/usr/bin/env bash
#
# run-tests.sh
# Run the repository's test suites (test-*.sh in the repo root) and print one line per suite.
#
# Usage:
#   ./run-tests.sh                        # every test-*.sh, in parallel
#   ./run-tests.sh test-fleet.sh safety-guard   # only these (test- prefix and .sh optional)
#   ./run-tests.sh -j 1                   # one at a time
#   ./run-tests.sh --list                 # list the suites
#
# Suites run in parallel (one per CPU, at most 8), slowest first: each run records how long every
# passing suite took, so the long ones start at once instead of last. A full run takes about as
# long as the slowest suite (a few minutes) instead of the sum (over half an hour).
#
# Every suite gets the same two settings, so parallel suites never write to the same place:
#   AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1  a test deploy never pulls the superpowers subtree into
#                                        this repo (network, and a race on the subtree)
#   AI_CONFIG_CLAUDE_DIR=<run folder>    global skills link into a folder made for this run and
#                                        linked once before any suite starts, never ~/.claude
# A suite that sets its own AI_CONFIG_CLAUDE_DIR still wins.
#
# Exit codes:
#   0  every suite passed
#   1  at least one suite failed
#   2  usage error
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAIL_LINES=30
MAX_AUTO_JOBS=8
TIMES_FILE="${AI_CONFIG_TEST_TIMES:-${XDG_CACHE_HOME:-$HOME/.cache}/ai-config/test-times.tsv}"

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
Usage: run-tests.sh [-j N] [--list] [SUITE...]

Runs every test-*.sh in the repository root, or only the named suites.
A suite name may omit the test- prefix and the .sh suffix (fleet = test-fleet.sh).

Suites run in parallel, slowest first (timings from earlier runs). Each suite's output is
captured to a log; one line is printed per suite as it finishes, then totals. A failing
suite also shows the last 30 lines of its log, and the log folder is kept (it is removed
when all pass).

Options:
  -j, --jobs N  Run N suites at a time (default: one per CPU, at most 8; 1 = one at a time)
  --list        List the available suites and exit
  -h, --help    Show this help

Exit codes: 0 = all suites passed, 1 = a suite failed, 2 = usage error
EOF
}

all_suites() {
  local f
  for f in "$SCRIPT_DIR"/test-*.sh; do
    [[ -f "$f" ]] && echo "${f##*/}"
  done | LC_ALL=C sort
}

cpu_count() {
  local n
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] || n=2
  echo "$n"
}

# ============================================================================
# Arguments
# ============================================================================

SUITES=()
LIST=false
JOBS=""
while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --list) LIST=true ;;
    -h|--help) usage; exit 0 ;;
    -j|--jobs)
      [[ $# -ge 2 ]] || { echo -e "${RED}✗${NC} $arg needs a number" >&2; exit 2; }
      JOBS="$2"; shift ;;
    -j*) JOBS="${arg#-j}" ;;
    --jobs=*) JOBS="${arg#--jobs=}" ;;
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
  shift
done

if [[ -n "$JOBS" ]] && ! [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -gt 0 ]]; then
  echo -e "${RED}✗${NC} --jobs needs a whole number above 0, not '$JOBS'" >&2
  exit 2
fi

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

if [[ -z "$JOBS" ]]; then
  JOBS="$(cpu_count)"
  [[ "$JOBS" -gt "$MAX_AUTO_JOBS" ]] && JOBS=$MAX_AUTO_JOBS
fi
[[ "$JOBS" -gt ${#SUITES[@]} ]] && JOBS=${#SUITES[@]}

# Slowest first: suites with a recorded time, longest first, after any without one (a new suite
# may be slow, and starting it early costs nothing).
order_by_time() {
  local suite secs
  for suite in "$@"; do
    secs="$( [[ -f "$TIMES_FILE" ]] && awk -F'\t' -v s="$suite" '$1 == s { t = $2 } END { print t }' "$TIMES_FILE")"
    printf '%s\t%s\n' "${secs:-999999}" "$suite"
  done | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | cut -f2
}
ORDERED=()
while IFS= read -r suite; do ORDERED+=("$suite"); done < <(order_by_time "${SUITES[@]}")

# ============================================================================
# Run
# ============================================================================

tmp_base="${TMPDIR:-/tmp}"
LOG_DIR="$(mktemp -d "${tmp_base%/}/ai-config-tests.XXXXXX")" || {
  echo -e "${RED}✗${NC} Could not create a log folder in $tmp_base" >&2
  exit 2
}

export AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1
if [[ -z "${AI_CONFIG_CLAUDE_DIR:-}" ]]; then
  export AI_CONFIG_CLAUDE_DIR="$LOG_DIR/claude"
  mkdir -p "$AI_CONFIG_CLAUDE_DIR"
  # Linked once, before any suite: a deploy only adds missing links, so none of them write here.
  "$BASH" "$SCRIPT_DIR/scripts/link-global-skills.sh" > "$LOG_DIR/link-global-skills.log" 2>&1 || true
fi

echo -e "${CYAN}Running ${#SUITES[@]} test suite(s), $JOBS at a time${NC}, with $BASH"
echo ""

SUITES_PASSED=0
SUITES_FAILED=0
TESTS_PASSED=0
TESTS_FAILED=0
STARTED=$SECONDS
NEW_TIMES=""

# report_suite <suite> <exit status> <seconds>: one line, plus the log tail on failure.
report_suite() {
  local suite="$1" status="$2" secs="$3" log plain passed failed detail
  log="$LOG_DIR/${suite%.sh}.log"
  plain="$(LC_ALL=C sed "s/${ESC}\\[[0-9;]*m//g" "$log")"
  # Summary formats in use: "All N tests passed", "PASS: N" / "FAIL: N", "name: N passed, M failed".
  passed="$(LC_ALL=C sed -nE 's/.*All ([0-9]+) tests passed.*/\1/p' <<< "$plain" | tail -n 1)"
  [[ -n "$passed" ]] || passed="$(LC_ALL=C sed -nE 's/^[[:space:]]*PASS: ([0-9]+)[[:space:]]*$/\1/p' <<< "$plain" | tail -n 1)"
  [[ -n "$passed" ]] || passed="$(LC_ALL=C sed -nE 's/^[A-Za-z0-9_-]+: ([0-9]+) passed, [0-9]+ failed$/\1/p' <<< "$plain" | tail -n 1)"
  failed="$(LC_ALL=C sed -nE 's/^[[:space:]]*FAIL: ([0-9]+)[[:space:]]*$/\1/p' <<< "$plain" | tail -n 1)"
  [[ -n "$failed" ]] || failed="$(LC_ALL=C sed -nE 's/^[A-Za-z0-9_-]+: [0-9]+ passed, ([0-9]+) failed$/\1/p' <<< "$plain" | tail -n 1)"

  [[ -n "$passed" ]] && TESTS_PASSED=$((TESTS_PASSED + passed))
  [[ -n "$failed" ]] && TESTS_FAILED=$((TESTS_FAILED + failed))

  if [[ $status -eq 0 && "${failed:-0}" -eq 0 ]]; then
    SUITES_PASSED=$((SUITES_PASSED + 1))
    NEW_TIMES+="${suite}"$'\t'"${secs}"$'\n'
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
}

# A pool of background suites. bash 3.2 (macOS) has no `wait -n`, so finished jobs are found by
# polling `kill -0`; `wait <pid>` then returns that job's exit status.
RUN_PIDS=()
RUN_NAMES=()
RUN_STARTS=()
cleanup() {
  local pid
  for pid in ${RUN_PIDS[@]+"${RUN_PIDS[@]}"}; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  done
}
trap 'cleanup; echo ""; echo "Interrupted — logs: $LOG_DIR" >&2; exit 130' INT TERM

progress() {
  [[ -t 1 ]] || return 0
  local names="" i
  for i in "${!RUN_NAMES[@]}"; do
    [[ -n "${RUN_NAMES[$i]}" ]] && names+="${RUN_NAMES[$i]%.sh} "
  done
  printf '\r\033[K  … %d/%d done; running: %s' "$((SUITES_PASSED + SUITES_FAILED))" "${#ORDERED[@]}" "${names% }" \
    | cut -c1-"$(tput cols 2>/dev/null || echo 120)"
}

next=0
running=0
while [[ $next -lt ${#ORDERED[@]} || $running -gt 0 ]]; do
  while [[ $running -lt $JOBS && $next -lt ${#ORDERED[@]} ]]; do
    suite="${ORDERED[$next]}"
    (cd "$SCRIPT_DIR" && exec "$BASH" "./$suite") > "$LOG_DIR/${suite%.sh}.log" 2>&1 < /dev/null &
    RUN_PIDS+=("$!")
    RUN_NAMES+=("$suite")
    RUN_STARTS+=("$SECONDS")
    next=$((next + 1))
    running=$((running + 1))
  done
  progress
  finished=false
  for i in "${!RUN_PIDS[@]}"; do
    pid="${RUN_PIDS[$i]}"
    [[ -n "$pid" ]] || continue
    kill -0 "$pid" 2>/dev/null && continue
    wait "$pid"
    status=$?
    [[ -t 1 ]] && printf '\r\033[K'
    report_suite "${RUN_NAMES[$i]}" "$status" "$((SECONDS - RUN_STARTS[i]))"
    RUN_PIDS[$i]=""
    RUN_NAMES[$i]=""
    running=$((running - 1))
    finished=true
  done
  [[ "$finished" == true ]] || sleep 0.5
done
[[ -t 1 ]] && printf '\r\033[K'

# Remember how long each passing suite took, for the next run's order. Best effort.
if [[ -n "$NEW_TIMES" ]] && mkdir -p "$(dirname "$TIMES_FILE")" 2>/dev/null; then
  {
    [[ -f "$TIMES_FILE" ]] && cat "$TIMES_FILE"
    printf '%s' "$NEW_TIMES"
  } | awk -F'\t' 'NF == 2 { t[$1] = $2 } END { for (s in t) print s "\t" t[s] }' | LC_ALL=C sort \
    > "$TIMES_FILE.tmp.$$" 2>/dev/null && mv "$TIMES_FILE.tmp.$$" "$TIMES_FILE" 2>/dev/null
  rm -f "$TIMES_FILE.tmp.$$" 2>/dev/null
fi

# ============================================================================
# Totals
# ============================================================================

echo ""
echo -e "${CYAN}================================${NC}"
echo "  Suites: $SUITES_PASSED passed, $SUITES_FAILED failed"
echo "  Tests:  $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "  Time:   $((SECONDS - STARTED))s ($JOBS at a time)"
echo -e "${CYAN}================================${NC}"

if [[ $SUITES_FAILED -gt 0 ]]; then
  echo -e "${RED}✗ $SUITES_FAILED suite(s) failed${NC} — logs: $LOG_DIR"
  exit 1
fi
rm -rf "$LOG_DIR"
echo -e "${GREEN}✓ All ${#SUITES[@]} suite(s) passed${NC}"
exit 0
