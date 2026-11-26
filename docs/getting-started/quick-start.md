# Set up a project

This page walks you through your first project. You need ai-config [installed](installation.md) first.

## 1. Go to the project folder

Change the path to your own project:

```bash
cd ~/sites/my-site
```

## 2. Preview it (optional)

This shows what ai-config found and what it would write. Nothing changes.

```bash
ai-config --dry-run --project=.
```

## 3. Set it up

```bash
ai-config --project=.
```

It works out what the project is built with, then writes Claude's setup. At the end it checks its own work and
prints any problem it found. A line starting with ✗ is a real problem. A line starting with ⚠ is advice.

## 4. Start Claude Code

Open Claude Code in the same folder as usual. Claude now knows the project and follows its safety rules.

## 5. Check it any time

This tests the setup without changing anything. It also confirms that Claude is really blocked from reading a
secret file.

```bash
ai-config --doctor --project=.
```

## If it can't tell what the project is

For a framework ai-config doesn't know, use discovery mode:

```bash
ai-config --discover --project=.
```

Then, inside Claude Code, type:

```text
/project-discover
```

Claude studies the code and writes rules that fit it.

To name the stack yourself instead (the [list of stacks](../reference/stacks.md) has every name):

```bash
ai-config --stack=craftcms --project=.
```

## What to commit to git

Most of what ai-config writes is personal setup, so it's kept out of git for you: `CLAUDE.md`, `MEMORY.md` and
the `.claude/` folder. You don't need to do anything.

One file is worth committing: `ai-config.conf`. It records this project's choices, so a fresh clone gets the
same setup. Create it with:

```bash
ai-config --save-policy --project=.
```

Then commit it like any other file. See [The project settings file](../guides/project-policy.md).

## Common extras

| To do this | Add this to the command |
|---|---|
| Skip the VS Code settings | `--skip-vscode` |
| Install the recommended VS Code extensions | `--install-extensions` |
| Leave out the workflow skills | `--no-superpowers` |
| Also write `AGENTS.md` for OpenAI Codex | `--with-openai` |

For example:

```bash
ai-config --project=. --install-extensions
```

Every option is on [All ai-config options](../guides/setup-script.md).

Next: [What it adds to a project](configuration.md), or [Keep projects up to date](../guides/updating-projects.md).
