# Environment Variables

Settings ai-config reads from the environment. None is needed for everyday use: they change where
things live, switch off a step, or point a test at a throwaway folder.

## Everyday

| Variable | Read by | Effect |
|---|---|---|
| `AI_CONFIG_PROFILE` | `profile.sh`, setup, the dev container kit | Use this profile, ahead of `ai-config.conf`, the folder map and the machine default. [Profiles](../guides/profiles.md) |
| `AI_CONFIG_REPO` | Skills and runbooks | Where this repository is checked out. Set in your shell config; update it after moving the repo |
| `AI_CONFIG_HOME` | Setup, the kit, `link-global-skills.sh` | The private profiles repository (default `~/.config/ai-config`) |
| `AI_CONFIG_PKG_MANAGER` | `--install-deps` | Package manager to use instead of the detected one (`brew`, `apt-get`, `dnf`, …); `none` installs nothing |

## Switching steps off

| Variable | Effect |
|---|---|
| `AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1` | Don't pull the Superpowers subtree before deploying (same as `--skip-superpowers-update`). `run-tests.sh` sets it |
| `AI_CONFIG_SKIP_GLOBAL_SKILLS=1` | Don't link the global skills into `~/.claude/skills/` on this run |

## Locations

| Variable | Default | What it points at |
|---|---|---|
| `AI_CONFIG_CLAUDE_DIR` | `~/.claude` | Where global skills are linked and `--doctor` looks for them; also used by `install-global-guard.sh`, `install-managed-settings.sh` and `scan-transcripts.sh`. `run-tests.sh` sets a folder per run |
| `AI_CONFIG_USER_SETTINGS` | `~/.claude/settings.json` | The user-level Claude settings `--doctor` reads (global guard, plugins) |
| `AI_CONFIG_VSCODE_USER_SETTINGS` | macOS: `~/Library/Application Support/Code/User/settings.json`; Linux: `~/.config/Code/User/settings.json` | The VS Code user settings `--vscode-overrides` and `--doctor` compare a project's `.vscode/settings.json` with |
| `AI_CONFIG_TEST_TIMES` | `~/.cache/ai-config/test-times.tsv` | Where `run-tests.sh` keeps suite timings |
| `AI_CONFIG_MANAGED_DIR` | macOS: `/Library/Application Support/ClaudeCode/managed-settings.d`; Linux: `/etc/claude-code/managed-settings.d` | Where `install-managed-settings.sh` installs the managed-settings floor |
| `AI_CONFIG_MANAGED_GUARD_DIR` | `…/ClaudeCode/ai-config` next to it | The root-owned copy of the safety guard the floor runs |
| `AI_CONFIG_MANAGED_STAGE` | `~/.cache/ai-config/managed` | Where the files are staged before the printed `sudo` command moves them |

## Safety guard

| Variable | Effect |
|---|---|
| `AI_CONFIG_SCAN_MAX_BYTES` | Largest file the content scan reads (default 20 MB); a larger file is denied, not read unscanned |
| `AI_CONFIG_GUARD_SCOPE=global` | Set by the global hook registration (`install-global-guard.sh`) and the git pre-commit hook. A project's own copy of the guard stands aside when an identical global copy is registered |
| `AI_CONFIG_GH_LIGHT_WRITES=allow` | Let pull request and issue writes (create, comment, edit, review, close) run without asking. Writes aimed at another repository still ask; merges, releases and workflow runs always ask. Only the dev containers' root-owned managed settings set it, so nothing inside can turn it on for itself |

## Tests only

| Variable | Effect |
|---|---|
| `AI_CONFIG_MANAGED_SUDO=` (empty) | `install-managed-settings.sh` runs its install command without `sudo` |
