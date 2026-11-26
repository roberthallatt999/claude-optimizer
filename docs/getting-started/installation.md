# Install

You do this once per computer. It takes about a minute.

## What you need

- A Mac, Linux, or Windows with WSL.
- `git`.
- A few standard tools: `jq`, `perl`, `awk`, `sed`, `find`, `cmp`, `mktemp` and `shasum` (or `sha256sum`). Most
  computers already have them except `jq`. If one is missing, ai-config stops before changing anything and tells
  you which. To install them for you, see [Missing tools](#missing-tools) below.

## Install it

Run these one at a time in Terminal.

**1. Download it:**

```bash
git clone https://github.com/roberthallatt999/claude-optimizer.git ~/.ai-config
```

**2. Run the installer:**

```bash
~/.ai-config/install.sh
```

The installer:

- adds three commands to your shell: `ai-config`, `ai-config-docs` and `ai-config-fleet`
- turns on the safety guard for every Claude Code session on this computer, not only in ai-config projects
- links the shared skills (`noslop`, `humanizer`) into `~/.claude/skills/`

**3. Load the new commands** (zsh, the Mac default):

```bash
source ~/.zshrc
```

If you use bash, run this instead:

```bash
source ~/.bashrc
```

Opening a new Terminal window works too.

## Check it worked

```bash
ai-config --help
```

You should see a list of options. If you see `command not found`, open a new Terminal window and try again.

## Missing tools

ai-config can install what's missing. It uses Homebrew on a Mac, or your Linux package manager. It shows you
the commands first and asks before running them. Run it from inside a project folder:

```bash
ai-config --project=. --install-deps
```

To see what it would install without installing anything:

```bash
ai-config --project=. --install-deps --dry-run
```

## Update ai-config

Get the latest version:

```bash
git -C ~/.ai-config pull
```

Then re-run the installer. It picks up any new commands and asks before replacing old ones:

```bash
~/.ai-config/install.sh
```

Updating ai-config doesn't change your projects. To update them too, see
[Keep projects up to date](../guides/updating-projects.md).

## Installed somewhere else?

The commands on these pages assume ai-config lives in `~/.ai-config`. If you cloned it somewhere else, use that
folder instead. If you move it later, re-run its `install.sh` from the new place. That also re-links the safety
guard and the skills.

## Remove it

**From one project.** This keeps every file you edited, keeps `MEMORY.md`, and backs up everything it removes.
Run it from inside the project folder:

```bash
ai-config --uninstall --project=.
```

**From your computer.** First turn off the computer-wide safety guard:

```bash
~/.ai-config/scripts/install-global-guard.sh --remove
```

Then delete the downloaded folder:

```bash
rm -rf ~/.ai-config
```

Last, open `~/.zshrc` (or `~/.bashrc`) and delete the lines under `# AI Config`. Projects you already set up keep
their files. Run `--uninstall` in each one first if you want them cleaned up too.

## Problems

| What you see | What to do |
|---|---|
| `command not found: ai-config` | Open a new Terminal window, or run `source ~/.zshrc` |
| `Permission denied` | Run `chmod +x ~/.ai-config/*.sh`, then try again |
| `Missing required tools: jq` (or another tool) | Run `ai-config --project=. --install-deps` |

Next: [Set up a project](quick-start.md).
