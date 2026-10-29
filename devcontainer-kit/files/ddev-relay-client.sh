#!/bin/bash
# Sends a `ddev` command from the Claude sandbox to the relay on the Mac (ddev-relay.pl), which
# checks it against its allowlist and runs the real ddev there. Called by the ddev shim for
# anything it can't run inside. Read from the read-only .devcontainer mount, so it updates
# without a rebuild.
set -uo pipefail
TOKEN_FILE=/run/ddev-relay/token
HOST=host.docker.internal
PORT=${CPS_DDEV_RELAY_PORT:-20090}

if [ ! -r "$TOKEN_FILE" ]; then
  echo "ddev ${1:-}: the DDEV relay isn't set up for this container (no $TOKEN_FILE)." >&2
  echo "Run it in a terminal on the Mac, or rebuild the container with kit 1.9.0 or later." >&2
  exit 1
fi
for arg in "$@"; do
  case "$arg" in
    *$'\n'*|*$'\r'*) echo 'ddev (relay): arguments may not contain newlines' >&2; exit 2 ;;
  esac
done

if ! exec 3<>"/dev/tcp/$HOST/$PORT" 2>/dev/null; then
  echo "ddev ${1:-}: the DDEV relay on the Mac isn't answering on $HOST:$PORT." >&2
  echo 'Reopen the container (ensure-ddev.sh starts it), or run the command on the Mac.' >&2
  exit 1
fi

{
  printf 'CPSRELAY1\n%s\n%s\n%s\n' "$(cat "$TOKEN_FILE")" "$PWD" "$#"
  printf '%s\n' "$@"
} >&3

code=1
while IFS= read -r line <&3; do
  if [[ "$line" == $'\x1e'EXIT\ * ]]; then
    code=${line#$'\x1e'EXIT }
    break
  fi
  printf '%s\n' "$line"
done
exec 3<&-
exit "$code"
