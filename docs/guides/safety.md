# How it keeps you safe

Every project gets the same three promises, with no option to turn them off:

1. **Claude never reads secrets.** That means `.env` files, passwords, keys, certificates and tokens.
2. **Claude never pushes to GitHub without your yes**, every time. Local commits are fine.
3. **Claude never changes a live site without your permission.** That covers databases, deploys and files.

Telling Claude isn't enough, so each promise is enforced in several ways.

## The layers

| Layer | What it does |
|---|---|
| **Instructions** | `CLAUDE.md` spells out the three promises. Claude reads them in every session |
| **Permission rules** | `.claude/settings.local.json` lists files Claude can never read, and actions it must ask about first: push, open a pull request, publish, deploy, delete |
| **The safety guard** | A script that checks every command and file read before it runs. It catches what simple rules miss, such as a push hidden inside `bash -c "…"` |
| **The content check** | The guard opens a file before Claude reads it. If it holds something that looks like a password or key, the read is blocked |
| **The commit check** | A commit that contains a secret is stopped, whether Claude makes it or you do |
| **The computer-wide guard** | The installer turns the guard on for every Claude Code session on your computer, not only in ai-config projects |

## What the guard blocks, and what it asks about

| Blocked (no way around it) | Asks you first |
|---|---|
| Reading `.env`, keys, credential files, database dumps | `git push`, opening or merging a pull request |
| Reading any file whose contents look like a password or key | Publishing a package, deploying |
| Commands that print a secret, like `gh auth token` | `rm` and other deletes, `git reset --hard` |
| Changing anything on a server you marked as production | Running a command on another server that could change it |
| Writing a password into `MEMORY.md` | Editing the safety files themselves |

The same rules apply to MCP tools, which connect Claude to outside services. A tool that pushes, deploys, sends,
deletes or writes asks first. A tool that only reads goes ahead.

## Why a clean log file is still readable

Logs aren't blocked by name, because "read the error log" is an everyday request. Each log is scanned instead.
A clean one reads normally; one with a password in it is blocked. A guard that gets in the way all day gets
switched off, and then it protects nothing.

The check skips template files (`.example`, `.sample`, `.dist`) and lines that are plainly examples, such as
`your_password` or `${DB_PASSWORD}`. Files over 20 MB are blocked, not waved through.

## Files each stack protects

On top of the shared list, each stack blocks its own sensitive files:

| Stack | Also blocked |
|---|---|
| WordPress | `wp-config.php`, `wp-salt.php`, backup plugin folders, `*.sql` |
| WordPress (Bedrock) | `config/environments/`, backup folders, `*.sql` |
| ExpressionEngine | `system/user/config/`, `*.sql` |
| Coilpack | `system/user/config/`, Laravel session files, `*.sql` |
| Craft CMS | `storage/backups/`, `storage/runtime/validation.key`, `*.sql` |
| Next.js, T3 | `.vercel/project.json`, `prisma/*.db` |
| Astro + Strapi | `backend/.env`, `backend/.tmp/` |
| Astro + Sanity | `.sanity/`, `sanity.cli.env*` |

On a CMS site a loose `.sql` file is almost always a database dump, so it's blocked. On a JavaScript site it's
more likely a migration, so it stays readable.

## Live servers

Tell ai-config which servers are production in `ai-config.conf`. Claude is then blocked from changing them, while
read-only checks still work. See [`[remote]` in the project settings file](project-policy.md#remote-which-servers-are-live).

## When a step needs you

When Claude hits a blocked step, such as one that needs a password or production access, it doesn't try another
way round. It gives you the exact command to run yourself, in a separate Terminal window, and asks you only for
the result. It never asks you to paste a secret into the chat.

## Check that it works

`--doctor` feeds the guard a fake secret and confirms it gets blocked:

```bash
ai-config --doctor --project=.
```

Once a month, run the [monthly safety check](../runbooks/safety-checkup.md).

## Make it stronger (optional)

| Want | Do |
|---|---|
| Everyone who clones the repo gets the rules | `ai-config --shared-policy --project=.`, then commit `.claude/settings.json` and `.claude/hooks/safety-guard.sh` |
| Rules nobody can switch off on this computer | Install the managed settings. See [Sandboxes](sandbox.md#a-floor-for-the-whole-computer) |
| Claude can only reach sites you allow | Use a [sandbox](sandbox.md) |
| Names and emails hidden before Claude sees them | Set up [Philter](philter.md) |

## A note on `.claudeignore`

ai-config writes a `.claudeignore` file listing build output and dependencies. **Claude Code doesn't read this
file yet**
([open request](https://github.com/anthropics/claude-code/issues/29455)), so it protects nothing on its own. The
real blocks are the permission rules and the guard. The file is there to document the project's boundaries, and
for other tools that read that format.
