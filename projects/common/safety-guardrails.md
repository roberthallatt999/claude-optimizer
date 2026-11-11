<!-- BEGIN SAFETY GUARDRAILS (managed by ai-config; do not edit between markers) -->
## Operational Safety Guardrails

These take precedence over speed, momentum, and inferred intent. When unsure, stop and ask.

1. **Don't read or expose secrets.** Don't open, print, copy, or summarize `.env` /
   `.env.*`, private keys, certificates, credentials, tokens, or passwords
   (`.env.example` is fine). If you need a value, ask the developer. Never put a real
   secret in code, logs, commits, memory, or responses.
2. **Don't publish without per-action approval.** Local commits are fine. `git push`
   (any form), creating/merging/editing pull requests, releases, tags, and package
   publishing each need the developer's explicit "yes" for that specific action in
   this session. An earlier approval doesn't cover the next one.
3. **Don't change production without explicit permission.** No deploys, migrations,
   write queries, schema/config/secret/DNS/feature-flag changes, or destructive
   commands against production or any remote environment. If you can't tell whether
   a target is production, treat it as production and ask first.
4. **On remote servers and databases, read freely but change nothing unprompted.**
   Status, versions, listings, counts and hashes are fine. Prefer `COUNT(*)`, `wc -l`
   and `sha256sum` to printing files, config, logs or rows, which can carry secrets or
   personal data. Every remote write needs approval; a production write is the
   developer's to run, so give them the exact command. Name the path and database
   explicitly, and prove the database (`SELECT DATABASE()`) before any write: an SSH
   alias is not a boundary, because staging and production often share a host.

5. **Hand risky steps to the developer; don't work around them.** When a step needs a
   secret, production access, or anything blocked, give the exact command in a code block
   to run in their own terminal (a separate window: a `!` command in this chat sends its
   output back here), or numbered steps in the service's web dashboard (GitHub repo →
   Settings → Secrets and variables; Cloudflare → Workers → Settings → Variables). Say what
   it does and what to report back: only a non-secret result (done, an exit status, a
   count). Never ask for a secret to be pasted into the chat.

The harness enforces these with deny/ask rules in `.claude/settings.local.json` and
the `.claude/hooks/safety-guard.sh` PreToolUse hook. If a call is blocked, don't route
around it with a different command or tool: hand it off as in #5.
Production targets are declared under `[remote]` in `ai-config.conf`; remote writes
that name one are denied outright. Details: `.claude/rules/deployment-safety.md`,
`.claude/rules/sensitive-files.md`.
<!-- END SAFETY GUARDRAILS -->
