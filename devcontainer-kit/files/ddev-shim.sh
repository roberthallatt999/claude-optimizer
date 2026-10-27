#!/bin/bash
# Stand-in for `ddev` inside the Claude sandbox (installed as /usr/local/bin/ddev).
#
# CLAUDE.md files tell Claude to run `ddev artisan …`, `ddev composer …`, `ddev ee …`.
# This runs the same tools directly in the container. The project's own custom web
# commands (.ddev/commands/web/*) run too, with /var/www/html mapped to /workspace.
# Anything that controls Docker or DDEV itself (start, stop, import-db, push, …) is
# refused: run it on the Mac.
set -euo pipefail
ROOT=/workspace
cmd="${1:-}"; shift || true

export DDEV_APPROOT="$ROOT"
export DDEV_PROJECT="${DDEV_PROJECT:-}"
export DDEV_DOCROOT="${DDEV_DOCROOT:-}"

case "$cmd" in
  artisan)               cd "$ROOT" && exec php artisan "$@" ;;
  craft)                 cd "$ROOT" && exec php craft "$@" ;;
  composer)              cd "$ROOT" && exec composer "$@" ;;
  npm|npx|node|yarn|pnpm) cd "$ROOT" && exec "$cmd" "$@" ;;
  php|python|python3|pip) exec "$cmd" "$@" ;;
  exec)                  cd "$ROOT" && exec "$@" ;;
  mysql|mariadb)         exec mariadb -h db -u db -pdb "${DDEV_DB_NAME:-db}" "$@" ;;
  describe)              echo "Claude sandbox. DDEV runs on the Mac (project: ${DDEV_PROJECT:-none})."; exit 0 ;;
esac

# Project custom web commands, e.g. `ddev ee`, `ddev mcp-serve`, `ddev wp`.
custom="$ROOT/.ddev/commands/web/$cmd"
if [ -n "$cmd" ] && [ -f "$custom" ]; then
  tmp=$(mktemp)
  sed 's#/var/www/html#/workspace#g' "$custom" > "$tmp"
  cd "$ROOT"
  exec bash "$tmp" "$@"
fi

echo "ddev ${cmd:-}: not available inside the Claude sandbox." >&2
echo "Run it in a terminal on the Mac (outside the dev container)." >&2
exit 1
