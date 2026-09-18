# Claude Optimizer - Status Report

## Executive Summary

**Status: PRODUCTION READY**

19 technology stacks have complete Claude Code configurations:
- Full template systems with generic `{{PLACEHOLDER}}` variables
- Stack-appropriate `settings.local.json` for all stacks, plus a shared safety policy (deny/ask rules + PreToolUse hook) merged into every project
- Memory bank system for persistent context with Design System, Integrations, and API inventory sections (or an OKF `.okf/` bundle via `--okf-memory`)
- Token optimization and sensitive file protection rules
- 16 Superpowers workflow skills (including design-system-builder and component-scaffolder)
- 29 library references covering modern web tooling (auto-injected on detection)
- Technology-specific coding rules, layered on shared common rules deployed to every stack
- Additive `--refresh`, health checks (`--doctor`), dependency installation (`--install-deps`), and a fleet runner (`ai-config-fleet.sh`) for many projects
- 590 automated tests across 10 suites, run in CI on macOS and Ubuntu (`run-tests.sh`, `.github/workflows/tests.yml`)

---

## Stack Coverage

"Rules" is the guaranteed count (every deploy gets these); "+N gated" rules also deploy, but only
once their technology is detected (Tailwind, Alpine.js, bilingual content). See
[Stacks Reference → Deployed to Every Stack](../reference/stacks.md#deployed-to-every-stack) for
exactly which rule that is per stack.

| Stack | Claude | Rules | Skills | Memory | Permissions | Status |
|-------|--------|-------|--------|--------|-------------|--------|
| **sveltekit** | Yes | 7 rules | 16 | Yes | Yes | Complete |
| **remix** | Yes | 6 rules | 16 | Yes | Yes | Complete |
| **t3-stack** | Yes | 6 rules | 16 | Yes | Yes | Complete |
| **nuxt** | Yes | 6 rules | 16 | Yes | Yes | Complete |
| **coilpack** | Yes | 7 rules +3 gated | 16 | Yes | Yes | Complete |
| **craftcms** | Yes | 7 rules +3 gated | 16 | Yes | Yes | Complete |
| **docusaurus** | Yes | 9 rules +1 gated | 16 | Yes | Yes | Complete |
| **expressionengine** | Yes | 7 rules +3 gated | 20 | Yes | Yes | Complete |
| **nextjs** | Yes | 9 rules +1 gated | 16 | Yes | Yes | Complete |
| **wordpress-roots** | Yes | 7 rules +3 gated | 16 | Yes | Yes | Complete |
| **wordpress** | Yes | 8 rules | 16 | Yes | Yes | Complete |
| **craftcms-nuxt** | Yes | 10 rules +1 gated | 16 | Yes | Yes | Complete |
| **craftcms-nextjs** | Yes | 10 rules +1 gated | 16 | Yes | Yes | Complete |
| **ee-nextjs** | Yes | 10 rules +1 gated | 16 | Yes | Yes | Complete |
| **astro-tina** | Yes | 6 rules | 16 | Yes | Yes | Complete |
| **astro** | Yes | 6 rules | 16 | Yes | Yes | Complete |
| **astro-strapi** | Yes | 10 rules +1 gated | 16 | Yes | Yes | Complete |
| **astro-sanity** | Yes | 10 rules +1 gated | 16 | Yes | Yes | Complete |
| **custom** | Yes | 6 rules | 16 | Yes | Yes | Complete |

Every stack's guaranteed count also grows by one when `tsconfig.json` exists
(`typescript-patterns.md`); the JS-framework stacks' counts above already include
`design-system.md` and `api-design.md`.

---

## Memory & Token System

Every deployment includes:

| Component | File | Purpose |
|-----------|------|---------|
| Memory Bank | `MEMORY.md` | Persistent project context |
| Memory Rules | `.claude/rules/memory-management.md` | Update protocols |
| Token Rules | `.claude/rules/token-optimization.md` | Efficiency guidelines |
| Sensitive Files | `.claude/rules/sensitive-files.md` | Prevents reading credentials |
| Permissions | `.claude/settings.local.json` | Stack-appropriate CLI permissions |
| Memory Protocol | `CLAUDE.md` managed block | Always-on read/update instructions |

### Memory Bank Sections

- **Project Identity** — Name, type, tech stack
- **Architecture** — Patterns, directory map, decisions
- **Decision Log** — Architectural decisions with rationale
- **Active Context** — Current work, blockers, recent changes
- **Session Handoff** — Next steps for incomplete work
- **Knowledge Base** — Environment setup, common issues
- **Design System** — Token categories, CSS variables, Tailwind keys, component registry
- **Third-Party Integrations** — Service, purpose, SDK, config location, status
- **Environment Variables** — Variable, purpose, required/optional, where set
- **MCP Servers** — Configured MCP integrations
- **API / Route Inventory** — Method, path, auth, handler, status

---

## Superpowers Skills

16 workflow skills deployed with every stack:

| Skill | Purpose |
|-------|---------|
| `brainstorming` | Structured idea generation |
| `writing-plans` | Implementation planning |
| `executing-plans` | Step-by-step execution |
| `systematic-debugging` | Root cause analysis |
| `test-driven-development` | TDD workflow |
| `dispatching-parallel-agents` | Multi-agent coordination |
| `using-git-worktrees` | Git worktree workflows |
| `finishing-a-development-branch` | Branch completion |
| `receiving-code-review` | Review handling |
| `requesting-code-review` | Review requests |
| `subagent-driven-development` | Agent orchestration |
| `using-superpowers` | Skill system guide |
| `verification-before-completion` | Quality checks |
| `writing-skills` | Custom skill creation |
| `design-system-builder` | Token audit, component inventory, shadcn/ui + cva scaffold |
| `component-scaffolder` | Typed React/Vue/Svelte component + test generation |

---

## Detailed Rules Breakdown

**All Stacks Include (common rules, from `projects/common/rules/`):**
- `memory-management.md` - Memory protocols
- `token-optimization.md` - Token efficiency
- `sensitive-files.md` - Credential and secret protection
- `deployment-safety.md` - No unauthorized pushes or production changes

`accessibility.md` and `performance.md` are copied only when the stack ships its own copy — there
is no common fallback for those two names. Every other `.md` file in a stack's own `rules/`
directory deploys too (not a fixed filename allowlist), plus `typescript-patterns.md` on any
stack when `tsconfig.json` exists, and `design-system.md` / `api-design.md` on the JS-framework
stacks. See [Stacks Reference](../reference/stacks.md#deployed-to-every-stack) for the mechanism
and [Conditional Deployment](../guides/conditional-deployment.md#rule-categories) for the
category breakdown.

**Coilpack (Laravel + EE) - 7 rules, +3 gated:**
- accessibility, laravel-patterns, performance, memory-management, token-optimization,
  sensitive-files, deployment-safety
- Gated: alpinejs, bilingual-content, tailwind-css

**Craft CMS - 7 rules, +3 gated:**
- accessibility, craft-templates, performance, memory-management, token-optimization,
  sensitive-files, deployment-safety
- Gated: alpinejs, bilingual-content, tailwind-css

**Docusaurus - 9 rules, +1 gated:**
- accessibility, markdown-content, performance, design-system, api-design, memory-management,
  token-optimization, sensitive-files, deployment-safety
- Gated: tailwind-css

**ExpressionEngine - 7 rules, +3 gated, + 4 stack skills:**
- accessibility, expressionengine-templates, performance, memory-management, token-optimization,
  sensitive-files, deployment-safety
- Gated: alpinejs, bilingual-content, tailwind-css
- Skills: alpine-component-builder, ee-stash-optimizer, ee-template-assistant, tailwind-utility-finder

**Next.js - 9 rules, +1 gated:**
- accessibility, nextjs-patterns, performance, design-system, api-design, memory-management,
  token-optimization, sensitive-files, deployment-safety
- Gated: tailwind-css

**WordPress/Roots - 7 rules, +3 gated:**
- accessibility, blade-templates, performance, memory-management, token-optimization,
  sensitive-files, deployment-safety
- Gated: alpinejs, bilingual-content, tailwind-css

**WordPress (Standard) - 8 rules:**
- accessibility, performance, wordpress-coding-standards, wordpress-security,
  memory-management, token-optimization, sensitive-files, deployment-safety

**Custom (Discovery Mode) - 6 rules:**
- accessibility, coding-standards, memory-management, token-optimization, sensitive-files,
  deployment-safety

Every count above grows by one more when `tsconfig.json` exists (`typescript-patterns.md`).

---

## Configuration Structure Per Stack

Each stack in `projects/` contains:

```
projects/{stack}/
├── CLAUDE.md.template          # Main AI context (templated with project vars)
├── settings.local.json         # Claude Code permissions
├── agents/                     # Specialized AI agents
├── commands/                   # Claude slash commands
├── rules/                      # Always-on coding constraints
├── skills/                     # Stack-specific knowledge modules
└── .vscode/                    # VSCode settings
```

### Common Templates
```
projects/common/
├── rules/                      # Common rules
│   ├── memory-management.md
│   ├── token-optimization.md
│   └── sensitive-files.md
└── MEMORY.md.template          # Memory bank template
```

---

## Template Variable Substitution

Templates support these auto-detected variables:

| Variable | Example | Detection Source |
|----------|---------|------------------|
| `{{PROJECT_NAME}}` | `myproject` | Directory name or `--name` |
| `{{PROJECT_SLUG}}` | `myproject` | Derived from name |
| `{{DDEV_NAME}}` | `myproject` | `.ddev/config.yaml` |
| `{{DDEV_DOCROOT}}` | `public` | `.ddev/config.yaml` |
| `{{DDEV_PHP}}` | `8.2` | `.ddev/config.yaml` |
| `{{DDEV_DB_TYPE}}` | `MariaDB` | `.ddev/config.yaml` |
| `{{DDEV_DB_VERSION}}` | `10.11` | `.ddev/config.yaml` |
| `{{DDEV_PRIMARY_URL}}` | `https://myproject.ddev.site` | `.ddev/config.yaml` |
| `{{TEMPLATE_GROUP}}` | `myproject` | `system/user/templates/` (EE) |
| `{{GIT_MAIN_BRANCH}}` | `main` | Git repository |
| `{{GIT_INTEGRATION_BRANCH}}` | `main` | Git repository |
| `{{BRAND_GREEN}}` | `#238937` | Tailwind config or manual |
| `{{BRAND_BLUE}}` | `#00639A` | Tailwind config or manual |
| `{{BRAND_ORANGE}}` | `#F15922` | Tailwind config or manual |
| `{{BRAND_LIGHT_GREEN}}` | `#D7DF21` | Tailwind config or manual |

---

## Current Capabilities & Test Coverage

Capabilities added since the stack/skill counts above were first written (see `docs/guides/setup-script.md` for full detail on each):

| Area | What it does |
|------|--------------|
| **Safety policy + hook** | `projects/common/security.settings.local.json` merges deny/ask rules into every project's `.claude/settings.local.json` on deploy and `--refresh`. A PreToolUse hook, `.claude/hooks/safety-guard.sh`, denies secret reads and catastrophic deletes, and asks before pushes, PRs, publishing, deploys, destructive git/SQL, edits to `.claude/settings*.json`/hooks, and outward-acting MCP tools. |
| **Additive updates** | `.claude/ai-config/` tracks a manifest, per-run backups, and `pending/` staged versions. `--refresh` never overwrites edited files — it backs up and stages the new version; `--apply-pending` adopts it. Settings merges only add entries; `.gitignore` is append-only; `MEMORY.md` is never modified. |
| **Managed CLAUDE.md/AGENTS.md blocks** | SAFETY GUARDRAILS, MEMORY PROTOCOL (or OKF MEMORY PROTOCOL), RESPONSE STYLE, FRONTEND STACK, CODE INDEX, and ORCHESTRATOR POLICY (`--orchestrator`) are inserted between `<!-- BEGIN/END -->` markers and refreshed in place. |
| **OKF memory & code intelligence** | `--okf-memory` records project memory as an Open Knowledge Format bundle in `.okf/` (`index.md`, `log.md`, `handoff.md`) with `okf-check.sh` conformance checks, instead of `MEMORY.md`. For JS-framework stacks, an installed `codegraph` with an existing `.codegraph/` index is registered as a local-scope MCP server; PHP stacks enable the `php-lsp` plugin when Intelephense is on PATH. |
| **Front-end detection** | `projects/common/detect-frontend.sh` scans every `package.json` (including theme folders), vendored assets, CDN/enqueue references, and `x-data`/`hx-*` markup against a 50+ entry catalog of CSS/JS frameworks, UI kits, and build tools, reporting "custom JavaScript/CSS, no framework detected" when nothing matches. |
| **Health checks & `--install-deps`** | Every run preflights required tools (`jq`, `perl`, `shasum`, …) and stops before writing if one is missing; a post-run check (including a live safety-hook test) exits 1 on a critical failure. `--doctor` runs the same checks read-only; `--install-deps` installs missing tools via the system package manager. |
| **Fleet management** | `ai-config-fleet.sh` (aliased `ai-config-fleet`) runs `--doctor` (default), `--refresh`, or `--list` across every ai-config project under a `--root` folder. |
| **Tests & CI** | 590 tests across 10 `test-*.sh` suites (all 10 passing on macOS after the rule-copy fix; `test-refresh-additive.sh` grew from 41 to 54 tests to cover it), run via `run-tests.sh`. `.github/workflows/tests.yml` runs the same suites on macOS and Ubuntu, plus `shellcheck -S warning`. |

---

## Recent Changes

*(History below — stack, skill, and library counts in these entries reflect the state at the time they were written, not the current totals in the Executive Summary above.)*

### Rule Copy Fix (Sep 2026)

Fixed a long-standing gap where the deploy script only copied rule files matching a fixed
filename list, so several stack-shipped rules (`craft-graphql.md`, `nuxt-patterns.md`,
`astro-patterns.md`, `strapi-patterns.md`, `sanity-patterns.md`, `laravel-api.md`,
`sveltekit-patterns.md`, `wordpress-coding-standards.md`, `wordpress-security.md`,
`coding-standards.md`) and the three shared JS/TypeScript rules added in the Web Design
Optimization pass below (`typescript-patterns.md`, `design-system.md`, `api-design.md`) existed
in the templates but were never actually deployed to a project.

- `stack_rule_sources()` now copies every `.md` file in a stack's `rules/` directory (minus the
  core and detection-gated names), plus `typescript-patterns.md` on any stack with `tsconfig.json`
  and `design-system.md` / `api-design.md` on the JS-framework stacks.
- `refresh_stack_rules()` adds any of these newly-recognized rules to an already-deployed project
  when it's missing and was never recorded in `.claude/ai-config/manifest.tsv`, and updates it
  when present — without disturbing a rule you deleted on purpose. The original six stack-pattern
  rules, the core rules, and the detection-gated rules are unchanged: still deploy-only, not
  refreshed.
- See [Stacks Reference → Deployed to Every Stack](../reference/stacks.md#deployed-to-every-stack)
  for the corrected per-stack rule counts and
  [Conditional Deployment → Rule Categories](../guides/conditional-deployment.md#rule-categories)
  for the mechanism.

### Web Design Optimization (Jun 2026)

**4 new modern JS stacks:**
- `sveltekit` — SvelteKit 2 + Svelte 5 Runes, load functions, form actions, `$lib` alias
- `remix` — Remix/React Router v7, loaders/actions with Zod, error boundaries, `useFetcher`
- `t3-stack` — Next.js + tRPC + Prisma + NextAuth + shadcn/ui + Zod (detected before generic nextjs)
- `nuxt` — Nuxt 3, server API routes, `useFetch`, Pinia, `runtimeConfig`

**13 new library references** (`libraries/`):
- `typescript.md` — strict mode, utility types, branded IDs, exhaustive checks
- `zod.md` — schema validation, `safeParse`, React Hook Form integration
- `tanstack-query.md` — React Query v5, query keys, mutations, prefetching
- `zustand.md` — global state, slice pattern, persistence, selectors
- `shadcn-ui.md` — component usage, form + Zod integration, `cva` variants
- `supabase.md` — browser/server clients, auth, RLS, storage, realtime
- `prisma.md` — schema, singleton client, CRUD, transactions, migrations
- `vitest.md` — unit tests, React Testing Library, mocking patterns
- `playwright.md` — E2E, page object model, locator strategies
- `framer-motion.md` — AnimatePresence, scroll effects, layout animations
- `trpc.md` — end-to-end typesafe APIs, procedures, client patterns
- `pinia.md` — Vue/Nuxt state management, composition stores, persistence
- `tinacms.md` — Git-based CMS, `defineConfig`, collections, Astro SSG integration

**3 new common rules** (`projects/common/rules/`):
- `typescript-patterns.md` — strict TS enforcement, discriminated unions
- `design-system.md` — token-first design, `cva` variants, component inventory protocol
- `api-design.md` — Zod validation, response envelopes, auth guard, rate limiting

(These three rules are now actually wired into the deploy script's rule-copy step — see the
"Rule Copy Fix" entry below. From their addition until that fix, the files existed in the
template but the deploy script never copied them to a project.)

**Expanded MEMORY.md template**: Design System tokens, Component Registry, Third-Party Integrations, Environment Variables, MCP Servers, API Inventory sections

**2 new Superpowers skills:**
- `design-system-builder` — token audit, component inventory, build + document
- `component-scaffolder` — typed React/Vue/Svelte component + test generation

**Smart library auto-injection:**
- 13 `HAS_*` detection variables for modern web tooling
- `inject_detected_library_imports()` — idempotent, runs on fresh deploy and `--refresh`
- 16 detection-backed libraries (file presence + `package.json` signals)

**New docs:**
- `docs/guides/mcp-integration.md` — Supabase, GitHub, Cloudflare, PostgreSQL, Zapier MCP setup

**Tests:**
- `test-stack-detection.sh` — 22 automated integration tests (all passing)

### Headless CMS Stacks & Library References (Mar 2026)
- Added 5 headless CMS stacks: `craftcms-nuxt`, `craftcms-nextjs`, `ee-nextjs`, `astro-strapi`, `astro-sanity`
- Moved library references from global `~/.claude/libraries/` to project-local `.claude/libraries/` for portability
- Added 10+ library reference docs (React, Vue, Next.js, Nuxt, Angular, Bootstrap, etc.)

### Genericized Templates (Feb 2026)
- Replaced all hardcoded project references with `{{PLACEHOLDER}}` variables
- Added `{{BRAND_*}}` color placeholders for project brand colors
- Fixed `{{PRIMARY_URL}}` → `{{DDEV_PRIMARY_URL}}` across all templates

### Sensitive File Protection (Feb 2026)
- Added `sensitive-files.md` rule preventing Claude from reading credentials, API keys, `.env` files, etc.
- Deployed as a core rule to all stacks

### Cross-Platform Compatibility (Feb 2026)
- Added `sed_inplace()` wrapper function for macOS/Linux `sed -i` compatibility
- Script now works on both macOS and Linux without modification

### Stack Permissions (Feb 2026)
- Added `settings.local.json` with stack-appropriate CLI permissions to all 13 stacks
- PHP stacks include `composer`, `php`; WordPress stacks include `wp`; JS stacks include `node`, `yarn`

### CLI Flags (Feb 2026)
- Implemented `--skip-vscode` flag to skip VSCode settings deployment
- Implemented `--install-extensions` flag to auto-install recommended VSCode extensions

### Other AI Assistants Removed (Feb 2026)
- Removed Gemini, Windsurf, Copilot, and Codex configurations
- Focused exclusively on Claude Code + VS Code

### Memory System
- `projects/common/MEMORY.md.template` - Memory bank template
- `projects/common/rules/memory-management.md` - Memory protocols
- `projects/common/rules/token-optimization.md` - Token efficiency
- `projects/common/memory-protocol.md` - Always-on memory protocol block

### Superpowers Skills Integration
- 16 workflow skills (skipped when the superpowers plugin is enabled globally)
- Session hooks for auto-activation
- Slash commands (`/brainstorm`, `/write-plan`, `/execute-plan`)

---

## Verification Checklist

### All Stacks Have:
- [x] CLAUDE.md.template with variable substitution
- [x] settings.local.json with stack-appropriate permissions
- [x] MEMORY.md.template (common fallback)
- [x] Memory management rules
- [x] Token optimization rules
- [x] Sensitive file protection rules
- [x] Superpowers workflow skills
- [x] Session hooks
- [x] No hardcoded project-specific references

### Setup Script Handles:
- [x] Memory bank deployment
- [x] Memory preservation on refresh
- [x] Superpowers skills deployment
- [x] Token optimization rules
- [x] Sensitive file protection rules
- [x] settings.local.json deployment
- [x] Template variable substitution (including brand colors)
- [x] Cross-platform sed compatibility (macOS/Linux)
- [x] --skip-vscode flag
- [x] --install-extensions flag
- [x] Discovery mode for unknown stacks

---

## Summary

**Repository Status: Production Ready**

All 19 technology stacks have complete Claude Code configurations with:
- **Generic templates** using `{{PLACEHOLDER}}` variables
- **Stack permissions** via `settings.local.json`
- **Sensitive file protection** preventing credential exposure
- **Memory bank** for persistent context
- **Token optimization** rules
- **16 Superpowers** workflow skills
- **Cross-platform** macOS/Linux compatibility
- **VSCode integration** with optional extension installation
