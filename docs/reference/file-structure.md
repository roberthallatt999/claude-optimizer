# File Structure

Complete reference for the configuration repository structure.

## Repository Structure

```
claude-optimizer/
├── setup-project.sh              # Main deployment script
├── serve-docs.sh                 # Documentation server
├── install.sh                    # Installer script
├── README.md                     # Overview and quick links
├── CLAUDE.md                     # Repository context for Claude
│
├── docs/                         # Documentation
│   ├── getting-started/
│   ├── guides/
│   ├── reference/
│   └── development/
│
├── superpowers/                  # Workflow skills system
│   ├── skills/                   # All available skills
│   │   ├── memory-management/
│   │   ├── brainstorming/
│   │   ├── writing-plans/
│   │   ├── executing-plans/
│   │   ├── systematic-debugging/
│   │   ├── test-driven-development/
│   │   └── ...
│   ├── commands/                 # Slash commands
│   └── hooks/                    # Session hooks
│
├── libraries/                    # Project-local library references (30+ files)
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
│   ├── tinacms.md                # Git-based CMS (auto-injected when detected)
│   └── vanilla-js.md, jquery.md
│
└── projects/                     # Stack templates
    ├── common/                   # Global fallback templates
    │   ├── rules/                # Common rules (deployed to all/most stacks)
    │   │   ├── memory-management.md
    │   │   ├── token-optimization.md
    │   │   ├── sensitive-files.md
    │   │   ├── deployment-safety.md
    │   │   ├── accessibility.md
    │   │   ├── performance.md
    │   │   ├── typescript-patterns.md  # Strict TS, discriminated unions
    │   │   ├── design-system.md        # Token-first design, cva variants
    │   │   └── api-design.md           # Zod validation, response envelopes
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

The `projects/common/rules/` directory contains rules deployed to all stacks:

```
projects/common/rules/
├── memory-management.md      # Memory protocols + what to log (components, integrations, env vars)
├── token-optimization.md     # Token efficiency
├── sensitive-files.md        # Prevents reading credentials/secrets
├── deployment-safety.md      # No unauthorized pushes or production changes
├── accessibility.md          # WCAG AA compliance
├── performance.md            # Core web vitals and perceived performance
├── typescript-patterns.md    # Strict TS, discriminated unions, branded types (modern JS stacks)
├── design-system.md          # Token-first, cva variants, component inventory (modern JS stacks)
└── api-design.md             # Zod at boundaries, response envelopes, auth guards (modern JS stacks)
```

## Superpowers Skills Structure

```
superpowers/
├── skills/
│   ├── memory-management/
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
├── commands/
│   ├── brainstorm.md
│   ├── write-plan.md
│   └── execute-plan.md
└── hooks/
    └── session-start              # Auto-bootstrap on Claude Code session start
```

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
├── CLAUDE.md                     # Generated from template
├── MEMORY.md                     # Persistent memory bank
│
├── .claude/
│   ├── settings.local.json       # Permissions + MCP config
│   ├── libraries/                # Project-local framework/library references
│   ├── rules/
│   │   ├── memory-management.md  # Memory protocols
│   │   ├── token-optimization.md # Token efficiency
│   │   ├── sensitive-files.md    # Credential protection
│   │   └── ...                   # Stack-specific rules
│   ├── agents/
│   ├── commands/
│   │   ├── brainstorm.md         # Superpowers commands
│   │   ├── write-plan.md
│   │   └── execute-plan.md
│   ├── skills/
│   │   └── superpowers/          # Workflow skills
│   │       ├── memory-management/
│   │       ├── brainstorming/
│   │       ├── writing-plans/
│   │       └── ...
│   └── hooks/                    # Session hooks
│       ├── hooks.json
│       └── session-start.sh
│
├── .vscode/                      # If not --skip-vscode
│   ├── settings.json
│   ├── launch.json
│   └── tasks.json
│
└── (your existing project files)
```

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
- `settings.local.json` - Claude Code permissions and MCP config
- `.vscode/settings.json` - VSCode settings
- `.claude/hooks/hooks.json` - Session hooks

## File Permissions

Scripts should be executable:
```bash
chmod +x setup-project.sh
chmod +x serve-docs.sh
chmod +x .claude/hooks/session-start.sh
```

## Ignored Files

Recommended `.gitignore` for projects:

```gitignore
# AI Configuration (project-specific, not committed)
CLAUDE.md
MEMORY.md
MEMORY-ARCHIVE.md
.claude/

# VSCode (optional - some teams commit these)
.vscode/
```

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
