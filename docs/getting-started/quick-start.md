# Quick Start

Configure Claude Code for your project in under a minute.

## 1. Install (One Time)

```bash
git clone https://github.com/roberthallatt/claude-optimizer.git ~/.ai-config && \
~/.ai-config/install.sh && \
source ~/.zshrc
```

## 2. Configure Your Project

```bash
ai-config --project=/path/to/your/project
```

That's it! The script auto-detects your framework and technologies.

---

## What Happens

When you run `ai-config --project=.`:

1. **Framework Detection** - Identifies ExpressionEngine, Craft CMS, WordPress, Next.js, etc.
2. **Technology Detection** - Finds Tailwind, Alpine.js, SCSS, bilingual content, etc.
3. **Claude Configuration** - Deploys optimized Claude Code config with rules, agents, skills
4. **Memory System** - Sets up persistent context (`MEMORY.md`)
5. **Permissions** - Deploys `settings.local.json` with stack-appropriate permissions
6. **VSCode Setup** - Configures syntax highlighting, debugging, tasks

---

## Common Commands

### Current Directory

```bash
cd /path/to/your/project
ai-config --project=.
```

### Preview First

```bash
ai-config --project=. --dry-run
```

### Update After Changes

```bash
ai-config --refresh --project=.
```

### Discovery Mode (Unknown Framework)

```bash
ai-config --project=. --discover
```

Then run `/project-discover` in Claude Code.

### Skip VSCode Settings

```bash
ai-config --project=. --skip-vscode
```

### Install VSCode Extensions

```bash
ai-config --project=. --install-extensions
```

---

## Deployed Files

| Component | Files |
|-----------|-------|
| Claude Code | `CLAUDE.md`, `MEMORY.md`, `.claude/` |
| Permissions | `.claude/settings.local.json` |
| VSCode | `.vscode/settings.json`, `launch.json`, `tasks.json` |

---

## Auto-Detected Frameworks

| Framework | Detection |
|-----------|-----------|
| ExpressionEngine | `system/ee/` directory |
| Craft CMS | `craft` executable |
| WordPress (Roots) | `web/app/themes/` |
| WordPress | `wp-config.php` |
| Next.js | `next.config.js` |
| Docusaurus | `docusaurus.config.js` |
| Coilpack | Laravel + EE structure |

---

## Auto-Detected Technologies

| Technology | Result |
|------------|--------|
| Tailwind CSS | Adds rules + VSCode Tailwind support |
| Alpine.js | Adds Alpine.js rules |
| Foundation | Adds Foundation patterns |
| SCSS/Sass | Adds SCSS best practices |
| Bilingual (EN/FR) | Adds bilingual content rules |
| DDEV | Extracts project config |

---

## Superpowers Skills

Workflow skills are deployed by default:

| Skill | Purpose |
|-------|---------|
| `memory-management` | Persistent context |
| `brainstorming` | Idea generation |
| `writing-plans` | Implementation planning |
| `executing-plans` | Step-by-step execution |
| `systematic-debugging` | Root cause analysis |
| `test-driven-development` | TDD workflow |

Disable with `--no-superpowers`.

---

## Next Steps

- **[Memory System](../guides/memory-system.md)** - Persistent context guide
- **[Setup Script](../guides/setup-script.md)** - All options
- **[Configuration](configuration.md)** - What gets deployed
