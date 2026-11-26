#!/usr/bin/env bash
# Tests for run-tests.sh, with fake suites in a throwaway folder:
#   * suites run in parallel (-j), or one at a time (-j 1)
#   * the summary formats suites print are counted, and a failure shows its log tail and exit 1
#   * every suite gets AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1 and a run-scoped AI_CONFIG_CLAUDE_DIR
#   * recorded timings put the slowest suite first; a bad --jobs value is a usage error
# shellcheck disable=SC2034  # variables are read inside the check strings, which check() evals
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export NO_COLOR=1 AI_CONFIG_TEST_TIMES="$work/times.tsv"
unset AI_CONFIG_CLAUDE_DIR

R="$work/repo"
mkdir -p "$R"
cp "$HERE/run-tests.sh" "$R/"
suite() { # suite <name> <body>: a fake suite that sleeps a second, then runs <body>
  printf '#!/usr/bin/env bash\nsleep 1\n%s\n' "$2" > "$R/test-$1.sh"
}
suite alpha 'echo "alpha: 3 passed, 0 failed"'
suite beta  'echo "PASS: 2"'
suite gamma 'echo "All 4 tests passed"'
suite env   'printf "%s\n%s\n" "${AI_CONFIG_SKIP_SUPERPOWERS_UPDATE:-}" "${AI_CONFIG_CLAUDE_DIR:-}" > "'"$work"'/env-seen"; echo "env: 1 passed, 0 failed"'

start=$SECONDS
out=$("$R/run-tests.sh" -j 4 2>&1); rc=$?
took=$((SECONDS - start))
check "all pass: exit 0" '[[ $rc -eq 0 ]]'
check "four one-second suites with -j 4 finish together" '[[ $took -lt 4 ]]'
check "'name: N passed, M failed' is counted" '[[ "$out" == *"test-alpha.sh — 3 passed"* ]]'
check "'PASS: N' and 'All N tests passed' are counted" '[[ "$out" == *"test-beta.sh — 2 passed"* && "$out" == *"test-gamma.sh — 4 passed"* ]]'
check "the totals add every format" '[[ "$out" == *"Tests:  10 passed, 0 failed"* ]]'
check "the run says how many at a time" '[[ "$out" == *"4 at a time"* ]]'

skip_seen=$(sed -n 1p "$work/env-seen"); claude_dir=$(sed -n 2p "$work/env-seen")
check "suites get AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1" '[[ $skip_seen == 1 ]]'
check "suites get a run-scoped AI_CONFIG_CLAUDE_DIR, not ~/.claude" '[[ -n "$claude_dir" && "$claude_dir" != "$HOME/.claude" && "$claude_dir" == */claude ]]'
check "the run folder is removed when everything passes" '[[ ! -e "$claude_dir" ]]'
AI_CONFIG_CLAUDE_DIR="$work/mine" "$R/run-tests.sh" env >/dev/null 2>&1
check "an AI_CONFIG_CLAUDE_DIR set by the caller wins" '[[ $(sed -n 2p "$work/env-seen") == "$work/mine" ]]'

check "timings are recorded for passing suites" '[[ $(cut -f1 "$AI_CONFIG_TEST_TIMES" | sort | tr "\n" " ") == "test-alpha.sh test-beta.sh test-env.sh test-gamma.sh " ]]'
printf 'test-alpha.sh\t1\ntest-beta.sh\t1\ntest-env.sh\t1\ntest-gamma.sh\t90\n' > "$AI_CONFIG_TEST_TIMES"
start=$SECONDS
out=$("$R/run-tests.sh" -j 1 2>&1)
took=$((SECONDS - start))
check "-j 1 runs one at a time" '[[ $took -ge 4 ]]'
check "the slowest recorded suite starts first" '[[ $(grep -m1 "—" <<< "$out") == *test-gamma.sh* ]]'

suite zeta 'echo "zeta: 1 passed, 2 failed"; echo "the reason it failed"; exit 1'
out=$("$R/run-tests.sh" 2>&1); rc=$?
check "a failing suite: exit 1" '[[ $rc -eq 1 ]]'
check "its failures are counted and its log tail shown" '[[ "$out" == *"test-zeta.sh — 2 failed"* && "$out" == *"│ the reason it failed"* ]]'
log_dir=$(sed -n "s/.* — logs: //p" <<< "$out")
check "the log folder is kept after a failure" '[[ -n "$log_dir" && -f "$log_dir/test-zeta.log" ]]'
rm -rf "$log_dir"
check "a failed suite's time isn't recorded" '! grep -q "^test-zeta.sh" "$AI_CONFIG_TEST_TIMES"'

"$R/run-tests.sh" -j 0 >/dev/null 2>&1; rc0=$?
"$R/run-tests.sh" --jobs=x >/dev/null 2>&1; rcx=$?
check "a bad --jobs value is a usage error" '[[ $rc0 -eq 2 && $rcx -eq 2 ]]'
check "-jN and --jobs=N are accepted" '"$R/run-tests.sh" -j2 alpha >/dev/null 2>&1 && "$R/run-tests.sh" --jobs=2 alpha >/dev/null 2>&1'

echo ""
echo "run-tests: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
