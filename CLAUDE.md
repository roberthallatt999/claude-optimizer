# Claude Optimizer

Automated Claude Code configuration for modern web development stacks with VS Code integration.

## Project Overview

This repository provides automated Claude Code configuration deployment across **14 technology stacks** with:
- Automatic stack detection
- Memory bank for persistent context
- Token optimization and sensitive file protection rules
- VSCode settings (formatters, Xdebug, tasks)
- 15 Superpowers workflow skills
- `settings.local.json` with stack-appropriate permissions

**Repository Path:** `/Users/robert/data/business/_tools/claude-optimizer`

## Supported Stacks

### Monolithic Stacks

| Stack ID | Framework | Template Engine |
|----------|-----------|-----------------|
| `expressionengine` | ExpressionEngine 7.x | EE Templates |
| `coilpack` | Laravel + EE | Blade/Twig/EE |
| `craftcms` | Craft CMS | Twig |
| `wordpress-roots` | WordPress/Bedrock | Blade (Sage) |
| `wordpress` | WordPress | PHP |
| `nextjs` | Next.js 14+ | React/TSX |
| `docusaurus` | Docusaurus 3+ | MDX |
| `custom` | Discovery mode | Any |

### JS / Static Stacks

| Stack ID | Framework | Notes |
|----------|-----------|-------|
| `astro` | Astro 4.x | Standalone Astro (Content Collections, MDX) |

### Headless CMS Stacks

| Stack ID | Backend | Frontend |
|----------|---------|----------|
| `craftcms-nuxt` | Craft CMS (GraphQL) | Nuxt 3 (Vue SSR/SSG) |
| `craftcms-nextjs` | Craft CMS (GraphQL) | Next.js 14+ (React SSR/SSG) |
| `ee-nextjs` | EE Coilpack (Laravel REST API) | Next.js 14+ (React SSR/SSG) |
| `astro-strapi` | Strapi (REST/GraphQL) | Astro (Islands) |
| `astro-sanity` | Sanity.io (GROQ) | Astro (Islands) |

## Key Files

### Scripts
- `setup-project.sh` - Main deployment script (aliased as `ai-config`)
- `serve-docs.sh` - Local documentation server (aliased as `ai-config-docs`)

### Template Structure
```
projects/
├── common/                    # Global templates
│   ├── rules/                # Memory, token & sensitive file rules
│   └── MEMORY.md.template    # Memory bank template
├── expressionengine/         # Full Claude config
├── coilpack/                 # Full Claude config
├── craftcms/                 # Full Claude config
├── wordpress-roots/          # Full Claude config
├── wordpress/                # Full Claude config
├── nextjs/                   # Full Claude config
├── docusaurus/               # Full Claude config
├── craftcms-nuxt/            # Headless Craft CMS + Nuxt
├── craftcms-nextjs/          # Headless Craft CMS + Next.js
├── ee-nextjs/                # Headless EE Coilpack + Next.js
├── astro/                    # Astro standalone (Content Collections, MDX)
├── astro-strapi/             # Astro + Strapi
├── astro-sanity/             # Astro + Sanity Studio
└── custom/                   # Discovery mode base

superpowers/
├── skills/                   # 15 workflow skills
│   ├── memory-management/
│   ├── brainstorming/
│   ├── writing-plans/
│   ├── systematic-debugging/
│   └── ...
├── commands/                 # Slash commands
└── hooks/                    # Session hooks
```

## Memory System

Every deployment includes persistent memory:

| Component | Purpose |
|-----------|---------|
| `MEMORY.md` | Project memory bank (preserved on refresh) |
| `memory-management.md` | Memory update protocols |
| `token-optimization.md` | Token efficiency rules |
| `sensitive-files.md` | Prevents reading credentials/secrets |
| `memory-management/` | Memory skill in Superpowers |

See `docs/guides/memory-system.md` for full documentation.

## Usage

### Deploy to a Project
```bash
# Auto-detect stack and deploy
ai-config --project=/path/to/project

# Specify stack manually
ai-config --stack=expressionengine --project=/path/to/project

# Discovery mode for unknown stacks
ai-config --discover --project=/path/to/project
```

### Update Existing Project
```bash
ai-config --refresh --stack=custom --project=/path/to/project
```

### View Documentation
```bash
ai-config-docs  # Opens at http://localhost:8000
```

## Stack Templates

Each stack includes:

- `CLAUDE.md.template` - Main project context
- `settings.local.json` - Claude Code permissions and MCP config
- `rules/` - Stack-specific coding standards
- `agents/` - Specialized agent personas (optional)
- `commands/` - Stack-specific slash commands (optional)
- `skills/` - Stack-specific skills (optional)
- `.vscode/` - VSCode settings and tasks

## Superpowers Skills

15 workflow skills deployed by default:

