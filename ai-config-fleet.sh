#!/usr/bin/env bash
#
# ai-config-fleet.sh
# Run ai-config (setup-project.sh) across every client project under a folder and print
# one compact summary. Full per-project output goes to log files in a run folder.
#
# Usage:
#   ./ai-config-fleet.sh [--root=DIR] [--depth=N] [--doctor|--refresh|--list] [--dry-run] [-- ARGS...]
#
# Exit codes:
#   0  no project failed (warnings allowed), or --list / --help
#   1  at least one project failed
#   2  usage error, or setup-project.sh not found
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="${AI_CONFIG_SETUP_SCRIPT:-$SCRIPT_DIR/setup-project.sh}"

# Colors only on a terminal, so logs and captured output stay plain
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
Usage: ai-config-fleet [--root=DIR] [--depth=N] [--doctor|--refresh|--list] [--dry-run] [-- ARGS...]

Run ai-config across every client project under a folder and print one summary.

Modes (pick one; default: --doctor):
  --doctor      Read-only health check of each project:
                  setup-project.sh --doctor --project=DIR
  --refresh     Update each project (one at a time — refresh writes files):
                  setup-project.sh --refresh --project=DIR --skip-vscode
  --list        Only list the detected projects with stack and deployed version

Options:
  --root=DIR    Folder to search (default: current directory)
  --depth=N     Directory levels below the root to search (default: 3)
  --dry-run     With --refresh, also pass --dry-run so nothing is written
                (--doctor is already read-only; ignored with --list)
  -- ARGS...    Everything after -- is appended to every setup-project.sh run
  -h, --help    Show this help

Detection:
  A directory is an ai-config project when it contains .claude/ai-config/manifest.tsv,
  or its CLAUDE.md contains "<!-- BEGIN SAFETY GUARDRAILS" (deployed before the manifest).
  The search never enters node_modules, vendor, hidden directories (.git, .ddev, ...),
  or the subfolders of a project it already found.

Output:
  Each project's full output is saved to its own log file in a fresh run folder (the
  folder path is printed once). The terminal shows one row per project:
    PROJECT  path relative to the root
    STACK    stack= from .claude/ai-config/version ("unknown" if the file is missing)
    VERSION  short commit= and deployed_at= date from the same file ("unknown" if missing)
    RESULT   ✓ ok            exit 0
             ⚠ N warnings    exit 0 and "Health check: ... N warning(s)" in the output
             ✗ failed        non-zero exit (a critical check or the refresh failed)
    LOG      log file name inside the run folder
  setup-project.sh runs with stdin closed, so it can never wait on a prompt.

Environment:
  AI_CONFIG_SETUP_SCRIPT  setup-project.sh to run (default: the one next to this script)
  NO_COLOR                Disable colors (also off when output is not a terminal)

Exit codes:
  0  no project failed (warnings allowed)
  1  at least one project failed
  2  usage error, or setup-project.sh not found

Examples:
  ai-config-fleet --root=~/sites                         # health-check every project
  ai-config-fleet --root=~/sites --list                  # what is deployed where
  ai-config-fleet --root=~/sites --refresh --dry-run     # preview a fleet-wide refresh
  ai-config-fleet --root=~/sites --refresh -- --skip-superpowers-update
EOF
}

die_usage() {
  echo -e "${RED}✗${NC} $*" >&2
  echo "Run with --help for usage." >&2
  exit 2
}

# ============================================================================
# Arguments
# ============================================================================

ROOT="."
DEPTH=3
MODE=""
DRY_RUN=false
EXTRA_ARGS=()

set_mode() {
  if [[ -n "$MODE" && "$MODE" != "$1" ]]; then
    die_usage "Choose only one of --doctor, --refresh, --list"
  fi
  MODE="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root=*)  ROOT="${1#--root=}" ;;
    --depth=*) DEPTH="${1#--depth=}" ;;
    --doctor)  set_mode doctor ;;
    --refresh) set_mode refresh ;;
    --list)    set_mode list ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    --)        shift; EXTRA_ARGS=("$@"); break ;;
    *)         die_usage "Unknown option: $1" ;;
  esac
  shift
done

[[ -n "$MODE" ]] || MODE=doctor
[[ "$DEPTH" =~ ^[0-9]+$ ]] || die_usage "--depth must be a non-negative integer (got '$DEPTH')"

