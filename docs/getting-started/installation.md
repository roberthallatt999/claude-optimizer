# Installation

## Quick Install (Recommended)

One command to install:

```bash
git clone https://github.com/roberthallatt/claude-config.git ~/.ai-config && \
~/.ai-config/install.sh
```

Then reload your shell:

```bash
source ~/.zshrc  # or ~/.bashrc
```

Now use `ai-config` from anywhere:

```bash
ai-config --project=/path/to/project 
```

---

## What the Installer Does

1. **Detects your shell** (zsh, bash, fish)
2. **Makes scripts executable**
3. **Adds aliases** to your shell config:
   - `ai-config` → Main deployment command
   - `ai-config-docs` → Documentation server
4. **Installs global Claude config** (if present)
   - Includes stack metadata and global base guidance.
   - Project-specific library references are deployed during each `ai-config` run.

---

## Manual Installation

If you prefer to install manually or to a custom location:

### 1. Clone Repository

```bash
git clone https://github.com/roberthallatt/claude-config.git ~/path/to/ai-config
cd ~/path/to/ai-config
```

### 2. Make Scripts Executable

```bash
chmod +x setup-project.sh
chmod +x serve-docs.sh
```

### 3. Add Shell Aliases

Edit your shell configuration file:

| Shell | File |
|-------|------|
| Zsh (macOS default) | `~/.zshrc` |
| Bash | `~/.bashrc` or `~/.bash_profile` |
| Fish | `~/.config/fish/config.fish` |

**For Zsh/Bash:**

```bash
# AI Config
export AI_CONFIG_REPO="$HOME/path/to/ai-config"
alias ai-config="$AI_CONFIG_REPO/setup-project.sh"
alias ai-config-docs="$AI_CONFIG_REPO/serve-docs.sh"
```

**For Fish:**

```fish
# AI Config
set -gx AI_CONFIG_REPO "$HOME/path/to/ai-config"
alias ai-config "$AI_CONFIG_REPO/setup-project.sh"
alias ai-config-docs "$AI_CONFIG_REPO/serve-docs.sh"
```

### 4. Reload Shell

```bash
source ~/.zshrc  # or your shell's config file
```

---

## Verify Installation

```bash
ai-config --help
```

You should see the usage documentation.

---

## Updating

To update to the latest version:

```bash
cd ~/.ai-config  # or your install location
git pull
```

Your aliases will continue to work.

---

## Uninstalling

### 1. Remove Aliases

Edit your shell config file and remove the AI Config section:

```bash
# Remove these lines from ~/.zshrc or ~/.bashrc:
# AI Config
export AI_CONFIG_REPO="..."
alias ai-config="..."
alias ai-config-docs="..."
```

### 2. Remove Repository

```bash
rm -rf ~/.ai-config  # or your install location
```

### 3. Remove Global Config (Optional)

```bash
rm -rf ~/.claude/stacks
```

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Bash** | macOS, Linux, or WSL |
| **Git** | To clone the repository |
| **VSCode** | Optional, for IDE integration |
| **VSCode CLI** | Optional, for `--install-extensions` flag |

---

## Troubleshooting

### "command not found: ai-config"

Your shell config hasn't been reloaded:

```bash
source ~/.zshrc  # or ~/.bashrc
```

Or open a new terminal window.

### Aliases Not Working

Check if aliases were added:

```bash
grep "ai-config" ~/.zshrc
```

If not found, run the installer again or add manually.

### Permission Denied

Make scripts executable:

```bash
chmod +x ~/.ai-config/setup-project.sh
chmod +x ~/.ai-config/serve-docs.sh
```

---

## Next Steps

- **[Quick Start](quick-start.md)** - Configure your first project
- **[Configuration](configuration.md)** - What gets deployed
