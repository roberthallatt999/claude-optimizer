# Repository layout

Where things live in this repository. For the files ai-config adds to *your* project, see
[What it adds to a project](../getting-started/configuration.md).

## Top level

| Path | What it is |
|---|---|
| `setup-project.sh` | The main script. The `ai-config` command runs it |
| `ai-config-fleet.sh` | Runs ai-config across many projects (`ai-config-fleet`) |
| `serve-docs.sh`, `index.html` | The docs website (`ai-config-docs`) |
| `install.sh` | Sets up ai-config on a computer |
| `update-superpowers.sh` | Downloads the latest workflow skills |
| `run-tests.sh`, `test-*.sh` | The tests: one suite per feature |
| `ai-config.conf` | This repository's own [project settings](../guides/project-policy.md) |
| `CLAUDE.md` | Instructions for Claude when working on this repository |
| `.github/workflows/tests.yml` | Runs the tests on GitHub, on macOS and Ubuntu |

## Folders

| Folder | What's in it |
|---|---|
| `projects/` | One folder per stack: the templates ai-config copies into a project |
| `projects/common/` | What every stack shares: the safety guard, shared rules, the `CLAUDE.md` sections, the memory template, front-end detection |
| `libraries/` | Short notes on libraries (Tailwind, React, Prisma…) copied into each project's `.claude/libraries/` |
| `stacks/` | Background notes on some stacks, copied to `~/.claude/stacks/` by the installer |
| `superpowers/` | The workflow skills, copied from their fork. Don't edit them here |
| `global-skills/` | `noslop` and `humanizer`, linked into `~/.claude/skills/` |
| `design-skills/` | Front-end design skills, copied into JavaScript projects |
| `vendor/` | Which exact version of each outside skill is used (`skills.conf`), and local patches |
| `devcontainer-kit/` | Everything for the [sandboxes](../guides/sandbox.md) |
| `scripts/` | Smaller tools. See [Other scripts](scripts.md) |
| `profiles/` | `example.conf`, a sample [profile](../guides/profiles.md). Real profiles live in your private repository |
| `examples/` | Sample finished `CLAUDE.md` files |
| `docs/` | These pages |

## Inside a stack folder

Each folder in `projects/` can have these. Anything a stack doesn't have falls back to `projects/common/`.

| Path | What it becomes in a project |
|---|---|
| `CLAUDE.md.template` | The project's `CLAUDE.md` |
| `AGENTS.md.template` | `AGENTS.md`, with `--with-openai` |
| `settings.local.json` | The starting `.claude/settings.local.json`. The shared safety rules are merged in on top |
| `protected-paths.conf` | Extra files this stack never lets Claude read (`[deny]`), and noise to skip (`[ignore]`) |
| `rules/` | `.claude/rules/` |
| `agents/` | `.claude/agents/` |
| `commands/` | `.claude/commands/` |
| `skills/` | `.claude/skills/` |
| `.vscode/` | `.vscode/` |

## Placeholders in templates

Templates use `{{NAME}}` placeholders that ai-config fills in:

| Placeholder | Filled with |
|---|---|
| `{{PROJECT_NAME}}`, `{{PROJECT_SLUG}}`, `{{PROJECT_PATH}}` | The project's name, short name and folder |
| `{{DDEV_NAME}}`, `{{DDEV_PRIMARY_URL}}`, `{{DDEV_PHP}}`, `{{DDEV_DB_TYPE}}`, `{{DDEV_DB_VERSION}}`, `{{DDEV_DOCROOT}}` | Values from `.ddev/config.yaml` |
| `{{TEMPLATE_GROUP}}` | The ExpressionEngine template folder |
| `{{GIT_MAIN_BRANCH}}`, `{{GIT_INTEGRATION_BRANCH}}` | The git branches |
| `{{BRAND_GREEN}}`, `{{BRAND_BLUE}}`, `{{BRAND_ORANGE}}`, `{{BRAND_LIGHT_GREEN}}` | Brand colours found in the Tailwind config |

A value that can't be found becomes plain text, such as `(brand green: not set)`. It never becomes a made-up value.
