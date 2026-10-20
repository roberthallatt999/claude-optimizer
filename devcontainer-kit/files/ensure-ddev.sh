#!/bin/bash
# Runs on the Mac as the dev container's initializeCommand, before the container starts.
#
# Starts every DDEV project the container needs: this folder's own project, plus any project
# docker-compose.yml links to (Statements Studio reads ddev-cps-db; intranet-frontend calls
# intranet-api through the router).
#
# Then leaves a watcher in the background that stops those projects again once the container
# stops (VS Code stops it when the window closes). The spec has no host-side "on close" hook,
# so this is the only way to get one. The watcher stops only projects this script started, so
# a site you had running on the Mac beforehand stays up, and it skips any project another open
# dev container still needs.
#
# bash 3.2 compatible: macOS runs this with /bin/bash.
set -euo pipefail

# VS Code launched from the Dock doesn't inherit the shell's PATH, so Homebrew's ddev is invisible.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

STATE_DIR="$HOME/.cache/cps-devcontainer"
# How long a fresh build may take before the container first appears.
APPEAR_TIMEOUT=${CPS_DDEV_APPEAR_TIMEOUT:-1800}
# A rebuild stops the container and creates a new one; don't mistake that gap for a close.
CLOSE_GRACE=${CPS_DDEV_CLOSE_GRACE:-90}

is_running() {
  docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -q true
}

ddev_name() {
  [ -f "$1/.ddev/config.yaml" ] || return 0
  sed -n 's/^name:[[:space:]]*//p' "$1/.ddev/config.yaml" | head -1 | tr -d "\"'"
}

# Prints "project container" pairs a workspace's dev container needs. Links to
# ddev-<project>-db/web name the project directly; a router link (ddev-router:intranet-api.test)
# names it as the hostname's first label. ddev-router and ddev-ssh-agent are global.
needed_for() {
  local workspace="$1" compose="$1/.devcontainer/docker-compose.yml" own
  own=$(ddev_name "$workspace")
  {
    [ -n "$own" ] && echo "$own ddev-$own-web"
    grep -oE 'ddev-[a-z0-9-]+-(db|web)' "$compose" 2>/dev/null \
      | sed -E 's/^ddev-(.+)-(db|web)$/\1 &/' || true
    grep -oE 'ddev-router:[a-z0-9-]+' "$compose" 2>/dev/null \
      | sed -E 's/^ddev-router:(.+)$/\1 ddev-\1-web/' || true
  } | sort -u
}

# VS Code labels every dev container with the Mac folder it was opened from.
container_for() {
  docker ps -q --filter "label=devcontainer.local_folder=$1" | head -1
}

state_file_for() {
  echo "$STATE_DIR/$(echo "$1" | tr '/' '_').watch"
}

# True when a dev container other than this workspace's is running and needs the project.
needed_elsewhere() {
  local project="$1" workspace="$2" other
  for other in $(docker ps --filter label=devcontainer.local_folder \
      --format '{{.Label "devcontainer.local_folder"}}' | sort -u); do
    [ "$other" = "$workspace" ] && continue
    needed_for "$other" | awk '{print $1}' | grep -qx "$project" && return 0
  done
  return 1
}

watch() {
  local workspace="$1" state_file container waited=0 project
  shift
  state_file=$(state_file_for "$workspace")
  echo "$(date '+%F %T') watching $workspace for: $*"

  until container=$(container_for "$workspace") && [ -n "$container" ]; do
    if [ "$waited" -ge "$APPEAR_TIMEOUT" ]; then
      echo "$(date '+%F %T') container never started; leaving DDEV running"
      rm -f "$state_file"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done

  while :; do
    docker wait "$container" >/dev/null 2>&1 || true
    sleep "$CLOSE_GRACE"
    container=$(container_for "$workspace")
    [ -z "$container" ] && break
    echo "$(date '+%F %T') container came back (rebuild); still watching"
  done

  for project in "$@"; do
    if needed_elsewhere "$project" "$workspace"; then
      echo "$(date '+%F %T') $project: another open dev container needs it; leaving it running"
      continue
    fi
    echo "$(date '+%F %T') stopping $project"
    ddev stop "$project" || true
  done
  rm -f "$state_file"
}

if [ "${1:-}" = '--watch' ]; then
  shift
  watch "$@"
  exit 0
fi

workspace="${1:-$PWD}"

if ! docker info >/dev/null 2>&1; then
  echo 'Docker is not running. Start Docker, then reopen the container.'
  exit 1
fi
if ! command -v ddev >/dev/null 2>&1; then
  echo 'ddev is not installed on this Mac (expected in /opt/homebrew/bin).'
  exit 1
fi

own_project=$(ddev_name "$workspace")
needed=$(needed_for "$workspace")
if [ -z "$needed" ]; then
  echo 'No DDEV project found for this container; nothing to start.'
  exit 0
fi

started=''
while read -r project container; do
  [ -z "$project" ] && continue
  is_running "$container" && continue
  case " $started " in *" $project "*) continue ;; esac
  echo "DDEV project $project is not running; starting it..."
  if ddev start "$project"; then
    started="$started $project"
    continue
  fi
  # The container can't work without its own project; a linked one only costs that link.
  if [ "$project" = "$own_project" ]; then
    echo "Could not start DDEV project $project."
    exit 1
  fi
  echo "Warning: could not start linked DDEV project $project; continuing without it."
done <<< "$needed"

# A reopen or rebuild replaces the previous watcher and inherits the projects it owned, so
# sites started on the first open still stop when the container finally closes.
mkdir -p "$STATE_DIR"
state_file=$(state_file_for "$workspace")
owned="$started"
if [ -f "$state_file" ]; then
  read -r old_pid old_projects < "$state_file" || true
  kill "${old_pid:-0}" 2>/dev/null || true
  owned="$owned ${old_projects:-}"
fi
owned=$(echo $owned | tr ' ' '\n' | sort -u | tr '\n' ' ')
owned="${owned% }"

if [ -z "$owned" ]; then
  rm -f "$state_file"
  exit 0
fi

# In its own session, not just nohup'd: when this script exits, VS Code kills its whole process
# group, and nohup only shields against SIGHUP. macOS has no setsid(1), so perl calls setsid(2).
# shellcheck disable=SC2086
nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid() >= 0 or die "setsid: $!\n"; exec @ARGV or die "exec: $!\n"' \
  /bin/bash "$0" --watch "$workspace" $owned </dev/null >>"$STATE_DIR/watch.log" 2>&1 &
watcher=$!
# Exiting before the watcher has left our process group would get it killed along with us.
tries=0
until [ "$(ps -o pgid= -p "$watcher" 2>/dev/null | tr -d ' ')" = "$watcher" ]; do
  tries=$((tries + 1))
  if [ "$tries" -gt 50 ]; then
    echo "Warning: the DDEV stop-on-close watcher did not start; stop DDEV by hand. Log: $STATE_DIR/watch.log"
    rm -f "$state_file"
    exit 0
  fi
  sleep 0.1
done
echo "$watcher $owned" > "$state_file"
echo "Will stop DDEV ($owned) when this container closes. Log: $STATE_DIR/watch.log"
