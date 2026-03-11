# Supported Stacks

Complete reference for all supported technology stacks.

## Stack Overview

### Monolithic Stacks

| Stack | CMS/Framework | Template Engine | Primary Use Case |
|-------|--------------|-----------------|------------------|
| **expressionengine** | ExpressionEngine 7.x | EE Template Language | Content-heavy websites |
| **coilpack** | Laravel + EE | Blade/Twig/EE | Hybrid apps with CMS |
| **craftcms** | Craft CMS | Twig | Content management |
| **wordpress-roots** | WordPress/Bedrock | Blade (via Sage) | WordPress with modern stack |
| **wordpress** | WordPress | PHP Templates | Standard WordPress |
| **nextjs** | Next.js | React/TSX | React web applications |
| **docusaurus** | Docusaurus | MDX | Documentation sites |
| **custom** | Any | Any | Discovery mode for unknown stacks |

### Headless CMS Stacks

| Stack | Backend | Frontend | Primary Use Case |
|-------|---------|----------|------------------|
| **craftcms-nuxt** | Craft CMS (GraphQL) | Nuxt 3 (Vue SSR/SSG) | Headless Craft with Vue |
| **craftcms-nextjs** | Craft CMS (GraphQL) | Next.js 14+ (React SSR/SSG) | Headless Craft with React |
| **ee-nextjs** | EE Coilpack (Laravel REST API) | Next.js 14+ (React SSR/SSG) | Headless EE with React |
| **astro-strapi** | Strapi (REST/GraphQL) | Astro (Islands) | Content-driven Astro sites |
| **astro-sanity** | Sanity.io (GROQ) | Astro (Islands) | Sanity-powered Astro sites |

## Common Features (All Stacks)

Every stack deployment includes:

| Feature | Files |
|---------|-------|
| Memory Bank | `MEMORY.md` |
| Memory Rules | `.claude/rules/memory-management.md` |
| Token Optimization | `.claude/rules/token-optimization.md` |
| Sensitive File Protection | `.claude/rules/sensitive-files.md` |
| Permissions | `.claude/settings.local.json` |
| Superpowers Skills | `.claude/skills/superpowers/` |
| Session Hooks | `.claude/hooks/` |

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

## Detection Logic

### How Stacks Are Detected

The script checks for:

| Stack | Detection Method |
|-------|------------------|
| craftcms-nuxt | Craft CMS + `frontend/nuxt.config.ts` |
| craftcms-nextjs | Craft CMS + `frontend/next.config.js` |
| ee-nextjs | Coilpack + `frontend/next.config.js` |
| astro-sanity | `astro.config.mjs` + `sanity.config.ts` |
| astro-strapi | `astro.config.mjs` + Strapi in `backend/` |
| expressionengine | `system/ee/` directory |
| coilpack | Laravel + EE indicators |
| craftcms | `craft` executable |
| wordpress-roots | `wp-config.php` + Bedrock structure |
| wordpress | `wp-config.php` |
| nextjs | `next.config.js` or `.next/` |
| docusaurus | `docusaurus.config.js` |

### How Technologies Are Detected

**Tailwind CSS:**
- `tailwind.config.js` exists, OR
- `npm list tailwindcss` succeeds, OR
- CDN link in HTML

**Alpine.js:**
- `x-data` or `@click` attributes in template files

**SCSS/Sass:**
- `.scss` or `.sass` files exist

**Bilingual Content:**
- `user_language` compared to `'en'` or `'fr'`
- `{lang:` ExpressionEngine language tags
- `{% if.*lang` Twig language conditionals
- `@lang` Laravel localization helper

**EE Add-ons:**
- Stash: `{exp:stash` in templates
- Structure: `{exp:structure` in templates

See [Conditional Deployment Guide](../guides/conditional-deployment.md) for detailed detection logic.

## Next Steps

- **[Memory System](../guides/memory-system.md)** - Persistent context guide
- **[Configuration](../getting-started/configuration.md)** - File structure details
- **[Conditional Deployment](../guides/conditional-deployment.md)** - Detection logic
