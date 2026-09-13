<!-- BEGIN MEMORY PROTOCOL (managed by ai-config; do not edit between markers) -->
## Project Memory Protocol

`MEMORY.md` (project root) is the cross-session record of what changed and why;
`CLAUDE.md` is static documentation. Keep `MEMORY.md` current without being asked.

- **Before substantive work** (design decisions, core changes, architecture
  questions), read `MEMORY.md`. Quick self-contained questions don't need it.
- **After a meaningful change** (feature, fix, refactor, config change — not trivial
  edits), add one row to **Recent Changes**: `Date | Change | Files`.
- **After an architectural decision**, add a short **Decision Log** entry (context,
  decision, rationale).
- **When the developer signals they're done**, update **Session Handoff** with
  unfinished work and next steps.

Keep entries terse and never record secret values. Past ~500 lines, archive completed
sections to `MEMORY-ARCHIVE.md`. Formats: `.claude/rules/memory-management.md`.
<!-- END MEMORY PROTOCOL -->
