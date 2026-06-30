# Setup Script Guide

Comprehensive guide to using the `ai-config` command (the global alias for `setup-project.sh`).

## Synopsis

```bash
ai-config [OPTIONS]
```

## Required Options

### --project=\<path>

Target project directory (absolute or relative path, use `.` for current directory).

**Required for all operations.**

## Stack Selection

### Auto-Detect (Recommended)

If you omit `--stack`, the script will automatically detect your project's stack:

```bash
ai-config --project=/path/to/project
```

**Detects:**
- SvelteKit 2
- Remix / React Router v7
- T3 Stack (Next.js + tRPC + Prisma)
- Nuxt 3
- Next.js 14+
- Astro (standalone, + Sanity, + Strapi)
- Docusaurus 3+
- ExpressionEngine 7.x
- Craft CMS (standalone, + Nuxt, + Next.js)
- WordPress / Bedrock
- Coilpack (Laravel + EE hybrid)

### --stack=\<name>

Manually specify the technology stack template to use.

**Available stacks:**
- `sveltekit`
- `remix`
- `t3-stack`
- `nuxt`
- `nextjs`
- `astro` / `astro-sanity` / `astro-strapi`
- `docusaurus`
- `expressionengine`
- `coilpack`
- `craftcms` / `craftcms-nuxt` / `craftcms-nextjs`
- `ee-nextjs`
- `wordpress-roots`
- `wordpress`
- `custom` (used with `--discover`)

**Example:**
```bash
ai-config --stack=expressionengine --project=/path/to/project
```

### --discover

AI-powered discovery mode for projects that don't match a known stack.

```bash
ai-config --discover --project=/path/to/project
```

This will:
1. Detect 50+ technologies (React, Vue, Laravel, Django, Express, etc.)
2. Deploy base Claude Code configuration
3. Deploy memory bank and token optimization
4. Generate a discovery prompt for AI analysis

Then open in Claude Code and run `/project-discover` to generate custom rules.

## Deployment

### What Gets Deployed

Every deployment creates:
- `CLAUDE.md` - Generated from stack template
- `MEMORY.md` - Persistent memory bank
- `.claude/` directory with rules, agents, commands, skills, hooks
- `.claude/libraries/` - Project-local library references
- `.claude/settings.local.json` - Stack-appropriate permissions
- `.vscode/` - Editor settings (unless `--skip-vscode`)

## Memory & Token Optimization

Every deployment includes the memory system:

- `MEMORY.md` - Persistent memory bank (preserved on refresh)
- `.claude/rules/memory-management.md` - Memory update protocols
- `.claude/rules/token-optimization.md` - Token efficiency rules
- `.claude/rules/sensitive-files.md` - Prevents reading credentials and secrets
- `.claude/skills/superpowers/memory-management/` - Memory skill

See [Memory System Guide](memory-system.md) for details.

## Superpowers Skills

Superpowers workflow skills are enabled by default:

### Skill Options

| Flag | Description |
|------|-------------|
| `--no-superpowers` | Disable all Superpowers skills |
| `--superpowers-all` | Deploy all skills (default) |
| `--superpowers-core` | Deploy core skills only |
| `--superpowers-minimal` | Deploy bootstrap skill only |
| `--superpowers-skill=X` | Deploy specific skills (comma-separated) |
| `--skip-superpowers-update` | Don't pull the latest subtree before deploying |

