# Slash commands

These are commands you type **inside Claude Code**, not in Terminal. For example:

```text
/project-analyze
```

Each stack gets its own set. For the `ai-config` command itself, see [All ai-config options](../guides/setup-script.md).

## By stack

| Stack | Commands |
|---|---|
| `expressionengine` | `/project-analyze`, `/ee-template-scaffold`, `/ee-check-syntax`, `/stash-optimize`, `/alpine-component-gen`, `/tailwind-build`, `/ddev-helper` |
| `coilpack` | `/project-analyze`, `/ee-helper`, `/ee-check-syntax`, `/laravel-helper`, `/livewire-component`, `/twig-helper`, `/twig-scaffold`, `/stash-optimize`, `/alpine-component-gen`, `/tailwind-build`, `/ddev-helper` |
| `craftcms` | `/project-analyze`, `/craft-helper`, `/alpine-component-gen`, `/tailwind-build`, `/ddev-helper` |
| `wordpress` | `/project-analyze`, `/wp-helper`, `/wp-theme-scaffold`, `/ddev-helper` |
| `wordpress-roots` | `/project-analyze`, `/wordpress-helper`, `/alpine-component-gen`, `/tailwind-build`, `/ddev-helper` |
| `nextjs` | `/project-analyze`, `/nextjs-helper`, `/alpine-component-gen`, `/tailwind-build` |
| `docusaurus` | `/project-analyze`, `/docusaurus-helper`, `/tailwind-build` |
| `craftcms-nuxt`, `craftcms-nextjs`, `ee-nextjs`, `astro-strapi`, `astro-sanity` | `/project-analyze` |
| `custom` | `/project-discover` |
| `astro`, `astro-tina`, `nuxt`, `remix`, `sveltekit`, `t3-stack` | None of their own |

## What the main ones do

| Command | What it does |
|---|---|
| `/project-analyze` | Looks over the project and suggests improvements to its structure, setup and Claude configuration |
| `/project-discover` | For an unknown framework: studies the code and writes rules, and the right `.gitignore` lines, to fit it |
| `/ddev-helper` | Common DDEV jobs: start, logs, database |
| `/ee-template-scaffold` | Starts a new ExpressionEngine template |
| `/ee-check-syntax` | Checks an ExpressionEngine template for unclosed tags and bad variables |
| `/stash-optimize` | Suggests better caching where a site uses the Stash add-on |
| `/tailwind-build` | Builds the Tailwind CSS |
| `/alpine-component-gen` | Starts a new Alpine.js component |
| `/craft-helper`, `/wp-helper`, `/wordpress-helper`, `/laravel-helper`, `/nextjs-helper`, `/docusaurus-helper` | Shortcuts for that framework's own command-line tool |

## Skills for ExpressionEngine

ExpressionEngine projects also get these skills, which Claude uses when the task fits:

| Skill | Helps with |
|---|---|
| `ee-template-assistant` | Writing and debugging EE templates |
| `ee-stash-optimizer` | Stash caching |
| `alpine-component-builder` | Alpine.js components |
| `tailwind-utility-finder` | Picking the right Tailwind classes |
| `ee-migrate` | Writing and shipping database migrations: new channels, fields, field groups, categories. Only on sites with the CPS migration tools (`cps_tools` add-on) |

Every project also gets the [workflow skills](../guides/superpowers.md).

## Make your own command

Create a Markdown file in `.claude/commands/`. The file name becomes the command: `.claude/commands/check-links.md`
is `/check-links`. Write in it what Claude should do:

```markdown
# Check links

Find every link in the templates folder and report any that point to a page that doesn't exist.
```

ai-config never touches a command file it didn't ship.
