# Claude Optimizer

Automated Claude Code configuration for modern web development stacks with VS Code integration.

## Project Overview

This repository provides automated Claude Code configuration deployment across **19 technology stacks** with:
- Automatic stack detection
- Memory bank for persistent context (or an OKF `.okf/` bundle with `--okf-memory`)
- A shared safety policy (deny/ask rules + a PreToolUse hook) merged into every project
- Stack-aware protected paths (`protected-paths.conf` → deny rules, hook patterns, `.claudeignore`)
- Content scanning: files are checked for credentials before Claude can read them
- Additive, non-destructive `--refresh` (edits are kept, backed up, and staged in `pending/`)
- Token optimization and sensitive file protection rules
- VSCode settings (formatters, Xdebug, tasks)
- 16 Superpowers workflow skills
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
| `nuxt` | Nuxt 3 | Vue 3, Pinia, server API routes |
| `remix` | Remix / React Router v7 | Loaders/actions, Zod validation |
| `sveltekit` | SvelteKit 2 | Svelte 5 Runes, load functions, form actions |
| `t3-stack` | Next.js + tRPC + Prisma | NextAuth, shadcn/ui, Zod (detected before generic `nextjs`) |

### Headless CMS Stacks

| Stack ID | Backend | Frontend |
|----------|---------|----------|
| `craftcms-nuxt` | Craft CMS (GraphQL) | Nuxt 3 (Vue SSR/SSG) |
| `craftcms-nextjs` | Craft CMS (GraphQL) | Next.js 14+ (React SSR/SSG) |
| `ee-nextjs` | EE Coilpack (Laravel REST API) | Next.js 14+ (React SSR/SSG) |
| `astro-strapi` | Strapi (REST/GraphQL) | Astro (Islands) |
| `astro-sanity` | Sanity.io (GROQ) | Astro (Islands) |
| `astro-tina` | Tina CMS (Git-based, MDX/Markdown) | Astro (Islands) |

## Key Files

### Scripts
- `setup-project.sh` - Main deployment script (aliased as `ai-config`)
- `serve-docs.sh` - Local documentation server (aliased as `ai-config-docs`)
- `ai-config-fleet.sh` - Run `--doctor` / `--refresh` across every project under a folder (aliased as `ai-config-fleet`)
- `run-tests.sh` - Run every `test-*.sh` suite (CI: `.github/workflows/tests.yml`)

### Template Structure
```
projects/
├── common/                    # Global/shared templates
│   ├── rules/                 # Shared memory, token, safety & design rules
│   ├── hooks/                 # safety-guard.sh (PreToolUse hook source)
│   ├── okf/                   # OKF bundle templates + template-map.sh (--okf-memory)
│   ├── orchestrator/          # --orchestrator templates (CLAUDE block + implementer agent)
│   ├── detect-frontend.sh     # Front-end stack detection (50+ frameworks/tools)
│   ├── security.settings.local.json   # Shared safety policy merged into every project
│   ├── protected-paths.conf   # Universal [deny]/[ignore] paths; each stack adds its own
│   ├── memory-protocol.md, safety-guardrails.md, response-style.md,
│   │   code-index.md, okf-memory-protocol.md   # Managed CLAUDE.md/AGENTS.md block sources
│   └── MEMORY.md.template     # Memory bank template
├── expressionengine/          # Full Claude config
├── coilpack/                  # Full Claude config
├── craftcms/                  # Full Claude config
├── wordpress-roots/           # Full Claude config
├── wordpress/                 # Full Claude config
├── nextjs/                    # Full Claude config
├── nuxt/, remix/, sveltekit/, t3-stack/   # Standalone JS framework stacks
├── docusaurus/                # Full Claude config
├── craftcms-nuxt/             # Headless Craft CMS + Nuxt
├── craftcms-nextjs/           # Headless Craft CMS + Next.js
├── ee-nextjs/                 # Headless EE Coilpack + Next.js
├── astro/                     # Astro standalone (Content Collections, MDX)
├── astro-strapi/              # Astro + Strapi
├── astro-sanity/              # Astro + Sanity Studio
├── astro-tina/                # Astro + Tina CMS (Git-based)
└── custom/                    # Discovery mode base

superpowers/
├── skills/                   # 16 workflow skills
│   ├── brainstorming/
│   ├── writing-plans/
│   ├── systematic-debugging/
│   ├── test-driven-development/
│   └── ...
├── commands/                 # Slash commands
└── hooks/                    # Session hooks

test-*.sh                     # 12 test suites, each independently runnable
run-tests.sh                  # Runs every test-*.sh suite, or a selected subset
ai-config-fleet.sh            # --doctor / --refresh / --list across many projects
.github/workflows/tests.yml   # CI: runs the suites on macOS + Ubuntu, plus shellcheck
```

