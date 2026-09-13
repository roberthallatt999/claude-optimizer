#!/usr/bin/env bash
# test-fleet.sh — ai-config-fleet.sh: project discovery, per-project runs, and the summary.
# Uses a fake setup-project.sh (via AI_CONFIG_SETUP_SCRIPT) that logs its arguments,
# fails for one project and reports warnings for another.
#
# Usage: ./test-fleet.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET="$SCRIPT_DIR/ai-config-fleet.sh"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

TMPS=()
tmp_dir() { local d; d="$(mktemp -d)"; TMPS+=("$d"); echo "$d"; }
cleanup_all() { local d; for d in "${TMPS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"; FAIL=$((FAIL + 1)); fi
}
assert_true() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1)); fi
}
assert_false() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1))
  else echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1)); fi
}
contains() { grep -qF -- "$2" <<< "$1"; }
logged() { grep -qxF -- "$2" "$1" 2>/dev/null; }

fleet() { "$BASH" "$FLEET" "$@" 2>&1; }                      # same interpreter as this suite
projects_in() { sed -n 's/^  \([^ ][^ ]*\)  .*/\1/p' <<< "$1" | grep -v '^PROJECT$' | paste -sd' ' -; }
row() { grep -F -- "  $2  " <<< "$1"; }                       # the table row for one project
args_lines() { paste -sd'|' - < "$FAKE_ARGS_LOG"; }

# Run folders and every other temp dir land here, so the trap removes them all
base=$(tmp_dir)
export TMPDIR="$base"

# ----------------------------------------------------------------------------
# Fake setup-project.sh
# ----------------------------------------------------------------------------
bin=$(tmp_dir)
export AI_CONFIG_SETUP_SCRIPT="$bin/setup-project.sh"
export FAKE_ARGS_LOG="$bin/args.log" FAKE_FAIL_PROJECT="broken" FAKE_WARN_PROJECT="legacy"
cat > "$AI_CONFIG_SETUP_SCRIPT" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_ARGS_LOG"
project=""
for arg in "$@"; do
  case "$arg" in --project=*) project="${arg#--project=}" ;; esac
done
echo "fake setup-project.sh output for $project"
case "${project##*/}" in
  "$FAKE_FAIL_PROJECT")
    printf '  \033[0;31mHealth check: 2 failure(s), 1 warning(s)\033[0m\n'
    exit 1 ;;
  "$FAKE_WARN_PROJECT")
    printf '  \033[0;32mHealth check: 0 failures, 3 warning(s)\033[0m\n' ;;
esac
exit 0
SH
chmod +x "$AI_CONFIG_SETUP_SCRIPT"

# ----------------------------------------------------------------------------
# Project tree
# ----------------------------------------------------------------------------
root=$(tmp_dir)
root=$(cd "$root" && pwd)
manifest() { mkdir -p "$1/.claude/ai-config"; printf 'CLAUDE.md\t0123abcd\n' > "$1/.claude/ai-config/manifest.tsv"; }

manifest "$root/clients/acme"                                   # manifest-based, with version file
printf 'commit=abc1234def5678\ndeployed_at=2026-09-13T10:00:00Z\nstack=nextjs\n' \
  > "$root/clients/acme/.claude/ai-config/version"
mkdir -p "$root/clients/legacy"                                 # legacy: CLAUDE.md marker only
printf '# Legacy\n\n<!-- BEGIN SAFETY GUARDRAILS -->\nRules.\n<!-- END SAFETY GUARDRAILS -->\n' \
  > "$root/clients/legacy/CLAUDE.md"
manifest "$root/sites/broken"                                   # the fake fails for this one
mkdir -p "$root/clients/plain/.claude"                          # not an ai-config project
printf '# Plain project\n' > "$root/clients/plain/CLAUDE.md"
manifest "$root/tools/node_modules/decoy-npm"                   # never descend into node_modules
manifest "$root/tools/vendor/decoy-composer"                    # ... or vendor
manifest "$root/.git/decoy-git"                                 # ... or .git
manifest "$root/clients/acme/packages/inner"                    # ... or a detected project
manifest "$root/deep/a/b/too-deep"                              # level 4 > default depth 3

# ============================================================================
echo -e "\n${CYAN}=== Discovery (--list) ===${NC}\n"
# ============================================================================

out=$(fleet --root="$root" --list); status=$?
assert_eq "--list exits 0" "0" "$status"
assert_eq "detects manifest and legacy CLAUDE.md projects, sorted" \
  "clients/acme clients/legacy sites/broken" "$(projects_in "$out")"
