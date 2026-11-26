# Environment variables

You don't need any of these for everyday use. They change where things are kept, turn off a step, or point a
test at a throwaway folder.

To set one for a single command, put it in front:

```bash
AI_CONFIG_PROFILE=personal ai-config --doctor --project=.
```

To set one for good, add an `export` line to `~/.zshrc`:

```bash
export AI_CONFIG_PROFILE=personal
```

## Everyday

| Variable | What it does |
|---|---|
| `AI_CONFIG_PROFILE` | Use this [profile](../guides/profiles.md), whatever `ai-config.conf`, the folders file or the computer's default say |
| `AI_CONFIG_REPO` | Where ai-config is. The installer sets it; update it if you move the folder |
| `AI_CONFIG_HOME` | Where your private profiles are. Default: `~/.config/ai-config` |
| `AI_CONFIG_PKG_MANAGER` | Which package manager `--install-deps` uses (`brew`, `apt-get`, `dnf` and so on). `none` installs nothing |

## Turning steps off

| Variable | What it does |
|---|---|
| `AI_CONFIG_SKIP_SUPERPOWERS_UPDATE=1` | Don't download the latest workflow skills first. Same as `--skip-superpowers-update` |
| `AI_CONFIG_SKIP_GLOBAL_SKILLS=1` | Don't link the shared skills into `~/.claude/skills/` this time |

## Where things are kept

| Variable | Default | What it points at |
|---|---|---|
| `AI_CONFIG_CLAUDE_DIR` | `~/.claude` | Claude's own folder, where skills are linked |
| `AI_CONFIG_USER_SETTINGS` | `~/.claude/settings.json` | Your Claude settings, which `--doctor` reads |
| `AI_CONFIG_VSCODE_USER_SETTINGS` | Mac: `~/Library/Application Support/Code/User/settings.json` | Your VS Code settings, which `--doctor` compares against |
| `AI_CONFIG_TEST_TIMES` | `~/.cache/ai-config/test-times.tsv` | How long each test suite took last time |
| `AI_CONFIG_MANAGED_DIR` | Mac: `/Library/Application Support/ClaudeCode/managed-settings.d` | Where the managed settings go |
| `AI_CONFIG_MANAGED_GUARD_DIR` | `…/ClaudeCode/ai-config` | The root-owned copy of the safety guard |
| `AI_CONFIG_MANAGED_STAGE` | `~/.cache/ai-config/managed` | Where those files wait before you install them |

On Linux, VS Code settings are in `~/.config/Code/User/settings.json`, and managed settings go in
`/etc/claude-code/managed-settings.d`.

## Safety guard

| Variable | What it does |
|---|---|
| `AI_CONFIG_SCAN_MAX_BYTES` | The largest file the content check reads. Default: 20 MB. Bigger files are blocked, not read unchecked |
| `AI_CONFIG_GUARD_SCOPE=global` | Set by the computer-wide guard and the commit check. You don't set it yourself |
| `AI_CONFIG_GH_LIGHT_WRITES=allow` | Let pull request and issue comments and edits go ahead without asking. Merges and releases still ask. Only the dev container's locked settings use it, so nothing inside can turn it on |

## Tests only

| Variable | What it does |
|---|---|
| `AI_CONFIG_MANAGED_SUDO=` (empty) | Install managed settings without `sudo` |