# A quoted or zsh-style --root=~/x reaches us unexpanded
[[ -n "$ROOT" ]] || ROOT="."
case "$ROOT" in
  \~|\~/*) ROOT="$HOME${ROOT#\~}" ;;
esac
[[ -d "$ROOT" ]] || die_usage "Not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

if [[ "$MODE" != list && ! -f "$SETUP_SCRIPT" ]]; then
  echo -e "${RED}✗${NC} setup-project.sh not found: $SETUP_SCRIPT" >&2
  echo "  Set AI_CONFIG_SETUP_SCRIPT to its path." >&2
  exit 2
fi

# ============================================================================
# Discovery
# ============================================================================

is_project() {
  [[ -f "$1/.claude/ai-config/manifest.tsv" ]] && return 0
  [[ -f "$1/CLAUDE.md" ]] && grep -qF -- '<!-- BEGIN SAFETY GUARDRAILS' "$1/CLAUDE.md" 2>/dev/null
}

PROJECTS=()
scan() {  # scan <dir> <level> — the root is level 0
  local dir="$1" level="$2" child
  if is_project "$dir"; then
    PROJECTS+=("$dir")
    return 0
  fi
  [[ "$level" -lt "$DEPTH" ]] || return 0
  # */ matches directories only; hidden directories are not matched by the glob
  for child in "${dir%/}"/*/; do
    child="${child%/}"
    [[ -d "$child" ]] || continue
    case "${child##*/}" in
      node_modules|vendor|.git) continue ;;
    esac
    scan "$child" $((level + 1))
  done
}

rel_path() {
  if [[ "$1" == "$ROOT" ]]; then
    echo "."
  else
    echo "${1#"${ROOT%/}"/}"
  fi
}

# read_version <project> — sets V_STACK and V_VERSION from .claude/ai-config/version
read_version() {
  local file="$1/.claude/ai-config/version" line key value commit="" deployed="" stack=""
  V_STACK="unknown"
  V_VERSION="unknown"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      commit)      commit="$value" ;;
      deployed_at) deployed="$value" ;;
      stack)       stack="$value" ;;
    esac
  done < "$file"
  deployed="${deployed%%T*}"   # 2026-09-13T10:00:00Z → 2026-09-13
  deployed="${deployed%% *}"   # 2026-09-13 10:00:00  → 2026-09-13
  [[ -n "$stack" ]] && V_STACK="$stack"
  if [[ -n "$commit" && -n "$deployed" ]]; then
    V_VERSION="${commit:0:7} ($deployed)"
  elif [[ -n "$commit" ]]; then
    V_VERSION="${commit:0:7}"
  elif [[ -n "$deployed" ]]; then
    V_VERSION="$deployed"
  fi
  return 0
}

