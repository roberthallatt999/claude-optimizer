# Supported stacks

A **stack** is the kind of project: the CMS or framework it's built on. ai-config usually works it out by itself
(see [How it detects a project](../guides/conditional-deployment.md)). To name one yourself, use its name from
the first column:

```bash
ai-config --stack=craftcms --project=.
```

## CMS sites

| Name | What it is | Extra rules |
|---|---|---|
| `expressionengine` | ExpressionEngine 7 | EE templates, accessibility, performance |
| `coilpack` | ExpressionEngine running inside Laravel | Laravel patterns, accessibility, performance |
| `craftcms` | Craft CMS with Twig templates | Craft templates, accessibility, performance |
| `wordpress` | Standard WordPress | WordPress coding standards, WordPress security, accessibility, performance |
| `wordpress-roots` | WordPress on Bedrock, with a Sage theme | Blade templates, accessibility, performance |

## CMS back end with a separate front end

| Name | Back end | Front end | Extra rules |
|---|---|---|---|
| `craftcms-nuxt` | Craft CMS (GraphQL) | Nuxt 3 | Craft GraphQL, Nuxt patterns |
| `craftcms-nextjs` | Craft CMS (GraphQL) | Next.js | Craft GraphQL, Next.js patterns |
| `ee-nextjs` | ExpressionEngine in Coilpack (API) | Next.js | Laravel API, Next.js patterns |
| `astro-strapi` | Strapi | Astro | Astro patterns, Strapi patterns |
| `astro-sanity` | Sanity | Astro | Astro patterns, Sanity patterns |
| `astro-tina` | Tina CMS (content in git) | Astro | Shared rules only |

## JavaScript frameworks

| Name | What it is | Extra rules |
|---|---|---|
| `nextjs` | Next.js 14 or later | Next.js patterns, accessibility, performance |
| `nuxt` | Nuxt 3 (Vue) | Shared rules only |
| `sveltekit` | SvelteKit 2 | SvelteKit patterns |
| `remix` | Remix, or React Router 7 | Shared rules only |
| `t3-stack` | Next.js with tRPC and Prisma | Shared rules only |
| `astro` | Astro on its own | Shared rules only |
| `docusaurus` | Docusaurus 3 documentation sites | Markdown content, accessibility, performance |

## Anything else

| Name | What it is |
|---|---|
| `custom` | Any other project. Use it with `--discover`, then type `/project-discover` in Claude Code to write rules that fit |

## What every stack gets

- the safety rules, the safety guard and the commit check
- `MEMORY.md` (or a `.okf/` folder with `--okf-memory`)
- the shared rules: memory, saving tokens, secret files, deployment safety and engineering practices
- the workflow skills
- library notes for the tools found in the project
- a TypeScript rule when the project has `tsconfig.json`
- on JavaScript stacks, design-system and API-design rules, and the design skills

The "Shared rules only" stacks get everything in this list; they just have no rules of their own on top.

## Extra code help by stack

| Stacks | PHP code help (`php-lsp`) | Code search (codegraph) | Template map (`--okf-memory`) |
|---|---|---|---|
| `expressionengine`, `coilpack`, `craftcms`, `wordpress-roots` | Yes | — | Yes |
| `wordpress` | Yes | — | — |
| `craftcms-nuxt`, `craftcms-nextjs`, `ee-nextjs` | Yes | Yes | Yes |
| The JavaScript stacks and the Astro + CMS stacks | — | Yes | — |

`php-lsp` turns on when Intelephense is installed. codegraph is connected when you've installed it and indexed
the project. See [Connect outside services](../guides/mcp-integration.md).

## Slash commands and skills by stack

See [Slash commands](commands.md).