assert_false "folder without manifest or marker not detected" contains "$out" "clients/plain"
assert_false "decoy inside node_modules skipped" contains "$out" "decoy-npm"
assert_false "decoy inside vendor skipped" contains "$out" "decoy-composer"
assert_false "decoy inside .git skipped" contains "$out" "decoy-git"
assert_false "project nested in a detected project skipped" contains "$out" "packages/inner"
assert_false "project deeper than the default depth skipped" contains "$out" "too-deep"
assert_true "version file → stack, short commit and date" \
  grep -qE '^  clients/acme +nextjs +abc1234 \(2026-09-13\)$' <<< "$out"
assert_true "no version file → unknown stack and version" \
  grep -qE '^  clients/legacy +unknown +unknown$' <<< "$out"
assert_true "--list reports the count" contains "$out" "3 project(s) found"
assert_false "--list runs nothing" test -e "$FAKE_ARGS_LOG"

out=$(fleet --root="$root" --list --depth=4)
assert_eq "--depth=4 reaches the deeper project" \
  "clients/acme clients/legacy deep/a/b/too-deep sites/broken" "$(projects_in "$out")"

out=$(fleet --root="$root" --list --depth=1); status=$?
assert_eq "--depth=1 finds nothing two levels down" "" "$(projects_in "$out")"
assert_true "none found is reported" contains "$out" "No ai-config projects found"
assert_eq "none found still exits 0" "0" "$status"

out=$(cd "$root/clients" && fleet --list)
assert_eq "root defaults to the current directory" "acme legacy" "$(projects_in "$out")"

out=$(fleet --root="$root/clients/acme" --list)
assert_eq "a root that is itself a project is listed as ." "." "$(projects_in "$out")"

out=$(export AI_CONFIG_SETUP_SCRIPT=/nonexistent/setup-project.sh; fleet --root="$root" --list); status=$?
assert_eq "--list works without a setup script" "0" "$status"

# ============================================================================
echo -e "\n${CYAN}=== --doctor (default mode) ===${NC}\n"
# ============================================================================

out=$(fleet --root="$root"); status=$?
assert_eq "a failing project → exit 1" "1" "$status"
assert_eq "one --doctor run per project, in order" \
  "--doctor --project=$root/clients/acme|--doctor --project=$root/clients/legacy|--doctor --project=$root/sites/broken" \
  "$(args_lines)"
assert_true "healthy project → ✓ ok" contains "$(row "$out" clients/acme)" "✓ ok"
assert_true "healthy row shows stack and version" grep -qE 'nextjs +abc1234 \(2026-09-13\)' <<< "$(row "$out" clients/acme)"
assert_true "warnings parsed from colored output → ⚠ 3 warnings" contains "$(row "$out" clients/legacy)" "⚠ 3 warnings"
assert_true "non-zero exit → ✗ failed" contains "$(row "$out" sites/broken)" "✗ failed"
assert_false "failed project not shown as warnings" contains "$(row "$out" sites/broken)" "⚠"
assert_true "summary counts" contains "$out" "3 project(s): 1 ok, 1 with warnings, 1 failed"
assert_false "full setup output stays out of the terminal" contains "$out" "fake setup-project.sh output"

run_dir=$(sed -n 's/^Logs: //p' <<< "$out")
assert_true "run folder printed and created" test -d "$run_dir"
assert_eq "run folder path printed once" "1" "$(grep -cF -- "$run_dir" <<< "$out")"
assert_eq "one log file per project" "3" "$(find "$run_dir" -name '*.log' | wc -l | tr -d ' ')"
broken_log="$run_dir/$(row "$out" sites/broken | awk '{print $NF}')"
assert_true "log file named in the row exists" test -f "$broken_log"
assert_true "log holds the full output" grep -qF "fake setup-project.sh output for $root/sites/broken" "$broken_log"
assert_true "log records the command" grep -qF -- "--doctor --project=$root/sites/broken" "$broken_log"
assert_true "log records the exit status" grep -qx "# exit status: 1" "$broken_log"

rm -f "$FAKE_ARGS_LOG"
out=$(fleet --root="$root" --doctor --dry-run -- --effort=high --with-openai)
assert_true "args after -- appended to the --doctor run" \
  logged "$FAKE_ARGS_LOG" "--doctor --project=$root/clients/legacy --effort=high --with-openai"
