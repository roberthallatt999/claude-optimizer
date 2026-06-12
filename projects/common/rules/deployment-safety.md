# Deployment & Production Safety

These are **hard guardrails**. They override convenience, momentum, and any
inferred intent. When in doubt, stop and ask the developer. There is no penalty
for asking; there is real cost in an unauthorized push or a production change.

## 1. Never push to GitHub without explicit authorization

Under **no circumstances** push commits, branches, or tags to any remote
(`git push`, `git push --force`, creating/merging a PR, etc.) unless the
developer has **explicitly authorized that specific push in the current
session**.

- Committing locally is fine. **Publishing is not** — pushing sends code to a
  shared, often public, remote that may be cached or indexed even if later
  deleted.
- "Commit and push" earlier in the conversation does **not** authorize later
  pushes. Approval is per-action, not standing.
- Opening, updating, or merging a pull request counts as pushing — same rule.
- Never enable auto-push hooks, CI triggers, or aliases that push as a side
  effect of another command.

**Always allowed without asking:** `git add`, `git commit`, `git status`,
`git diff`, `git log`, local branches.
**Requires explicit per-action approval:** `git push` (any form), `gh pr create`,
`gh pr merge`, tag pushes, release publishing.

## 2. Never change a production environment without explicit permission

Do **not** make changes against a production environment — application, database,
infrastructure, or third-party service — unless the developer has **explicitly
granted permission for that specific action** in the current session.

This includes, but is not limited to:

- **Production databases:** migrations, schema changes, `UPDATE`/`DELETE`/`DROP`,
  seeding, backfills, or running any write query against a production DB.
- **Deploys/releases** to a production host, server, or platform.
- **Production config / secrets / DNS / feature flags** that affect live users.
- **Destructive or irreversible commands** against production data or backups.

Safe by default: read-only inspection of local/dev environments, work against
local or staging databases the developer controls.

### How to recognize "production"

Treat an environment as production unless you have confirmed otherwise. Signals:
hostnames/URLs without `local`/`dev`/`staging`/`test`; `.env.production` or
production credentials; `--prod`/`production` flags; live customer data. If you
cannot tell whether a target is production, **assume it is and ask first**.

## When permission is required

State plainly what you intend to do, against which target, and why — then wait
for an explicit "yes." A one-time approval covers only that one action; it does
not extend to the next push or the next environment.
