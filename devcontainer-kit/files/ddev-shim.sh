#!/bin/bash
# Stand-in for `ddev` inside the Claude sandbox (installed as /usr/local/bin/ddev).
#
# CLAUDE.md files tell Claude to run `ddev artisan …`, `ddev composer …`, `ddev ee …`.
# This runs the same tools directly in the container. The project's own custom web
# commands (.ddev/commands/web/*) run too, with /var/www/html mapped to /workspace.
# Anything that controls DDEV itself (start, stop, logs, snapshot, import-db, …) goes to
# the relay on the Mac (ddev-relay-client.sh), which runs an allowlisted set of commands.
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
  mysql|mariadb)
    # `ddev mysql [--project=NAME] [database] [mariadb options…]`. --database only sets the
    # default, so a name given as an argument wins, as with real `ddev mysql` (ee-migrate.sh
    # runs `ddev mysql admin_cps -N …`). --project reaches another DDEV project's database
    # server over ddev_default; its default database is `db`, so name the site's one.
    host=db db_name="${DDEV_DB_NAME:-db}" project="" other_project=false
    case "${1:-}" in
      --project=*) other_project=true project="${1#--project=}"; shift ;;
      --project)   other_project=true project="${2:-}"; shift; shift || true ;;
    esac
    if [ "$other_project" = true ]; then
      if ! [[ "$project" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        echo "ddev mysql: --project needs a DDEV project name, e.g. --project=cfk" >&2
        exit 2
      fi
      host="ddev-$project-db" db_name=db
    fi
    exec mariadb -h "$host" -u db -pdb --database="$db_name" "$@" ;;
esac

# Project custom web commands, e.g. `ddev ee`, `ddev mcp-serve`, `ddev wp`.
custom="$ROOT/.ddev/commands/web/$cmd"
if [ -n "$cmd" ] && [ -f "$custom" ]; then
  tmp=$(mktemp)
  sed 's#/var/www/html#/workspace#g' "$custom" > "$tmp"
  cd "$ROOT"
  exec bash "$tmp" "$@"
fi

RELAY=/workspace/.devcontainer/ddev-relay-client.sh
if [ -n "$cmd" ] && [ -f "$RELAY" ]; then
  exec bash "$RELAY" "$cmd" "$@"
fi

echo "ddev ${cmd:-}: not available inside the Claude sandbox." >&2
echo "Run it in a terminal on the Mac (outside the dev container)." >&2
exit 1
