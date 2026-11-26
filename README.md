# Claude Optimizer

**Run one command and Claude Code knows how your project is built, plus it gets safety rules that stop it doing
real damage.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## What it does

You point `ai-config` at a project folder. It works out what the site is built with (WordPress, Craft CMS,
ExpressionEngine, Next.js, Astro and [14 others](docs/reference/stacks.md)), then sets Claude Code up for that
project:

- **It tells Claude about the project.** Claude gets the framework, its coding rules and the right library notes.
  It stops guessing.
- **It keeps secrets away from Claude.** Claude can't read `.env` files, passwords or keys, even by accident.
- **It asks before anything risky.** Every `git push`, deploy, delete or change to a live server waits for your
  yes.
- **It gives Claude a memory.** Decisions and changes are written down, so the next session doesn't start from
  zero.
- **It never overwrites your edits.** When you update, files you changed are kept and everything is backed up.

It's a plain shell script. It needs no account and no service.

## Install

Run these three commands in Terminal, one at a time.

```bash
git clone https://github.com/roberthallatt999/claude-optimizer.git ~/.ai-config
```

```bash
~/.ai-config/install.sh
```

```bash
source ~/.zshrc
```

If you use bash rather than zsh, run `source ~/.bashrc` for the last one instead. More detail:
[Install](docs/getting-started/installation.md).

## Set up a project

Go to the project's folder. Change the path to your own project:

```bash
cd ~/sites/my-site
```

Then run:

```bash
ai-config --project=.
```

That's all. Start Claude Code in that folder as usual. More detail:
[Set up a project](docs/getting-started/quick-start.md).

## The commands you'll use most

Run each one from inside the project folder.

| To do this | Run |
|---|---|
| Set up a project | `ai-config --project=.` |
| Update it after you update ai-config | `ai-config --refresh --project=.` |
| Check everything works (changes nothing) | `ai-config --doctor --project=.` |
| See what would happen, without changing anything | `ai-config --dry-run --project=.` |
| Remove ai-config from the project | `ai-config --uninstall --project=.` |

To check every project in a folder at once:

```bash
ai-config-fleet --root=~/sites
```

Every option is listed on [All ai-config options](docs/guides/setup-script.md).

## Read the docs in your browser

```bash
ai-config-docs
```

It opens the docs at `http://localhost:8000`. Every command has a **Copy** button you can paste straight into
Terminal.

## Where to go next

| I want to… | Read |
|---|---|
| Install it | [Install](docs/getting-started/installation.md) |
| Set up my first project | [Set up a project](docs/getting-started/quick-start.md) |
| Know what files it adds | [What it adds to a project](docs/getting-started/configuration.md) |
| Update projects | [Keep projects up to date](docs/guides/updating-projects.md) |
| Understand the safety rules | [How it keeps you safe](docs/guides/safety.md) |
| Save settings for one project | [The project settings file](docs/guides/project-policy.md) |
| Run Claude in a locked-down container | [Sandboxes](docs/guides/sandbox.md) |
| Change ai-config itself | [Contributing](docs/development/contributing.md) |

## Credits and licence

MIT licence. See [LICENSE](LICENSE).

The workflow skills come from [Superpowers](https://github.com/obra/superpowers) by Jesse Vincent, through
[this fork](https://github.com/roberthallatt999/superpowers). They're MIT-licensed separately; see
[superpowers/LICENSE](superpowers/LICENSE).

Questions and bugs: [GitHub Issues](https://github.com/roberthallatt999/claude-optimizer/issues).
