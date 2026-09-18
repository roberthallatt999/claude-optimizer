# Configuration

Understanding the Claude Code configuration structure.

## Configuration Files

### CLAUDE.md

Main project context file for Claude Code. Contains:
- Project overview and description
- Technology stack references
- Available commands and workflows
- Custom instructions
- A set of **managed blocks** — sections ai-config owns and refreshes in place between
  `<!-- BEGIN X -->` / `<!-- END X -->` markers, without touching anything else you write:

  | Block | Content | Opt-out |
  |---|---|---|
  | Safety Guardrails | Never read secrets, never push/publish or touch production without approval | always on |
  | Memory Protocol (or OKF Memory Protocol) | When to read/update `MEMORY.md` (or the `.okf/` bundle) | `--okf-memory` swaps which one |
  | Response Style | Concise-output defaults | `--no-response-style` |
  | Front-End Stack | The detected front-end stack, when one is found | automatic |
  | Code Index | Points at the registered codegraph MCP server | JS-framework stacks with codegraph installed |
  | Orchestrator Policy | Model & delegation policy (Opus main, Sonnet subagents) | `--orchestrator` |

**Location:** `{project-root}/CLAUDE.md`

**Generated from:** `projects/{stack}/CLAUDE.md.template`. On `--refresh`, an unedited
`CLAUDE.md` is regenerated from the template; an edited one keeps your changes and only
its managed blocks are refreshed.

### .claude/ Directory

Detailed configuration and rules:

```
.claude/
├── settings.local.json # Permissions, merged safety policy, hooks (gitignored)
├── ai-config/          # manifest.tsv, backups/, pending/, version (gitignored)
├── hooks/
│   └── safety-guard.sh # PreToolUse hook enforcing the safety guardrails
├── libraries/          # Project-local framework/library references (read on demand)
├── rules/              # Stack-specific + shared rules, some path-scoped
│   ├── accessibility.md
│   ├── sensitive-files.md
│   ├── deployment-safety.md
│   ├── memory-management.md
│   ├── token-optimization.md
│   ├── tailwind-css.md
│   ├── performance.md
│   └── ...
├── agents/             # Custom agent personas (subagents)
│   ├── code-quality-specialist.md
│   └── security-expert.md
└── commands/           # Project-specific commands
    ├── project-analyze.md
    └── ...
```

### settings.local.json

Claude Code permissions for the project, gitignored by default. Each stack has a
tailored version with appropriate CLI tool permissions (e.g., `composer` for PHP
stacks, `wp` for WordPress, `yarn`/`pnpm`/`bun` for JS stacks).

Every deploy and `--refresh` additively merges in the shared safety policy from
`projects/common/security.settings.local.json`:

- `permissions.deny` — blocks reading secrets (`.env`, `wp-config.php`, `*.key`, SSH
  keys, credential files, etc.)
- `permissions.ask` — requires approval for `git push`, PR/release creation, package
  publishing, production deploys, `ddev push`/`delete`, `terraform`/`kubectl` writes,
  `git reset --hard`, `git clean`, `rm`
- a `PreToolUse` hook registering `.claude/hooks/safety-guard.sh`, which also prompts
  before outward-acting or destructive MCP tool calls and credential-shaped strings in
  written content or commands
- `enableAllProjectMcpServers: false` (added only if unset) — MCP servers listed in
  `.mcp.json` must be explicitly named in `enabledMcpjsonServers` to start

