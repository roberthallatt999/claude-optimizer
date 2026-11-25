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
#   hooks.PreToolUse                     a root-owned copy of the safety guard
# and, with --strict:
#   allowManagedHooksOnly, allowManagedPermissionRulesOnly
#     (only managed hooks and permission rules load: every project's own hooks and rules are
#      ignored, so use it only where every session should run under the same fixed policy)
#
# Those folders belong to root, so this never writes there itself. It builds the file in
# ~/.cache/ai-config/managed/, checks it, and prints the one command to run in your own
# terminal (it asks for your password). Nothing is installed without you.
#
# The hook runs a copy of this repo's guard installed next to the managed settings
# (.../ClaudeCode/ai-config/safety-guard.sh, root-owned), not ~/.claude/hooks/: a file you can
# write is a file anything running as you can rewrite, and the managed floor would then be only
# as strong as that file. The printed command copies the staged files into root-owned places
# first and checks their SHA-256 against the sums printed here before it moves them into place,
# so a staged file changed after this run is refused.
#
# Usage:
#   scripts/install-managed-settings.sh            build, compare with what's installed, print the command
#   scripts/install-managed-settings.sh --strict   the same, with the two managed-only switches
#   scripts/install-managed-settings.sh --check    exit 0 when the installed file matches a fresh build
#   scripts/install-managed-settings.sh --remove   print the command that removes it
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO/projects/common/security.settings.local.json"
GUARD_SRC="$REPO/projects/common/hooks/safety-guard.sh"
PATHS_SRC="${AI_CONFIG_CLAUDE_DIR:-$HOME/.claude}/hooks/protected-paths.conf"
STAGE_DIR="${AI_CONFIG_MANAGED_STAGE:-$HOME/.cache/ai-config/managed}"
NAME="50-ai-config.json"

case "$(uname -s)" in
  Darwin) MANAGED_DIR="${AI_CONFIG_MANAGED_DIR:-/Library/Application Support/ClaudeCode/managed-settings.d}"; OWNER="root:wheel" ;;
  *)      MANAGED_DIR="${AI_CONFIG_MANAGED_DIR:-/etc/claude-code/managed-settings.d}"; OWNER="root:root" ;;
esac
TARGET="$MANAGED_DIR/$NAME"
GUARD_DIR="${AI_CONFIG_MANAGED_GUARD_DIR:-${MANAGED_DIR%/*}/ai-config}"
GUARD="$GUARD_DIR/safety-guard.sh"
# Tests set AI_CONFIG_MANAGED_SUDO= (empty) to run the printed command without root.
SUDO="${AI_CONFIG_MANAGED_SUDO-sudo}"
if command -v shasum >/dev/null; then SHA="shasum -a 256"; else SHA="sha256sum"; fi

mode=install
strict=false
for arg in "$@"; do
  case "$arg" in
    --strict) strict=true ;;
    --check) mode=check ;;
    --remove) mode=remove ;;
    -h|--help) sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install-managed-settings.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "install-managed-settings.sh: needs jq" >&2; exit 1; }

if [[ "$mode" == remove ]]; then
  if [[ -e "$TARGET" || -e "$GUARD" ]]; then
    echo "Run this in your own terminal to remove ai-config's managed settings:"
    echo ""
    printf '  sudo rm -f %q %q %q\n' "$TARGET" "$GUARD" "$GUARD_DIR/protected-paths.conf"
  else
    echo "Not installed ($TARGET)."
  fi
  exit 0
fi

[[ -f "$GUARD_SRC" ]] || { echo "install-managed-settings.sh: $GUARD_SRC is missing" >&2; exit 1; }

mkdir -p "$STAGE_DIR"
chmod 700 "$STAGE_DIR"
staged="$STAGE_DIR/$NAME"
staged_guard="$STAGE_DIR/safety-guard.sh"
staged_paths="$STAGE_DIR/protected-paths.conf"
cp "$GUARD_SRC" "$staged_guard.new" && mv "$staged_guard.new" "$staged_guard"
if [[ -f "$PATHS_SRC" ]]; then cp "$PATHS_SRC" "$staged_paths.new" && mv "$staged_paths.new" "$staged_paths"; else : > "$staged_paths"; fi
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
[[ -f "$TARGET" ]] && cmp -s "$staged" "$TARGET" && cmp -s "$staged_guard" "$GUARD" \
  && cmp -s "$staged_paths" "$GUARD_DIR/protected-paths.conf" && same=true

if [[ "$mode" == check ]]; then
  if [[ "$same" == true ]]; then echo "Managed settings are current ($TARGET)."; exit 0; fi
  if [[ -f "$TARGET" ]]; then echo "Managed settings (or the managed guard copy) differ from a fresh build: rerun scripts/install-managed-settings.sh."; else echo "Not installed ($TARGET)."; fi
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
sum() { $SHA "$1" | awk '{print $1}'; }
q() { printf '%q' "$1"; }
own=""
[[ -n "$SUDO" ]] && own="-o ${OWNER%%:*} -g ${OWNER##*:}"
# One root shell: copy into root-owned temporary names, check those copies, then rename. The
# check runs on the root-owned copy, so nothing can swap a file between the check and the move.
script="set -e; umask 022; install -d -m 755 $(q "$MANAGED_DIR") $(q "$GUARD_DIR")"
script+="; install -m 644 $own $(q "$staged") $(q "$TARGET.new")"
script+="; install -m 755 $own $(q "$staged_guard") $(q "$GUARD.new")"
script+="; install -m 644 $own $(q "$staged_paths") $(q "$GUARD_DIR/protected-paths.conf.new")"
check=""
for pair in "$staged|$TARGET.new" "$staged_guard|$GUARD.new" "$staged_paths|$GUARD_DIR/protected-paths.conf.new"; do
  check+="${check:+ && }echo $(q "$(sum "${pair%%|*}")  ${pair#*|}") | $SHA -c - >/dev/null"
done
script+="; { $check; }"
script+=" || { rm -f $(q "$TARGET.new") $(q "$GUARD.new") $(q "$GUARD_DIR/protected-paths.conf.new"); echo 'Refused: a staged file changed after it was built. Rerun scripts/install-managed-settings.sh.' >&2; exit 1; }"
script+="; mv -f $(q "$GUARD.new") $(q "$GUARD"); mv -f $(q "$GUARD_DIR/protected-paths.conf.new") $(q "$GUARD_DIR/protected-paths.conf"); mv -f $(q "$TARGET.new") $(q "$TARGET")"
INSTALL_CMD="${SUDO:+$SUDO }sh -c $(q "$script")"
echo "Run this in your own terminal (it asks for your password), then restart Claude Code:"
echo ""
printf '  %s\n' "$INSTALL_CMD"
echo ""
echo "It installs the guard as $GUARD (root-owned) and refuses if a staged file's SHA-256"
echo "no longer matches: settings $(sum "$staged" | cut -c1-12)…, guard $(sum "$staged_guard" | cut -c1-12)…"
echo ""
echo "Check it afterwards with /status in Claude Code (Setting sources lists the managed file),"
echo "or: scripts/install-managed-settings.sh --check"
