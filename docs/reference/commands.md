# Commands Reference

Available commands and skills for each stack. For `ai-config` / `setup-project.sh` CLI flags
(`--stack`, `--refresh`, `--okf-memory`, etc.), see the [Setup Script Guide](../guides/setup-script.md)
— this page is about slash commands used *inside* a deployed project.

Superpowers also deploys `/brainstorm`, `/write-plan`, and `/execute-plan` to every project, but
they are currently deprecated stubs — each just tells Claude to use the equivalent skill
(`superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:executing-plans`)
instead. See [Superpowers → Slash Commands](../guides/superpowers.md#slash-commands).

## Universal Commands

Available in all stacks:

### /project-analyze

Analyze the current project structure and provide recommendations.

**What it does:**
- Scans codebase structure
- Identifies technologies
- Suggests improvements
- Recommends configuration updates

**Usage:**
```
/project-analyze
```

**Output:**
- File organization analysis
- Technology stack summary
- Performance recommendations
- Security considerations

### /sync-configs

Synchronize project configuration files.

**What it does:**
- Compares configuration files
- Identifies differences
- Suggests synchronization

**Usage:**
```
/sync-configs
```

**Available in:** Coilpack, Craft CMS, Docusaurus, ExpressionEngine, Next.js, WordPress/Roots

## ExpressionEngine Commands

### /ee-template-scaffold

Generate ExpressionEngine template boilerplate.

**Usage:**
```
/ee-template-scaffold template_group/template_name
```

**Generates:**
- Template file with header comments
- Common variables
- Conditional logic structure
- Embed placeholders

### /ee-check-syntax

Validate ExpressionEngine template syntax.

**What it does:**
- Checks for unclosed tags
- Validates variable syntax
- Identifies potential issues

**Usage:**
```
/ee-check-syntax path/to/template.html
```

### /stash-optimize

Optimize Stash usage in templates (if Stash detected).

**What it does:**
- Analyzes Stash variable usage
- Suggests caching improvements
- Identifies redundant queries

**Usage:**
```
/stash-optimize
```

### /alpine-component-gen

Generate Alpine.js component (if Alpine.js detected).

**Usage:**
```
/alpine-component-gen component-name
```

**Generates:**
- Alpine.js component structure
- Data properties
- Methods
- Event handlers

### /tailwind-build

Build Tailwind CSS (if Tailwind detected).

**What it does:**
- Runs Tailwind build process
- Watches for changes
- Purges unused styles

**Usage:**
```
/tailwind-build [--watch]
```

### /ddev-helper

DDEV command shortcuts.

**What it does:**
- Common DDEV operations
- Quick access to logs
- Database operations

**Usage:**
```
/ddev-helper [command]
```

## Coilpack Commands

Includes all ExpressionEngine commands plus:

### /laravel-helper

Laravel-specific operations.

**Usage:**
```
/laravel-helper [artisan-command]
```

## Craft CMS Commands

### /craft-helper

Craft CMS console commands.

**Usage:**
```
/craft-helper [command]
```

## WordPress/Roots Commands

### /wp-helper

WordPress CLI and Roots/Bedrock operations.

**Usage:**
```
/wp-helper [wp-command]
```

## Next.js Commands

### /next-build

Build and development server operations.

**Usage:**
```
/next-build [--dev|--build|--start]
```

## Docusaurus Commands

### /docs-build

Docusaurus build and serve operations.

**Usage:**
```
/docs-build [--dev|--build|--serve]
```

## Skills (ExpressionEngine Only)

Skills are specialized knowledge modules. ExpressionEngine is currently the only stack with skills.

### alpine-component-builder

Build complex Alpine.js components with best practices.

**Capabilities:**
- Component architecture
- State management
- Event handling
- Integration with EE

### ee-stash-optimizer

Optimize Stash add-on usage for performance.

**Capabilities:**
- Cache strategy recommendations
- Query optimization
- Variable scoping
- Performance profiling

### ee-template-assistant

ExpressionEngine template development assistance.

**Capabilities:**
- Template structure
- Variable usage
- Tag syntax
- Debugging assistance

### tailwind-utility-finder

Find and suggest appropriate Tailwind CSS utilities.

**Capabilities:**
- Utility class recommendations
- Custom configuration
- Responsive design patterns
- Component extraction


## Creating Custom Commands

### For Claude Code

Create `.claude/commands/my-command.md`:

```markdown
# My Command

Description of what this command does.

## Usage

How to use this command.

## Implementation

What the AI should do when this command is invoked.
```


## Command Conventions

### Naming

- Use kebab-case: `my-command`
- Prefix stack-specific commands: `ee-`, `craft-`, `wp-`, `next-`
- Use verbs: `analyze`, `build`, `optimize`, `check`

### Documentation

Each command should document:
- Purpose and description
- Usage syntax
- Parameters/options
- Expected output
- Examples

## Next Steps

- **[Stacks Reference](stacks.md)** - Stack details
- **[Configuration](../getting-started/configuration.md)** - Command customization
- **[Contributing](../development/contributing.md)** - Add custom commands
