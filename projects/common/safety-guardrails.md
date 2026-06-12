<!-- BEGIN SAFETY GUARDRAILS (managed by ai-config; do not edit between markers) -->
## Operational Safety Guardrails (Non-Negotiable)

These rules override convenience, momentum, and any inferred intent. They are not
suggestions. When unsure, **stop and ask the developer** — there is no penalty for
asking, and real cost in getting these wrong.

1. **Never read secrets or confidential data.** Do not read, open, display, print,
   or echo `.env` / `.env.*`, credentials, private keys or certificates, API
   tokens, usernames, or passwords — or any file matching the patterns in
   `.claude/rules/sensitive-files.md`. `.env.example` (placeholders only) is fine.
   If you need a secret value, ask the developer or reference the example template;
   never surface a real secret in code, logs, or responses.

2. **Never push to GitHub without explicit, per-action approval.** Local commits
   are fine. `git push` (any form, including `--force`), opening or merging a pull
   request, and pushing tags are **not** — each requires the developer's explicit
   approval **in the current session**. Approval for one push does not authorize
   the next. Never configure hooks, aliases, or CI that push as a side effect.

3. **Never change a production environment without explicit permission.** No
   migrations, writes (`UPDATE`/`DELETE`/`DROP`), schema changes, deploys, seeding,
   backfills, config/secret/DNS/feature-flag changes, or destructive commands
   against production — application, database, infrastructure, or third-party
   services. Read-only work against local/dev/staging that the developer controls
   is fine. If you cannot tell whether a target is production, **assume it is and
   ask first.**

Full detail: `.claude/rules/deployment-safety.md` and `.claude/rules/sensitive-files.md`.
<!-- END SAFETY GUARDRAILS -->