| Skill | Purpose |
|-------|---------|
| `memory-management` | Persistent context |
| `brainstorming` | Idea generation |
| `writing-plans` | Implementation planning |
| `executing-plans` | Step-by-step execution |
| `systematic-debugging` | Root cause analysis |
| `test-driven-development` | TDD workflow |

Disable with `--no-superpowers`.

## Template Variables

Templates use `{{VARIABLE}}` syntax, replaced during deployment:

| Variable | Source |
|----------|--------|
| `{{PROJECT_NAME}}` | Directory name or `--name` flag |
| `{{PROJECT_SLUG}}` | Derived from name |
| `{{PROJECT_PATH}}` | Absolute path |
| `{{DDEV_NAME}}` | `.ddev/config.yaml` |
| `{{DDEV_PRIMARY_URL}}` | `.ddev/config.yaml` |
| `{{DDEV_PHP}}` | `.ddev/config.yaml` |
| `{{DDEV_DB_TYPE}}` | `.ddev/config.yaml` |
| `{{DDEV_DB_VERSION}}` | `.ddev/config.yaml` |
| `{{DDEV_DOCROOT}}` | `.ddev/config.yaml` |
| `{{TEMPLATE_GROUP}}` | EE template directory |
| `{{GIT_MAIN_BRANCH}}` | Git default branch |
| `{{GIT_INTEGRATION_BRANCH}}` | Git integration branch |
| `{{BRAND_GREEN}}` | Project brand color (discovered from Tailwind config) |
| `{{BRAND_BLUE}}` | Project brand color |
| `{{BRAND_ORANGE}}` | Project brand color |
| `{{BRAND_LIGHT_GREEN}}` | Project brand color |

## Development Guidelines

### Adding Stack-Specific Templates

1. Create template in `projects/{stack}/`
2. Stack-specific automatically takes priority over common
3. No script changes needed

### Code Style (This Repository)

- Bash scripts: Use `set -e`, quote variables, meaningful names
- Markdown: ATX headings, fenced code blocks, reference links
- Templates: `{{UPPERCASE}}` for variables, no hardcoded project-specific values

## Documentation

- `docs/getting-started/` - Installation, quick start, configuration
- `docs/guides/` - Setup script, memory system
- `docs/reference/` - Stacks, file structure, commands
- `docs/development/` - Project status, contributing

## Recent Changes

- **Fixed SessionStart hook deployment** — hooks now injected into `settings.local.json` (where Claude Code actually reads them) instead of a standalone `hooks.json` that was never loaded
- **Fixed `@import` paths** in `nextjs`, `craftcms`, `wordpress-roots`, and `docusaurus` templates — broken `../shared/knowledge/` paths replaced with correct `.claude/libraries/` paths
- **Added `astro` standalone stack** — handles plain Astro projects (Content Collections, MDX, islands) that previously fell through to `custom`
- **Added `bun` and `pnpm`** to allowed commands in all stack `settings.local.json` templates
- **Removed dead `detect_stack()` function** — stack detection code was duplicated; consolidated into the single inline detection block
- **Fixed standalone Astro detection** — plain Astro projects (no Sanity/Strapi) now correctly detected instead of falling through undetected
- **Fixed `frontend/astro.config.*` detection** — subdirectory-layout Astro projects without Strapi now correctly fall back to `astro` stack instead of being undetected
- **Added package.json Strapi fallback** — `astro-strapi` detection now works via `package.json` when no `astro.config.*` config file is present
- **Updated `token-optimization.md`** — removed outdated token budget table; replaced with current strategy guidance
- **Cleaned up repo `settings.local.json`** — removed accumulated junk command approvals
- Genericized all templates (replaced hardcoded project references with `{{PLACEHOLDER}}` variables)
- Added `sensitive-files.md` rule to prevent reading credentials, secrets, and API keys
- Added 5 headless CMS stacks: `craftcms-nuxt`, `craftcms-nextjs`, `ee-nextjs`, `astro-strapi`, `astro-sanity`
- Added `settings.local.json` with stack-appropriate permissions to all stacks
- Added `{{BRAND_*}}` color placeholders for project brand colors
- Fixed cross-platform `sed -i` compatibility (macOS/Linux)
- Implemented `--skip-vscode` and `--install-extensions` CLI flags
- Added memory bank system (`MEMORY.md`, memory rules, memory skill)
- Added token optimization rules
- Added 15 Superpowers workflow skills

## Quick Reference

```bash
# Auto-detect and deploy
ai-config --project=.

# Discovery mode for unknown stacks
ai-config --discover --project=.

# Refresh (preserves MEMORY.md)
ai-config --refresh --project=.

# Preview without changes
ai-config --dry-run --project=.

# Skip VSCode settings
ai-config --project=. --skip-vscode

# Install VSCode extensions
ai-config --project=. --install-extensions

# Force clean reinstall
ai-config --clean --force --project=.
```
