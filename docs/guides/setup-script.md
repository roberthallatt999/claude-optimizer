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
- Astro (standalone, + Sanity, + Strapi, + Tina CMS)
- Docusaurus 3+
- ExpressionEngine 7.x (standalone, + Coilpack, + Coilpack/Next.js)
- Craft CMS (standalone, + Nuxt, + Next.js)
- WordPress / Bedrock (standalone, + Sage/Roots)

### --stack=\<name>

Manually specify the technology stack template to use.

**Available stacks:**
- `sveltekit`
- `remix`
- `t3-stack`
- `nuxt`
- `nextjs`
- `astro` / `astro-sanity` / `astro-strapi` / `astro-tina`
- `docusaurus`
- `expressionengine`
- `coilpack`
- `craftcms` / `craftcms-nuxt` / `craftcms-nextjs`
- `ee-nextjs`
- `wordpress-roots`
- `wordpress`
- `custom` (used with `--discover`)

Run `./setup-project.sh --help` for the exact, current list (also printed at the bottom of its
output).

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
- `.claude/settings.local.json` - Stack-appropriate permissions plus the shared
  safety policy (deny/ask rules, safety-guard hook registration)
- `.claude/hooks/safety-guard.sh` - PreToolUse hook enforcing the safety guardrails
- `.vscode/` - Editor settings (unless `--skip-vscode`)

## Memory & Token Optimization

Every deployment includes the memory system and token-saving defaults:

- `MEMORY.md` - Persistent memory bank (preserved on refresh)
- **Response Style block** in `CLAUDE.md` - concise-output defaults: lead with the
  answer, no narration or recaps, `path:line` references instead of pasted code.
  Output tokens are the most expensive, so this is on by default.
- **On-demand library references** - `@.claude/libraries/*.md` imports are rewritten
  to plain path references. `@imports` expand into context in every session; a path
  reference is read only when the task involves that library.
- **Path-scoped rules** - stack rules carry `paths:` frontmatter and load only when
  Claude works with matching files (`memory-management.md` loads with `MEMORY.md`,
  `sensitive-files.md` / `deployment-safety.md` with config and deploy files).
- `.claude/rules/token-optimization.md` - Compact context-efficiency habits (always loaded)
- **Superpowers de-duplication** - when the superpowers plugin is enabled in
  `~/.claude/settings.json`, the project copy is skipped because it would inject the
  same bootstrap and skill list a second time. An explicit `--superpowers-*` flag
  deploys it anyway.

### Token & cost options

| Flag | Effect |
|------|--------|
| `--no-response-style` | Omit the Response Style block (removes it on `--refresh`) |
| `--eager-libraries` | Keep `@.claude/libraries/*.md` imports (loaded every session) |
| `--effort=<level>` | Set `effortLevel` (`low`, `medium`, `high`, `xhigh`, `max`) in `settings.local.json` |
| `--okf-memory` | Store project memory as an OKF bundle in `.okf/` instead of `MEMORY.md` (see [Memory System Guide](memory-system.md)) |

