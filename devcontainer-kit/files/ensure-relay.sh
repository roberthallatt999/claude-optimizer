#!/bin/bash
# Runs on the Mac before the dev container starts (initializeCommand, or from ensure-ddev.sh).
#
# Starts the relay (ddev-relay.pl) if it isn't running, and gives this project its token. One
# relay serves every container on this Mac; each project's token is mounted into its own
# container only, and the token decides the project (a request can't name another one).
# The relay carries domain requests from sandbox-domains (every project) and, for DDEV
# projects, allowlisted ddev commands.
#
#   ensure-relay.sh <workspace> <key>
#
# State: ~/.cache/ai-devcontainer/relay/. On a Mac that ran kit 1.x, ~/.cache/ai-devcontainer
# is made a link to ~/.cache/cps-devcontainer, so running 1.x containers keep their mounts.
# bash 3.2 compatible: macOS runs this with /bin/bash.
set -euo pipefail

workspace="${1:?usage: ensure-relay.sh <workspace> <key>}"
key="${2:?usage: ensure-relay.sh <workspace> <key>}"
case "$key" in
  *[!A-Za-z0-9_.-]*|'') echo "ensure-relay.sh: bad project key '$key'" >&2; exit 2 ;;
esac

STATE_DIR="$HOME/.cache/ai-devcontainer"
OLD_STATE="$HOME/.cache/cps-devcontainer"
if [ ! -e "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ -d "$OLD_STATE" ] && [ ! -L "$OLD_STATE" ]; then
  ln -s "$OLD_STATE" "$STATE_DIR"
fi
PORT=${AI_DEVCONTAINER_RELAY_PORT:-${CPS_DDEV_RELAY_PORT:-20090}}
relay_dir="$STATE_DIR/relay"

relay_version() {
  sed -n 's/^our \$VERSION = \([0-9][0-9]*\);.*/\1/p' "$1" 2>/dev/null | head -1
}

# In its own session: VS Code kills this script's process group when it exits, and nohup only
# shields against SIGHUP. macOS has no setsid(1), so perl calls setsid(2).
start_detached() {
  nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid() >= 0 or die "setsid: $!\n"; exec @ARGV or die "exec: $!\n"' \
    "$@" </dev/null >>"$relay_dir/relay.log" 2>&1 &
}

source="$workspace/.devcontainer/ddev-relay.pl"
[ -f "$source" ] || exit 0
mkdir -p "$relay_dir/tokens"
chmod 700 "$relay_dir" "$relay_dir/tokens"
token_file="$relay_dir/tokens/$key.token"
# Docker creates a directory for a bind-mount source that doesn't exist yet.
[ -d "$token_file" ] && rmdir "$token_file" 2>/dev/null
# Written once and never replaced: the container's bind mount holds the old inode.
if [ ! -s "$token_file" ]; then
  (umask 077 && openssl rand -hex 32 > "$token_file")
fi
echo "$workspace" > "$relay_dir/tokens/$key.root"

installed="$relay_dir/ddev-relay.pl"
# Repos may carry different kit versions; only ever move the shared copy forward.
if [ ! -f "$installed" ] || [ "$(relay_version "$source")" -gt "$(relay_version "$installed")" ]; then
  cp "$source" "$installed"
fi
running=$(AI_DEVCONTAINER_RELAY_PORT=$PORT /usr/bin/perl "$installed" --ping 2>/dev/null || true)
if [ -n "$running" ] && [ "$running" -ge "$(relay_version "$installed")" ]; then
  exit 0
fi
if [ -n "$running" ]; then
  pid=$(cat "$relay_dir/relay.pid" 2>/dev/null || true)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  sleep 1
fi
AI_DEVCONTAINER_RELAY_PORT=$PORT start_detached /usr/bin/perl "$installed" --serve
tries=0
until AI_DEVCONTAINER_RELAY_PORT=$PORT /usr/bin/perl "$installed" --ping >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -gt 30 ]; then
    echo "Warning: the relay did not start, so sandbox-domains (and ddev start/stop/logs) won't work inside. Log: $relay_dir/relay.log"
    exit 0
  fi
  sleep 0.2
done
echo "Relay running on 127.0.0.1:$PORT (requests: $relay_dir/relay.log)."
