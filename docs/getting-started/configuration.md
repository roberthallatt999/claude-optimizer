# Configuration

Understanding the Claude Code configuration structure.

## Configuration Files

### CLAUDE.md

Main project context file for Claude Code. Contains:
- Project overview and description
- Technology stack references
- Available commands and workflows
- Custom instructions

**Location:** `{project-root}/CLAUDE.md`

**Generated from:** `projects/{stack}/CLAUDE.md.template`

### .claude/ Directory

Detailed configuration and rules:

```
.claude/
├── settings.local.json # Permissions and MCP config
├── libraries/          # Project-local framework/library references
├── rules/              # Stack-specific rules
│   ├── accessibility.md
│   ├── sensitive-files.md
│   ├── tailwind-css.md
│   ├── performance.md
│   └── ...
├── agents/             # Custom agent personas
│   ├── code-quality-specialist.md
│   └── security-expert.md
└── commands/           # Project-specific commands
    ├── project-analyze.md
    └── ...
```

### settings.local.json

Claude Code permissions and MCP server configuration. Each stack has a tailored version with appropriate CLI tool permissions (e.g., `composer` for PHP stacks, `wp` for WordPress, `yarn` for JS stacks).

### .vscode/ Directory

VSCode IDE configuration:

```
.vscode/
├── settings.json       # Editor settings + file associations
├── launch.json         # Debug configuration
└── tasks.json          # Build/run tasks
```

Use `--skip-vscode` to skip deploying these files. Use `--install-extensions` to auto-install recommended VSCode extensions for your stack.

## Template Variables

Templates support variable substitution:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{PROJECT_NAME}}` | Human-readable name | "My Project" |
| `{{PROJECT_SLUG}}` | URL-safe identifier | "my-project" |
| `{{PROJECT_PATH}}` | Absolute path | "/Users/dev/project" |
| `{{DDEV_NAME}}` | DDEV project name | "myproject" |
| `{{DDEV_PRIMARY_URL}}` | Primary URL | "https://myproject.ddev.site" |
| `{{DDEV_PHP}}` | PHP version | "8.2" |
| `{{DDEV_DB_TYPE}}` | Database type | "MariaDB" |
| `{{DDEV_DB_VERSION}}` | Database version | "10.11" |
| `{{DDEV_DOCROOT}}` | Document root | "public" |
| `{{TEMPLATE_GROUP}}` | EE template directory | "myproject" |
| `{{GIT_MAIN_BRANCH}}` | Default git branch | "main" |
| `{{GIT_INTEGRATION_BRANCH}}` | Integration branch | "main" |
| `{{BRAND_GREEN}}` | Brand color hex | "#238937" |
| `{{BRAND_BLUE}}` | Brand color hex | "#00639A" |
| `{{BRAND_ORANGE}}` | Brand color hex | "#F15922" |
| `{{BRAND_LIGHT_GREEN}}` | Brand color hex | "#D7DF21" |

## Conditional Deployment

Rules and configurations are deployed based on detected technologies:

### Always Deployed
- `accessibility.md`
- `performance.md`
- `sensitive-files.md` - Prevents Claude from reading credentials and secrets
- `memory-management.md`
- `token-optimization.md`
- Base stack rules (EE templates, Craft templates, etc.)

### Conditionally Deployed
- `tailwind-css.md` - When Tailwind CSS detected
- `alpinejs.md` - When Alpine.js detected
- `bilingual-content.md` - When French/English patterns detected
- Stack-specific add-ons (Stash, Structure for EE)

See **[Conditional Deployment Guide](../guides/conditional-deployment.md)** for detection logic.

## Customization

### Modifying Templates

1. Edit templates in `projects/{stack}/`
2. Test changes with `--dry-run`
3. Re-deploy to projects

### Project-Specific Rules

Add custom rules to `.claude/rules/` in your project. They won't be overwritten by `--refresh`.

### Version Control

**Recommended .gitignore:**
```
# Claude Code
CLAUDE.md
MEMORY.md
MEMORY-ARCHIVE.md
.claude/
```

These files are project-specific and shouldn't be committed. See [File Structure](../reference/file-structure.md#ignored-files) for complete details.

## Next Steps

- **[Conditional Deployment](../guides/conditional-deployment.md)** - How detection works
- **[Updating Projects](../guides/updating-projects.md)** - Refresh workflows
- **[Stacks Reference](../reference/stacks.md)** - Stack-specific details
