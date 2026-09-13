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

The harness enforces these with deny/ask rules in `.claude/settings.local.json` and
the `.claude/hooks/safety-guard.sh` PreToolUse hook. If a call is blocked, don't route
around it with a different command or tool — say what you need and ask the developer.
Details: `.claude/rules/deployment-safety.md`, `.claude/rules/sensitive-files.md`.
<!-- END SAFETY GUARDRAILS -->
