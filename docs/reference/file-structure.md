# File Structure

Complete reference for the configuration repository structure.

## Repository Structure

```
claude-optimizer/
├── setup-project.sh              # Main deployment script (aliased ai-config)
├── ai-config-fleet.sh            # Run --doctor/--refresh/--list across many projects
├── serve-docs.sh                 # Documentation server
├── install.sh                    # Installer script
├── update-superpowers.sh         # Pulls the latest superpowers subtree (called on deploy/refresh)
├── run-tests.sh                  # Runs every test-*.sh suite
├── test-*.sh                     # 10 suites: cms-intelligence, fleet, frontend-detection,
│                                  #   install-deps, lifecycle, okf-memory, refresh-additive,
│                                  #   safety-guard, security-policy, stack-detection
├── README.md                     # Overview and quick links
├── CLAUDE.md                     # Repository context for Claude
│
├── .github/workflows/tests.yml   # CI: runs run-tests.sh
│
├── docs/                         # Documentation
│   ├── getting-started/
│   ├── guides/
│   ├── reference/
│   └── development/
│
├── superpowers/                  # Workflow skills system (vendored subtree)
│   ├── skills/                   # 16 skills — see the Superpowers guide for the full list
│   │   ├── brainstorming/
│   │   ├── writing-plans/
│   │   ├── executing-plans/
│   │   ├── systematic-debugging/
│   │   ├── test-driven-development/
│   │   ├── component-scaffolder/
│   │   ├── design-system-builder/
│   │   └── ...
│   ├── commands/                 # 3 deprecated stub commands (point to the equivalent skill)
│   └── hooks/
│       ├── session-start         # Deployed to every project as .claude/hooks/session-start
│       ├── run-hook.cmd
│       └── hooks.json            # Vendored from upstream; NOT deployed (hooks live in settings.local.json)
│
├── libraries/                    # Project-local library references (copied to every project)
│   ├── README.md
│   ├── react.md, vue.md, svelte.md, nextjs.md, nuxt.md, angular.md
│   ├── typescript.md             # Strict mode, utility types, branded IDs
│   ├── tailwind.md, bootstrap.md, bulma.md, foundation.md, scss.md, html5.md
│   ├── shadcn-ui.md              # Radix-based, copy-into-project components
│   ├── alpinejs.md, material-ui.md
│   ├── framer-motion.md          # Motion v11+ animation
│   ├── zustand.md, pinia.md      # React and Vue state management
│   ├── tanstack-query.md         # React Query v5
│   ├── zod.md                    # Schema validation
│   ├── trpc.md                   # End-to-end typesafe APIs
│   ├── prisma.md, supabase.md    # Database / backend
│   ├── vitest.md, playwright.md  # Testing
│   ├── tinacms.md                # Git-based CMS
│   └── vanilla-js.md, jquery.md
│
└── projects/                     # Stack templates
    ├── common/                   # Shared templates and scripts, used by every stack
    │   ├── rules/                # Common rules (deployed to all stacks; see below)
    │   ├── detect-frontend.sh    # Front-end stack detection (CSS/JS frameworks, custom code)
    │   ├── hooks/
    │   │   └── safety-guard.sh   # PreToolUse safety hook (installed in every project)
    │   ├── okf/                  # OKF bundle seeds (index/log/handoff), okf-check.sh, template-map.sh
    │   ├── orchestrator/         # CLAUDE-orchestrator.md, implementer.md (--orchestrator)
    │   ├── security.settings.local.json  # Shared deny/ask rules + hook registration (merged, never copied)
    │   ├── protected-paths.conf   # Universal [deny]/[ignore] paths (each stack adds its own)
    │   ├── safety-guardrails.md  # Managed CLAUDE.md block: safety guardrails
    │   ├── memory-protocol.md    # Managed CLAUDE.md block: memory protocol
    │   ├── okf-memory-protocol.md  # Managed CLAUDE.md block: OKF memory protocol (--okf-memory)
    │   ├── response-style.md     # Managed CLAUDE.md block: concise output defaults
    │   ├── code-index.md         # Managed CLAUDE.md block: codegraph code index
    │   ├── AGENTS.md.template    # Fallback AGENTS.md template (--with-openai)
    │   └── MEMORY.md.template    # Memory bank template (with Design System, Integrations, API inventory)
    ├── sveltekit/                # SvelteKit 2 + Svelte 5 Runes
    ├── remix/                    # Remix / React Router v7
    ├── t3-stack/                 # Next.js + tRPC + Prisma + shadcn/ui
    ├── nuxt/                     # Nuxt 3 standalone
    ├── expressionengine/
    ├── coilpack/
    ├── craftcms/
    ├── craftcms-nuxt/            # Headless Craft CMS + Nuxt
    ├── craftcms-nextjs/          # Headless Craft CMS + Next.js
    ├── ee-nextjs/                # Headless EE Coilpack + Next.js
    ├── astro-tina/               # Astro + Tina CMS (Git-based MDX content)
    ├── astro/                    # Astro standalone
    ├── astro-strapi/             # Astro + Strapi
    ├── astro-sanity/             # Astro + Sanity Studio
    ├── wordpress-roots/
    ├── wordpress/
    ├── nextjs/
    ├── docusaurus/
    └── custom/
```

