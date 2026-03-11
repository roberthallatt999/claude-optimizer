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
├── libraries/                    # Project-local library references
│   ├── README.md
│   ├── react.md
│   ├── vue.md
│   ├── nextjs.md
│   ├── nuxt.md
│   └── ...                       # 10+ framework/CSS/JS references
│
└── projects/                     # Stack templates
    ├── common/                   # Global fallback templates
    │   ├── rules/                # Common rules
    │   │   ├── memory-management.md
    │   │   ├── token-optimization.md
    │   │   └── sensitive-files.md
    │   └── MEMORY.md.template    # Memory bank template
    ├── expressionengine/
    ├── coilpack/
    ├── craftcms/
    ├── craftcms-nuxt/            # Headless Craft CMS + Nuxt
    ├── craftcms-nextjs/          # Headless Craft CMS + Next.js
    ├── ee-nextjs/                # Headless EE Coilpack + Next.js
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
├── memory-management.md      # Memory protocols
├── token-optimization.md     # Token efficiency
└── sensitive-files.md        # Prevents reading credentials/secrets
```

## Superpowers Skills Structure

```
superpowers/
├── skills/
│   ├── memory-management/
│   │   └── SKILL.md
│   ├── brainstorming/
│   │   └── SKILL.md
│   ├── writing-plans/
│   │   └── SKILL.md
│   ├── executing-plans/
│   │   └── SKILL.md
│   ├── systematic-debugging/
│   │   └── SKILL.md
│   ├── test-driven-development/
│   │   └── SKILL.md
│   ├── dispatching-parallel-agents/
│   │   └── SKILL.md
│   └── using-superpowers/
│       └── SKILL.md
├── commands/
│   ├── brainstorm.md
│   ├── write-plan.md
│   └── execute-plan.md
└── hooks/
    ├── hooks.json.template
    └── session-start.sh
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
