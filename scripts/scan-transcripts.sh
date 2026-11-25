#!/usr/bin/env bash
#
# scan-transcripts.sh
# Check Claude Code's saved conversations for credentials that got into them.
#
# Claude Code keeps every session as a transcript in ~/.claude/projects/<project>/*.jsonl. If a
# secret ever reached a session (pasted, printed by a tool before a guard existed, read from a
# file), it stays in that file until Claude Code deletes it after cleanupPeriodDays (30 by
# default). This scans those files with the safety guard's own credential patterns
# (projects/common/hooks/safety-guard.sh, SECRET_CONTENT_RE: private keys and vendor token
# shapes) and prints which files hold how many matching lines. It never prints a match.
#
# What to do with a hit: rotate the credential (assume it's exposed), then delete that
# transcript file. Lowering cleanupPeriodDays in ~/.claude/settings.json keeps fewer around.
#
# Usage:
#   scripts/scan-transcripts.sh               scan ~/.claude/projects
#   scripts/scan-transcripts.sh DIR           scan another folder of .jsonl files
# Exit 0 when nothing is found, 1 when something is, 2 on an error.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO/projects/common/hooks/safety-guard.sh"
CLAUDE_DIR="${AI_CONFIG_CLAUDE_DIR:-$HOME/.claude}"
DIR="${1:-$CLAUDE_DIR/projects}"

pattern=$(sed -n "s/^SECRET_CONTENT_RE='\(.*\)'\$/\1/p" "$GUARD" | head -n 1)
[[ -n "$pattern" ]] || { echo "scan-transcripts.sh: couldn't read the credential patterns from $GUARD" >&2; exit 2; }
[[ -d "$DIR" ]] || { echo "No transcripts at $DIR."; exit 0; }

days=$(jq -r '.cleanupPeriodDays // empty' "$CLAUDE_DIR/settings.json" 2>/dev/null || true)
echo "Transcripts in $DIR (kept ${days:-30} days${days:+ by your settings}${days:- by default})."

found=0 files=0
while IFS= read -r -d '' f; do
  files=$((files + 1))
  n=$(LC_ALL=C grep -Ec -e "$pattern" "$f" 2>/dev/null || true)
  if [[ "${n:-0}" -gt 0 ]]; then
    found=$((found + 1))
    printf '  %4d line(s)  %s\n' "$n" "${f#"$DIR"/}"
  fi
done < <(find "$DIR" -type f -name '*.jsonl' -print0 2>/dev/null)

echo ""
if [[ $found -eq 0 ]]; then
  echo "Scanned $files transcript(s): no credential-shaped text."
  exit 0
fi
echo "Scanned $files transcript(s): $found hold credential-shaped text (values not shown)."
echo "For each: rotate the credential it held, then delete the file. To keep fewer transcripts,"
echo "set \"cleanupPeriodDays\" in $CLAUDE_DIR/settings.json (for example 14)."
exit 1