By default, every deploy/refresh first runs `update-superpowers.sh` (best-effort)
to pull the latest vendored skills. See
[Superpowers → Maintaining Superpowers](superpowers.md#maintaining-superpowers-upstream-updates).
Pass `--skip-superpowers-update` to use the already-vendored copy without touching
the network or the optimizer repo.

### Available Skills

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
| `design-system-builder` | Token audit, component inventory, shadcn/ui + cva build |
| `component-scaffolder` | Typed React/Vue/Svelte component generation with tests |

## Update Options

### --refresh

Update configuration files while preserving customizations.

**Behavior:**
- Re-scans project for technology changes
- Regenerates `CLAUDE.md` (re-applying the managed safety-guardrails and
  memory-protocol blocks in place)
- **Preserves `MEMORY.md`** (never overwritten)
- Preserves `.claude/` customizations (rules, agents, and skills are **not**
  re-copied on refresh)
- Updates the vendored Superpowers subtree (best-effort) before deploying skills

**Library references respect your curation.** On refresh, `.claude/libraries/` is
updated, not reset:

- A library that is **already present** is updated to the latest version.
- A library you **deleted** is **not** re-added — unless this refresh newly
  **detects** its technology (e.g. you just added Tailwind, so `tailwind.md`
  comes back).
- Detection-backed libraries (16 total): `typescript.md`, `zod.md`, `zustand.md`,
  `tanstack-query.md`, `trpc.md`, `prisma.md`, `supabase.md`, `vitest.md`,
  `playwright.md`, `framer-motion.md`, `shadcn-ui.md`, `pinia.md`, `tailwind.md`,
  `alpinejs.md`, `foundation.md`, `scss.md`, `tinacms.md`.
- Framework libraries (`react.md`, `vue.md`, `nextjs.md`, …) are stack-implied
  with no runtime signal, so once removed they stay removed.

This means a refresh never silently re-introduces a library you intentionally
curated away — the kind of change that previously required re-running analysis to
undo.

**Example:**
```bash
ai-config --refresh --project=/path/to/project
```

**Note:** Specify `--stack` for refresh if auto-detection fails.

### --force

Overwrite existing files without prompting.

**Warning:** This will replace config files, but still preserves `MEMORY.md`.

### --clean

Remove all existing AI configuration before deploying.

Deletes:
- `CLAUDE.md`, `.claude/`

**Note:** `MEMORY.md` is NOT deleted by `--clean` to preserve project memory.

Use this for a complete fresh start.

## VSCode Options

### --skip-vscode

Skip VSCode configuration deployment.

Use this if you manage `.vscode/` settings separately or don't use VSCode.

### --install-extensions

Auto-install recommended VSCode extensions for your stack.

Installs stack-appropriate extensions:
- **All stacks:** Prettier, EditorConfig
- **PHP stacks:** Intelephense, Xdebug
- **JS stacks:** ESLint
- **Tailwind projects:** Tailwind CSS IntelliSense

Requires the `code` CLI command to be available.

## Other Options

### --dry-run

Preview changes without modifying any files.

**Output shows:**
- What would be created
- What would be overwritten
- Detected technologies
- Template variables

**Example:**
```bash
ai-config --dry-run --stack=expressionengine --project=.
```

### --name=\<name>

Set project name manually instead of deriving from directory name.

### --analyze

Generate analysis prompt for Claude to customize configuration.

Outputs a prompt you can paste into Claude to get customization suggestions.

## OpenAI / API Tools

### --with-openai

Deploy an `AGENTS.md` file for OpenAI Codex and other API-based AI coding tools
(GitHub Copilot Workspace, and similar assistants that read `AGENTS.md`). Opt-in,
disabled by default.

`AGENTS.md` is the OpenAI-ecosystem counterpart to `CLAUDE.md`: it gives those
tools the same project context (identity, local dev commands, git workflow, coding
conventions) that `CLAUDE.md` gives Claude Code. Deploy it when a project is worked
on by both Claude Code **and** OpenAI/Codex-based tools.

**Template resolution:** the script uses the stack-specific
`projects/<stack>/AGENTS.md.template` when one exists, falling back to
`projects/common/AGENTS.md.template`. Template variables (`{{PROJECT_NAME}}`,
`{{GIT_MAIN_BRANCH}}`, etc.) are substituted the same way as in `CLAUDE.md`.

**Refresh:** unlike `--orchestrator`, this flag is **not** sticky — pass
`--with-openai` again on `--refresh` to regenerate `AGENTS.md`. (It is regenerated
from the template, so local edits to a deployed `AGENTS.md` are overwritten.)

**Example:**
```bash
ai-config --project=. --with-openai
```

## Model Orchestration

### --orchestrator

Deploy the **Opus orchestrator + Sonnet implementer** pattern (opt-in, disabled by default).

When enabled, the script:

- Pins the main session to Opus (`model: "opus"` in `settings.local.json`)
- Forces every subagent to Sonnet (`CLAUDE_CODE_SUBAGENT_MODEL=sonnet`), which wins over
  any subagent's own `model:` frontmatter, so delegated work never consumes the Opus quota
- Deploys an `implementer` subagent (Sonnet) to `.claude/agents/implementer.md`
- Appends a **Model & Delegation Policy** block to `CLAUDE.md`

The intent: Opus reasons, plans, architects, and reviews in the main thread; routine
implementation, scaffolding, and refactors are delegated to the Sonnet `implementer`.

**Refresh is sticky:** once deployed, `--refresh` re-applies the pattern automatically
(detected via `.claude/agents/implementer.md` or the `CLAUDE_CODE_SUBAGENT_MODEL` env key),
so you don't need to re-pass `--orchestrator`. Requires `jq` for the settings injection.

**Example:**
```bash
ai-config --project=. --orchestrator
```

## Safety Guardrails (Always Deployed)

Every deploy and refresh — for **all** stacks, with no flag required — writes a
non-negotiable **Operational Safety Guardrails** block into the project's
`CLAUDE.md` (and `AGENTS.md` when `--with-openai` is used). It is wrapped in
managed markers, so refreshes update it in place rather than duplicating it.

The block instructs the AI assistant to:

1. **Never read secrets or confidential data** — `.env`/`.env.*`, credentials,
   keys, certs, tokens, usernames, passwords (full patterns in
   `.claude/rules/sensitive-files.md`).
2. **Never push to GitHub without explicit, per-action approval** — local commits
   are fine; `git push`, PRs, and tag pushes are not.
3. **Never change a production environment without explicit permission** — no
   migrations, writes, deploys, or destructive commands against production.

These are reinforced at two layers:

- **Awareness:** the always-loaded `CLAUDE.md` block (source:
  `projects/common/safety-guardrails.md`).
- **Reference rules:** `.claude/rules/deployment-safety.md` and
  `.claude/rules/sensitive-files.md`.
- **Enforcement:** the `deny` list in `.claude/settings.local.json` blocks reads of
  `.env`, keys, certs, and other secret files at the permission layer.

## Project Detection

The script automatically detects:

### DDEV Configuration
- Project name, document root, PHP version, database type and version, primary URL

### Modern Web Tooling (triggers auto-injection of library docs)
- **TypeScript** — `tsconfig.json` at project root
- **Zod** — `zod` in `package.json`
- **Zustand** — `zustand` in `package.json`
- **TanStack Query** — `@tanstack/react-query` in `package.json`
- **tRPC** — `@trpc/server` in `package.json`
- **Prisma** — `prisma/schema.prisma` file or `@prisma/client` in `package.json`
- **Supabase** — `@supabase/supabase-js` or `@supabase/ssr` in `package.json`
- **Vitest** — `vitest` in `package.json`
- **Playwright** — `playwright.config.ts/js` or `@playwright/test` in `package.json`
- **Framer Motion** — `framer-motion` or `motion` in `package.json`
- **shadcn/ui** — `components/ui/` directory (root, `src/`, or `app/`)
- **Pinia** — `pinia` in `package.json`
- **Tina CMS** — `tina/config.ts/js` or `tinacms` in `package.json`

### CSS / Styling
- **Tailwind CSS** — `tailwind.config.*` or `tailwindcss` in `package.json`
- **Foundation** — `foundation-sites` in `package.json`
- **SCSS/Sass** — `sass` or `node-sass` in `package.json`, or `.scss` files
- **Alpine.js** — `alpinejs` in `package.json` or `x-data`/`@click` in templates

### CMS / Template Engines
- **ExpressionEngine** — `system/ee/` directory
- **Craft CMS** — `craft` executable
- **Blade** — `.blade.php` files
- **Twig** — `.twig` files

### Content Patterns
- **Bilingual** — French language strings or `lang:` tags
- **Stash add-on** — `exp:stash` tags (ExpressionEngine)
- **Structure add-on** — `exp:structure` tags (ExpressionEngine)

## Examples

### Auto-Detect Any Project (Recommended)

```bash
ai-config --project=/Users/dev/myproject
```

### First-Time Setup (Manual Stack)

```bash
ai-config \
  --stack=expressionengine \
  --project=/Users/dev/myproject
```

### Discovery Mode for Unknown Stack

```bash
ai-config --discover --project=/Users/dev/my-vue-app
```

### Current Directory Shortcut

```bash
cd /path/to/project
ai-config --project=.
```

### Update After Technology Changes

```bash
ai-config --refresh --project=/Users/dev/myproject
```

### Force Clean Reinstall

```bash
ai-config \
  --clean \
  --force \
  --stack=craftcms \
  --project=.
```

### Preview Without Changes

```bash
ai-config --dry-run --project=../my-nextjs-app
```

### Skip VSCode, Install Extensions

```bash
ai-config --project=. --skip-vscode
ai-config --project=. --install-extensions
```

### Core Skills Only

```bash
ai-config --project=. --superpowers-core
```

### Deploy AGENTS.md for OpenAI / Codex

```bash
ai-config --project=. --with-openai
```

### Opus Orchestrator + Sonnet Implementer

```bash
ai-config --project=. --orchestrator
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid options or missing requirements |
| 2 | Project directory doesn't exist |
| 3 | Stack not found |

## Troubleshooting

### "Unknown option" Error

Make sure to use `=` syntax for values:
```bash
# Correct
--stack=expressionengine

# Incorrect
--stack expressionengine
```

### "Could not detect stack" Error

The script couldn't automatically identify your project's stack. Options:

1. **Specify manually:** Use `--stack=<name>` if it's a known stack
2. **Use discovery mode:** Run with `--discover` for unknown stacks
3. **Check project:** Ensure project has recognizable files (e.g., `system/ee/`, `craft`, `wp-config.php`, `next.config.js`)

### Technology Not Detected

Detection scans template files only (excluding `node_modules`, `vendor`). If technology isn't detected:
1. Ensure config files are in project root
2. Check template files contain the expected patterns
3. Use `--dry-run` to see detection results

## Next Steps

- **[Memory System](memory-system.md)** - Persistent context guide
- **[Installation](../getting-started/installation.md)** - Shell aliases and VSCode CLI setup
- **[Conditional Deployment](conditional-deployment.md)** - Detection logic
- **[Updating Projects](updating-projects.md)** - Update workflows