## Memory System

Every deployment includes persistent memory:

| Component | Purpose |
|-----------|---------|
| `MEMORY.md` | Project memory bank (preserved on refresh) |
| Memory Protocol block | Managed `<!-- BEGIN/END MEMORY PROTOCOL -->` block in `CLAUDE.md`/`AGENTS.md` — read MEMORY.md before substantive work, log meaningful changes |
| `memory-management.md` | Memory update protocols (`.claude/rules/`) |
| `token-optimization.md` | Token efficiency rules |
| `sensitive-files.md` | Prevents reading credentials/secrets |
| `--okf-memory` | Records project memory as an OKF bundle in `.okf/` instead of `MEMORY.md` |

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
# --refresh auto-detects the stack from the deployed CLAUDE.md; additive (see Recent Changes)
ai-config --refresh --project=/path/to/project
```

### View Documentation
```bash
ai-config-docs  # Opens at http://localhost:8000
```

## Stack Templates

Each stack includes:

- `CLAUDE.md.template` - Main project context
- `settings.local.json` - Claude Code permissions and MCP config
- `protected-paths.conf` - Paths this stack blocks (`[deny]`) or keeps out of context (`[ignore]`)
- `rules/` - Stack-specific coding standards (every file deploys; `tailwind-css`, `alpinejs`, `bilingual-content` only when detected)
- `agents/` - Specialized agent personas (optional)
- `commands/` - Stack-specific slash commands (optional)
- `skills/` - Stack-specific skills (optional)
- `.vscode/` - VSCode settings and tasks

## Superpowers Skills

16 workflow skills deployed by default (see `docs/guides/superpowers.md` for the full list):

| Skill | Purpose |
|-------|---------|
| `brainstorming` | Idea generation |
| `writing-plans` | Implementation planning |
| `executing-plans` | Step-by-step execution |
| `systematic-debugging` | Root cause analysis |
| `test-driven-development` | TDD workflow |
| `using-git-worktrees` | Isolated workspace per feature |

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
- `docs/guides/` - Setup script, memory system, MCP integration, Superpowers, conditional deployment, updating projects
- `docs/reference/` - Stacks, file structure, commands
- `docs/development/` - Project status, contributing

## Recent Changes

- **Content scanning before read** — path rules only block what can be named, so
  `safety-guard.sh` now opens the file. `Read`/`Grep`, and Bash reading verbs (`cat`, `tail`,
  `grep`, `strings`, …), are checked for credential-shaped content before it reaches the
  transcript; a hit is a **deny** naming the pattern class and line numbers, never the value.
  This closes a hole where `cat storage/logs/laravel.log` was unprotected end to end: the
  shared policy's `Read(**/*.log)` rules bind the Read tool only, and `Bash(cat …)` is a
  different rule namespace. Logs are scanned rather than blanket-denied, so a clean log stays
  readable — a guard too annoying to live with gets switched off. The patterns now cover
  **database credentials** (connection URIs with an inline password, `DB_PASSWORD=`,
  `aws_secret_access_key=`, JWTs) alongside the vendor token shapes, and are shared with the
  write path; writes to `MEMORY.md`/`.okf/**` are denied rather than prompted, since those
  reload every session. Template files and documentation-shaped lines are forgiven by design.
  Fail-closed: a file too large to scan (`AI_CONFIG_SCAN_MAX_BYTES`, default 20 MB) is denied.
  Two-stage by necessity — one compiled `awk` alternation rejects most files and the precise
  regexes run only over candidate lines, because on BSD `awk`/`grep` (macOS, and the macOS CI
  runner) the one-stage forms cost 3.3s per read versus ~160ms on a 4 MB log. `okf-check.sh`
  shares the patterns. Tests: `test-secret-scanning.sh`.
- **Stack-aware protected paths** — `projects/common/protected-paths.conf` plus a
  `protected-paths.conf` in each of the 19 stacks, in two tiers. `[deny]` (secrets, credentials,
  `.git/`, database dumps) becomes a `Read()` rule in `settings.local.json` *and* a pattern in the
  generated `.claude/hooks/protected-paths.conf`, which `safety-guard.sh` now reads and enforces for
  file tools and Bash alike — closing real gaps in the shared list (`*.sqlite`/`*.db`/`*dump*.sql`,
  `.git/`, `credentials*`/`secrets*`). `[ignore]` (dependencies, build output, lockfiles, media) is
  written only to `.claudeignore`; denying `node_modules/` or `dist/` would break ordinary debugging.
  A stack may promote an `[ignore]` pattern to `[deny]` — the CMS stacks do this with `*.sql`, where a
  loose `.sql` file is a dump, while Prisma/Drizzle migrations on JS stacks stay readable.
  **`.claudeignore` is advisory:** Claude Code does not read it
  ([anthropics/claude-code#29455](https://github.com/anthropics/claude-code/issues/29455) is still
  open); it documents the project's boundaries and serves gitignore-syntax tools, and its header says
  so. `--no-claudeignore` skips the file and keeps the deny rules. Both generated files go through
  `install_file`, so edits are kept and staged; `--doctor` checks the conf is current and runs the
  hook against a test dump; `--uninstall` withdraws the rules using the conf the project was actually
  deployed with. Tests: `test-protected-paths.sh`.
- **Every stack rule now deploys** — the rule copy step only knew a fixed list of file names, so 12 shipped stack rules never reached a project (`sveltekit-patterns`, `nuxt-patterns`, `astro-patterns` ×2, `sanity-patterns`, `strapi-patterns`, `craft-graphql` ×2, `laravel-api`, `wordpress-coding-standards`, `wordpress-security`, custom's `coding-standards`). `stack_rule_sources()` now copies every file in a stack's `rules/` except the detection-gated `tailwind-css`/`alpinejs`/`bilingual-content`, plus the shared, now path-scoped `typescript-patterns.md` (when `tsconfig.json` exists), `design-system.md` and `api-design.md` (JS-framework stacks). `--refresh` adds rules older versions never deployed when they're missing and absent from the manifest; rules deleted on purpose stay deleted. Tests: `test-refresh-additive.sh`.
- **Project policy (`ai-config.conf`)** — a committed, project-root file that ai-config reads on
  every run, before it writes anything. It exists because every other thing ai-config produces
  (`.claude/`, `CLAUDE.md`, `MEMORY.md`, `.okf/`) is gitignored in most projects, so a fresh
  clone had no manifest and no stickiness markers and silently rebuilt the stock config —
  re-adding pruned library references, sending a relocated decision log back into `MEMORY.md` /
  `.okf/`, and dropping `--okf-memory` / `--orchestrator` / `--shared-policy`. `[options]`
  supplies the stack and those flags (an explicit CLI flag still wins); `[decisions] path`
  redirects architectural decisions to a tracked file and is re-rendered into the managed Memory
  Protocol block and the memory rules (including their `paths:` frontmatter) on every run, so it
  can't drift back; `[exclude]` lists shipped files removed on purpose or taken over, the one
  case where "missing" does not mean "add". `--save-policy` writes the file from a project's
  current state (union with what's already there, no timestamp churn); `--doctor` flags an
  uncommitted policy file and removals that aren't recorded yet. Malformed lines are reported,
  never fatal. Tests: `test-project-policy.sh`. Guide: `docs/guides/project-policy.md`.
- **Front-end stack detection** — `projects/common/detect-frontend.sh` replaces the Tailwind/Foundation/SCSS/Alpine-only checks with a 50+ entry catalog (CSS frameworks and tooling, UI kits, JS frameworks and libraries, build tools, TypeScript), read from every `package.json` (theme folders included), vendored asset names, CDN/`wp_enqueue` references, and `x-data`/`hx-*` markup, with versions and evidence. CMS core and third-party folders are skipped. Projects without a framework are reported as "custom JavaScript/CSS, no framework detected" with file counts; vanilla JS is no longer assumed whenever Tailwind/Foundation/Alpine are absent. Results go to the scan summary, a deterministic **Front-End Stack** managed block in `CLAUDE.md`/`AGENTS.md`, discovery mode, and new Bootstrap/Bulma/jQuery/Material UI/Foundation/vanilla-JS library references. Tests: `test-frontend-detection.sh`.
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

# Apply the stack's protected paths but skip the advisory .claudeignore
ai-config --project=. --no-claudeignore

# Remove ai-config from a project (unedited files only; everything backed up)
ai-config --uninstall --project=.

# Record this project's policy in a committed ai-config.conf (stack, flags, decisions
# path, files removed on purpose) so a fresh clone redeploys the tuned config
ai-config --save-policy --project=.

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
