#!/bin/bash
# cps-ship.sh — merge a finished branch into staging (when the repo has one) and main, and push.
#
# Usage: cps-ship.sh <branch> <repo-folder>...
#   e.g. cps-ship.sh chore/devcontainer-github-access cps cfk cpsp
#
# Pushing staging or main DEPLOYS. Claude may run this script only after Robert has said yes
# to that specific ship in the conversation; it is allow-listed so auto mode doesn't block it.
#
# Guards (any failure skips that repo, pushes nothing for it, and leaves main where it was):
#   - the working tree must be clean, and local main/staging must not hold unpushed commits;
#   - origin/staging must hold nothing that isn't already on main (no unreleased work);
#   - staging and main only fast-forward or merge; nothing is rebased or force-pushed;
#   - before pushing main, the commits about to ship must be exactly the branch's own commits
#     (merge commits aside). Unreleased work sitting on staging, or anything else, stops it.
set -uo pipefail
ROOT=${CPS_ROOT:-~/Web/code/github.com/canadian-paediatric-society}

[ $# -ge 2 ] || { echo "Usage: $0 <branch> <repo-folder>..." >&2; exit 2; }
branch=$1; shift
failed=0

ship_one() {
  local repo=$1 g
  g() { git -C "$ROOT/$repo" "$@"; }
  echo "== $repo"
  [ -d "$ROOT/$repo/.git" ] || { echo "   FAIL no repo at $ROOT/$repo"; return 1; }
  g rev-parse -q --verify "refs/heads/$branch" >/dev/null || { echo "   FAIL no local branch $branch"; return 1; }
  [ -z "$(g status --porcelain)" ] || { echo "   FAIL working tree not clean"; return 1; }
  g fetch -q origin || { echo "   FAIL fetch"; return 1; }

  local b ahead
  for b in main staging; do
    g rev-parse -q --verify "refs/heads/$b" >/dev/null || continue
    g rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null || continue
    ahead=$(g rev-list --count "origin/$b..$b")
    [ "$ahead" = 0 ] || { echo "   FAIL local $b has $ahead unpushed commit(s); ship or drop them first"; return 1; }
  done

  # A branch cut from staging carries everything on staging, so unreleased staging work would
  # ride along to production. Refuse; that work has to be shipped deliberately.
  local unreleased
  if g rev-parse -q --verify refs/remotes/origin/staging >/dev/null; then
    unreleased=$(g rev-list --no-merges --count origin/main..origin/staging)
    if [ "$unreleased" != 0 ]; then
      echo "   FAIL staging has $unreleased commit(s) not on main:"
      g log --no-merges --format='     %h %s' origin/main..origin/staging
      return 1
    fi
  fi

  # The branch's own commits: what may reach production.
  local expected
  expected=$(g rev-list --no-merges "origin/main..$branch" | sort)
  [ -n "$expected" ] || { echo "   nothing to ship: $branch is already on main"; return 0; }
  echo "   shipping:"; g log --no-merges --format='     %h %s' "origin/main..$branch"

  local src=$branch
  if g rev-parse -q --verify refs/remotes/origin/staging >/dev/null; then
    g switch -q staging && g merge -q --ff-only origin/staging \
      && g merge -q --ff-only "$branch" || { echo "   FAIL staging fast-forward"; g switch -q "$branch"; return 1; }
    g push -q origin staging || { echo "   FAIL push staging"; return 1; }
    echo "   staging -> $(g rev-parse --short HEAD)"
    src=staging
  fi

  g switch -q main && g merge -q --ff-only origin/main || { echo "   FAIL main update"; return 1; }
  local before
  before=$(g rev-parse HEAD)
  g merge -q --ff-only "$src" 2>/dev/null || g merge -q --no-ff --no-edit "$src" \
    || { g merge --abort 2>/dev/null; echo "   FAIL main merge"; return 1; }

  local shipping
  shipping=$(g rev-list --no-merges "origin/main..main" | sort)
  if [ "$shipping" != "$expected" ]; then
    echo "   STOP main would ship commits that aren't on $branch:"
    comm -13 <(echo "$expected") <(echo "$shipping") | while read -r c; do g log -1 --format='     %h %s' "$c"; done
    g reset -q --hard "$before"
    return 1
  fi
  g push -q origin main || { echo "   FAIL push main"; return 1; }
  echo "   main -> $(g rev-parse --short HEAD)"
  g branch -q -d "$branch" && echo "   deleted $branch"
}

for repo in "$@"; do
  ship_one "$repo" || failed=1
done
exit $failed