assert_eq "... for every project" "3" "$(grep -c -- ' --effort=high --with-openai$' "$FAKE_ARGS_LOG")"
assert_false "--dry-run not passed to --doctor" grep -q -- '--dry-run' "$FAKE_ARGS_LOG"
assert_true "--dry-run with --doctor noted as ignored" contains "$out" "--dry-run ignored"

rm -f "$FAKE_ARGS_LOG"
out=$(export FAKE_FAIL_PROJECT=none; fleet --root="$root" --doctor); status=$?
assert_eq "no failing project → exit 0" "0" "$status"
assert_true "summary with no failures" contains "$out" "3 project(s): 2 ok, 1 with warnings, 0 failed"
assert_false "no ✗ rows when nothing fails" contains "$out" "✗"

# ============================================================================
echo -e "\n${CYAN}=== --refresh ===${NC}\n"
# ============================================================================

rm -f "$FAKE_ARGS_LOG"
out=$(fleet --root="$root" --refresh); status=$?
assert_eq "one --refresh --skip-vscode run per project, in order" \
  "--refresh --project=$root/clients/acme --skip-vscode|--refresh --project=$root/clients/legacy --skip-vscode|--refresh --project=$root/sites/broken --skip-vscode" \
  "$(args_lines)"
assert_eq "--refresh with a failing project → exit 1" "1" "$status"

rm -f "$FAKE_ARGS_LOG"
out=$(fleet --root="$root" --refresh --dry-run -- --with-openai); status=$?
assert_eq "--refresh --dry-run passes --dry-run, then the -- args" \
  "--refresh --project=$root/clients/acme --skip-vscode --dry-run --with-openai|--refresh --project=$root/clients/legacy --skip-vscode --dry-run --with-openai|--refresh --project=$root/sites/broken --skip-vscode --dry-run --with-openai" \
  "$(args_lines)"
assert_true "header names the dry-run" contains "$out" "--refresh --dry-run on 3 project(s)"

rm -f "$FAKE_ARGS_LOG"
out=$(fleet --root="$root" --depth=4 --refresh -- --skip-superpowers-update)
assert_true "--depth applies to runs too" \
  logged "$FAKE_ARGS_LOG" "--refresh --project=$root/deep/a/b/too-deep --skip-vscode --skip-superpowers-update"
assert_eq "runs never touch decoys" "0" "$(grep -c 'decoy\|inner\|plain' "$FAKE_ARGS_LOG")"

rm -f "$FAKE_ARGS_LOG"
out=$(fleet --root="$root/clients/plain" --refresh); status=$?
assert_eq "no projects → exit 0" "0" "$status"
assert_true "no projects → reported" contains "$out" "No ai-config projects found"
assert_false "no projects → nothing run" test -e "$FAKE_ARGS_LOG"

# ============================================================================
echo -e "\n${CYAN}=== Usage ===${NC}\n"
# ============================================================================

out=$(fleet --help); status=$?
assert_eq "--help exits 0" "0" "$status"
for word in "--root=DIR" "--depth=N" "--doctor" "--refresh" "--list" "--dry-run" "-- ARGS" \
  "AI_CONFIG_SETUP_SCRIPT" "manifest.tsv" "BEGIN SAFETY GUARDRAILS" "node_modules" \
  ".claude/ai-config/version" "Exit codes"; do
  assert_true "--help documents $word" contains "$out" "$word"
done
assert_true "-h is --help" contains "$(fleet -h)" "Usage: ai-config-fleet"

out=$(fleet --bogus); status=$?
assert_eq "unknown option → exit 2" "2" "$status"
out=$(fleet --list --refresh); status=$?
assert_eq "two modes → exit 2" "2" "$status"
out=$(fleet --depth=three); status=$?
assert_eq "non-numeric --depth → exit 2" "2" "$status"
out=$(fleet --root="$root/does-not-exist"); status=$?
assert_eq "missing root → exit 2" "2" "$status"
out=$(export AI_CONFIG_SETUP_SCRIPT=/nonexistent/setup-project.sh; fleet --root="$root"); status=$?
assert_eq "missing setup script → exit 2" "2" "$status"
assert_true "missing setup script is named" contains "$out" "/nonexistent/setup-project.sh"

# ============================================================================
echo ""
echo -e "${CYAN}================================${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  FAIL: $FAIL"
echo -e "${CYAN}================================${NC}"
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}✗ $FAIL test(s) failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ All $PASS tests passed${NC}"