Nothing existing is removed by this merge; your own `allow` rules and any MCP server
config are left as-is. See [Setup Script → Safety Guardrails](../guides/setup-script.md#safety-guardrails-always-deployed)
and [MCP Integration](../guides/mcp-integration.md).

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
- `sensitive-files.md` - Prevents Claude from reading credentials and secrets
- `deployment-safety.md` - Detail for the push/production-safety guardrails
- `memory-management.md`
- `token-optimization.md`
- Every other `.md` file the stack ships in its own `projects/{stack}/rules/` (stack-pattern
  rules like EE templates, Craft templates, `craft-graphql.md`, `sveltekit-patterns.md`, etc.,
  plus `accessibility.md` / `performance.md` where the stack has its own copy — there's no common
  fallback for those two)
- `typescript-patterns.md` - On **any** stack, when `tsconfig.json` exists
- `design-system.md` and `api-design.md` - On the JS-framework stacks (Next.js, Nuxt, Astro
  variants, SvelteKit, Remix, T3 Stack, Docusaurus, headless Craft/EE)

### Conditionally Deployed
- `tailwind-css.md` - When Tailwind CSS detected
- `alpinejs.md` - When Alpine.js detected
- `bilingual-content.md` - When French/English patterns detected
- Stack-specific add-ons (Stash, Structure for EE)

See **[Conditional Deployment Guide](../guides/conditional-deployment.md)** and
**[Stacks Reference](../reference/stacks.md#deployed-to-every-stack)** for detection logic and
the exact per-stack rule counts.

### Path-Scoped Rules

Most rules carry a `paths:` frontmatter block and only load into context when Claude
touches a matching file, instead of on every turn:

- `sensitive-files.md`, `deployment-safety.md` — config, env, CI/deploy, and infra paths
- `memory-management.md` — `MEMORY.md` / `MEMORY-ARCHIVE.md`
- `okf-memory.md` (with `--okf-memory`) — `.okf/**`
- Stack rules (`tailwind-css.md`, `nextjs-patterns.md`, …) — their relevant file types

`token-optimization.md` has no `paths:` and is always loaded — it's kept compact for
that reason.

### Library References (On Demand)

`.claude/libraries/*.md` are reference docs for a detected framework or library
(Tailwind, TypeScript, Prisma, Vitest, etc.). By default `CLAUDE.md` links to them as
plain paths, read only when a task actually involves that library — not `@imported`
(which would load every one of them into every session). `--eager-libraries` keeps the
`@import` form instead. See [Setup Script → Memory & Token Optimization](../guides/setup-script.md#memory--token-optimization).

### Subagents

Files in `.claude/agents/` need YAML frontmatter with `name`, `description`, and
`model: sonnet` to be picked up as subagents; `--orchestrator` adds an `implementer`
agent using the same shape.

## Customization

### Modifying Templates

1. Edit templates in `projects/{stack}/`
2. Test changes with `--dry-run`
3. Re-deploy to projects

### Project-Specific Rules

Add custom rules to `.claude/rules/` in your project — a filename ai-config doesn't ship is never
touched. For rules ai-config does ship, `--refresh` updates the four common rules if present
(restoring the two safety rules if missing), adds any stack rule that was never deployed to this
project before, and otherwise updates a shipped rule you haven't edited or keeps your edits (new
version staged in `.claude/ai-config/pending/`). See
[Conditional Deployment → Refresh Behavior](../guides/conditional-deployment.md#refresh-behavior)
for the handful of rules (the original six stack-pattern rules, `accessibility.md` /
`performance.md`, and the detection-gated rules) that are still deploy-only, not refresh.

### Token & Cost Options

| Flag | Effect |
|------|--------|
| `--no-response-style` | Omit the Response Style block in `CLAUDE.md` |
| `--eager-libraries` | Keep `@import`s of `.claude/libraries/*.md` |
| `--effort=<low\|medium\|high\|xhigh\|max>` | Set `effortLevel` in `settings.local.json` |
| `--okf-memory` | Store project memory as an OKF bundle instead of `MEMORY.md` |
| `--shared-policy` | Also commit the safety policy to `.claude/settings.json` for teammates |

See [Setup Script](../guides/setup-script.md#memory--token-optimization) for details,
[Memory System](../guides/memory-system.md) for `--okf-memory`, and
[Setup Script → --shared-policy](../guides/setup-script.md#--shared-policy).

### Version Control

**Recommended .gitignore:**
```
# Claude Code
CLAUDE.md
MEMORY.md
MEMORY-ARCHIVE.md
.claude/
```

`ai-config` maintains these entries for you (plus `.okf/` with `--okf-memory` and
`.codegraph/` when the code index is registered). These files are project-specific and
shouldn't be committed, unless you opt into `--shared-policy` for the two files it
carves out of `.claude/`. See [File Structure](../reference/file-structure.md#ignored-files)
for complete details.

## Next Steps

- **[Conditional Deployment](../guides/conditional-deployment.md)** - How detection works
- **[Updating Projects](../guides/updating-projects.md)** - Refresh workflows
- **[Stacks Reference](../reference/stacks.md)** - Stack-specific details
