# Other scripts

Every tool in this repository besides `ai-config` itself. Run them from the ai-config folder:

```bash
cd ~/.ai-config
```

## Everyday

| Command | What it does |
|---|---|
| `ai-config` | Set up, refresh, check or remove one project. See [All ai-config options](../guides/setup-script.md) |
| `ai-config-fleet --root=~/sites` | Check every project in a folder. Add `--refresh` to refresh them all, or `--list` to list them |
| `ai-config-docs` | Open these docs at `http://localhost:8000`. Add a port number to use another port, or `--no-open` to skip opening the browser |
| `./install.sh` | Set up ai-config on this computer. Safe to run again |
| `./update-superpowers.sh` | Download the latest workflow skills. Every setup does this unless you add `--skip-superpowers-update` |

## Safety

| Command | What it does |
|---|---|
| `scripts/install-global-guard.sh` | Turn the safety guard on for every Claude session on this computer. `--check` to check it, `--remove` to turn it off |
| `scripts/install-managed-settings.sh` | Build rules nobody can remove, and print the one `sudo` command to install them. `--check`, `--remove`, `--strict`. See [Sandboxes](../guides/sandbox.md#a-floor-for-the-whole-computer) |
| `scripts/scan-transcripts.sh` | Look for keys in Claude Code's saved conversations. Shows file names and counts, never values |

## Skills

| Command | What it does |
|---|---|
| `scripts/link-global-skills.sh` | Link the shared skills and your own into `~/.claude/skills/`. Every setup does this. `--dry-run` to preview |
| `scripts/vendor-skills.sh` | `--list`, `--fetch`, or `--bump <skill>` the outside skills pinned in `vendor/skills.conf` |
| `scripts/sync-noslop.sh` | Rebuild the `noslop` skill. `--update` fetches a newer original for review |
| `scripts/install-noslop-prune.sh` | Add a weekly job (Mondays, 9 a.m.) that deletes expired `noslop` pages |
| `~/.claude/skills/noslop/scripts/profile.sh` | Show which [profile](../guides/profiles.md) is active here |
| `~/.claude/skills/noslop/scripts/cloudflare.sh` | Publish, list, prune and delete password-protected `noslop` pages |

## CPS only

| Command | What it does |
|---|---|
| `scripts/cps-ship.sh` | Merge a finished branch into `staging` (where there is one) and `main`, and push. **Pushing those branches deploys the site.** Claude runs it only after your yes for that release. It refuses if there are uncommitted changes, unpushed commits, or unreleased work on `staging` |

## The dev container kit

`ai-config --devcontainer` runs this for you. You can also run it yourself, from the ai-config folder. Replace
`site` with the project's folder.

| Command | What it does |
|---|---|
| `python3 devcontainer-kit/ai-devcontainer.py --root ~/sites --list` | One line per project |
| `python3 devcontainer-kit/ai-devcontainer.py --project site` | Preview: `+` handled, `!` needs you. Writes nothing |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --out /tmp/preview` | Write the files to another folder to look at |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --write` | Write `.devcontainer/`. Add `--force` to replace an existing one |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --update` | Update files you haven't edited. Add `--yes` to accept new sites |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --json` | Facts about the project for a container review. Read-only |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --vscode-overrides` | What `.vscode/settings.json` overrides |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --profile cps` | Use another profile than the active one |
| `python3 devcontainer-kit/ai-devcontainer.py --project site --db-name admin_site` | Name the site's database when it can't be detected |

The scripts in `devcontainer-kit/files/` are copied into each `.devcontainer/` and run inside the container.

## Tests

| Command | What it does |
|---|---|
| `./run-tests.sh` | Run every test suite, several at once |
| `./run-tests.sh -j 1` | Run them one at a time |
| `./run-tests.sh fleet safety-guard` | Run only the suites you name |
| `./run-tests.sh --list` | List the suites |

See [Contributing](../development/contributing.md).
