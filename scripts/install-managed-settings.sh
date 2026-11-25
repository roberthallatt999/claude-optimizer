#!/usr/bin/env bash
#
# install-managed-settings.sh
# Put ai-config's safety floor in Claude Code's machine-wide managed settings, where no user,
# project or plugin settings file can remove it.
#
# install-global-guard.sh registers the safety guard and the secret-file deny rules in
# ~/.claude/settings.json. That file is yours to edit, and so is every project's: a careless
# edit, a plugin or a project file could drop them. Managed settings rank above every other
# source, and lists merge, so a deny rule there can't be taken away
# (https://code.claude.com/docs/en/settings, settings precedence).
#
# This writes one drop-in file, so an existing managed-settings.json is never replaced:
#   macOS  /Library/Application Support/ClaudeCode/managed-settings.d/50-ai-config.json
#   Linux  /etc/claude-code/managed-settings.d/50-ai-config.json
# holding:
#   permissions.deny                     the shared secret-file deny rules
#   permissions.disableBypassPermissionsMode = "disable"   (no --dangerously-skip-permissions)
#   hooks.PreToolUse                     this machine's global safety guard
# and, with --strict:
#   allowManagedHooksOnly, allowManagedPermissionRulesOnly
#     (only managed hooks and permission rules load: every project's own hooks and rules are
#      ignored, so use it only where every session should run under the same fixed policy)
#
# Those folders belong to root, so this never writes there itself. It builds the file in
# ~/.cache/ai-config/managed/, checks it, and prints the one command to run in your own
# terminal (it asks for your password). Nothing is installed without you.
#
# Usage:
#   scripts/install-managed-settings.sh            build, compare with what's installed, print the command
#   scripts/install-managed-settings.sh --strict   the same, with the two managed-only switches
#   scripts/install-managed-settings.sh --check    exit 0 when the installed file matches a fresh build
#   scripts/install-managed-settings.sh --remove   print the command that removes it
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO/projects/common/security.settings.local.json"
GUARD="${AI_CONFIG_CLAUDE_DIR:-$HOME/.claude}/hooks/safety-guard.sh"
STAGE_DIR="${AI_CONFIG_MANAGED_STAGE:-$HOME/.cache/ai-config/managed}"
NAME="50-ai-config.json"

case "$(uname -s)" in
  Darwin) MANAGED_DIR="${AI_CONFIG_MANAGED_DIR:-/Library/Application Support/ClaudeCode/managed-settings.d}"; OWNER="root:wheel" ;;
  *)      MANAGED_DIR="${AI_CONFIG_MANAGED_DIR:-/etc/claude-code/managed-settings.d}"; OWNER="root:root" ;;
esac
TARGET="$MANAGED_DIR/$NAME"

mode=install
strict=false
for arg in "$@"; do
  case "$arg" in
    --strict) strict=true ;;
    --check) mode=check ;;
    --remove) mode=remove ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install-managed-settings.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "install-managed-settings.sh: needs jq" >&2; exit 1; }

if [[ "$mode" == remove ]]; then
  if [[ -e "$TARGET" ]]; then
    echo "Run this in your own terminal to remove ai-config's managed settings:"
    echo ""
    printf '  sudo rm %q\n' "$TARGET"
  else
    echo "Not installed ($TARGET)."
  fi
  exit 0
fi

[[ -f "$GUARD" ]] || echo "Note: $GUARD doesn't exist yet; run scripts/install-global-guard.sh first, or the hook can't start." >&2

mkdir -p "$STAGE_DIR"
staged="$STAGE_DIR/$NAME"
jq -n --slurpfile p "$POLICY" --arg guard "$GUARD" --argjson strict "$strict" '
  {
    "$schema": "https://json.schemastore.org/claude-code-settings.json",
    "permissions": {
      "deny": ($p[0].permissions.deny // []),
      "disableBypassPermissionsMode": "disable"
    },
    "hooks": {
      "PreToolUse": [{
        "matcher": "Bash|Read|Edit|MultiEdit|Write|NotebookEdit|Grep|Glob|mcp__.*",
        "hooks": [{"type": "command", "timeout": 10,
                   "command": ("AI_CONFIG_GUARD_SCOPE=global bash " + ($guard | @sh))}]
      }]
    }
  }
  | if $strict then .allowManagedHooksOnly = true | .permissions.allowManagedPermissionRulesOnly = true else . end
' > "$staged.new"
jq -e '.permissions.deny | length > 0' "$staged.new" >/dev/null \
  || { echo "install-managed-settings.sh: built an empty deny list from $POLICY; nothing to install" >&2; rm -f "$staged.new"; exit 1; }
mv "$staged.new" "$staged"
chmod 644 "$staged"

same=false
[[ -f "$TARGET" ]] && cmp -s "$staged" "$TARGET" && same=true

if [[ "$mode" == check ]]; then
  if [[ "$same" == true ]]; then echo "Managed settings are current ($TARGET)."; exit 0; fi
  if [[ -f "$TARGET" ]]; then echo "Managed settings differ from a fresh build: rerun scripts/install-managed-settings.sh."; else echo "Not installed ($TARGET)."; fi
  exit 1
fi

echo "Built $staged:"
echo "  $(jq '.permissions.deny | length' "$staged") deny rules, bypass mode disabled, the safety guard as a PreToolUse hook$( [[ "$strict" == true ]] && echo ', managed hooks and rules only')."
if [[ "$same" == true ]]; then
  echo "Already installed and current: $TARGET"
  exit 0
fi
if [[ -f "$TARGET" ]]; then
  echo ""
  echo "Changes from the installed copy:"
  diff -u "$TARGET" "$staged" || true
fi
echo ""
echo "Run this in your own terminal (it asks for your password), then restart Claude Code:"
echo ""
printf '  sudo install -d -m 755 %q && sudo install -m 644 -o %s -g %s %q %q\n' \
  "$MANAGED_DIR" "${OWNER%%:*}" "${OWNER##*:}" "$staged" "$TARGET"
echo ""
echo "Check it afterwards with /status in Claude Code (Setting sources lists the managed file),"
echo "or: scripts/install-managed-settings.sh --check"
