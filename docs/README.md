# Documentation

New here? Read these three pages in order:

1. [Install](getting-started/installation.md): put `ai-config` on your computer.
2. [Set up a project](getting-started/quick-start.md): run it on your first site.
3. [Keep projects up to date](guides/updating-projects.md): what to do after that.

## How to read these pages

- **Every command is in its own box** with a **Copy** button. Paste it into Terminal and press Return.
- **Most commands run from inside the project folder.** `cd` into the project first. `--project=.` means "this
  folder".
- **Words in `<angle brackets>` are placeholders.** Replace them, brackets included, before you run the command.
- **Boxes marked `ini` or `json` are file contents, not commands.** Put them in the file the page names.

## Everyday use

| Page | What it covers |
|---|---|
| [Keep projects up to date](guides/updating-projects.md) | Refresh a project, review changes, update many projects at once |
| [All ai-config options](guides/setup-script.md) | Every option, grouped by what you're trying to do |
| [The project settings file](guides/project-policy.md) | `ai-config.conf`: settings one project keeps, even on a fresh clone |
| [How it keeps you safe](guides/safety.md) | What Claude can't read or do, and why |
| [How Claude remembers](guides/memory-system.md) | `MEMORY.md` and the alternative `.okf/` folder |

## Extras

| Page | What it covers |
|---|---|
| [Workflow skills](guides/superpowers.md) | Planning, debugging and testing skills that come with every project |
| [How it detects a project](guides/conditional-deployment.md) | What it looks for, and what each finding adds |
| [Profiles and skills](guides/profiles.md) | Who you are in each context (work, volunteer, side work) |
| [Connect outside services](guides/mcp-integration.md) | Give Claude access to GitHub, databases and other services |
| [Hide personal data (Philter)](guides/philter.md) | Replace names, emails and phone numbers before Claude sees them |
| [Sandboxes](guides/sandbox.md) | Run Claude where it can only reach the sites you allow |

## Step by step

| Page | When to use it |
|---|---|
| [Dev container](runbooks/devcontainer.md) | Run Claude for one project inside a locked-down VS Code container |
| [Enclave](runbooks/enclave.md) | The same idea, using Eclipse Enclave |
| [Claude Code sandbox](runbooks/claude-sandbox.md) | The lightest option: no Docker needed |
| [Monthly safety check](runbooks/safety-checkup.md) | Ten minutes to confirm the protections still work |

## Reference

| Page | What it lists |
|---|---|
| [Supported stacks](reference/stacks.md) | The 19 project types and how each is recognized |
| [Slash commands](reference/commands.md) | Commands like `/project-analyze` that you type inside Claude Code |
| [Other scripts](reference/scripts.md) | Every other tool in this repository |
| [Environment variables](reference/environment.md) | Settings you can change from the shell |
| [Repository layout](reference/file-structure.md) | Where things live in this repository |

## Working on ai-config

[Contributing](development/contributing.md) covers tests and adding a stack. [Project status](development/project-status.md)
says what's finished.
