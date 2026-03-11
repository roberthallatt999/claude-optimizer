# AI Config

**One command to configure Claude Code for any project.**

```bash
ai-config --project=/path/to/your/project
```

Auto-detects your framework, deploys optimized Claude Code configuration, and sets up VSCode.

[![Production Ready](https://img.shields.io/badge/status-production%20ready-success)]()
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)]()

---

## Quick Install

```bash
# Clone and install (one command)
git clone https://github.com/roberthallatt/claude-config.git ~/.ai-config && \
~/.ai-config/install.sh
```

Now use `ai-config` from anywhere on your system.

<details>
<summary><strong>Manual Installation</strong></summary>

```bash
# Clone to your preferred location
git clone https://github.com/roberthallatt/claude-config.git ~/path/to/ai-config

# Make scripts executable
chmod +x ~/path/to/ai-config/setup-project.sh
chmod +x ~/path/to/ai-config/serve-docs.sh

# Add to ~/.zshrc or ~/.bashrc
export AI_CONFIG_REPO="$HOME/path/to/ai-config"
alias ai-config="$AI_CONFIG_REPO/setup-project.sh"
alias ai-config-docs="$AI_CONFIG_REPO/serve-docs.sh"

# Reload shell
source ~/.zshrc
```

</details>

---

## Usage

### Configure Any Project

```bash
ai-config --project=/path/to/project
```

The script automatically:
- **Detects your framework** (WordPress, Next.js, Craft CMS, ExpressionEngine, etc.)
- **Detects technologies** (Tailwind, Alpine.js, SCSS, bilingual content, etc.)
- **Deploys optimized Claude Code configuration**
- **Sets up VSCode** with syntax highlighting, debugging, and tasks

### Current Directory Shortcut

```bash
cd /path/to/project
ai-config --project=.
```

### Update Existing Project

```bash
ai-config --refresh --project=/path/to/project
```

Re-scans for new technologies and updates all configurations.

### Discovery Mode (Unknown Stacks)

For projects that don't match a known framework:

```bash
ai-config --project=/path/to/project --discover
```

This detects 50+ technologies (React, Vue, Laravel, Django, etc.), deploys base configuration, and generates a discovery prompt. Then run `/project-discover` in Claude Code to generate custom rules.

---

## What Gets Deployed

### Claude Code Configuration

| Component | Files |
|-----------|-------|
| **Main Config** | `CLAUDE.md` - Project context and commands |
| **Memory Bank** | `MEMORY.md` - Persistent context across sessions |
| **Rules** | `.claude/rules/` - Coding standards and constraints |
| **Agents** | `.claude/agents/` - Custom agent personas |
| **Commands** | `.claude/commands/` - Slash commands |
| **Skills** | `.claude/skills/` - Workflow automation |
| **Hooks** | `.claude/hooks/` - Session hooks |

### Additional Features

- **Superpowers Skills** - Workflow automation (planning, debugging, TDD)
- **VSCode Settings** - Syntax highlighting, Xdebug, DDEV tasks
- **Context7 Integration** - Up-to-date library documentation
- **MCP Server Support** - Supabase, Playwright, and more

---

## Auto-Detection

### Frameworks

| Framework | Detection |
|-----------|-----------|
| ExpressionEngine 7.x | `system/ee/` directory |
| Craft CMS | `craft` executable |
| WordPress (Roots/Bedrock) | `web/app/themes/` structure |
| WordPress | `wp-config.php` |
| Next.js 14+ | `next.config.js` or `.mjs` |
| Docusaurus 3+ | `docusaurus.config.js` |
| Coilpack (Laravel + EE) | Laravel + ExpressionEngine structure |

### Technologies

| Technology | Detection | Result |
|------------|-----------|--------|
| Tailwind CSS | `tailwind.config.*` or package.json | Adds Tailwind rules + VSCode support |
| Alpine.js | `x-data` attributes or package.json | Adds Alpine.js rules |
| Foundation | `foundation-sites` in package.json | Adds Foundation patterns |
| SCSS/Sass | `.scss` files or package.json | Adds SCSS best practices |
| Bilingual (EN/FR) | Language patterns in templates | Adds bilingual content rules |
| Stash (EE) | `exp:stash` tags | Adds Stash optimization tools |

---

## Command Reference

```bash
ai-config --project=<path> [options]
```

### Required

| Option | Description |
|--------|-------------|
| `--project=<path>` | Target directory (use `.` for current) |

### Superpowers Options

