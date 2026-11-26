# How it detects a project

ai-config looks at the project's files to work out two things: the **stack** (what the site is built on) and the
**tools** it uses (Tailwind, Alpine.js, TypeScript and so on). Then it gives Claude only what fits.

To see what it finds without changing anything:

```bash
ai-config --dry-run --project=.
```

## The stack

It checks in this order and stops at the first match:

| Stack | It looks for |
|---|---|
| ExpressionEngine | a `system/ee/` folder |
| Coilpack | ExpressionEngine plus Laravel |
| Craft CMS + Nuxt | Craft plus `frontend/nuxt.config.ts` |
| Craft CMS + Next.js | Craft plus `frontend/next.config.js` |
| Craft CMS | the `craft` file and `craftcms/cms` in `composer.json` |
| EE Coilpack + Next.js | Coilpack plus `frontend/next.config.js` |
| WordPress (Bedrock) | Bedrock's folder layout, or `roots/bedrock` in `composer.json` |
| WordPress | `wp-config.php` |
| SvelteKit | `svelte.config.js` |
| Nuxt | `nuxt.config.ts` |
| T3 Stack | Next.js plus Prisma plus tRPC |
| Remix | `remix.config.js`, or `app/root.tsx` with Remix or React Router |
| Astro + Sanity | Astro plus `sanity.config.ts` |
| Astro + Strapi | Astro plus Strapi in `backend/` |
| Astro + Tina | Astro plus `tina/config.ts` |
| Astro | `astro.config.mjs` |
| Next.js | `next.config.js` |
| Docusaurus | `docusaurus.config.js` |

If nothing matches, name the stack with `--stack=<name>`, or use `--discover`. See
[Supported stacks](../reference/stacks.md).

## The tools

ai-config knows more than 50 front-end tools. It finds them in four places:

1. every `package.json`, including theme folders, not just the top one
2. files like `jquery-3.7.1.min.js` or `bootstrap.bundle.min.js`
3. `<script>` and `<link>` tags, and WordPress `wp_enqueue_script` calls
4. markup such as `x-data` (Alpine.js) or `hx-get` (htmx)

It ignores code that belongs to the CMS or to plugins (`node_modules`, `vendor`, ExpressionEngine's system
folders, WordPress core), so it doesn't report tools the site doesn't really use.

If it finds no framework, it says so plainly: "custom JavaScript, no framework detected", with a file count. It
doesn't guess.

## What each finding adds

| Found | Claude gets |
|---|---|
| Any front-end tools | A **Front-End Stack** section in `CLAUDE.md` listing them |
| Tailwind CSS | A Tailwind rule, a library note, and the Tailwind VS Code extension |
| Alpine.js | An Alpine.js rule and a library note |
| French and English content | A bilingual content rule |
| Bootstrap, Foundation, Bulma, jQuery, Material UI, SCSS | A library note |
| TypeScript, Zod, Prisma, tRPC, Vitest, Playwright and others | A library note |
| `tsconfig.json` | A TypeScript rule |
| A `.ddev/config.yaml` | The PHP version, database, URL and project name, filled into `CLAUDE.md` |
| Stash or Structure (ExpressionEngine) | Notes on those add-ons |

Library notes are read only when a task needs them, so extra ones cost nothing in sessions that don't use them.

## Rules load only when they matter

Most rules apply only to certain files. The Tailwind rule, for example, loads when Claude opens a CSS or template
file, not in every session. Each rule says which files it covers in a `paths:` line at the top.

## Added a tool to an existing project?

A refresh notices new tools and adds their library notes:

```bash
ai-config --refresh --project=.
```

The Tailwind, Alpine.js and bilingual **rules** are added only on the first setup. To add one later, copy it
from this repository into the project. Run this from inside the project folder, changing `expressionengine` to
your stack:

```bash
cp ~/.ai-config/projects/expressionengine/rules/tailwind-css.md .claude/rules/
```

Not every stack ships every rule. If yours doesn't have it, copy the one from the closest stack.
