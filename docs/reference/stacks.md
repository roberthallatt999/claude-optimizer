# Supported Stacks

Complete reference for all supported technology stacks.

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

## Common Features (All Stacks)

Every stack deployment includes:

| Feature | Files |
|---------|-------|
| Memory Bank | `MEMORY.md` |
| Memory Rules | `.claude/rules/memory-management.md` |
| Token Optimization | `.claude/rules/token-optimization.md` |
| Sensitive File Protection | `.claude/rules/sensitive-files.md` |
| Deployment Safety | `.claude/rules/deployment-safety.md` |
| Accessibility | `.claude/rules/accessibility.md` |
| TypeScript Patterns | `.claude/rules/typescript-patterns.md` |
| Design System | `.claude/rules/design-system.md` |
| API Design | `.claude/rules/api-design.md` |
| Permissions | `.claude/settings.local.json` |
| Superpowers Skills | `.claude/skills/superpowers/` |
| Session Hooks | `.claude/hooks/` |

> The three rules marked in bold above (`typescript-patterns`, `design-system`, `api-design`) are
> deployed from `projects/common/rules/` to modern JS stacks (SvelteKit, Remix, T3, Nuxt, Next.js).
> PHP/CMS stacks (WordPress, Craft, EE) continue to receive the original 6-rule set.

## ExpressionEngine

**Stack ID:** `expressionengine`

### Technologies

- **CMS:** ExpressionEngine 7.x
- **Template Engine:** ExpressionEngine Template Language
- **PHP:** 8.0+
- **Database:** MySQL/MariaDB

### Rules Included

**Always:**
- `accessibility.md` - WCAG compliance
- `expressionengine-templates.md` - EE template best practices
- `performance.md` - Performance optimization
- `sensitive-files.md` - Credential protection
- `memory-management.md` - Memory protocols
- `token-optimization.md` - Token efficiency

**Conditional:**
- `tailwind-css.md` - If Tailwind detected
- `alpinejs.md` - If Alpine.js detected
- `bilingual-content.md` - If language/bilingual patterns detected

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

**Always:**
- `accessibility.md`
- `laravel-patterns.md` - Laravel best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`
- `bilingual-content.md`

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

**Always:**
- `accessibility.md`
- `craft-templates.md` - Craft/Twig best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`
- `bilingual-content.md`

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

**Always:**
- `accessibility.md`
- `wordpress-patterns.md` - WordPress/Roots best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`
- `bilingual-content.md`

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

**Always:**
- `accessibility.md`
- `wordpress-patterns.md`
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

**Conditional:**
- `tailwind-css.md`
- `alpinejs.md`

## Next.js

**Stack ID:** `nextjs`

### Technologies

- **Framework:** Next.js 14+
- **Language:** TypeScript
- **React:** 18+
- **Node:** 18+

### Rules Included

**Always:**
- `accessibility.md`
- `nextjs-patterns.md` - Next.js best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

**Conditional:**
- `tailwind-css.md`

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

**Always:**
- `accessibility.md`
- `markdown-content.md` - MDX best practices
- `performance.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

**Conditional:**
- `tailwind-css.md`

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

**Always:**
- `accessibility.md`
- `craft-patterns.md` - Craft CMS backend best practices
- `nuxt-patterns.md` - Nuxt 3 frontend patterns
- `performance.md`
- `tailwind-css.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

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

**Always:**
- `accessibility.md`
- `craft-patterns.md` - Craft CMS backend best practices
- `nextjs-patterns.md` - Next.js frontend patterns
- `performance.md`
- `tailwind-css.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

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

**Always:**
- `accessibility.md`
- `laravel-patterns.md` - Laravel API patterns
- `nextjs-patterns.md` - Next.js frontend patterns
- `performance.md`
- `tailwind-css.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

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

**Always:**
- `accessibility.md`
- `astro-patterns.md` - Astro component patterns
- `strapi-patterns.md` - Strapi content modeling
- `performance.md`
- `tailwind-css.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

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

**Always:**
- `accessibility.md`
- `astro-patterns.md` - Astro component patterns
- `sanity-patterns.md` - Sanity schema and GROQ
- `performance.md`
- `tailwind-css.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

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

**Always:**
- `accessibility.md`
- `sensitive-files.md`
- `memory-management.md`
- `token-optimization.md`

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

**Always:**
- `accessibility.md`, `performance.md`, `sensitive-files.md`, `deployment-safety.md`
- `memory-management.md`, `token-optimization.md`
- `sveltekit-patterns.md` — routing files, Runes, load functions, form actions

**Conditional (auto-injected via library detection):**
- `typescript.md`, `tailwind.md`, `vitest.md`, `playwright.md`, `zod.md`

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

**Always:**
- `accessibility.md`, `performance.md`, `sensitive-files.md`, `deployment-safety.md`
- `memory-management.md`, `token-optimization.md`

**Conditional (auto-injected):**
- `typescript.md`, `tailwind.md`, `zod.md`, `vitest.md`, `playwright.md`, `shadcn-ui.md`

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

**Always:**
- `accessibility.md`, `performance.md`, `sensitive-files.md`, `deployment-safety.md`
- `memory-management.md`, `token-optimization.md`

**Auto-injected (all detected by default in T3):**
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

**Always:**
- `accessibility.md`, `performance.md`, `sensitive-files.md`, `deployment-safety.md`
- `memory-management.md`, `token-optimization.md`

**Conditional (auto-injected):**
- `typescript.md`, `tailwind.md`, `pinia.md`, `zod.md`, `vitest.md`, `playwright.md`

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

**Always:**
- `accessibility.md`, `performance.md`, `sensitive-files.md`, `deployment-safety.md`
- `memory-management.md`, `token-optimization.md`

**Auto-injected on detection:**
- `tinacms.md` — schema definition, collections, Astro data fetching, live editing
- `typescript.md`, `tailwind.md`, `vitest.md`, `playwright.md`, `zod.md` (if detected)

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

**CMS / PHP:**
- Bilingual: `user_language` in EE templates, `@lang` in Blade, `{%.*lang` in Twig
- Stash add-on: `{exp:stash` in templates
- Structure add-on: `{exp:structure` in templates

See [Conditional Deployment Guide](../guides/conditional-deployment.md) for detailed detection logic.

## Next Steps

- **[Memory System](../guides/memory-system.md)** - Persistent context guide
- **[Configuration](../getting-started/configuration.md)** - File structure details
- **[Conditional Deployment](../guides/conditional-deployment.md)** - Detection logic