scan "$ROOT" 0
COUNT=${#PROJECTS[@]}

if [[ $COUNT -eq 0 ]]; then
  echo -e "${YELLOW}○${NC} No ai-config projects found under $ROOT (depth $DEPTH)"
  exit 0
fi

# Column widths (stack/version are re-read after each run; longer values just widen the row)
W_PROJ=7 W_STACK=5 W_VER=7 W_RES=13
for dir in "${PROJECTS[@]}"; do
  rel="$(rel_path "$dir")"
  read_version "$dir"
  [[ ${#rel} -gt $W_PROJ ]] && W_PROJ=${#rel}
  [[ ${#V_STACK} -gt $W_STACK ]] && W_STACK=${#V_STACK}
  [[ ${#V_VERSION} -gt $W_VER ]] && W_VER=${#V_VERSION}
done

# ============================================================================
# --list
# ============================================================================

if [[ "$MODE" == list ]]; then
  echo -e "${CYAN}ai-config projects${NC} under $ROOT (depth $DEPTH)"
  echo ""
  printf '  %-*s  %-*s  %s\n' "$W_PROJ" PROJECT "$W_STACK" STACK VERSION
  for dir in "${PROJECTS[@]}"; do
    read_version "$dir"
    printf '  %-*s  %-*s  %s\n' "$W_PROJ" "$(rel_path "$dir")" "$W_STACK" "$V_STACK" "$V_VERSION"
  done
  echo ""
  echo "$COUNT project(s) found"
  exit 0
fi

# ============================================================================
# --doctor / --refresh
# ============================================================================

run_setup() {
  if [[ -x "$SETUP_SCRIPT" ]]; then
    "$SETUP_SCRIPT" "$@"
  else
    bash "$SETUP_SCRIPT" "$@"
  fi
}

# warning_count <log> — N from the last "Health check: ... N warning(s)" line, or empty
warning_count() {
  LC_ALL=C sed "s/${ESC}\\[[0-9;]*m//g" "$1" \
    | LC_ALL=C grep 'Health check:' \
    | tail -n 1 \
    | LC_ALL=C sed -nE 's/.*[^0-9]([0-9]+) warning.*/\1/p'
}

tmp_base="${TMPDIR:-/tmp}"
RUN_DIR="$(mktemp -d "${tmp_base%/}/ai-config-fleet.XXXXXX")" || {
  echo -e "${RED}✗${NC} Could not create a run folder in $tmp_base" >&2
  exit 2
}

mode_label="--$MODE"
[[ "$MODE" == refresh && "$DRY_RUN" == true ]] && mode_label="--refresh --dry-run"
echo -e "${CYAN}ai-config fleet${NC}: $mode_label on $COUNT project(s) under $ROOT (depth $DEPTH)"
if [[ "$MODE" == doctor && "$DRY_RUN" == true ]]; then
  echo -e "${YELLOW}○${NC} --dry-run ignored: --doctor is already read-only"
fi
echo "Logs: $RUN_DIR"
echo ""
printf '  %-*s  %-*s  %-*s  %-*s  %s\n' "$W_PROJ" PROJECT "$W_STACK" STACK "$W_VER" VERSION \
  $((W_RES + 2)) RESULT LOG

OK=0
WARNED=0
FAILED=0

for ((i = 0; i < COUNT; i++)); do
  dir="${PROJECTS[$i]}"
  rel="$(rel_path "$dir")"
  slug="${rel//\//__}"
  [[ "$rel" == "." ]] && slug="root"
  log_name="$(printf '%02d' $((i + 1)))-$slug.log"
  log="$RUN_DIR/$log_name"

  if [[ "$MODE" == refresh ]]; then
    cmd=(--refresh --project="$dir" --skip-vscode)
    [[ "$DRY_RUN" == true ]] && cmd+=(--dry-run)
  else
    cmd=(--doctor --project="$dir")
  fi
  [[ ${#EXTRA_ARGS[@]} -gt 0 ]] && cmd+=("${EXTRA_ARGS[@]}")

  {
    echo "# $(printf '%q ' "$SETUP_SCRIPT" "${cmd[@]}")"
    echo "# started $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
  } > "$log"
  run_setup "${cmd[@]}" >> "$log" 2>&1 < /dev/null
  status=$?
  printf '\n# exit status: %s\n' "$status" >> "$log"

  warnings="$(warning_count "$log")"
  if [[ $status -ne 0 ]]; then
    FAILED=$((FAILED + 1))
    color="$RED" glyph="✗" text="failed"
    [[ $status -ne 1 ]] && text="failed (exit $status)"
  elif [[ -n "$warnings" && "$warnings" -gt 0 ]]; then
    WARNED=$((WARNED + 1))
    color="$YELLOW" glyph="⚠" text="$warnings warnings"
    [[ "$warnings" -eq 1 ]] && text="1 warning"
  else
    OK=$((OK + 1))
    color="$GREEN" glyph="✓" text="ok"
  fi

  read_version "$dir"   # after the run: a refresh may have redeployed
  printf '  %-*s  %-*s  %-*s  ' "$W_PROJ" "$rel" "$W_STACK" "$V_STACK" "$W_VER" "$V_VERSION"
  printf '%b%s%b %-*s  %s\n' "$color" "$glyph" "$NC" "$W_RES" "$text" "$log_name"
done

echo ""
summary="$COUNT project(s): $OK ok, $WARNED with warnings, $FAILED failed"
if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}✗${NC} $summary"
  exit 1
elif [[ $WARNED -gt 0 ]]; then
  echo -e "${YELLOW}⚠${NC} $summary"
else
  echo -e "${GREEN}✓${NC} $summary"
fi
exit 0
