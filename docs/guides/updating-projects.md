# Keep projects up to date

When ai-config gets new rules or fixes, your projects don't change on their own. You refresh each one.

## Refresh one project

From inside the project folder:

```bash
ai-config --refresh --project=.
```

To see what it would change first, without changing anything:

```bash
ai-config --refresh --dry-run --project=.
```

## What a refresh does with your files

A refresh never throws away your work. For each file ai-config ships:

| The file in your project is… | A refresh… |
|---|---|
| Missing | Adds it |
| Unchanged since ai-config wrote it | Updates it and keeps a backup of the old copy |
| Edited by you | **Keeps your version.** It puts the new version next to it for you to look at |
| Deleted by you on purpose | Leaves it deleted (see [Make deletions stick](#make-deletions-stick)) |

Some things it never changes:

- `MEMORY.md` is never touched.
- In `CLAUDE.md`, only ai-config's own marked sections are updated. Your text stays.
- In `settings.local.json`, entries are only ever added. Nothing of yours is removed.

Backups go in `.claude/ai-config/backups/`, one folder per run.

## Look at new versions of files you edited

When a refresh keeps your edited file, it saves the new version under `.claude/ai-config/pending/`, at the same
path. To compare the two, for example for `CLAUDE.md`:

```bash
diff CLAUDE.md .claude/ai-config/pending/CLAUDE.md
```

If you want all the new versions, this swaps them in. It backs up your copies first:

```bash
ai-config --refresh --apply-pending --project=.
```

If you want only some of them, copy those files over by hand.

## Make deletions stick

A refresh leaves deleted files deleted, but a fresh clone or a new computer doesn't know what you deleted. To
record it, run:

```bash
ai-config --save-policy --project=.
```

That writes the list into `ai-config.conf`. Commit that file. See
[The project settings file](project-policy.md).

## Refresh every project at once

`ai-config-fleet` finds every ai-config project under a folder. Change `~/sites` to the folder that holds your
projects.

List them:

```bash
ai-config-fleet --root=~/sites --list
```

Check them all (changes nothing):

```bash
ai-config-fleet --root=~/sites
```

Preview a refresh of them all:

```bash
ai-config-fleet --root=~/sites --refresh --dry-run
```

Refresh them all:

```bash
ai-config-fleet --root=~/sites --refresh
```

You get one line per project: ✓ fine, ⚠ warnings, ✗ failed. The full output for each project is saved in a log
folder, and the command tells you where.

## Start again from scratch

This moves the current setup into a backup folder, then sets the project up fresh. Nothing is deleted, and
`MEMORY.md` stays where it is.

```bash
ai-config --clean --force --project=.
```

Use it when a project's setup is badly out of date, or to pick up new VS Code settings. A normal refresh doesn't
touch `.vscode/`.

## Things a refresh doesn't add

A refresh adds most new rules, but a few are written only on the first setup:

- `.vscode/` settings
- the Tailwind, Alpine.js and bilingual rules, when you add one of those to an existing project

To get them, either copy the rule from `projects/<stack>/rules/` in this repository into `.claude/rules/`, or run
the clean setup above.

## After a refresh

1. Start a new Claude Code session, so it loads the new `CLAUDE.md`.
2. If `.vscode/` changed, reload VS Code: press `Cmd+Shift+P`, then choose **Developer: Reload Window**.

## Problems

| What you see | What to do |
|---|---|
| "stack is required" | The project's `CLAUDE.md` is from an old version. Name the stack: `ai-config --refresh --stack=craftcms --project=.` |
| A file you expected didn't change | You probably edited it. Look in `.claude/ai-config/pending/` |
| A ✗ in the health check | Run the refresh again. If it stays, run `ai-config --doctor --project=.` and read the fix it suggests |
