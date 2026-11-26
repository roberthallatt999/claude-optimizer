# Scripts Reference

Every command-line tool in this repository besides `setup-project.sh` itself (see the
[Setup Script guide](../guides/setup-script.md) for that). Run them from the repository root, or
through the aliases `install.sh` sets up.

## Everyday tools

| Script | What it does |
|---|---|
| `setup-project.sh` (alias `ai-config`) | Deploy, refresh, check or remove the Claude config for one project. [Guide](../guides/setup-script.md) |
| `ai-config-fleet.sh` (alias `ai-config-fleet`) | `--doctor`, `--refresh` or `--list` across every project under a folder (`--root=~/sites`, default depth 5) |
| `serve-docs.sh` (alias `ai-config-docs`) | Serve these docs at `http://localhost:8000` (`./serve-docs.sh [port] [--no-open]`) |
| `install.sh` | One-time setup on a Mac: aliases, the global safety guard, global skill links |
| `update-superpowers.sh` | Pull the vendored Superpowers subtree from its fork. Every deploy runs it unless `--skip-superpowers-update` |

## Safety and maintenance

| Script | What it does |
|---|---|
| `scripts/install-global-guard.sh` | Register the safety guard for every Claude session on this computer, and remove broad allow rules from user settings. `--check`, `--remove` |
| `scripts/install-managed-settings.sh` | Build the machine-wide managed-settings floor and print the one `sudo` line to install it. `--strict`, `--check`, `--remove`. [Safety checkup](../runbooks/safety-checkup.md) |
| `scripts/scan-transcripts.sh` | Check `~/.claude/projects/*.jsonl` for credential shapes; lists files and counts, never values |
| `scripts/link-global-skills.sh` | Link `global-skills/*` and the private `~/.config/ai-config/skills/*` into `~/.claude/skills/`. Every deploy runs it for missing links; `install.sh` also repoints links to this checkout. `--dry-run` |
| `scripts/vendor-skills.sh` | `--list`, `--fetch` or `--bump <skill>` the third-party skills pinned in `vendor/skills.conf` (patches in `vendor/patches/`) |
| `scripts/sync-noslop.sh` | Build the global `noslop` skill from its overlay and pinned upstream; `--update` pulls a newer upstream for review |
| `scripts/install-noslop-prune.sh` | Install the weekly LaunchAgent that deletes expired noslop share pages (`cloudflare.sh prune --delete`) |
| `global-skills/noslop/scripts/profile.sh` | Print the active profile (env, nearest `ai-config.conf`, folder map, machine default). [Profiles](../guides/profiles.md) |
| `global-skills/noslop/scripts/cloudflare.sh` | Publish, list, prune and delete passcode-gated share pages on the profile's share domain |
| `scripts/cps-ship.sh` | CPS sites only: merge a finished branch into `staging` (when the repo has one) and `main`, and push. **Pushing those branches deploys**: Claude runs it only after an explicit yes for that ship. Refuses a repo with a dirty tree, unpushed commits, or unreleased work on `staging` |

## Dev container kit (`devcontainer-kit/`)

`ai-config --devcontainer` drives these; you can also run them yourself.

### ai-devcontainer.py

```bash
K=devcontainer-kit/ai-devcontainer.py
python3 $K --root ~/sites --list               # one line per project
python3 $K --project site                       # dry run: + handled, ! follow-ups
python3 $K --project site --out /tmp/preview    # write previews instead
python3 $K --project site --write [--force]     # write .devcontainer/
python3 $K --project site --update [--yes]      # regenerate unedited files; --yes accepts new hosts
python3 $K --project site --json                # review fact sheet (read-only)
python3 $K --root ~/sites --only a,b --json     # several, as a list
python3 $K --project site --vscode-overrides    # what .vscode/settings.json overrides
python3 $K --project site --profile cps         # another profile than the active one
python3 $K --project site --db-name admin_site  # the site's database, when detection can't tell
```

| Module | Role |
|---|---|
| `sandbox_policy.py` | What a sandbox may reach: profile `devcontainer_*` keys, `[sandbox]`, integrations |
| `vscode_policy.py` | `[vscode]` extensions and settings, locked isolation keys, `.vscode/settings.json` comparison |
| `review.py` | Facts for a container review: config files in use, template file counts, dependency names |
| `claude-sandbox-policy.py` | `--sandbox=claude`: Claude Code's own sandbox block in `.claude/settings.local.json` |
| `enclave-policy.py` | `--sandbox=enclave`: Eclipse Enclave's project config |

The scripts in `devcontainer-kit/files/` are copied into each `.devcontainer/` and run there or by
VS Code (firewall, egress proxy, DDEV relay and shim, `sandbox-domains`). See the
[Sandbox guide](../guides/sandbox.md) and the [dev container runbook](../runbooks/devcontainer.md).

## Tests

```bash
./run-tests.sh                        # every suite, in parallel (one per CPU, at most 8)
./run-tests.sh -j 1                   # one at a time
./run-tests.sh fleet safety-guard     # selected suites ("test-" and ".sh" optional)
./run-tests.sh --list
```

Suites start slowest first, from timings saved in `~/.cache/ai-config/test-times.tsv`. Each suite
gets `AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1` and a run-scoped `AI_CONFIG_CLAUDE_DIR`, so parallel
suites never write to the same place or to `~/.claude`. A failing suite prints its last 30 log
lines and the log folder is kept. CI (`.github/workflows/tests.yml`) runs the same on macOS and
Ubuntu, plus `shellcheck -S warning`. More in [Contributing](../development/contributing.md#test-changes).
