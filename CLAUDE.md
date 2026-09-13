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
- `ai-config-fleet.sh` - Run `--doctor` / `--refresh` across every project under a folder (aliased as `ai-config-fleet`)
- `run-tests.sh` - Run every `test-*.sh` suite (CI: `.github/workflows/tests.yml`)

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

Disable with `--no-superpowers`. Skipped automatically when the superpowers plugin is already enabled globally (avoids loading it twice).

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

Placeholders are rendered in `CLAUDE.md` / `AGENTS.md` templates and in copied stack agents, rules,
commands, and skills. Unset or unsupported values (brand colors, `{{PROJECT_DOMAIN}}`, …) become
readable text such as `(brand green: not set)` rather than a fake value.

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

- **Gap fixes: superpowers, MCP guard, placeholders, lifecycle** — Superpowers skills deploy to `.claude/skills/<skill>/` (the nested `.claude/skills/superpowers/` layout was never discovered, and the session-start hook injected a read error instead of the skill); refresh moves nested copies up and re-registers the hook with `CLAUDE_PLUGIN_ROOT`. `safety-guard.sh` covers MCP tools (push/merge/deploy/send/buy/delete/write, SQL writes) and credential-shaped content in Write/Edit; the managed hook matcher is updated on refresh. Copied stack files render `{{VARIABLES}}` (unset ones become readable text; brand colors are no longer faked as `#000000`). New `--shared-policy`, `--uninstall`, `.claude/ai-config/version` stamps, `ai-config-fleet.sh`, `run-tests.sh` + CI workflow; `--doctor` flags missing/stale `@~/.claude/stacks` imports and undefined `enabledMcpjsonServers`; the dead `context7` entry was dropped from stack templates. Tests: `test-lifecycle.sh`, `test-fleet.sh`.
- **`--install-deps`** — installs missing required tools (`jq`, `perl`, `shasum`, …) and `git` through the system package manager (Homebrew; `apt-get` with update-and-retry, `dnf`, `yum`, `pacman`, `zypper`, `apk`; `sudo` only for system managers when not root), and for PHP stacks Intelephense via `npm install -g` (Node.js/npm from the package manager first if needed). Shows the commands, asks on a terminal unless `--force`, and `--dry-run` only prints the plan. Never installs a package manager, never pipes remote install scripts (codegraph and Claude Code stay manual and are named), never runs npm with `sudo`. `AI_CONFIG_PKG_MANAGER` overrides detection. Tests: `test-install-deps.sh`.
- **CMS code intelligence + health checks** — PHP stacks enable the official `php-lsp` plugin (`claude plugin install … --scope local`) when Intelephense is on PATH, respecting explicit settings. `--okf-memory` projects on EE/Coilpack/Craft/Sage get `.okf/architecture/templates.md` from `projects/common/okf/template-map.sh` (embeds, layouts, includes, partials, components, channels/sections/add-ons, reverse index, Craft section routes; deterministic, rewritten only on real changes, additive). Every run preflights required tools (`jq`, `perl`, `shasum`, …) and stops before writing if one is missing, then runs `verify_deployment` (live safety-hook test, policy rules, managed blocks, OKF conformance, codegraph/php-lsp consistency, gitignore) and exits 1 on a critical failure; `--doctor` runs the same checks read-only. `claude` CLI calls read `</dev/null` so a prompt can't hang the script. Tests: `test-cms-intelligence.sh`.
- **OKF memory + code index (opt-in)** — `--okf-memory` records project memory as a Google Open Knowledge Format v0.2 bundle in `.okf/` (read `index.md` first, open only needed concepts; `generated`/`verified`/`stale_after` trust fields), with a managed OKF Memory Protocol block, a `.okf/**`-scoped rule, and `okf-check.sh` conformance/hygiene checks. Seed files are create-only, the mode is sticky, and `MEMORY.md` is never migrated. For JS-framework stacks, an installed codegraph with an existing `.codegraph/` index is registered at local MCP scope (never installed) and a Code Index block is added. A per-commit LLM wiki pipeline was evaluated and rejected (token cost, code egress, trust drift). Tests: `test-okf-memory.sh`.
- **Refresh and redeploy are additive** — every shipped file goes through `install_file` / `install_rendered`: missing → added; unedited (hash in `.claude/ai-config/manifest.tsv`, or for legacy projects any committed version in this repo's git history) → updated with a backup; edited → kept, new version staged in `.claude/ai-config/pending/` (`--apply-pending` adopts, with backup). In-place changes — order-preserving `settings.local.json` unions that never remove entries, append-only `.gitignore`, managed CLAUDE.md blocks refreshed between their markers — are backed up per run to `.claude/ai-config/backups/<run>/` and written only on a real change. `--clean` moves config into a backup instead of `rm -rf`; a sticky orchestrator no longer resets a changed `model`. Tests: `test-refresh-additive.sh`.
- **Enforced safety policy for every stack** — `apply_security_policy()` merges `projects/common/security.settings.local.json` into each project on deploy and `--refresh`: secret-file `deny` rules, `ask` rules (push, PRs, publishing, prod deploys, `rm`, destructive git), `ask` rules that override the `git push`/`rm` auto-allows every stack used to ship, `enableAllProjectMcpServers: false` when unset, and registration of the `.claude/hooks/safety-guard.sh` PreToolUse hook (catches `bash -c`, `source .env`, remote copies, cloud CLIs, destructive SQL/git, harness self-edits). Stack templates no longer carry deny lists or hooks. Tests: `test-safety-guard.sh`, `test-security-policy.sh`.
- **Token-cost defaults** — new managed **Response Style** block (concise output; `--no-response-style` opts out); library `@imports` rewritten to on-demand references (`--eager-libraries` keeps them); stack rules path-scoped with `paths:` frontmatter; common rules and managed blocks compressed and scoped; superpowers project copy skipped when the plugin is enabled globally; optional `--effort=<level>`.
- **Harness fixes** — 97 of 108 subagent files had no `name`/`description` frontmatter and were silently ignored by Claude Code (fixed, `model: sonnet`); hook registration merges instead of overwriting `.hooks`; `merge_settings_json` unions `ask` rules and no longer aborts `--refresh` under `set -e`; common safety rules deploy to stacks without a `rules/` dir; removed a hardcoded client name from the EE/Coilpack templates.
- **`--refresh` now respects library curation** — `.claude/libraries/` is no longer blindly re-copied. A library that's already present is updated; a deleted one is re-added only when this refresh newly *detects* its technology (`tailwind.md`/`alpinejs.md`/`foundation.md`/`scss.md` via `library_is_detected()`). Framework libraries are stack-implied and stay removed once curated away. Rules/agents/skills were already not re-copied on refresh (refresh exits before those blocks).
- **Added always-on memory protocol block** — `append_memory_policy()` appends a managed `<!-- BEGIN/END MEMORY PROTOCOL -->` block to every `CLAUDE.md` (and `AGENTS.md` with `--with-openai`), so the read-MEMORY.md-at-start / log-every-change behavior is actually in always-loaded context (the `.claude/rules/memory-management.md` rule was deployed but never `@import`ed). Source: `projects/common/memory-protocol.md`. Idempotent across refresh.
- **Added always-on safety guardrails** — every deploy/refresh appends a managed **Operational Safety Guardrails** block to each project's `CLAUDE.md` (and `AGENTS.md` with `--with-openai`): never read secrets/`.env`/credentials, never push to GitHub without explicit per-action approval, never change production without explicit permission. Source: `projects/common/safety-guardrails.md`; reference rule: `projects/common/rules/deployment-safety.md` (deployed to `.claude/rules/`). Idempotent across refresh via `<!-- BEGIN/END SAFETY GUARDRAILS -->` markers.
- **Superpowers auto-updates on deploy/refresh** — `deploy_superpowers()` now runs `update-superpowers.sh` (best-effort) first, pulling the latest squashed subtree from the fork. Skips cleanly when the optimizer repo is dirty/offline. Opt out with `--skip-superpowers-update`.
- **Documented `--with-openai`** — the AGENTS.md flag for OpenAI Codex / API tools is now covered in `docs/guides/setup-script.md`.
- **Added `--orchestrator` flag** — opt-in Opus orchestrator + Sonnet implementer pattern. Pins the main session to Opus (`model: "opus"`), forces all subagents to Sonnet (`CLAUDE_CODE_SUBAGENT_MODEL=sonnet`), deploys an `implementer` subagent, and appends a Model & Delegation Policy block to `CLAUDE.md`. Sticky across `--refresh`. Templates live in `projects/common/orchestrator/`. Requires `jq`.
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

# Refresh (additive: keeps your edits, backs up changes, never touches MEMORY.md)
ai-config --refresh --project=.

# Project memory as an OKF bundle (.okf/) instead of MEMORY.md
ai-config --project=. --okf-memory

# Read-only health check: prerequisites, live safety-hook test, config consistency
ai-config --doctor --project=.

# Install missing tools first (jq, git; Intelephense for PHP stacks) — asks unless --force
ai-config --project=. --install-deps

# Share the safety policy with teammates (committed .claude/settings.json)
ai-config --project=. --shared-policy

# Remove ai-config from a project (unedited files only; everything backed up)
ai-config --uninstall --project=.

# Health check (or --refresh) every ai-config project under a folder
ai-config-fleet --root=~/sites

# Adopt staged new versions of files you edited (backs up first)
ai-config --refresh --apply-pending --project=.

# Preview without changes
ai-config --dry-run --project=.

# Skip VSCode settings
ai-config --project=. --skip-vscode

# Install VSCode extensions
ai-config --project=. --install-extensions

# Force clean reinstall
ai-config --clean --force --project=.

# Deploy AGENTS.md for OpenAI Codex / API tools (opt-in)
ai-config --project=. --with-openai

# Opus orchestrator + Sonnet implementer pattern (opt-in)
ai-config --project=. --orchestrator
```
