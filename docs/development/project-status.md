# Claude Optimizer - Status Report

## Executive Summary

**Status: PRODUCTION READY**

19 technology stacks have complete Claude Code configurations:
- Full template systems with generic `{{PLACEHOLDER}}` variables
- Stack-appropriate `settings.local.json` for all stacks
- Memory bank system for persistent context with Design System, Integrations, and API inventory sections
- Token optimization and sensitive file protection rules
- 17 Superpowers workflow skills (including design-system-builder and component-scaffolder)
- 30 library references covering modern web tooling (auto-injected on detection)
- Technology-specific coding rules (4-9 rules per stack)

---

## Stack Coverage

| Stack | Claude | Rules | Skills | Memory | Permissions | Status |
|-------|--------|-------|--------|--------|-------------|--------|
| **sveltekit** | Yes | 7 rules | 17+ | Yes | Yes | Complete |
| **remix** | Yes | 6 rules | 17+ | Yes | Yes | Complete |
| **t3-stack** | Yes | 6 rules | 17+ | Yes | Yes | Complete |
| **nuxt** | Yes | 6 rules | 17+ | Yes | Yes | Complete |
| **coilpack** | Yes | 9 rules | 17+ | Yes | Yes | Complete |
| **craftcms** | Yes | 9 rules | 17+ | Yes | Yes | Complete |
| **docusaurus** | Yes | 7 rules | 17+ | Yes | Yes | Complete |
| **expressionengine** | Yes | 9 rules | 21+ | Yes | Yes | Complete |
| **nextjs** | Yes | 7 rules | 17+ | Yes | Yes | Complete |
| **wordpress-roots** | Yes | 9 rules | 17+ | Yes | Yes | Complete |
| **wordpress** | Yes | 7 rules | 17+ | Yes | Yes | Complete |
| **craftcms-nuxt** | Yes | 8 rules | 17+ | Yes | Yes | Complete |
| **craftcms-nextjs** | Yes | 8 rules | 17+ | Yes | Yes | Complete |
| **ee-nextjs** | Yes | 8 rules | 17+ | Yes | Yes | Complete |
| **astro-tina** | Yes | 6 rules | 17+ | Yes | Yes | Complete |
| **astro** | Yes | 6 rules | 17+ | Yes | Yes | Complete |
| **astro-strapi** | Yes | 8 rules | 17+ | Yes | Yes | Complete |
| **astro-sanity** | Yes | 8 rules | 17+ | Yes | Yes | Complete |
| **custom** | Yes | 4 rules | 17+ | Yes | Yes | Complete |

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
| Memory Skill | `.claude/skills/superpowers/memory-management/` | Automated behaviors |

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

17 workflow skills deployed with every stack:

| Skill | Purpose |
|-------|---------|
| `memory-management` | Persistent context across sessions |
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

**All Stacks Include:**
- `memory-management.md` - Memory protocols
- `token-optimization.md` - Token efficiency
- `sensitive-files.md` - Credential and secret protection
- `accessibility.md` - WCAG compliance

**Coilpack (Laravel + EE) - 9 rules:**
- accessibility, alpinejs, bilingual-content, laravel-patterns, performance, tailwind-css
- memory-management, token-optimization, sensitive-files

**Craft CMS - 9 rules:**
- accessibility, alpinejs, bilingual-content, craft-templates, performance, tailwind-css
- memory-management, token-optimization, sensitive-files

**Docusaurus - 7 rules:**
- accessibility, markdown-content, performance, tailwind-css
- memory-management, token-optimization, sensitive-files

**ExpressionEngine - 9 rules + 4 stack skills:**
- accessibility, alpinejs, bilingual-content, expressionengine-templates, performance, tailwind-css
- memory-management, token-optimization, sensitive-files
- Skills: alpine-component-builder, ee-stash-optimizer, ee-template-assistant, tailwind-utility-finder

**Next.js - 7 rules:**
- accessibility, nextjs-patterns, performance, tailwind-css
- memory-management, token-optimization, sensitive-files

**WordPress/Roots - 9 rules:**
- accessibility, alpinejs, bilingual-content, blade-templates, performance, tailwind-css
- memory-management, token-optimization, sensitive-files

**Custom (Discovery Mode) - 4 rules:**
- accessibility, sensitive-files
- memory-management, token-optimization

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

## Recent Changes

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
- `superpowers/skills/memory-management/` - Memory skill

### Superpowers Skills Integration
- 15 workflow skills deployed by default
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

All 13 technology stacks have complete Claude Code configurations with:
- **Generic templates** using `{{PLACEHOLDER}}` variables
- **Stack permissions** via `settings.local.json`
- **Sensitive file protection** preventing credential exposure
- **Memory bank** for persistent context
- **Token optimization** rules
- **15 Superpowers** workflow skills
- **Cross-platform** macOS/Linux compatibility
- **VSCode integration** with optional extension installation
