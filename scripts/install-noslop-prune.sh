#!/usr/bin/env bash
#
# install-noslop-prune.sh
# Install (or remove) a macOS LaunchAgent that deletes expired noslop share pages every week.
#
# Runs `cloudflare.sh prune --delete` on Mondays at 09:00 local time (or at the next wake),
# appends the output to ~/Library/Logs/noslop-prune.log, and shows a notification when it
# deleted something. Only pages past their expiry date on the share domain are touched.
# Robert runs this himself: it creates a job that persists on the Mac.
#
# Usage:
#   scripts/install-noslop-prune.sh            # install or update the agent, then load it
#   scripts/install-noslop-prune.sh --print    # print the agent's plist; install nothing
#   scripts/install-noslop-prune.sh --remove   # unload and delete it
#
# Exit codes: 0 done, 1 not macOS or helper missing

set -euo pipefail

LABEL="ca.cps.noslop-prune"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/noslop-prune.log"
HELPER="$HOME/.claude/skills/noslop/scripts/cloudflare.sh"

# The job, run by bash with the helper as $0 and the log as $1: prune, log with a timestamp,
# and notify only when a page was deleted.
JOB='{ echo "== $(date "+%F %T")"; out=$("$0" prune --delete 2>&1); status=$?; echo "$out"; } >> "$1" 2>&1;
n=$(printf "%s\n" "$out" | grep -c "^deleted ");
if [ "$n" -gt 0 ]; then osascript -e "display notification \"Deleted $n expired page(s) from share.cps.ca\" with title \"noslop\""; fi;
exit $status'

# XML-escape the job for the plist. sed, not ${var//}: bash 5.2 reads & in a replacement as
# the matched text.
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

render_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>$(xml_escape "$JOB")</string>
    <string>$HELPER</string>
    <string>$LOG</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>1</integer>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
</dict>
</plist>
PLIST
}

case "${1:-}" in
  --print)
    render_plist
    exit 0
    ;;
  --remove)
    [[ "$(uname -s)" == Darwin ]] || { echo "macOS only (launchd)" >&2; exit 1; }
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed $LABEL"
    exit 0
    ;;
  "") ;;
  *)
    sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac

[[ "$(uname -s)" == Darwin ]] || { echo "macOS only (launchd)" >&2; exit 1; }
[[ -x "$HELPER" ]] || { echo "No noslop helper at $HELPER: run install.sh first" >&2; exit 1; }

mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
render_plist > "$PLIST"
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL: Mondays 09:00, log $LOG"