For JavaScript-framework stacks, an installed [codegraph](https://github.com/colbymchenry/codegraph)
with an existing `.codegraph/` index is registered automatically at local MCP scope; nothing is
installed (see [MCP Integration](mcp-integration.md#code-index-codegraph)).

For PHP stacks (ExpressionEngine, Coilpack, Craft, WordPress, Bedrock/Sage, and the headless
Craft/EE backends), when [Intelephense](https://intelephense.com/) is on PATH the official
`php-lsp` plugin is enabled for the project with
`claude plugin install php-lsp@claude-plugins-official --scope local` (writes only the
gitignored `settings.local.json`). Claude then gets go-to-definition, references, and
diagnostics for themes, plugins, modules, and add-ons. An explicit `true`/`false` for the plugin
in project or user settings is always respected. Install Intelephense with
`npm install -g intelephense`, then `--refresh`. Templates (EE tags, Twig, Blade) are covered by
the template map in `--okf-memory` projects (see [Memory System Guide](memory-system.md)).

## Prerequisites and Health Check

Every deploy and refresh first checks for the tools it relies on — `jq`, `perl`, `awk`, `sed`,
`find`, `cmp`, `mktemp`, and `shasum`/`sha256sum`. If one is missing the run stops before
changing anything, because the safety policy merge and the additive update rules depend on them.

### --install-deps

Install what the project needs before the run starts:

```bash
ai-config --project=/path/to/project --install-deps
```

| Installs | When | How |
|---|---|---|
| `jq`, `perl`, `awk`, `sed`, `find`, `cmp`, `mktemp`, `shasum`/`sha256sum` | missing | System package manager |
| `git` | missing | System package manager |
| Node.js + npm | PHP stack and npm missing | System package manager |
| Intelephense (for `php-lsp`) | PHP stack | `npm install -g intelephense` |

- **Package managers:** Homebrew on macOS; `apt-get` (runs `apt-get update` and retries if
  the first install fails), `dnf`, `yum`, `pacman`, `zypper`, or `apk` on Linux. System
  managers run through `sudo` when you aren't root. Override detection with
  `AI_CONFIG_PKG_MANAGER=<manager>` (or `none`).
- **Confirmation:** the exact commands are shown first; on a terminal you're asked before
  anything installs, unless `--force`. `--dry-run` shows the plan and installs nothing.
- **Never done:** installing a package manager, piping a remote install script (so codegraph
  and Claude Code itself stay manual — the run names them), or running npm with `sudo` (for an
  npm permissions error, use a user-owned prefix).

If a required tool still can't be installed, the preflight stops the run as usual.

After writing, a health check verifies the result works, printing only problems:

- `settings.local.json` is valid JSON and contains every shared deny/ask rule
- `safety-guard.sh` is registered, executable, and **actually blocks** a test `cat .env` call
- the SessionStart hook script exists when it's registered
- `CLAUDE.md` has the Safety Guardrails and memory protocol blocks; the safety rules exist
- the OKF bundle is conformant (`--okf-memory` projects)
- codegraph (JS stacks) and php-lsp/Intelephense (PHP stacks) are consistent with what's configured
- `.claude/ai-config/` is gitignored

A failing check (✗) makes the run exit 1. Run the same checks any time, read-only and with
passing checks listed too:

```bash
ai-config --doctor --project=/path/to/project
```

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

16 skills total, deployed to `.claude/skills/<skill>/`. See
[Superpowers → Available Skills](superpowers.md#available-skills) for the full, categorized
list — `brainstorming`, `writing-plans`, `executing-plans`, `verification-before-completion`,
`systematic-debugging`, `test-driven-development`, `requesting-code-review`,
`receiving-code-review`, `dispatching-parallel-agents`, `subagent-driven-development`,
`using-git-worktrees`, `finishing-a-development-branch`, `using-superpowers`, `writing-skills`,
`component-scaffolder`, `design-system-builder`.

## Update Options

### --refresh

Update configuration files while preserving customizations.

**Behavior:**
- Re-scans project for technology changes
- **Additive only.** A file you edited is kept and its new version staged in
  `.claude/ai-config/pending/`; an unedited file is updated; anything modified is backed
  up to `.claude/ai-config/backups/<run>/` first (see
  [Updating Projects](updating-projects.md#how-refresh-decides-additive-updates))
- Regenerates `CLAUDE.md` if unedited; otherwise refreshes only its managed blocks
  (safety guardrails, memory protocol, response style, front-end stack, code index, and the
  orchestrator policy when `--orchestrator` is active)
- Adds the shared safety policy to `settings.local.json` (nothing removed) and the
  `.claude/hooks/safety-guard.sh` hook
- **Preserves `MEMORY.md`** (never modified)
- Agents, commands, and skills are not re-copied on refresh. Rules are additive: the four common
  rules (`token-optimization.md`, `memory-management.md`, `sensitive-files.md`,
  `deployment-safety.md`) update if present and unedited, the two safety rules are restored if
  missing, and any stack rule a fresh deploy would add — including `typescript-patterns.md` /
  `design-system.md` / `api-design.md` where they apply — is added once if it's missing and was
  never deployed before, then kept in sync while present. The original six stack-pattern rules
  (`expressionengine-templates.md`, `craft-templates.md`, `blade-templates.md`,
  `nextjs-patterns.md`, `laravel-patterns.md`, `markdown-content.md`), `accessibility.md` /
  `performance.md`, and the detection-gated rules (`tailwind-css.md`, `alpinejs.md`,
  `bilingual-content.md`) are still only written on the initial deploy
- Updates the vendored Superpowers subtree (best-effort) before deploying skills

**Library references respect your curation.** On refresh, `.claude/libraries/` is
updated, not reset:

- A library that is **already present** is updated to the latest version.
- A library you **deleted** is **not** re-added — unless this refresh newly
  **detects** its technology (e.g. you just added Tailwind, so `tailwind.md`
  comes back).
- Detection-backed libraries (22 total): `typescript.md`, `zod.md`, `zustand.md`,
  `tanstack-query.md`, `trpc.md`, `prisma.md`, `supabase.md`, `vitest.md`,
  `playwright.md`, `framer-motion.md`, `shadcn-ui.md`, `pinia.md`, `tailwind.md`,
  `alpinejs.md`, `scss.md`, `tinacms.md`, `foundation.md`, `bootstrap.md`, `bulma.md`,
  `jquery.md`, `material-ui.md`, `vanilla-js.md`.
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

Skip the confirmation prompts. Updates stay additive: files you edited are kept (new
versions staged in `.claude/ai-config/pending/`), unedited files are updated with a backup,
and `MEMORY.md` is never modified.

### --apply-pending

Adopt the staged new versions in `.claude/ai-config/pending/`, backing up each file it
replaces. Review first with `diff <file> .claude/ai-config/pending/<file>`.

### --clean

Start from a fresh configuration without deleting anything: `CLAUDE.md` and `.claude/` are
moved to `.claude/ai-config/backups/<run>/` before deploying. `MEMORY.md` stays in place.

### --uninstall

Remove ai-config from a project without losing work:

```bash
ai-config --uninstall --project=/path/to/project     # add --dry-run to preview
```

- **Removed:** shipped files still identical to what ai-config wrote (per the manifest), an unedited
  generated `CLAUDE.md` / `AGENTS.md`, the shared deny/ask rules, and the safety-guard and
  session-start hook registrations (in `settings.local.json` and a shared `settings.json`).
- **Stripped:** the managed blocks from an edited `CLAUDE.md` / `AGENTS.md`; your own text stays.
- **Kept:** files you edited, `MEMORY.md`, the `.okf/` bundle, `.gitignore` entries, other settings
  (model, env, enabledPlugins, effortLevel), and plugin/MCP registrations — the commands to remove
  codegraph or php-lsp are printed.

Everything removed or changed is backed up to `.claude/ai-config/backups/<run>/` first. A deny rule
of your own that exactly matches a shared policy rule is removed with it; the backup has it.

### --shared-policy

By default everything ai-config writes is gitignored, so teammates on the same repo get no
guardrails. `--shared-policy` also merges the deny/ask rules and the safety-guard hook into the
committed `.claude/settings.json`, and adjusts `.gitignore` so `.claude/settings.json` and
`.claude/hooks/safety-guard.sh` can be committed while the rest of `.claude/` stays ignored (an exact
`.claude/` line becomes `.claude/*`, backed up first). Commit those two files yourself. The mode is
sticky once `.claude/settings.json` carries the hook, and `--doctor` checks both files are
committable.

## Managing Multiple Projects

`ai-config-fleet` (aliased from `ai-config-fleet.sh`) runs `setup-project.sh` across every
ai-config project under a folder — `--doctor` by default, or `--refresh` / `--list` — and prints
one pass/warn/fail summary instead of running each project by hand:

```bash
ai-config-fleet --root=~/sites --list
ai-config-fleet --root=~/sites --refresh --dry-run
```

See [Updating Projects → Updating Multiple Projects](updating-projects.md#updating-multiple-projects)
for the full flag set and output format.

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

### --slug=\<slug>

Set the `{{PROJECT_SLUG}}` template variable manually instead of deriving it from the project
name.

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

These are reinforced at three layers:

- **Awareness:** the always-loaded `CLAUDE.md` block (source:
  `projects/common/safety-guardrails.md`), which also tells Claude not to route
  around a blocked call. Detail lives in the path-scoped
  `.claude/rules/deployment-safety.md` and `.claude/rules/sensitive-files.md`.
- **Permission rules:** `projects/common/security.settings.local.json` is merged into
  every project's `settings.local.json` on deploy and `--refresh`:
  - `deny` — reads of `.env`, keys, certs, credentials, DB configs and snapshots
    (Claude Code also applies these to Grep/Glob and common Bash file commands).
  - `ask` — `git push`, PR create/merge, package publishing, `vercel --prod`,
    `ddev push`, `terraform apply`, `git reset --hard`, `rm`, and similar. `ask`
    beats `allow` and still prompts in bypass-permissions mode.
  - Nothing is removed: an existing `allow` entry that overlaps (e.g. a legacy
    `Bash(git push:*)`) stays, `ask`/`deny` take precedence, and refresh reports it.
  - `enableAllProjectMcpServers` defaults to `false` (only servers listed in
    `enabledMcpjsonServers` start automatically); an existing value is kept, with a
    warning when it is `true`.
- **Hook:** `.claude/hooks/safety-guard.sh` (PreToolUse on Bash and file tools) catches
  what prefix-based rules can't — `bash -c "git push"`, `source .env`,
  `base64 < key.pem`, `rsync` to a remote host, cloud/infra CLIs, destructive SQL and
  git, and edits to `.claude/settings*.json` or `.claude/hooks/`. Secret access and
  catastrophic deletes are denied; publishing, production, and irreversible operations
  prompt. Hooks run in every permission mode and inside subagents. Tests: `test-safety-guard.sh`.
- **MCP tools:** the same hook covers `mcp__*` tools. A tool whose name signals an outward or
  destructive action (push, merge, deploy, send, buy, delete, create, write, …) prompts, as does a
  SQL tool running a write query; read tools (`get_pull_request`, `list_deployments`, SELECT queries)
  and local browser automation pass. On refresh, the managed hook entry's matcher is updated to
  include MCP tools.
- **Secrets in written code:** Write/Edit/MultiEdit/NotebookEdit content containing a real-looking
  credential (private keys, AWS/GitHub/Stripe/Slack/Google/Anthropic/OpenAI tokens) prompts, with a
  reminder to reference an environment variable instead.

Requires `jq`; the script reports an error when it is missing.

## Protected Paths (Stack-Aware)

On top of the stack-agnostic policy above, every deploy and `--refresh` resolves a
**protected-path list for the detected stack** and applies it. The source is two files:

```
projects/common/protected-paths.conf     # universal baseline
projects/<stack>/protected-paths.conf    # what this stack needs on top
```

### Two tiers

Protecting a path means two different things, and conflating them is a mistake —
denying `node_modules/` or `dist/` breaks ordinary debugging.

| Tier | What belongs in it | What happens |
| --- | --- | --- |
| `[deny]` | Secrets, credentials, database dumps, `.git/` internals | A `Read()` rule in `settings.local.json` **and** a pattern in `.claude/hooks/protected-paths.conf`, which `safety-guard.sh` blocks for file tools *and* for Bash commands that name the path. A hard stop. |
| `[ignore]` | Dependencies, build output, lockfiles, binary assets | Written to `.claudeignore` only. Never denied — these are token sinks, not secrets. |

A stack may promote a baseline `[ignore]` pattern to `[deny]`. The CMS stacks do this
with `*.sql`: on a WordPress, ExpressionEngine, Craft or Coilpack site a loose `.sql`
file is a database dump, while on a JS stack it is far more likely a Prisma, Drizzle or
Knex migration — which stays readable.

### What each stack adds

| Stack | Blocked (beyond the baseline) | Advisory |
| --- | --- | --- |
| `wordpress` | `wp-config.php`, `wp-salt.php`, `wp-content/backup*/`, `ai1wm-backups/`, `updraft/`, `*.sql` | `wp-admin/`, `wp-includes/`, `wp-content/uploads/`, `cache/` |
| `wordpress-roots` | `config/environments/`, `web/app/backup*/`, `*.sql` | `web/wp/`, `web/app/uploads/`, Sage `public/`, `dist/` |
| `expressionengine` | `system/user/config/`, `*.sql` | `system/ee/`, `themes/ee/`, `system/user/cache/`, `images/uploads/` |
| `coilpack` | `system/user/config/`, `storage/framework/sessions/`, `storage/logs/`, `*.sql` | `system/ee/`, `bootstrap/cache/`, `public/build/` |
| `craftcms` (+ headless) | `storage/backups/`, `storage/logs/`, `storage/runtime/validation.key`, `*.sql` | `storage/runtime/`, `web/cpresources/` |
| `nextjs`, `t3-stack` | `.vercel/project.json`, `prisma/*.db` | `.next/`, `.vercel/`, `out/` |
| `nuxt`, `sveltekit`, `remix`, `astro`, `docusaurus` | — | `.nuxt/`, `.output/`, `.svelte-kit/`, `.astro/`, `.docusaurus/`, `build/`, `dist/` |
| `astro-strapi` | `backend/.env`, `backend/.tmp/` | `backend/build/`, `backend/public/uploads/` |
| `astro-sanity` | `.sanity/`, `sanity.cli.env*` | `dist-studio/` |
| `astro-tina` | Tina Cloud prebuild config | `.tina/`, `tina/__generated__/` |

The baseline itself covers `.env*`, `credentials*`, `secrets*`, `.git/`, `*.sqlite`,
`*.db`, `*.dump`, `*dump*.sql`, `dumps/`, `db_snapshots/` in `[deny]`, and
dependencies, build output, lockfiles, media and editor noise in `[ignore]`.

### About `.claudeignore`

`.claudeignore` is **advisory**. Claude Code does not read it — the feature request
([anthropics/claude-code#29455](https://github.com/anthropics/claude-code/issues/29455))
is still open, and a `.claudeignore` on disk is silently ignored. Enforcement comes
entirely from the deny rules and the hook.

It is still generated, because it documents what the project treats as off-limits in
one readable place and works with other tools that read gitignore-syntax exclude files.
The generated header says so, so nobody mistakes it for a control.

| Flag | Effect |
| --- | --- |
| `--no-claudeignore` | Don't write `.claudeignore`. The deny rules and `.claude/hooks/protected-paths.conf` are applied either way. |

### Customising

Both generated files go through the same additive install as every other shipped file:
edit them and `--refresh` keeps your version, staging its own in
`.claude/ai-config/pending/`. To change what every project gets, edit the `.conf`
files in this repository — no script changes needed.

`--doctor` reports a missing or out-of-date `.claude/hooks/protected-paths.conf` and
runs the hook against a test database dump. `--uninstall` withdraws the deny rules it
added, using the conf the project was actually deployed with (so the right stack's
rules go, even without `--stack`).

Tests: `test-protected-paths.sh`.

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

### Front-End Stack

`projects/common/detect-frontend.sh` looks for every front-end technology it knows, in four places:

1. **Every `package.json`**, including theme folders (`wp-content/themes/*`, `web/app/themes/*`) and
   `frontend/` — not just the project root
2. **Vendored asset files**, e.g. `assets/js/jquery-3.7.1.min.js` or `bootstrap.bundle.min.js`
3. **Template references**: CDN `<script>` / `<link>` tags and `wp_enqueue_script` /
   `wp_enqueue_style` calls, including dependencies such as `array('jquery')`
4. **Markup attributes**: `x-data` (Alpine.js), `hx-get` / `hx-post` (htmx)

| Category | Detected |
|---|---|
| CSS frameworks | Tailwind CSS, Bootstrap, Foundation, Bulma, UIkit, daisyUI, Pure.css, Materialize, Fomantic/Semantic UI, UnoCSS |
| CSS tooling | Sass/SCSS, Less, PostCSS, Stylus, styled-components, Emotion |
| UI components | Material UI, Chakra UI, Mantine, Ant Design, Radix UI, Headless UI, Vuetify, PrimeVue/PrimeReact |
| JS frameworks | React, Vue, Svelte, Angular, Preact, SolidJS, Lit, Alpine.js, htmx, Stimulus, Turbo |
| JS libraries | jQuery, GSAP, Swiper, Slick, Splide, Chart.js, Three.js, AOS |
| Build tools | Vite, webpack, Laravel Mix, Bud, Parcel, esbuild, Rollup, Gulp, Grunt |
| Language | TypeScript |

Versions come from `package.json` or the file/CDN name. Libraries bundled by CMS core or third-party
code are ignored: `node_modules`, `vendor`, EE `system/ee` / `themes/ee` / `themes/user` / add-ons,
Craft `cpresources`, WordPress core and plugins, build output, uploads, and caches.

When no framework is found, the script says so instead of guessing — for example *"custom
JavaScript, no framework detected (12 file(s), mainly in public/assets/js/)"*. First-party counts
skip minified, vendored, and build-config files.

The result appears in the scan summary and in a short **Front-End Stack** managed block in
`CLAUDE.md` (and `AGENTS.md`), so Claude works within the project's real stack. The block only
changes when the detected stack changes. Detected Tailwind CSS, Alpine.js, Foundation, SCSS,
Bootstrap, Bulma, jQuery, Material UI, and custom-JS projects also get the matching
`.claude/libraries/` references and conditional rules.

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
| 1 | Any error — invalid options, missing project directory, unknown stack, or a failing `--doctor`/post-run health check |

The script only ever exits `0` or `1`; there's no separate code per error type.

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
- **[Updating Projects](updating-projects.md)** - Update workflows, including
  [multiple projects at once](updating-projects.md#updating-multiple-projects)
- **[Contributing](../development/contributing.md)** - Run `./run-tests.sh` (or a single suite,
  e.g. `./run-tests.sh fleet`) before submitting a change to `setup-project.sh`
