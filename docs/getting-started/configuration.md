# What it adds to a project

After `ai-config --project=.`, your project has these new files.

| File or folder | What it's for |
|---|---|
| `CLAUDE.md` | Claude reads this at the start of every session: what the project is, how to run it, and the rules to follow |
| `MEMORY.md` | Claude's notes: decisions, recent changes, where you left off. See [How Claude remembers](../guides/memory-system.md) |
| `.claude/settings.local.json` | What Claude may do without asking, what it must ask about, and what it can never do |
| `.claude/hooks/safety-guard.sh` | The safety guard. It checks every command and file read before it happens. See [How it keeps you safe](../guides/safety.md) |
| `.claude/rules/` | Coding rules for this kind of project. Most load only when Claude opens a matching file |
| `.claude/libraries/` | Short notes on the libraries the project uses (Tailwind, Alpine.js and so on). Claude reads one only when it needs it |
| `.claude/skills/` | Step-by-step workflows Claude can follow. See [Workflow skills](../guides/superpowers.md) |
| `.claude/agents/`, `.claude/commands/` | Helper agents and slash commands for this stack. See [Slash commands](../reference/commands.md) |
| `.claude/ai-config/` | ai-config's own records: what it wrote, backups, and new versions waiting for you |
| `.vscode/` | Editor settings for the stack: formatters, debugging, tasks. Skip with `--skip-vscode` |
| `.claudeignore` | A list of folders that are just noise (build output, dependencies). For information only: Claude Code doesn't read it yet |
| `.gitignore` | ai-config adds lines so the personal files above stay out of git |
| `.git/hooks/pre-commit` | Stops a commit that contains a password or key. Not added if the project already has its own hook |

## The sections ai-config manages in `CLAUDE.md`

`CLAUDE.md` is yours to edit. ai-config also keeps a few sections of it up to date. Each one sits between two
marker lines like these:

```text
<!-- BEGIN SAFETY GUARDRAILS -->
...
<!-- END SAFETY GUARDRAILS -->
```

ai-config only ever changes the text between its markers. Everything else you write is left alone.

| Section | What it tells Claude | How to turn it off |
|---|---|---|
| Safety guardrails | Never read secrets. Ask before every push. Never touch a live site without permission | Always on |
| Memory protocol | When to read and update `MEMORY.md` | Always on |
| Engineering practices | Use the framework's security features, test security claims, keep files small | `--no-engineering-practices` |
| Response style | Keep answers short and to the point | `--no-response-style` |
| Front-end stack | The CSS and JavaScript tools this project actually uses | Added only when some are found |
| Code index | How to use the code search tool, if you have one | Added only when codegraph is set up |
| Model and delegation | Use Opus for thinking, Sonnet for routine work | Added only with `--orchestrator` |

## What stays out of git

By default these are personal and not committed: `CLAUDE.md`, `MEMORY.md`, `MEMORY-ARCHIVE.md` and `.claude/`.
ai-config adds them to `.gitignore` for you.

Two things are meant to be committed:

- `ai-config.conf`, the project's own settings. See [The project settings file](../guides/project-policy.md).
- With `--shared-policy`, also `.claude/settings.json` and `.claude/hooks/safety-guard.sh`. That way everyone
  who clones the repo gets the same safety rules.

## Changing what gets deployed

| You want to | Do this |
|---|---|
| Change a file in one project | Edit it. Updates keep your version |
| Remove a file from one project for good | Delete it, then run `ai-config --save-policy --project=.` so it stays deleted |
| Add your own rule | Put a new `.md` file in `.claude/rules/`. ai-config never touches files it didn't ship |
| Change what every project gets | Edit the templates in `projects/<stack>/` in this repository |

Next: [Keep projects up to date](../guides/updating-projects.md).
