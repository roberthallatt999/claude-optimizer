#!/usr/bin/env bash
#
# sync-noslop.sh
# Build global-skills/noslop/SKILL.md from the CPS overlay and the pinned upstream copy, or pull
# a newer upstream first.
#
# The skill is the "noslop" rules from github.com/rubenhassid1/grenade (MIT). The upstream text
# is kept verbatim in global-skills/noslop/upstream/ so an update is a reviewable diff. CPS
# changes live in cps-overlay.md, which carries the frontmatter and goes first in SKILL.md.
#
# Usage:
#   scripts/sync-noslop.sh                 # rebuild SKILL.md (writes only on a real change)
#   scripts/sync-noslop.sh --check         # exit 1 if SKILL.md is out of date; writes nothing
#   scripts/sync-noslop.sh --update [REF]  # fetch upstream REF (default main), then rebuild
#
# --update never commits. Review the diff of upstream/noslop.md before committing it.
#
# Exit codes:
#   0  built, already current, or updated
#   1  out of date (--check), fetch failed, or upstream layout changed
#   2  usage error

set -euo pipefail

REPO_URL="https://github.com/rubenhassid1/grenade.git"
UPSTREAM_SKILL="plugins/noslop/skills/noslop/SKILL.md"
UPSTREAM_PLUGIN="plugins/noslop/.claude-plugin/plugin.json"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="${NOSLOP_SKILL_DIR:-$ROOT/global-skills/noslop}"
OVERLAY="$SKILL_DIR/cps-overlay.md"
UPSTREAM_DIR="$SKILL_DIR/upstream"
TARGET="$SKILL_DIR/SKILL.md"

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# Upstream SKILL.md starts with its own frontmatter; the overlay supplies ours, so drop theirs.
strip_frontmatter() {
  awk 'NR == 1 && $0 == "---" { in_fm = 1; next }
       in_fm && $0 == "---"    { in_fm = 0; skip_blank = 1; next }
       in_fm                   { next }
       skip_blank && $0 == ""  { next }
                               { skip_blank = 0; print }' "$1"
}

render() {
  cat "$OVERLAY"
  strip_frontmatter "$UPSTREAM_DIR/noslop.md"
}

build() {
  local mode="$1" tmp
  for f in "$OVERLAY" "$UPSTREAM_DIR/noslop.md"; do
    [[ -f "$f" ]] || { echo "Missing $f" >&2; exit 1; }
  done
  tmp="$(mktemp)"
  render > "$tmp"
  if [[ -f "$TARGET" ]] && cmp -s "$tmp" "$TARGET"; then
    rm -f "$tmp"
    echo "SKILL.md is current."
    return 0
  fi
  if [[ "$mode" == check ]]; then
    rm -f "$tmp"
    echo "SKILL.md is out of date: run scripts/sync-noslop.sh" >&2
    exit 1
  fi
  mv "$tmp" "$TARGET"
  echo "Rebuilt $TARGET"
}

update() {
  local ref="$1" work commit version
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  git clone --quiet --depth 1 --branch "$ref" "$REPO_URL" "$work/grenade" \
    || { echo "Could not fetch $REPO_URL ($ref)" >&2; exit 1; }
  [[ -f "$work/grenade/$UPSTREAM_SKILL" ]] \
    || { echo "Upstream no longer has $UPSTREAM_SKILL: check the repo layout by hand" >&2; exit 1; }

  commit="$(git -C "$work/grenade" rev-parse HEAD)"
  version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$work/grenade/$UPSTREAM_PLUGIN" 2>/dev/null | head -1)"

  cp "$work/grenade/$UPSTREAM_SKILL" "$UPSTREAM_DIR/noslop.md"
  cp "$work/grenade/LICENSE" "$UPSTREAM_DIR/LICENSE"
  {
    echo "repo=https://github.com/rubenhassid1/grenade"
    echo "path=$UPSTREAM_SKILL (stored here as noslop.md)"
    echo "commit=$commit"
    echo "version=${version:-unknown}"
  } > "$UPSTREAM_DIR/SOURCE"
  echo "Fetched upstream ${version:-?} at ${commit:0:12}"
  git -C "$ROOT" --no-pager diff --stat -- "$UPSTREAM_DIR" || true
}

case "${1:-}" in
  "")       build write ;;
  --check)  build check ;;
  --update) update "${2:-main}"; build write ;;
  -h|--help) usage ;;
  *)        usage ;;
esac
