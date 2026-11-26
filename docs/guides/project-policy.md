# The project settings file (`ai-config.conf`)

`ai-config.conf` sits in the project's top folder. It holds the choices this one project has made, and
ai-config reads it every time it runs. **Commit it to git.**

## Why it matters

Almost everything ai-config writes stays out of git, which is usually right. But it means a fresh clone, a new
computer or a rebuilt container starts from the default setup. Library notes you deleted come back, options you
turned on are off again, and nothing warns you.

`ai-config.conf` is the one file that travels with the repository, so those choices survive.

## Create it

Run this from inside the project folder. It looks at the project as it is now and writes down what it finds:

```bash
ai-config --save-policy --project=.
```

Then commit it:

```bash
git add ai-config.conf
```

```bash
git commit -m "chore: record ai-config project settings"
```

Run `--save-policy` again whenever you delete more files. It keeps what's already in the file, including anything
you typed yourself.

## What it looks like

```ini
[options]
stack = craftcms
okf-memory = true

[decisions]
path = docs/decisions.md

[exclude]
.claude/libraries/react.md
.claude/libraries/vue.md
```

- A line starting with `#` is a comment.
- A typo never stops a run. ai-config reports the line and skips it.
- Editing this file from Claude always asks you first, because it's part of the safety setup.

## `[options]`: options this project always wants

Each line works like the matching command-line option. An option you type on the command line still wins for that
run.

| Line | Same as |
|---|---|
| `stack = craftcms` | `--stack=craftcms` |
| `name = My Site`, `slug = my-site` | `--name=`, `--slug=` |
| `effort = high` | `--effort=high` |
| `okf-memory = true` | `--okf-memory` |
| `orchestrator = true` | `--orchestrator`. `false` removes it, even if it was on before |
| `shared-policy = true` | `--shared-policy` |
| `with-openai = true` | `--with-openai` |
| `superpowers = false` | `--no-superpowers` |
| `superpowers-bootstrap = true` | `--superpowers-bootstrap` |
| `eager-libraries = true` | `--eager-libraries` |
| `engineering-practices = false` | `--no-engineering-practices` |
| `response-style = false` | `--no-response-style` |
| `claudeignore = false` | `--no-claudeignore` |
| `skip-vscode = true` | `--skip-vscode` |
| `design-skills = true` | `--design-skills` (`false` turns them off) |
| `sandbox = devcontainer` | `--devcontainer` |
| `ci-checks = false` | For a project with no automated tests online: `--doctor` stops warning about missing checks |
| `profile = cps` | Use this [profile](profiles.md) for this project |
| `philter = acme` | Use this [Philter](philter.md) policy. ai-config writes the name into a `.philter` file; commit that too |

`true`, `yes`, `on` and `1` all mean yes. `false`, `no`, `off` and `0` all mean no.

## `[decisions]`: where decisions are written down

```ini
[decisions]
path = docs/decisions.md
```

By default Claude writes architectural decisions in `MEMORY.md`, which isn't in git. Set a path to have it
write them in a file you commit instead. Then they're reviewed like code, and a bad edit can be undone.
ai-config puts the path into Claude's instructions on every run, so it can't drift back.

## `[exclude]`: files ai-config must leave alone

```ini
[exclude]
.claude/libraries/react.md
.claude/skills/brainstorming/
.claude/libraries/*.md
```

ai-config never creates, updates or stages a file listed here, whether it exists or not. You can list one file,
a whole folder (end it with `/`) or a pattern with `*`.

Use it for:

- **files you deleted on purpose**, such as library notes the project doesn't need
- **files you've taken over**, so ai-config stops offering new versions

An excluded file that isn't in git won't exist on a fresh clone. If you rewrote a shipped file and want to keep
it, commit it.

## `[remote]`: which servers are live

This tells the safety guard what your live (production) and staging servers look like. With it, Claude is
**blocked** from changing anything in production.

```ini
[remote]
production = /var/www/vhosts/example.org/www.example.org
production = example_prod, web-prod, @production
staging    = /var/www/vhosts/example.org/stg.example.org, example_stage
```

Each value is something that appears in a command aimed at that server: a folder path, an SSH host name, a
database name or a WP-CLI `@alias`. Matching ignores upper and lower case, and you can put several values on one
line, separated by commas.

What the guard does with a command sent to another server (`ssh`, `scp`, `rsync`, `wp @alias`, a remote database):

| The command… | Staging, or not listed | Production |
|---|---|---|
| Only reads harmless facts (versions, status, file lists, counts) | Runs | Runs |
| Shows file contents, settings or database rows | Asks | Asks |
| Changes something, or the guard doesn't recognize it | Asks | **Blocked** |
| Can't be checked (an interactive shell, a script file) | Asks | **Blocked** |

Three rules decide which server a command targets:

- **Any production value anywhere counts.** A staging host name with a production path is production.
- **The longest match is tried first.** So `stg.example.org` is matched as staging before `example.org` is tried.
- **Production always wins** when both match.

Without a `[remote]` section, nothing counts as production: remote changes ask, but aren't blocked.

If staging and production share a database server, add `assert-database = true` to the `[remote]` section. A change to staging is then
blocked unless the same command first checks which database it's connected to (`SELECT DATABASE()`).

`ai-config --doctor` tests that a production change really is blocked.

## `[scan]`: test files with fake passwords

The safety guard blocks any file that looks like it holds a real password or key. Tests for logins or payments
often need fake ones that look real. List those test files here so they can be read:

```ini
[scan]
allow = tests/fixtures/**, test-*.sh
```

This only skips the content check. Files like `.env`, keys and database dumps stay blocked whatever you list.

## `[gitignore]`: lines ai-config must not add

ai-config adds `.gitignore` lines suited to the stack. If this project is different (say it commits its
`vendor/` folder), list the lines to leave out:

```ini
[gitignore]
skip = /vendor/, *.sql
```

They're never added, and a refresh removes them from ai-config's part of `.gitignore`. To add lines of your own,
put them in `.gitignore` above ai-config's `(Added by ai-config …)` heading. ai-config never touches that part.

## `[sandbox]` and `[vscode]`

These set what a sandbox can reach, and the dev container's VS Code extensions and settings. See
[Sandboxes](sandbox.md).

## What `--doctor` checks

- whether `ai-config.conf` exists and is committed. An uncommitted one does nothing for a fresh clone
- files you deleted that aren't recorded yet, with the command to record them
- a `[decisions]` path that doesn't exist yet
- with `[remote]`: that a production change really is blocked
- without `[remote]`: a warning if the project seems to use `ssh` or `rsync`

`--uninstall` leaves `ai-config.conf` in place. It belongs to the project.
