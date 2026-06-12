#!/usr/bin/env bash
#
# update-superpowers.sh
# Pull the latest superpowers/ git subtree from the upstream fork (squashed).
#
# Safe to run standalone or to be called from setup-project.sh as a best-effort
# step before deploying skills. It operates on THIS repository (the directory the
# script lives in), never on a target project.
#
# Usage:
#   ./update-superpowers.sh [--quiet]
#
# Exit codes:
#   0  updated, already up to date, or cleanly skipped (e.g. offline)
#   1  could not update (dirty tree, conflict, not a git repo, git missing)

set -uo pipefail

REMOTE_URL="https://github.com/roberthallatt999/superpowers.git"
BRANCH="main"
PREFIX="superpowers"

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

log()  { [[ "$QUIET" == true ]] || echo "$@"; }
warn() { echo "  ⚠  $*" >&2; }

# Operate on the repo this script lives in, regardless of the caller's CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { warn "cannot cd to $SCRIPT_DIR"; exit 1; }

# --- preflight ---------------------------------------------------------------
command -v git >/dev/null 2>&1 || { warn "git not found — skipping superpowers update"; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { warn "$SCRIPT_DIR is not a git repository — skipping superpowers update"; exit 1; }

[[ -d "$PREFIX" ]] || { warn "$PREFIX/ subtree not found — skipping superpowers update"; exit 1; }

# git subtree pull refuses to run with a dirty tree and can abort mid-merge.
if [[ -n "$(git status --porcelain)" ]]; then
  warn "working tree has uncommitted changes — skipping superpowers update"
  warn "commit or stash your changes, then run ./update-superpowers.sh"
  exit 1
fi

# If upstream is unreachable (offline / auth), skip cleanly — not a failure.
if ! git ls-remote "$REMOTE_URL" "$BRANCH" >/dev/null 2>&1; then
  warn "cannot reach $REMOTE_URL ($BRANCH) — skipping (using vendored copy)"
  exit 0
fi

# --- update ------------------------------------------------------------------
log "Pulling latest superpowers from ${REMOTE_URL} (${BRANCH})..."

before="$(git rev-parse HEAD)"
if ! git subtree pull --prefix="$PREFIX" "$REMOTE_URL" "$BRANCH" --squash >/dev/null 2>&1; then
  warn "git subtree pull failed — superpowers left unchanged"
  # If a merge was started and conflicted, restore the clean state.
  git merge --abort 2>/dev/null || true
  exit 1
fi
after="$(git rev-parse HEAD)"

if [[ "$before" == "$after" ]]; then
  log "Superpowers already up to date."
else
  log "Superpowers updated (${before:0:7} → ${after:0:7})."
  log "Review with: git diff ${before:0:7} ${after:0:7} -- ${PREFIX}/"
fi
