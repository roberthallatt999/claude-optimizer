# All ai-config options

Every option goes after `ai-config`. Every command needs `--project=`, which is the project folder. From inside
the folder, use `--project=.`.

```bash
ai-config --project=.
```

Options always use `=` with no spaces: `--stack=craftcms`, not `--stack craftcms`.

To see this list in Terminal:

```bash
ai-config --help
```

## The main jobs

| Option | What it does |
|---|---|
| *(no option)* | Set the project up |
| `--refresh` | Update the setup. Keeps your edits. See [Keep projects up to date](updating-projects.md) |
| `--doctor` | Check that everything works. Changes nothing |
| `--dry-run` | Show what would happen. Changes nothing. Works with any other option |
| `--uninstall` | Remove ai-config. Keeps your edits and `MEMORY.md`, and backs up everything it removes |
| `--save-policy` | Write `ai-config.conf`, the project's settings file, then stop. See [The project settings file](project-policy.md) |

## Updating

| Option | What it does |
|---|---|
| `--apply-pending` | Swap in the new versions waiting in `.claude/ai-config/pending/`. Backs up your copies first |
| `--force` | Don't ask questions. Your edits are still kept |
| `--clean` | Move the current setup into a backup, then set up fresh. Usually used with `--force` |
| `--install-deps` | Install missing tools first (`jq`, `git`; Intelephense for PHP sites). Asks first unless you add `--force` |

## Choosing the stack

ai-config normally works out the stack itself. Use these when it can't.

| Option | What it does |
|---|---|
| `--stack=<name>` | Use this stack. Names are on [Supported stacks](../reference/stacks.md) |
| `--discover` | For a framework ai-config doesn't know. Then type `/project-discover` in Claude Code |
| `--name=<name>` | The project name Claude sees. Default: the folder name |
| `--slug=<slug>` | A short name used in templates. Default: made from the name |
| `--analyze` | Print a prompt you can paste into Claude to get suggestions for the setup |

## Safety

The safety rules are always on. These options add to them.

| Option | What it does |
|---|---|
| `--shared-policy` | Also put the safety rules in `.claude/settings.json`, which you commit, so everyone who clones the repo gets them |
| `--no-claudeignore` | Don't write `.claudeignore`. The real blocks still apply |

## Memory

| Option | What it does |
|---|---|
| `--okf-memory` | Keep Claude's notes in a `.okf/` folder, one file per topic, instead of one `MEMORY.md`. See [How Claude remembers](memory-system.md) |

## Cost and speed

| Option | What it does |
|---|---|
| `--effort=<level>` | How hard Claude thinks: `low`, `medium`, `high`, `xhigh` or `max` |
| `--orchestrator` | Use Opus for the main session and Sonnet for helpers. Adds an `implementer` helper agent |
| `--no-response-style` | Leave out the "keep answers short" section of `CLAUDE.md` |
| `--no-engineering-practices` | Leave out the coding-practices section and rule |
| `--eager-libraries` | Load every library note into every session. Costs more; normally they're read only when needed |

## Workflow skills

Skills are on by default. See [Workflow skills](superpowers.md).

| Option | What it does |
|---|---|
| `--no-superpowers` | Leave the skills out |
| `--with-superpowers` | Put them back for this run, even if `ai-config.conf` turns them off |
| `--superpowers-core` | Only the core skills: testing, debugging, brainstorming |
| `--superpowers-minimal` | Only the starter skill |
| `--superpowers-skill=<a,b>` | Only the skills you name, separated by commas |
| `--superpowers-bootstrap` | Remind Claude about the skills at the start of every session (costs about 1,300 tokens a session) |
| `--skip-superpowers-update` | Don't download the latest skills first |

## Design skills

| Option | What it does |
|---|---|
| `--design-skills` | Add the front-end design skills to a CMS project. JavaScript projects get them already |
| `--no-design-skills` | Leave them out |

## Sandbox

Nothing changes unless you use one of these. See [Sandboxes](sandbox.md).

| Option | What it does |
|---|---|
| `--devcontainer` | Also write a locked-down VS Code dev container |
| `--sandbox=devcontainer` | The same |
| `--sandbox=enclave` | Use Eclipse Enclave instead |
| `--sandbox=claude` | Use Claude Code's own sandbox. No Docker needed |
| `--sandbox=none` | Stop updating the sandbox. Nothing is deleted |

## Editor and other tools

| Option | What it does |
|---|---|
| `--skip-vscode` | Don't write `.vscode/` settings |
| `--install-extensions` | Install the recommended VS Code extensions. Needs the `code` command |
| `--with-openai` | Also write `AGENTS.md`, for OpenAI Codex and similar tools. Not remembered: add it again on each refresh |

## Options that are remembered

Some options stay on for later refreshes, so you don't need to repeat them: `--okf-memory`, `--orchestrator`,
`--shared-policy` and the sandbox options. To make any option stick for good, even on a fresh clone, put it in
`ai-config.conf`. See [The project settings file](project-policy.md).

## Examples

Set up a Craft site, naming the stack:

```bash
ai-config --stack=craftcms --project=.
```

Start fresh without being asked questions:

```bash
ai-config --clean --force --project=.
```

Install the editor extensions too:

```bash
ai-config --project=. --install-extensions
```

Preview a refresh:

```bash
ai-config --refresh --dry-run --project=.
```

## When it finishes

ai-config exits with `0` when all went well and `1` on any error, including a failed health check. That's useful
in scripts.

## Problems

| What you see | What to do |
|---|---|
| "Unknown option" | Use `=` with no spaces: `--stack=craftcms` |
| "Could not detect stack" | Add `--stack=<name>`, or use `--discover` |
| A library you use wasn't detected | Run `--dry-run` to see what was found. Detection reads `package.json`, asset files and templates, and skips `node_modules` and `vendor` |
