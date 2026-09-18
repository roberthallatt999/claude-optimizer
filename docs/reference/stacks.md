# Supported Stacks

Complete reference for all supported technology stacks.

## Quick Navigation

**Modern JS / Full-Stack**
[SvelteKit](#sveltekit) · [Remix](#remix--react-router-v7) · [T3 Stack](#t3-stack) · [Nuxt 3](#nuxt-3-standalone) · [Next.js](#nextjs) · [Docusaurus](#docusaurus) · [Custom](#custom-discovery-mode)

**Monolithic CMS**
[ExpressionEngine](#expressionengine) · [Coilpack](#coilpack) · [Craft CMS](#craft-cms) · [WordPress/Roots](#wordpressroots) · [WordPress](#wordpress-standard)

**Headless CMS**
[Craft + Nuxt](#craft-cms--nuxt) · [Craft + Next.js](#craft-cms--nextjs) · [EE + Next.js](#ee-coilpack--nextjs) · [Astro + Strapi](#astro--strapi) · [Astro + Sanity](#astro--sanity) · [Astro + Tina CMS](#astro--tina-cms)

**Reference**
[Detection Logic](#detection-logic)

---

## Stack Overview

### Modern JS / Full-Stack

| Stack | Framework | Language | Primary Use Case |
|-------|-----------|----------|------------------|
| **sveltekit** | SvelteKit 2 + Svelte 5 | TypeScript | Full-stack Svelte apps |
| **remix** | Remix / React Router v7 | TypeScript | Full-stack React apps |
| **t3-stack** | Next.js + tRPC + Prisma | TypeScript | End-to-end typesafe apps |
| **nuxt** | Nuxt 3 (standalone) | TypeScript | Vue SSR/SSG apps |
| **nextjs** | Next.js 14+ | TypeScript | React web applications |
| **docusaurus** | Docusaurus 3+ | TypeScript/MDX | Documentation sites |
| **custom** | Any | Any | Discovery mode for unknown stacks |

### Monolithic CMS Stacks

| Stack | CMS/Framework | Template Engine | Primary Use Case |
|-------|--------------|-----------------|------------------|
| **expressionengine** | ExpressionEngine 7.x | EE Template Language | Content-heavy websites |
| **coilpack** | Laravel + EE | Blade/Twig/EE | Hybrid apps with CMS |
| **craftcms** | Craft CMS | Twig | Content management |
| **wordpress-roots** | WordPress/Bedrock | Blade (via Sage) | WordPress with modern stack |
| **wordpress** | WordPress | PHP Templates | Standard WordPress |

### Headless CMS Stacks

| Stack | Backend | Frontend | Primary Use Case |
|-------|---------|----------|------------------|
| **craftcms-nuxt** | Craft CMS (GraphQL) | Nuxt 3 (Vue SSR/SSG) | Headless Craft with Vue |
| **craftcms-nextjs** | Craft CMS (GraphQL) | Next.js 14+ (React SSR/SSG) | Headless Craft with React |
| **ee-nextjs** | EE Coilpack (Laravel REST API) | Next.js 14+ (React SSR/SSG) | Headless EE with React |
| **astro-strapi** | Strapi (REST/GraphQL) | Astro (Islands) | Content-driven Astro sites |
| **astro-sanity** | Sanity.io (GROQ) | Astro (Islands) | Sanity-powered Astro sites |
| **astro-tina** | Tina CMS (Git-based) | Astro (Islands) | Git-committed MDX content + visual editor |
| **astro** | — | Astro (Islands) | Static/island sites (no CMS) |

## Deployed to Every Stack

Regardless of `--stack`, every deploy and `--refresh` includes:

| Feature | Files |
|---------|-------|
| Memory Bank | `MEMORY.md` (or `.okf/` bundle with `--okf-memory`) |
| Safety policy | Deny/ask rules + `safety-guard.sh` PreToolUse hook merged into `.claude/settings.local.json` |
| Common rules | `.claude/rules/memory-management.md`, `token-optimization.md`, `sensitive-files.md`, `deployment-safety.md` |
| Managed `CLAUDE.md` blocks | Safety Guardrails, Memory Protocol (or OKF Memory Protocol), Response Style, Front-End Stack (when front-end code is found), Code Index (when codegraph is registered) |
| Library references | All files in `libraries/` copied to `.claude/libraries/`; a path reference is added to `CLAUDE.md` only for what's actually detected (see below) |
| Superpowers skills | `.claude/skills/<skill>/` (16 skills by default) |
| Session hook | `.claude/hooks/session-start` (registered in `settings.local.json`) |
| Update tracking | `.claude/ai-config/` — `manifest.tsv`, `backups/`, `pending/`, `version` |
| Health check | Runs after every deploy/refresh; re-run anytime with `--doctor` |
| Permissions | `.claude/settings.local.json` (plus `.claude/settings.json` with `--shared-policy`) |

**Rules:** every `.md` file in a stack's own `projects/{stack}/rules/` is deployed, except
`tailwind-css.md` / `alpinejs.md` / `bilingual-content.md`, which need their technology detected
first. `accessibility.md` and `performance.md` are copied only when the stack ships its own copy
(no common fallback for these two) — see each stack's section below for exactly which rules it
ships. Three rules from `projects/common/rules/` are added on top, when the stack doesn't already
have its own file of the same name:
- `typescript-patterns.md` — **any** stack, when `tsconfig.json` exists
- `design-system.md` and `api-design.md` — the JS-framework stacks (`nextjs`, `nuxt`, `astro`,
  `astro-sanity`, `astro-strapi`, `astro-tina`, `sveltekit`, `remix`, `t3-stack`, `docusaurus`,
  `craftcms-nextjs`, `craftcms-nuxt`, `ee-nextjs`)

Most rules carry `paths:` frontmatter and load only for matching files, including the three
shared rules above — `typescript-patterns.md` for `*.{ts,tsx,mts,cts}`, `design-system.md` for
`*.{tsx,jsx,vue,svelte,astro,css,scss}` + `tailwind.config.*`, and `api-design.md` for
`**/api/**` + `**/server/**` + similar server-side paths. `token-optimization.md` and `custom`'s
`coding-standards.md` are the exceptions: always loaded, no path scoping. See
[Conditional Deployment](../guides/conditional-deployment.md).

**On `--refresh`:** the four common rules update when present (and the two safety rules are
restored if missing), and any rule a fresh deploy would add — the stack's own rules, plus
`typescript-patterns.md` / `design-system.md` / `api-design.md` — is added if it's missing and
was never recorded as deployed (so intentionally deleting one keeps it gone). The original
six stack-pattern rules (`expressionengine-templates.md`, `craft-templates.md`,
`blade-templates.md`, `nextjs-patterns.md`, `laravel-patterns.md`, `markdown-content.md`) and the
detection-gated rules are the exception: refresh never re-copies or re-checks these, so adding
Tailwind to an existing project still doesn't add `tailwind-css.md` on `--refresh` alone.

**Library references, on demand:** all ~30 files in `libraries/` land in every project's
`.claude/libraries/`, but `CLAUDE.md` only points at the ones actually detected — 22 are
signal-backed (auto-injected when found): `typescript`, `zod`, `zustand`, `tanstack-query`,
`trpc`, `prisma`, `supabase`, `vitest`, `playwright`, `framer-motion`, `shadcn-ui`, `pinia`,
`tailwind`, `alpinejs`, `scss`, `tinacms`, `foundation`, `bootstrap`, `bulma`, `jquery`,
`material-ui`, `vanilla-js`. Framework libraries (`react`, `vue`, `nextjs`, `nuxt`, …) are
`@`-imported directly by the stack's own `CLAUDE.md.template` instead, since they're implied by
the stack itself.

**Front-end detection:** every deploy runs `projects/common/detect-frontend.sh` against the
whole project (theme folders included), regardless of stack, and reports CSS/JS frameworks,
UI kits, build tools, and the project's own first-party code. See
[Setup Script → Front-End Stack](../guides/setup-script.md#front-end-stack).

### Code Intelligence and Template Map by Stack

Two optional, detect-and-register-only integrations, plus the OKF template map, apply to a
subset of stacks:

| Stack | codegraph (JS tree-sitter index) | php-lsp (Intelephense) | OKF template map |
|---|---|---|---|
| expressionengine | — | Yes | Yes |
| coilpack | — | Yes | — |
| craftcms | — | Yes | Yes |
| craftcms-nuxt | Yes | Yes | Yes |
| craftcms-nextjs | Yes | Yes | Yes |
| ee-nextjs | Yes | Yes | Yes |
| wordpress | — | Yes | — |
| wordpress-roots | — | Yes | Yes |
| nextjs, nuxt, astro, astro-sanity, astro-strapi, astro-tina, sveltekit, remix, t3-stack, docusaurus | Yes | — | — |
| custom | — | — | — |

- **codegraph:** registered as a local-scope MCP server only when `codegraph` is already
  installed and the project has a `.codegraph/` index — ai-config never installs it or builds
  the index. Twig/Blade/EE templates aren't tree-sitter-parseable, so monolithic PHP CMS stacks
  are excluded.
- **php-lsp:** the official `php-lsp@claude-plugins-official` plugin is enabled at local scope
  only when Intelephense is already on PATH.
- **OKF template map:** with `--okf-memory`, `.okf/architecture/templates.md` is kept in sync
  for stacks whose templates a code index can't parse (EE, Craft, and Sage/Blade).

## ExpressionEngine

**Stack ID:** `expressionengine`

### Technologies

- **CMS:** ExpressionEngine 7.x
- **Template Engine:** ExpressionEngine Template Language
- **PHP:** 8.0+
- **Database:** MySQL/MariaDB

### Rules Included

**Always (7):**
- `accessibility.md` - WCAG compliance
- `expressionengine-templates.md` - EE template best practices
- `performance.md` - Performance optimization
- `sensitive-files.md` - Credential protection
- `memory-management.md` - Memory protocols
- `token-optimization.md` - Token efficiency
- `deployment-safety.md` - No unauthorized pushes or production changes

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `alpinejs.md` - If Alpine.js detected
- `bilingual-content.md` - If language/bilingual patterns detected
- `typescript-patterns.md` - If `tsconfig.json` exists

### Skills Included

- `alpine-component-builder` - Build Alpine.js components
- `ee-stash-optimizer` - Optimize Stash usage
- `ee-template-assistant` - EE template help
- `tailwind-utility-finder` - Find Tailwind utilities
- Plus all Superpowers skills

### File Associations

```json
"files.associations": {
  "**/system/user/templates/**/*.html": "ExpressionEngine",
  "**/templates/**/*.html": "ExpressionEngine",
  "*.html": "ExpressionEngine"
}
```

## Coilpack

**Stack ID:** `coilpack`

### Technologies

- **Framework:** Laravel + ExpressionEngine hybrid
- **Template Engines:** Blade, Twig, or EE Template Language
- **PHP:** 8.1+
- **Database:** MySQL/MariaDB

### Rules Included

**Always (7):**
- `accessibility.md`
- `laravel-patterns.md` - Laravel best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`
- `bilingual-content.md`
- `typescript-patterns.md` - If `tsconfig.json` exists

### File Associations

```json
"files.associations": {
  "**/resources/views/**/*.blade.php": "blade",
  "**/resources/views/**/*.twig": "twig",
  "**/templates/**/*.html": "ExpressionEngine",
  "*.blade.php": "blade",
  "*.twig": "twig"
}
```

## Craft CMS

**Stack ID:** `craftcms`

### Technologies

- **CMS:** Craft CMS 4.x+
- **Template Engine:** Twig
- **PHP:** 8.0+
- **Database:** MySQL/PostgreSQL

### Rules Included

**Always (7):**
- `accessibility.md`
- `craft-templates.md` - Craft/Twig best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`
- `bilingual-content.md`
- `typescript-patterns.md` - If `tsconfig.json` exists

### File Associations

```json
"files.associations": {
  "**/templates/**/*.twig": "twig",
  "**/templates/**/*.html": "twig",
  "*.twig": "twig"
}
```

## WordPress/Roots

**Stack ID:** `wordpress-roots`

### Technologies

- **CMS:** WordPress with Bedrock
- **Theme:** Sage (Laravel Blade templates)
- **PHP:** 8.0+
- **Database:** MySQL/MariaDB

### Rules Included

**Always (7):**
- `accessibility.md`
- `blade-templates.md` - WordPress/Roots (Sage) Blade template best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`
- `bilingual-content.md`
- `typescript-patterns.md` - If `tsconfig.json` exists

### File Associations

```json
"files.associations": {
  "**/resources/views/**/*.blade.php": "blade",
  "*.blade.php": "blade",
  ".env": "dotenv"
}
```

## WordPress (Standard)

**Stack ID:** `wordpress`

### Technologies

- **CMS:** Standard WordPress
- **Template Engine:** PHP
- **PHP:** 7.4+
- **Database:** MySQL/MariaDB

### Rules Included

**Always (8):**
- `accessibility.md`
- `performance.md`
- `wordpress-coding-standards.md`
- `wordpress-security.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists

This stack ships no `tailwind-css.md` / `alpinejs.md`, so Tailwind/Alpine detection has no rule
to add here even when either is found (only the library reference).

## Next.js

**Stack ID:** `nextjs`

### Technologies

- **Framework:** Next.js 14+
- **Language:** TypeScript
- **React:** 18+
- **Node:** 18+

### Rules Included

**Always (9):**
- `accessibility.md`
- `nextjs-patterns.md` - Next.js best practices
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md`
- `typescript-patterns.md` - If `tsconfig.json` exists

### Special Settings

```json
"tailwindCSS.experimental.classRegex": [
  ["cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]"],
  ["cn\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]"]
]
```

For `cva()` and `cn()` utility functions.

## Docusaurus

**Stack ID:** `docusaurus`

### Technologies

- **Framework:** Docusaurus 3+
- **Language:** TypeScript/JavaScript
- **React:** 18+
- **Node:** 18+

### Rules Included

**Always (9):**
- `accessibility.md`
- `markdown-content.md` - MDX best practices
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md`
- `typescript-patterns.md` - If `tsconfig.json` exists

### Special Settings

```json
"[markdown]": {
  "editor.wordWrap": "on",
  "editor.quickSuggestions": true
}
```

## Craft CMS + Nuxt

**Stack ID:** `craftcms-nuxt`

### Technologies

- **Backend:** Craft CMS (GraphQL API)
- **Frontend:** Nuxt 3 (Vue SSR/SSG)
- **Languages:** PHP 8.0+, TypeScript
- **Database:** MySQL/PostgreSQL

### Rules Included

**Always (10):**
- `accessibility.md`
- `craft-graphql.md` - Craft CMS backend (GraphQL) patterns
- `nuxt-patterns.md` - Nuxt 3 frontend patterns
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `typescript-patterns.md` - If `tsconfig.json` exists

### Detection

Craft CMS detected + `frontend/nuxt.config.ts` exists.

---

## Craft CMS + Next.js

**Stack ID:** `craftcms-nextjs`

### Technologies

- **Backend:** Craft CMS (GraphQL API)
- **Frontend:** Next.js 14+ (React SSR/SSG)
- **Languages:** PHP 8.0+, TypeScript
- **Database:** MySQL/PostgreSQL

### Rules Included

**Always (10):**
- `accessibility.md`
- `craft-graphql.md` - Craft CMS backend (GraphQL) patterns
- `nextjs-patterns.md` - Next.js frontend patterns
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `typescript-patterns.md` - If `tsconfig.json` exists

### Detection

Craft CMS detected + `frontend/next.config.js` or `frontend/next.config.mjs` exists.

---

## EE Coilpack + Next.js

**Stack ID:** `ee-nextjs`

### Technologies

- **Backend:** ExpressionEngine + Coilpack (Laravel REST API)
- **Frontend:** Next.js 14+ (React SSR/SSG)
- **Languages:** PHP 8.1+, TypeScript
- **Database:** MySQL/MariaDB

### Rules Included

**Always (10):**
- `accessibility.md`
- `laravel-api.md` - Laravel REST API patterns
- `nextjs-patterns.md` - Next.js frontend patterns
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `typescript-patterns.md` - If `tsconfig.json` exists

### Detection

Coilpack detected + `frontend/next.config.js` or `frontend/next.config.mjs` exists.

---

## Astro + Strapi

**Stack ID:** `astro-strapi`

### Technologies

- **Backend:** Strapi (REST/GraphQL)
- **Frontend:** Astro (Islands Architecture)
- **Languages:** TypeScript, JavaScript
- **Node:** 18+

### Rules Included

**Always (10):**
- `accessibility.md`
- `astro-patterns.md` - Astro component patterns
- `strapi-patterns.md` - Strapi content modeling
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `typescript-patterns.md` - If `tsconfig.json` exists

### Detection

`astro.config.mjs` exists + Strapi detected in `backend/` directory.

---

## Astro + Sanity

**Stack ID:** `astro-sanity`

### Technologies

- **Backend:** Sanity.io (GROQ queries)
- **Frontend:** Astro (Islands Architecture)
- **Languages:** TypeScript, JavaScript
- **Node:** 18+

### Rules Included

**Always (10):**
- `accessibility.md`
- `astro-patterns.md` - Astro component patterns
- `sanity-patterns.md` - Sanity schema and GROQ
- `performance.md`
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `typescript-patterns.md` - If `tsconfig.json` exists

### Detection

`astro.config.mjs` exists + `sanity.config.ts` exists.

---

## Custom (Discovery Mode)

**Stack ID:** `custom`

### Technologies

- **Framework:** Any (auto-detected)
- **Languages:** 50+ supported
- **Detection:** React, Vue, Angular, Laravel, Django, Express, etc.

### Rules Included

**Always (6):**
- `accessibility.md`
- `coding-standards.md` - Baseline standards (unscoped; refine with `/project-discover`)
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`
- `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists

### Usage

```bash
ai-config --discover --project=/path/to/project
```

Then run `/project-discover` in Claude Code to generate custom rules.

## SvelteKit

**Stack ID:** `sveltekit`

### Technologies

- **Framework:** SvelteKit 2 with Svelte 5 Runes
- **Language:** TypeScript
- **Rendering:** SSR, SSG, or hybrid (per-route)
- **Node:** 18+

### Rules Included

**Always (7):**
- `sveltekit-patterns.md` — routing files, Runes, load functions, form actions
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `memory-management.md`, `token-optimization.md`, `sensitive-files.md`, `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists

**Library references (auto-injected via detection, not rules):**
- `typescript.md`, `tailwind.md`, `vitest.md`, `playwright.md`, `zod.md`

This stack has no `accessibility.md` / `performance.md` of its own, and there's no common
fallback for those two names, so they aren't part of its rule set.

### Detection

`svelte.config.js` or `svelte.config.ts` at project root, OR `@sveltejs/kit` in `package.json`.

---

## Remix / React Router v7

**Stack ID:** `remix`

### Technologies

- **Framework:** Remix or React Router v7
- **Language:** TypeScript
- **Rendering:** SSR-first, nested routes
- **Node:** 18+

### Rules Included

**Always (6):**
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `memory-management.md`, `token-optimization.md`, `sensitive-files.md`, `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists

**Library references (auto-injected):**
- `typescript.md`, `tailwind.md`, `zod.md`, `vitest.md`, `playwright.md`, `shadcn-ui.md`

This stack ships no `rules/` directory of its own, so there's no `accessibility.md` /
`performance.md` / framework-pattern rule — just the two shared JS-framework rules plus the four
common ones.

### Key Patterns

- Loaders/actions with Zod validation at every boundary
- Error boundaries with `isRouteErrorResponse()`
- `useFetcher` for optimistic updates and non-navigating mutations
- `Promise.all` in loaders for parallel data loading
- `app/lib/*.server.ts` for server-only modules

### Detection

`remix.config.js/ts` at project root, OR `app/root.tsx` + `@remix-run/react` in `package.json`.

---

## T3 Stack

**Stack ID:** `t3-stack`

### Technologies

- **Framework:** Next.js 14+
- **API Layer:** tRPC v11 (end-to-end typesafe)
- **ORM:** Prisma
- **Auth:** NextAuth.js / Auth.js
- **UI:** shadcn/ui + Tailwind CSS
- **Validation:** Zod
- **Language:** TypeScript (strict)

### Rules Included

**Always (6):**
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `memory-management.md`, `token-optimization.md`, `sensitive-files.md`, `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists (true for essentially every T3 project)

**Library references (auto-injected, all detected by default in T3):**
- `typescript.md`, `trpc.md`, `prisma.md`, `zod.md`, `tailwind.md`, `shadcn-ui.md`

### Detection

`next.config.*` + `prisma/schema.prisma` + `@trpc/server` in `package.json`. Checked **before** generic `nextjs` to avoid misclassification.

---

## Nuxt 3 (Standalone)

**Stack ID:** `nuxt`

### Technologies

- **Framework:** Nuxt 3
- **Language:** TypeScript
- **Rendering:** SSR, SSG, or hybrid
- **State:** Pinia
- **Node:** 18+

### Rules Included

**Always (6):**
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `memory-management.md`, `token-optimization.md`, `sensitive-files.md`, `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists

**Library references (auto-injected):**
- `typescript.md`, `tailwind.md`, `pinia.md`, `zod.md`, `vitest.md`, `playwright.md`

This stack ships no `rules/` directory of its own, so there's no `accessibility.md` /
`performance.md` / framework-pattern rule — just the two shared JS-framework rules plus the four
common ones.

### Key Patterns

- `useFetch` > `useAsyncData` > `$fetch` (prefer in that order)
- Server routes: `server/api/items.get.ts` (method suffix pattern)
- `defineEventHandler` + `readValidatedBody(event, schema.parse)` in API routes
- `runtimeConfig` for env vars; `useRuntimeConfig()` in composables

### Detection

`nuxt.config.ts` or `nuxt.config.js` at project root, OR `nuxt` in `package.json`.

---

## Astro + Tina CMS

**Stack ID:** `astro-tina`

### Technologies

- **CMS:** Tina CMS 2.x (Git-based, MDX/Markdown content)
- **Frontend:** Astro 4.x+ (Islands architecture)
- **Language:** TypeScript
- **Styling:** Tailwind CSS
- **Node:** 18+

### How Tina CMS Works

Tina is a Git-backed CMS — content is stored as `.mdx` / `.md` files committed directly to the repository, rather than in a hosted database. Editors use a visual admin UI (served at `/admin`) that writes changes back to Git. In production, Tina Cloud handles authentication and commits via GitHub OAuth.

### Rules Included

**Always (6):**
- `design-system.md` - Token-first design, cva variants (shared JS-framework rule)
- `api-design.md` - Zod at boundaries, response envelopes (shared JS-framework rule)
- `memory-management.md`, `token-optimization.md`, `sensitive-files.md`, `deployment-safety.md`

**Conditional:**
- `typescript-patterns.md` - If `tsconfig.json` exists

**Library references (auto-injected on detection):**
- `tinacms.md` — schema definition, collections, Astro data fetching, live editing
- `typescript.md`, `tailwind.md`, `vitest.md`, `playwright.md`, `zod.md` (if detected)

This stack ships no `rules/` directory of its own, so there's no `accessibility.md` /
`performance.md` / framework-pattern rule — just the two shared JS-framework rules plus the four
common ones.

### Key Patterns

- Schema defined in `tina/config.ts` → `defineConfig()` with collections
- `tina/__generated__/` is auto-generated — never edit
- Always import from `tina/__generated__/client` for type-safe queries
- Dev: `tinacms dev -c "astro dev"` (not `astro dev` directly)
- Build: `tinacms build && astro build` (order is mandatory)
- Admin UI shell at `src/pages/admin/[...all].astro` (served from `public/admin/`)

### Detection

`astro.config.mjs/ts` + `tina/config.ts/js` at project root. Falls back to `astro` + `tinacms` in `package.json`.

---

## Detection Logic

### How Stacks Are Detected

The script checks in this order (first match wins):

| Stack | Detection Method |
|-------|------------------|
| expressionengine | `system/ee/` directory |
| coilpack | Laravel + EE indicators |
| craftcms-nuxt | Craft CMS + `frontend/nuxt.config.ts` |
| craftcms-nextjs | Craft CMS + `frontend/next.config.js` |
| craftcms | `craft` executable |
| ee-nextjs | Coilpack + `frontend/next.config.js` |
| wordpress-roots | `wp-config.php` + Bedrock structure |
| wordpress | `wp-config.php` |
| sveltekit | `svelte.config.js/ts` |
| nuxt | `nuxt.config.ts/js` |
| t3-stack | `next.config.*` + `prisma/schema.prisma` + `@trpc/server` |
| remix | `remix.config.js/ts` or `app/root.tsx` + `@remix-run/react` |
| astro-sanity | `astro.config.mjs` + `sanity.config.ts` |
| astro-strapi | `astro.config.mjs` + Strapi in `backend/` |
| astro-tina | `astro.config.mjs` + `tina/config.ts` (or `tinacms` in `package.json`) |
| astro | `astro.config.mjs` or `astro.config.ts` |
| nextjs | `next.config.js/mjs/ts` |
| docusaurus | `docusaurus.config.js/ts` |

### How Technologies Are Detected

**CSS / Styling:**
- Tailwind: `tailwind.config.*` or `tailwindcss` in `package.json`
- Foundation: `foundation-sites` in `package.json`
- SCSS: `sass` or `node-sass` in `package.json`, or `.scss` files
- Alpine.js: `alpinejs` in `package.json` or `x-data`/`@click` in templates

**Modern Web Tooling (auto-inject library docs):**
- TypeScript: `tsconfig.json` at project root
- Zod: `zod` in `package.json`
- Zustand: `zustand` in `package.json`
- TanStack Query: `@tanstack/react-query` in `package.json`
- tRPC: `@trpc/server` in `package.json`
- Prisma: `prisma/schema.prisma` file OR `@prisma/client` in `package.json`
- Supabase: `@supabase/supabase-js` or `@supabase/ssr` in `package.json`
- Vitest: `vitest` in `package.json`
- Playwright: `playwright.config.ts/js` file OR `@playwright/test` in `package.json`
- Framer Motion: `framer-motion` or `motion` in `package.json`
- shadcn/ui: `components/ui/` directory (root, `src/`, or `app/`)
- Pinia: `pinia` in `package.json`
- Tina CMS: `tina/config.ts/js` file OR `tinacms` in `package.json`

Bootstrap, Bulma, jQuery, Material UI, and "vanilla JS, no framework" are detected the same way
(auto-inject a library reference), via `projects/common/detect-frontend.sh` rather than a
dedicated check — see [Setup Script → Front-End Stack](../guides/setup-script.md#front-end-stack).

**CMS / PHP:**
- Bilingual: `user_language` in EE templates, `@lang` in Blade, `{%.*lang` in Twig
- Stash add-on: `{exp:stash` in templates
- Structure add-on: `{exp:structure` in templates

See [Conditional Deployment Guide](../guides/conditional-deployment.md) for detailed detection logic.

## Next Steps

- **[Memory System](../guides/memory-system.md)** - Persistent context guide
- **[Configuration](../getting-started/configuration.md)** - File structure details
- **[Conditional Deployment](../guides/conditional-deployment.md)** - Detection logic
