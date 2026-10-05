#!/usr/bin/env bash
# ee-migrate-install.sh <site-repo-path> — copy the cps_tools add-on and ee-migrate.sh runner
# templates into an EE site repo. The runner's CONFIG block (between the
# "# >>> site config" and "# <<< site config" markers) is preserved when the file exists.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="${EE_MIGRATE_TEMPLATES:-$SCRIPT_DIR/projects/expressionengine/templates}"
repo="${1:?usage: ee-migrate-install.sh <site-repo-path>}"
[[ -d "$repo/.git" ]] || { echo "not a git repo: $repo" >&2; exit 2; }

sub=""; [[ -d "$repo/ee/system/user" ]] && sub="ee/"
addons="$repo/${sub}system/user/addons"
[[ -d "$addons" ]] || { echo "no EE addons dir under $repo" >&2; exit 2; }

rm -rf "$addons/cps_tools"
cp -R "$TPL/cps_tools" "$addons/cps_tools"
rm -rf "$addons/cps_tools/tests"      # tests stay in claude-config-repo
[[ -d "$addons/cps_logs" ]] && rm -rf "$addons/cps_logs" && echo "removed superseded cps_logs/"

mkdir -p "$repo/.admin-scripts"
runner="$repo/.admin-scripts/ee-migrate.sh"
if [[ -f "$TPL/ee-migrate/ee-migrate.sh" ]]; then
  if [[ -f "$runner" ]]; then
    # Multi-line values break BSD awk -v, so carry the block through a temp file.
    cfg_file=$(mktemp)
    sed -n '/^# >>> site config/,/^# <<< site config/p' "$runner" > "$cfg_file"
    [[ -s "$cfg_file" ]] || { echo "existing runner has no site config block — not overwriting" >&2; rm -f "$cfg_file"; exit 2; }
    sed -e "/^# >>> site config/r $cfg_file" \
        -e '/^# >>> site config/,/^# <<< site config/d' \
        "$TPL/ee-migrate/ee-migrate.sh" > "$runner.new" && mv "$runner.new" "$runner"
    rm -f "$cfg_file"
  else
    cp "$TPL/ee-migrate/ee-migrate.sh" "$runner"
    echo "NEW runner: fill in the site config block in $runner"
  fi
  chmod +x "$runner"
  # DDEV-side eecli wrapper for Coilpack sites (LOCAL_EECLI="ddev exec .admin-scripts/eecli-local.sh").
  cp "$TPL/ee-migrate/eecli-local.sh" "$repo/.admin-scripts/eecli-local.sh"
  chmod +x "$repo/.admin-scripts/eecli-local.sh"
fi
grep -q '^\.admin-scripts/\.ee-migrate/' "$repo/.gitignore" 2>/dev/null \
  || printf '\n# ee-migrate rehearsal stamps (local only)\n.admin-scripts/.ee-migrate/\n' >> "$repo/.gitignore"
echo "installed cps_tools $(grep -o "'version' *=> *'[^']*'" "$addons/cps_tools/addon.setup.php" | grep -o "[0-9.]*") into ${repo##*/}"