## Common Rules

The `projects/common/rules/` directory holds the rules that fall back to a shared version for
every stack — deployed even for a stack that ships no `rules/` directory of its own:

```
projects/common/rules/
├── memory-management.md      # Memory protocols + what to log (components, integrations, env vars)
├── token-optimization.md     # Token efficiency (always loaded, no paths: scoping)
├── sensitive-files.md        # Prevents reading credentials/secrets
├── deployment-safety.md      # No unauthorized pushes or production changes
├── okf-memory.md             # OKF bundle protocol (--okf-memory)
├── typescript-patterns.md    # Strict TS, discriminated unions, branded types
├── design-system.md          # Token-first, cva variants, component inventory
└── api-design.md             # Zod at boundaries, response envelopes, auth guards
```

`accessibility.md` and `performance.md` are always copied too, but each stack ships its own
version under `projects/{stack}/rules/` — there is no common fallback for those two.

Three more common rules deploy conditionally, added only when the stack doesn't already have its
own file of that name: `typescript-patterns.md` on **any** stack when `tsconfig.json` exists, and
`design-system.md` / `api-design.md` on the JS-framework stacks (`nextjs`, `nuxt`, `astro`,
`astro-sanity`, `astro-strapi`, `astro-tina`, `sveltekit`, `remix`, `t3-stack`, `docusaurus`,
`craftcms-nextjs`, `craftcms-nuxt`, `ee-nextjs`). Every other `.md` file in a stack's own
`projects/{stack}/rules/` deploys too (not just a fixed filename list) — see
[Stacks Reference](stacks.md#deployed-to-every-stack) for the per-stack rule counts.

Most rule files carry `paths:` frontmatter so they load only for matching files (e.g.
`memory-management.md` loads with `MEMORY.md`); see
[Conditional Deployment](../guides/conditional-deployment.md).

## Superpowers Skills Structure

```
superpowers/
├── skills/                        # 16 skills total
│   ├── brainstorming/
│   ├── writing-plans/
│   ├── executing-plans/
│   ├── systematic-debugging/
│   ├── test-driven-development/
│   ├── dispatching-parallel-agents/
│   ├── using-git-worktrees/
│   ├── finishing-a-development-branch/
│   ├── receiving-code-review/
│   ├── requesting-code-review/
│   ├── subagent-driven-development/
│   ├── using-superpowers/
│   ├── verification-before-completion/
│   ├── writing-skills/
│   ├── design-system-builder/    # Token audit, component inventory, shadcn/ui + cva
│   └── component-scaffolder/     # Typed React/Vue/Svelte component + test generation
├── commands/                      # Deprecated stubs — each just tells you to use the matching skill
│   ├── brainstorm.md              # → superpowers:brainstorming
│   ├── write-plan.md              # → superpowers:writing-plans
│   └── execute-plan.md            # → superpowers:executing-plans
└── hooks/
    └── session-start              # Auto-bootstrap on Claude Code session start (deployed)
```

`memory-management` is not a Superpowers skill — persistent memory is handled by
`.claude/rules/memory-management.md` and the always-on Memory Protocol block in `CLAUDE.md`
(see [Memory System](../guides/memory-system.md)).

## Project Template Structure

Each stack in `projects/{stack}/` contains:

```
projects/expressionengine/
├── CLAUDE.md.template            # Project context template
├── settings.local.json           # Claude Code permissions
│
├── rules/                        # Coding rules
│   ├── accessibility.md
│   ├── expressionengine-templates.md
│   ├── performance.md
│   ├── tailwind-css.md           # Conditional
│   ├── alpinejs.md               # Conditional
│   └── bilingual-content.md      # Conditional
│
├── agents/                       # Agent personas
│   ├── code-quality-specialist.md
│   └── performance-auditor.md
│
├── commands/                     # Slash commands
│   ├── project-analyze.md
│   └── ee-template-scaffold.md
│
├── skills/                       # Knowledge modules
│   ├── alpine-component-builder/
│   ├── ee-stash-optimizer/
│   ├── ee-template-assistant/
│   └── tailwind-utility-finder/
│
└── .vscode/                      # VSCode configuration
    ├── settings.json
    ├── launch.json
    └── tasks.json
```

## Deployed Project Structure

After running `ai-config --project=.`, your project will have:

```
your-project/
├── CLAUDE.md                     # Generated from template (AGENTS.md too, with --with-openai)
├── MEMORY.md                     # Persistent memory bank (or .okf/ with --okf-memory)
│
├── .claude/
│   ├── settings.local.json       # Permissions, MCP config, merged safety policy + hooks
│   ├── settings.json              # Only with --shared-policy (committed safety policy)
│   ├── libraries/                # Project-local framework/library references
│   ├── rules/
│   │   ├── memory-management.md  # Memory protocols
│   │   ├── token-optimization.md # Token efficiency
│   │   ├── sensitive-files.md    # Credential protection
│   │   ├── deployment-safety.md  # No unauthorized pushes or production changes
│   │   └── ...                   # Stack-specific rules
│   ├── agents/
│   ├── commands/
│   │   ├── brainstorm.md         # Superpowers commands (deprecated stubs)
│   │   ├── write-plan.md
│   │   └── execute-plan.md
│   ├── skills/                   # One folder per skill — Claude Code only discovers
│   │   ├── using-superpowers/    # skills one level deep, so these sit directly here
│   │   ├── brainstorming/        # (not nested under a superpowers/ subfolder)
│   │   ├── writing-plans/
│   │   └── ...
│   ├── scripts/                  # okf-check.sh — only with --okf-memory
│   ├── hooks/
│   │   ├── safety-guard.sh       # PreToolUse hook (registered in settings.local.json)
│   │   ├── protected-paths.conf  # Generated [deny] paths the hook blocks (stack-aware)
│   │   └── session-start         # SessionStart hook (registered in settings.local.json)
│   └── ai-config/                # manifest.tsv, backups/, pending/, version — always gitignored
│
├── .claudeignore                 # Generated; advisory (Claude Code doesn't read it) — see setup-script.md
│
├── .vscode/                      # If not --skip-vscode
│   ├── settings.json
│   ├── launch.json
│   └── tasks.json
│
└── (your existing project files)
```

There is no `.claude/hooks/hooks.json` — hooks are registered directly inside
`.claude/settings.local.json` (and `.claude/settings.json` with `--shared-policy`).

## File Types

### Templates (.template)

Files with `.template` extension contain template variables that get replaced during deployment.

**Variables:**
- `{{PROJECT_NAME}}` - Human-readable project name
- `{{PROJECT_SLUG}}` - URL-safe identifier
- `{{PROJECT_PATH}}` - Absolute path to project
- `{{DDEV_NAME}}` - DDEV project name
- `{{DDEV_PRIMARY_URL}}` - Primary URL
- `{{DDEV_DOCROOT}}` - Document root
- `{{DDEV_PHP}}` - PHP version
- `{{DDEV_DB_TYPE}}` - Database type
- `{{DDEV_DB_VERSION}}` - Database version
- `{{TEMPLATE_GROUP}}` - EE template directory
- `{{GIT_MAIN_BRANCH}}` - Default git branch
- `{{GIT_INTEGRATION_BRANCH}}` - Integration branch
- `{{BRAND_GREEN}}` - Brand color hex value
- `{{BRAND_BLUE}}` - Brand color hex value
- `{{BRAND_ORANGE}}` - Brand color hex value
- `{{BRAND_LIGHT_GREEN}}` - Brand color hex value

### Markdown (.md)

Documentation and configuration files:
- `CLAUDE.md` - Project context
- `MEMORY.md` - Persistent memory bank
- Rules, agents, commands, skills

### JSON

Configuration files:
- `settings.local.json` - Claude Code permissions, MCP config, and hook registrations
  (SessionStart, PreToolUse) — there is no separate `hooks.json`
- `.vscode/settings.json` - VSCode settings

## File Permissions

Scripts should be executable:
```bash
chmod +x setup-project.sh
chmod +x serve-docs.sh
chmod +x .claude/hooks/session-start
chmod +x .claude/hooks/safety-guard.sh
```

## Ignored Files

Recommended `.gitignore` for projects:

```gitignore
# AI Configuration (project-specific, not committed)
CLAUDE.md
AGENTS.md
MEMORY.md
MEMORY-ARCHIVE.md
.claude/

# VSCode (optional - some teams commit these)
.vscode/
```

`setup-project.sh` adds these entries itself (append-only) rather than requiring you to write
them by hand. With `--okf-memory` it also adds `.okf/`; with a registered codegraph index,
`.codegraph/`. `--shared-policy` narrows the `.claude/` line to `.claude/*` plus explicit
`!.claude/settings.json` and `!.claude/hooks/safety-guard.sh` exceptions so those two files can
be committed.

Configuration repository `.gitignore`:

```gitignore
# OS
.DS_Store
Thumbs.db

# Editors
*.swp
*.swo
*~

# Test projects
test-*/
```

## File Naming Conventions

- **Templates:** `{filename}.template`
- **Rules:** `kebab-case.md` (e.g., `memory-management.md`)
- **Agents:** `kebab-case.md` (e.g., `code-quality-specialist.md`)
- **Commands:** `kebab-case.md`
- **Skills:** `kebab-case/` directory with `SKILL.md`
- **VSCode:** Standard VSCode naming

## Next Steps

- **[Stacks Reference](stacks.md)** - Stack-specific details
- **[Memory System](../guides/memory-system.md)** - Memory bank guide
- **[Commands Reference](commands.md)** - Available commands