| Option | Description |
|--------|-------------|
| `--no-superpowers` | Disable Superpowers skills |
| `--superpowers-core` | Deploy core skills only |
| `--superpowers-minimal` | Deploy minimal bootstrap skill |

### Stack Options

| Option | Description |
|--------|-------------|
| `--stack=<name>` | Manually specify stack (auto-detected if omitted) |
| `--discover` | Discovery mode for unknown frameworks |

### Update Options

| Option | Description |
|--------|-------------|
| `--refresh` | Update existing configuration |
| `--force` | Overwrite without prompts |
| `--clean` | Remove existing config before deploying |

### Other Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview without making changes |
| `--skip-vscode` | Skip VSCode settings deployment |
| `--install-extensions` | Auto-install VSCode extensions |
| `--no-superpowers` | Disable Superpowers workflow skills |
| `--name=<name>` | Set project name (auto-detected from directory) |

### Available Stacks

`expressionengine`, `coilpack`, `craftcms`, `wordpress-roots`, `wordpress`, `nextjs`, `docusaurus`, `custom`

---

## Examples

```bash
# Auto-detect and configure
ai-config --project=.

# Preview what would be deployed
ai-config --project=. --dry-run

# Update after adding Tailwind
ai-config --refresh --project=.

# Discovery mode for a Vue/Nuxt project
ai-config --project=~/my-vue-app --discover

# Minimal skills only
ai-config --project=. --superpowers-minimal

# Force clean reinstall
ai-config --project=. --clean --force

# Manually specify stack
ai-config --stack=craftcms --project=.
```

---

## VSCode Integration

### Automatic Extension Installation

```bash
ai-config --project=. --install-extensions
```

### Extensions by Stack

| Stack | Extensions |
|-------|------------|
| ExpressionEngine | EE syntax, Tailwind, Intelephense, Xdebug |
| Craft CMS | Twig, Tailwind, Intelephense |
| WordPress | Blade, Tailwind, WordPress Toolbox |
| Next.js | Tailwind, ESLint, Prettier |

---

## Context7 Integration

All stacks include Context7 for up-to-date library documentation (Tailwind, Alpine.js, React, Vue, 100+ more).

---

## File Structure

After running `ai-config --project=.`:

```
your-project/
├── CLAUDE.md                     # Claude Code context
├── MEMORY.md                     # Persistent memory bank
├── .claude/
│   ├── rules/                    # Coding standards
│   ├── agents/                   # AI personas
│   ├── commands/                 # Slash commands
│   ├── skills/superpowers/       # Workflow skills
│   └── hooks/                    # Session hooks
└── .vscode/
    ├── settings.json
    ├── launch.json
    └── tasks.json
```

---

## Add to .gitignore

These files are per-developer and shouldn't be committed:

```gitignore
# Claude Code Configuration
CLAUDE.md
MEMORY.md
MEMORY-ARCHIVE.md
.claude/
```

---

## Documentation

| Guide | Description |
|-------|-------------|
| [Installation](docs/getting-started/installation.md) | Manual setup options |
| [Quick Start](docs/getting-started/quick-start.md) | First-run guide |
| [Memory System](docs/guides/memory-system.md) | Persistent context |
| [Setup Script](docs/guides/setup-script.md) | Complete reference |
| [Conditional Deployment](docs/guides/conditional-deployment.md) | Detection logic |
| [Updating Projects](docs/guides/updating-projects.md) | Refresh workflows |
| [Stacks Reference](docs/reference/stacks.md) | Stack-specific details |

**Start docs server locally:**
```bash
ai-config-docs  # Opens http://localhost:8000
```

---

## Requirements

- **Bash** - macOS, Linux, or WSL on Windows
- **Git** - To clone the repository
- **VSCode** (optional) - For IDE integration
- **VSCode CLI** (optional) - For automatic extension installation (`code` command)

---

## Contributing

Contributions welcome! See [Contributing Guide](docs/development/contributing.md).

- Report bugs or suggest features
- Improve documentation
- Add new stack support
- Enhance detection logic

---

## Credits

The [Superpowers](https://github.com/obra/superpowers) workflow skills framework by Jesse Vincent is included via a [forked copy](https://github.com/roberthallatt999/superpowers). Superpowers provides structured Claude Code skills for planning, debugging, code review, TDD, and more.

## License

MIT License - See [LICENSE](LICENSE) file.

---

## Support

- **Documentation:** Run `ai-config-docs` or browse [docs/](docs/)
- **Issues:** [GitHub Issues](https://github.com/roberthallatt/claude-config/issues)
- **Status:** [Project Status](docs/development/project-status.md)
