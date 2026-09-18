# Conditional Deployment & Technology Detection

**Updated:** March 11, 2026

## Overview

The setup script **intelligently detects** both your project's stack and its technologies, deploying only relevant configurations. This keeps everything clean and targeted to what your project actually uses.

## Stack Auto-Detection

When you run without specifying `--stack`:
```bash
ai-config --project=/path/to/project 
```

The script will:
1. **Auto-detect the stack** — 19 stacks total: the monolithic CMS stacks (ExpressionEngine,
   Coilpack, Craft CMS, WordPress, WordPress/Bedrock), the headless CMS stacks (Craft + Nuxt,
   Craft + Next.js, EE Coilpack + Next.js, Astro + Strapi, Astro + Sanity, Astro + Tina), the
   standalone JS/full-stack frameworks (Next.js, Nuxt, SvelteKit, Remix, T3 Stack, Astro,
   Docusaurus), and `custom` for discovery mode
2. **Scan for technologies** (Tailwind, Alpine.js, bilingual content, TypeScript, Zod, tRPC, etc.)
3. **Deploy stack-specific configurations** for all AI assistants
4. **Report** what was detected

### Detection Logic for Stacks

The script identifies stacks by looking for specific files and directories, checked in this
order (first match wins) — see [Stacks Reference → Detection Logic](../reference/stacks.md#detection-logic)
for the complete, current list:

| Stack | Detection Pattern |
|-------|------------------|
| **ExpressionEngine** | `system/ee/` directory exists |
| **EE Coilpack + Next.js** | ExpressionEngine + Laravel + `frontend/next.config.*` |
| **Coilpack** | ExpressionEngine + Laravel structure, no Next.js frontend |
| **Craft CMS + Nuxt** | Craft CMS + `frontend/nuxt.config.ts` |
| **Craft CMS + Next.js** | Craft CMS + `frontend/next.config.*` |
| **Craft CMS** | `craft` executable + `craftcms/cms` in `composer.json` |
| **WordPress/Bedrock** | `web/app/{mu-plugins,plugins}` or `roots/bedrock`/`roots/wordpress` in `composer.json` |
| **WordPress** | `wp-config.php` or `wp-content/` (root, `public/`, or `web/`) |
| **SvelteKit** | `svelte.config.js/ts`, or `@sveltejs/kit` in `package.json` |
| **Nuxt 3 (standalone)** | `nuxt.config.ts/js` at root, or `nuxt` in `package.json` |
| **T3 Stack** | `next.config.*` + `prisma/schema.prisma` + `@trpc/server` (checked before generic Next.js) |
| **Remix** | `remix.config.js/ts`, or `app/root.tsx` + `@remix-run/react`/`react-router` |
| **Astro + Sanity** | `astro.config.*` + `sanity.config.*` |
| **Astro + Strapi** | `astro.config.*` + Strapi detected in `backend/` |
| **Astro + Tina CMS** | `astro.config.*` + `tina/config.*` (or `tinacms` in `package.json`) |
| **Astro (standalone)** | `astro.config.*` alone, or `frontend/astro.config.*` |
| **Next.js** | `next.config.js/mjs/ts`, or `"next"` in `package.json` |
| **Docusaurus** | `docusaurus.config.js/ts`, or `@docusaurus/*` in `package.json` |
| **custom** | Nothing matched — used with `--discover` |

**Note:** Headless and framework-specific variants are checked before their more generic base
(e.g., `craftcms-nuxt` before `craftcms`; `t3-stack` before `nextjs`).

### Discovery Mode

For projects that don't match a known stack:
```bash
ai-config --project=/path/to/project --discover 
```

The script will:
1. **Detect 50+ technologies** (React, Vue, Laravel, Django, Express, etc.)
2. **Deploy base configuration** for all AI assistants
3. **Generate discovery prompt** for AI analysis

Then open in Claude Code and run `/project-discover` to generate custom rules.

## Technology Detection

After determining the stack (auto or manual), the script scans for specific technologies:

### How It Works

```bash
# With auto-detected stack
ai-config --project=/path/to/project 

# With manual stack
ai-config --stack=craftcms --project=/path/to/project 
```

The script will:
1. **Identify the stack** (auto or manual)
2. **Scan the project** for technologies (Tailwind, Alpine.js, bilingual content, etc.)
3. **Always copy** the common safety/token/memory rules, plus accessibility/performance/stack-pattern
   rules when the stack ships them
4. **Conditionally copy** rules based on detection, and add a library reference for anything else detected
5. **Report** what was detected and what was skipped

## Detection Logic

### Tailwind CSS
- ✅ Detected if: `tailwind.config.*` or `tailwindcss` in `package.json` (project root or docroot,
  theme folders included)
- → Deploys the `tailwind-css.md` rule (where the stack ships one) and adds the `tailwind.md`
  library reference

### Foundation Framework / SCSS / Bootstrap / Bulma / jQuery / Material UI
- ✅ Detected the same way, via `projects/common/detect-frontend.sh` (package.json dependencies,
  vendored asset file names, CDN tags, or file extensions)
- → No stack ships a rule file for any of these — detection only adds the matching
  `.claude/libraries/{foundation,scss,bootstrap,bulma,jquery,material-ui}.md` reference

### Alpine.js
- ✅ Detected if:
  - `alpinejs` in any `package.json` (theme folders included), OR
  - an Alpine script file or CDN tag, OR
  - `x-data` attributes in templates
- → Deploys the `alpinejs.md` rule (where the stack ships one) and adds the `alpinejs.md` library reference

### Vanilla JS/HTML
- ✅ Detected if the project has its own JavaScript files **and** no JS framework, JS library, or UI
  component library was detected (jQuery counts as a library)
- → Reported as "custom JavaScript, no framework detected (N file(s), mainly in <folder>/)"
- → Adds the `vanilla-js.md` library reference (there is no `vanilla-js.md` rule)

All front-end detection (Tailwind, Foundation, SCSS, Alpine, and 50+ other frameworks, libraries, and
build tools) comes from `projects/common/detect-frontend.sh` — see
[Setup Script → Front-End Stack](setup-script.md#front-end-stack).

### Bilingual Content
- ✅ Detected if patterns found in templates:
  - `user_language` compared to `'en'` or `'fr'` (e.g., `user_language == 'en'`)
  - `{lang:` (ExpressionEngine lang tags)
  - `{% if.*lang` (Twig conditionals with lang variable)
  - `@lang` (Laravel localization helper)
- → Deploys: `bilingual-content.md` (expressionengine, coilpack, craftcms, wordpress-roots ship this rule)

## Rule Categories

### Common Rules (Always Deployed, No Stack Dependency)
Deployed even for a stack that ships no `rules/` directory of its own, from
`projects/common/rules/`:
- `memory-management.md` - Memory protocols
- `token-optimization.md` - Token efficiency
- `sensitive-files.md` - Credential protection
- `deployment-safety.md` - No unauthorized pushes or production changes

### Core Rules (Deployed When the Stack Ships Them)
`accessibility.md` and `performance.md` are copied only from the stack's own `rules/` directory —
there is no common fallback, so a stack without its own copy (SvelteKit, Remix, T3 Stack, Nuxt,
Astro, Astro + Tina) doesn't get them. See [Stacks Reference](../reference/stacks.md) for which
stacks ship which.

### Stack-Specific Rules (Every Other File in the Stack's `rules/`)
Every `.md` file in `projects/{stack}/rules/` is deployed, whatever it's named — not just a fixed
list — except the detection-gated files below. So `expressionengine-templates.md`,
`craft-graphql.md`, `nuxt-patterns.md`, `astro-patterns.md`, `strapi-patterns.md`,
`sanity-patterns.md`, `laravel-api.md`, `sveltekit-patterns.md`, and similar stack-pattern rules
all deploy automatically; there's no filename allowlist to update when a stack adds one.

### Shared JS/TypeScript Rules (Deployed When the Stack Qualifies)
Three more rules come from `projects/common/rules/`, added only when the stack doesn't already
have its own file of the same name:
- `typescript-patterns.md` — **any** stack, when `tsconfig.json` exists
- `design-system.md` and `api-design.md` — the JS-framework stacks only (`nextjs`, `nuxt`,
  `astro`, `astro-sanity`, `astro-strapi`, `astro-tina`, `sveltekit`, `remix`, `t3-stack`,
  `docusaurus`, `craftcms-nextjs`, `craftcms-nuxt`, `ee-nextjs`)

All three carry `paths:` frontmatter, so they only load for matching files: `typescript-patterns.md`
for `**/*.{ts,tsx,mts,cts}`, `design-system.md` for `**/*.{tsx,jsx,vue,svelte,astro,css,scss}` and
`**/tailwind.config.*`, and `api-design.md` for `**/api/**`, `**/server/**`, `**/trpc/**`,
`**/actions/**`, and similar server-side paths.

### Optional Rules (Conditionally Deployed)
Real `.claude/rules/` files, copied only when detected — and only where the stack ships them:
- `tailwind-css.md` → if Tailwind detected
- `alpinejs.md` → if Alpine.js detected
- `bilingual-content.md` → if bilingual patterns detected

### Library References (On-Demand, Not Rules)
Everything else detected (Foundation, SCSS, Bootstrap, Bulma, jQuery, Material UI, vanilla JS,
TypeScript, Zod, tRPC, Prisma, and more — 22 in total) adds a path reference to
`.claude/libraries/<name>.md` in `CLAUDE.md` instead of a rule file — this is separate from, and
in addition to, the `typescript-patterns.md` **rule** above (both are gated on the same
`tsconfig.json` signal, but one lands in `.claude/libraries/` and the other in
`.claude/rules/`). See
[Setup Script → Token & Cost Options](setup-script.md#token--cost-options) and
[Stacks Reference → Deployed to Every Stack](../reference/stacks.md#deployed-to-every-stack).

## Agent Filtering

There's no runtime filtering logic — each stack's `projects/{stack}/agents/` directory is
pre-curated to the specialists relevant to it, and the deploy script copies every file it finds
there. This still keeps a Next.js project from getting a WordPress specialist, because that
agent file simply isn't in `projects/nextjs/agents/` to begin with.

A few illustrative examples (run `ls projects/{stack}/agents/` for the exact, current set):
- `backend-architect.md`, `frontend-architect.md`, `devops-engineer.md`, `security-expert.md`,
  `performance-auditor.md` — shipped by most stacks, but not a guaranteed universal set (e.g.
  `custom` ships none of these; `wordpress` ships no `code-quality-specialist.md`)
- `coilpack-specialist.md`, `craftcms-specialist.md`, `expressionengine-specialist.md`,
  `ee-template-expert.md` — ExpressionEngine/Coilpack stacks
- `nextjs-specialist.md`, `react-specialist.md` — Next.js and other React-based stacks
  (Docusaurus, EE + Next.js, Craft + Next.js)
- `wordpress-specialist.md`, `wordpress-theme-expert.md` — WordPress stacks
- `nuxt-specialist.md` — Craft + Nuxt
- `astro-specialist.md`, `sanity-specialist.md`, `strapi-specialist.md` — Astro + Sanity/Strapi

## Example Output

### Auto-Detected Craft CMS with Tailwind and Alpine.js:
```bash
Detecting stack...
  ✓ Detected stack: craftcms

Scanning project...
  ✓ Found DDEV config
  ✓ Found template group: blog
  ✓ Tailwind CSS detected
  ✓ Alpine.js detected
  ○ No bilingual patterns detected

Copying rules (conditional based on detection)...
  ✓ Copied accessibility.md
  ✓ Copied performance.md
  ✓ Copied craft-templates.md
  ✓ Copied tailwind-css.md
  ✓ Copied alpinejs.md
  ○ Skipped bilingual-content.md (not detected)
```

### Auto-Detected Next.js WITHOUT Tailwind:
```bash
Detecting stack...
  ✓ Detected stack: nextjs

Scanning project...
  ✓ Found package.json
  ○ No Tailwind detected
  ○ No Alpine.js detected
  ○ No bilingual patterns detected

Copying rules (conditional based on detection)...
  ✓ Copied accessibility.md
  ✓ Copied performance.md
  ✓ Copied nextjs-patterns.md
  ○ Skipped tailwind-css.md (not detected)
  ○ Skipped alpinejs.md (not detected)
  ○ Skipped bilingual-content.md (not detected)
```

Both examples are abbreviated — every run also copies (or restores) `memory-management.md`,
`token-optimization.md`, `sensitive-files.md`, and `deployment-safety.md`.

### Discovery Mode for Unknown Stack:
```bash
Detecting stack...
  ○ No known stack detected
  ✓ Using discovery mode

Scanning project...
  ✓ Detected: React, TypeScript, Vite, Vue Router
  ✓ Detected: Tailwind CSS
  ✓ Found 15 technologies

Deploying base configuration...
  ✓ Created discovery prompt
  ✓ Deployed all AI assistant configs

Next: Open in Claude Code and run /project-discover
```

## Benefits

### Zero Configuration Required
- No need to remember stack names or specify `--stack`
- Just point to your project and go
- Works for 18 known stacks automatically, plus `custom` via `--discover`

### Cleaner Configuration
- No unnecessary rules cluttering the `.claude/rules/` directory
- Only relevant AI assistants and configurations deployed
- Easier for developers to focus on what's relevant

### Accurate Context
- AI assistants only see rules for technologies actually in use
- Reduces potential confusion from irrelevant coding standards
- Stack-specific agents only deployed when relevant

### Automatic Adaptation
- As the project evolves and adds a detectable technology, run `--refresh` to pick it up
- Re-detection adds the matching `.claude/libraries/` reference automatically
- No need to remember what stack you originally specified — `--refresh` reads it from `CLAUDE.md`

### Works Everywhere
- Supports known stacks (auto-detect)
- Supports unknown stacks (discovery mode)
- Gracefully handles edge cases

## Manual Override

If you want to force inclusion of a rule, you can:

1. **Copy manually** after setup:
   ```bash
   cp ~/.claude-optimizer/projects/craftcms/rules/alpinejs.md /path/to/project/.claude/rules/
   ```

2. **Modify detection** in `setup-project.sh` to always return true for specific technologies

## Refresh Behavior

When using `--refresh`:
```bash
ai-config --refresh --project=/path/to/project
```

The script will:
- **Auto-detect the stack** from existing configuration (no `--stack` needed!)
- **Re-detect all technologies** (Tailwind, Alpine.js, TypeScript, Zod, etc.)
- **Regenerate `CLAUDE.md`** (if unedited) or refresh its managed blocks and add newly detected
  library references (if you edited it)
- **Update `.claude/libraries/`** — present libraries are refreshed, and a missing one is only
  added back if newly detected (your curation is preserved)
- **Refresh common and stack rules** — the four common rules update when present (and the two
  safety rules are restored if missing); any other rule a fresh deploy would add (the stack's own
  files, plus `typescript-patterns.md` / `design-system.md` / `api-design.md` where they apply)
  is added if it's missing and was never recorded as deployed, and updated when present
- **Re-apply the safety policy, OKF bundle, codegraph/php-lsp registration**

**`--refresh` still does not re-copy the original six stack-pattern rules**
(`expressionengine-templates.md`, `craft-templates.md`, `blade-templates.md`,
`nextjs-patterns.md`, `laravel-patterns.md`, `markdown-content.md`), the core rules
(`accessibility.md`, `performance.md`), or the detection-gated rules (`tailwind-css.md`,
`alpinejs.md`, `bilingual-content.md`) — nor agents/commands/skills or `.vscode/`. Those are only
written on the initial deploy (or `--clean`). If you add Tailwind to an existing project and run
`--refresh`, you still only get the `tailwind.md` **library reference**; to also get the
`tailwind-css.md` **rule**, copy it manually (see [Manual Override](#manual-override)) or
`--clean --force` to redeploy from scratch. See
[Updating Projects](updating-projects.md#how-refresh-decides-additive-updates) for the full
additive-update rules.

## Detection Improvements

Already implemented since this was first written: TypeScript, Zod, Zustand, TanStack Query,
tRPC, Prisma, Supabase, Vitest, Playwright, Framer Motion, shadcn/ui, Pinia, Tina CMS, Bootstrap,
Bulma, jQuery, Material UI, and "vanilla JS, no framework" detection (all auto-inject a library
reference — see [Stacks Reference → Deployed to Every Stack](../reference/stacks.md#deployed-to-every-stack)).
Also since implemented: every `.md` file in a stack's `rules/` directory now deploys (not just a
fixed filename list), plus the shared `typescript-patterns.md` / `design-system.md` /
`api-design.md` rules — see [Rule Categories](#rule-categories) above.

Still open:
- **Specific Craft plugins** (SEOmatic, etc.)
- **WordPress plugins** (ACF, etc.)

## Summary

**Before:** Manual `--stack` required + all rules copied blindly → cluttered configuration

**After:** Auto-detect stack + smart technology detection → clean, targeted configuration

The setup script is now fully automatic and respects what your project actually uses. 🎯

## Quick Reference

```bash
# Auto-detect everything (recommended)
ai-config --project=/path/to/project 

# Discovery mode for unknown stacks
ai-config --project=/path/to/project --discover 

# Manual stack (if auto-detect fails)
ai-config --stack=craftcms --project=/path/to/project 

# Refresh (auto-detects stack from existing config)
ai-config --refresh --project=/path/to/project
```
