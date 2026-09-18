# Claude Optimizer

**One command gives Claude Code everything it needs to know about your project, plus guardrails so it can't do real damage.**

```bash
ai-config --project=/path/to/your/project
```

[![Production Ready](https://img.shields.io/badge/status-production%20ready-success)]()
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## What is this?

Claude Optimizer is a setup script for [Claude Code](https://claude.com/claude-code). Point it at a project and it
works out what the project is built with (WordPress, Craft CMS, ExpressionEngine, Next.js, Astro, SvelteKit, and more).
Then it writes a project-specific Claude configuration: context, coding rules, library references, workflow skills,
permissions, safety hooks, persistent memory and VS Code settings.

It's plain Bash. You don't need a service, an account or a runtime.

## Why use it?

If you code with an AI agent, you've probably seen these problems:

- **Every session starts cold.** You explain the stack, the conventions and last week's decisions again.
- **The agent writes generic code.** You get React habits in a Twig template, or Tailwind v3 syntax in a v4 project.
- **Setup is hand-copied and drifts.** Each repo ends up with a slightly different `CLAUDE.md` and settings file.
  None of them get updated.
- **The agent can do too much.** It can read your `.env`, run `git push` or touch production when you only wanted a refactor.
- **Tokens get wasted.** Big instruction files load on every turn whether they're relevant or not.

Claude Optimizer fixes each of these once, and you can reuse the fix on every project you have.

## Key features

- 🔍 **Auto-detection:** Recognizes 19 stacks and 50+ front-end technologies from `package.json`, vendored assets and
  template markup. It configures the project for what it finds, and reports honestly when it finds only custom JS/CSS.
- 🛡️ **Enforced safety, not just advice:** A `PreToolUse` hook and a deny/ask permission policy block reads of secrets
  and credentials. Every `git push`, deploy or destructive command needs your approval, including through MCP tools.
  `--doctor` runs a live test to confirm the hook works.
- 🧠 **Persistent project memory:** A managed `MEMORY.md` (or an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog)
  knowledge bundle) records decisions and changes, so the next session starts with that context.
- 📚 **Stack-aware knowledge:** Includes 29 library references (Tailwind, Alpine, React, Vue, Prisma, Zod, and others) plus
  rules for each stack. References load on demand, so they don't cost tokens every turn.
- ⚡ **Workflow skills:** Comes with a bundled fork of [Superpowers](https://github.com/obra/superpowers) for brainstorming,
  planning, TDD, systematic debugging, code review and parallel subagents.
- 🔄 **Safe updates:** `--refresh` never overwrites your edits. New versions are staged for review and every change
  is backed up. `--uninstall` removes everything cleanly.
- 🚢 **Fleet mode:** `ai-config-fleet --root=~/sites` health-checks or refreshes every project in a folder and prints one
  summary.
- 💸 **Cost controls:** Includes a concise response style, an effort-level setting and an optional Opus-orchestrator /
  Sonnet-implementer split (`--orchestrator`).
- 🧩 **Editor setup:** Configures VS Code formatters, Xdebug, DDEV tasks and extensions for each stack. It can also generate
  `AGENTS.md` for OpenAI Codex.

---

## Quick Install

```bash
# Clone and install (one command)
git clone https://github.com/roberthallatt999/claude-optimizer.git ~/.ai-config && \
~/.ai-config/install.sh
```

Now use `ai-config` from anywhere on your system.

<details>
<summary><strong>Manual Installation</strong></summary>

```bash
# Clone to your preferred location
git clone https://github.com/roberthallatt999/claude-optimizer.git ~/path/to/ai-config

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
| **Library References** | `.claude/libraries/` - Framework/CSS/JS reference docs |
| **Hooks** | `.claude/hooks/` - Safety guard (PreToolUse) and session hooks |
| **Permissions** | `.claude/settings.local.json` - Stack permissions + shared deny/ask safety policy |
| **Protected paths** | `.claude/hooks/protected-paths.conf` - Stack-aware blocked paths; `.claudeignore` (advisory) |
| **Update state** | `.claude/ai-config/` - Manifest, backups, staged updates, version stamp |

### Additional Features

- **Enforced safety guardrails** - No secret reads; approval for each push, deploy, or destructive action (Bash and MCP tools)
- **Stack-aware protected paths** - Secrets, credentials and database dumps blocked per stack; build noise kept out of context
- **Additive updates** - `--refresh` never overwrites your edits; every change is backed up
- **Token-lean defaults** - Concise response style, on-demand library references, path-scoped rules
- **Superpowers Skills** - Workflow automation (planning, debugging, TDD)
- **Optional code intelligence** - OKF knowledge bundle (`--okf-memory`), codegraph, php-lsp, template maps for EE/Craft/Sage
- **VSCode Settings** - Syntax highlighting, Xdebug, DDEV tasks
- **MCP Server Guide** - Manual setup for Supabase, GitHub, Cloudflare, Zapier, and more (`docs/guides/mcp-integration.md`); `codegraph` is auto-registered at local scope when it's installed and the project has an index

---

## Auto-Detection

### Frameworks

| Framework | Detection |
|-----------|-----------|
| ExpressionEngine 7.x | `system/ee/` directory |
| Craft CMS | `craft` executable |
| Craft CMS + Nuxt | Craft CMS + `frontend/nuxt.config.ts` |
| Craft CMS + Next.js | Craft CMS + `frontend/next.config.js` |
| EE Coilpack + Next.js | Coilpack + `frontend/next.config.js` |
| WordPress (Roots/Bedrock) | `web/app/themes/` structure |
| WordPress | `wp-config.php` |
| Next.js 14+ | `next.config.js` or `.mjs` |
| T3 Stack | `next.config.*` + `prisma/schema.prisma` + `@trpc/server` (checked before generic Next.js) |
| SvelteKit | `svelte.config.js`/`.ts` |
| Nuxt 3 | `nuxt.config.ts`/`.js` (no CMS backend) |
| Remix / React Router v7 | `remix.config.js`/`.ts`, or `app/root.tsx` + `@remix-run/react`/`react-router` |
| Docusaurus 3+ | `docusaurus.config.js` |
| Astro (standalone) | `astro.config.mjs`/`.ts` with no CMS integration detected |
| Astro + Sanity | `astro.config.mjs` + `sanity.config.ts` |
| Astro + Strapi | `astro.config.mjs` + Strapi in `backend/` |
| Astro + Tina | `astro.config.mjs` + `tina/config.ts` or `tinacms` in `package.json` |
| Coilpack (Laravel + EE) | Laravel + ExpressionEngine structure |

### Technologies

| Technology | Detection | Result |
|------------|-----------|--------|
| Front-end stack (50+ CSS/JS frameworks, UI kits, libraries, build tools) | Every `package.json` (incl. theme folders), vendored asset files, CDN/enqueue references, `x-data` / `hx-*` markup | Scan summary + Front-End Stack block in `CLAUDE.md`; reports "custom JS/CSS, no framework" when none is found |
| Tailwind CSS / Alpine.js | As above | Adds Tailwind / Alpine rules + library references |
| Bootstrap, Foundation, Bulma, jQuery, Material UI, SCSS | As above | Adds library references |
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
| `--superpowers-all` | Deploy all skills (default when enabled) |
| `--superpowers-core` | Deploy core skills only |
| `--superpowers-minimal` | Deploy minimal bootstrap skill |
| `--superpowers-skill=X` | Deploy specific skills (comma-separated) |
| `--skip-superpowers-update` | Don't pull the latest superpowers subtree before deploying |

### Stack Options

| Option | Description |
|--------|-------------|
| `--stack=<name>` | Manually specify stack (auto-detected if omitted) |
| `--discover` | Discovery mode for unknown frameworks |

### Update Options

| Option | Description |
|--------|-------------|
| `--refresh` | Update existing configuration — additive: your edits are kept, new versions staged in `.claude/ai-config/pending/` |
| `--apply-pending` | Adopt staged new versions (backs up your copy first) |
| `--force` | Skip prompts (updates stay additive) |
| `--clean` | Move existing config to a backup, then deploy fresh |
| `--uninstall` | Remove ai-config: unedited files, managed blocks, policy rules, hook registrations (all backed up) |
| `--doctor` | Read-only health check, including a live safety-hook test |

### Safety, Memory & Cost Options

| Option | Description |
|--------|-------------|
| `--shared-policy` | Also put the safety policy in committed `.claude/settings.json` for teammates |
| `--no-claudeignore` | Skip the advisory `.claudeignore` (the stack's deny rules still apply) |
| `--okf-memory` | Project memory as an OKF knowledge bundle in `.okf/` instead of `MEMORY.md` |
| `--no-response-style` | Skip the concise Response Style block |
| `--eager-libraries` | Keep `@imports` of library references (loaded every session) |
| `--effort=<level>` | Set `effortLevel` (`low`, `medium`, `high`, `xhigh`, `max`) |
| `--orchestrator` | Opus orchestrator + Sonnet implementer |
| `--with-openai` | Also deploy `AGENTS.md` |

### Other Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview without making changes |
| `--install-deps` | Install missing tools first (jq, git; Intelephense for PHP stacks) |
| `--skip-vscode` | Skip VSCode settings deployment |
| `--install-extensions` | Auto-install VSCode extensions |
| `--name=<name>` | Set project name (auto-detected from directory) |
| `--slug=<slug>` | Set project slug used in templates (derived from name if omitted) |
| `--analyze` | Generate an analysis prompt for Claude |

### Many Projects

```bash
ai-config-fleet --root=~/sites            # --doctor every ai-config project, one summary
ai-config-fleet --root=~/sites --refresh  # refresh them all
```

### Available Stacks

`expressionengine`, `coilpack`, `craftcms`, `craftcms-nuxt`, `craftcms-nextjs`, `ee-nextjs`, `wordpress-roots`, `wordpress`, `nextjs`, `nuxt`, `remix`, `sveltekit`, `t3-stack`, `docusaurus`, `astro`, `astro-strapi`, `astro-sanity`, `astro-tina`, `custom`

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

`--install-extensions` installs Prettier and EditorConfig everywhere, then adds:

| Stack(s) | Extra Extensions |
|----------|-------------------|
| `expressionengine`, `coilpack`, `craftcms`, `wordpress`, `wordpress-roots` | Intelephense, Xdebug |
| `nextjs`, `docusaurus` | ESLint |
| Any stack, when Tailwind CSS is detected | Tailwind CSS IntelliSense |

Headless and other JS stacks (`craftcms-nuxt`, `craftcms-nextjs`, `ee-nextjs`, `nuxt`, `remix`, `sveltekit`, `t3-stack`, `astro`, `astro-strapi`, `astro-sanity`, `astro-tina`) currently get only the common extensions above (plus Tailwind when detected).

---

## Context7 Integration

For up-to-date library documentation (Tailwind, Alpine.js, React, Vue, 100+ more), install the Context7 plugin once: `/plugin install context7@claude-plugins-official`. Stack templates no longer enable a `context7` project MCP server, since no `.mcp.json` ever defined one.

---

## File Structure

After running `ai-config --project=.`:

```
your-project/
├── CLAUDE.md                     # Claude Code context
├── MEMORY.md                     # Persistent memory bank
├── .claude/
│   ├── libraries/                # Project-local framework/library references
│   ├── rules/                    # Coding standards
│   ├── agents/                   # AI personas
│   ├── commands/                 # Slash commands
│   ├── skills/                   # Stack + Superpowers skills (one folder per skill)
│   ├── hooks/                    # safety-guard.sh (PreToolUse) + session-start
│   ├── settings.local.json       # Permissions, safety policy, hook registrations
│   └── ai-config/                # Manifest, backups/, pending/, version (gitignored)
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

## Testing

```bash
./run-tests.sh                        # every test-*.sh suite (10 suites)
./run-tests.sh lifecycle safety-guard  # selected suites ("test-" and ".sh" optional)
./run-tests.sh --list
```

CI (`.github/workflows/tests.yml`) runs the same suites on macOS and Ubuntu, plus `shellcheck -S warning`. See [Contributing Guide](docs/development/contributing.md) for details.

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

To update Superpowers to the latest upstream version, run `./update-superpowers.sh`.

## License

MIT License. See the [LICENSE](LICENSE) file.

The bundled Superpowers skills in `superpowers/` are separately MIT-licensed by Jesse Vincent; see
[superpowers/LICENSE](superpowers/LICENSE).

---

## Support

- **Documentation:** Run `ai-config-docs` or browse [docs/](docs/)
- **Issues:** [GitHub Issues](https://github.com/roberthallatt999/claude-optimizer/issues)
- **Status:** [Project Status](docs/development/project-status.md)
