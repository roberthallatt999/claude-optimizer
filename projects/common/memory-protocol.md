<!-- BEGIN MEMORY PROTOCOL (managed by ai-config; do not edit between markers) -->
## Project Memory Protocol

This project keeps persistent, cross-session context in `MEMORY.md` at the project
root. Treat it as the running record of what has been done and why — keep it
current without being asked.

**At the start of every session**, read `MEMORY.md` before answering architecture
questions, making design decisions, or modifying core functionality.

**As you work, update `MEMORY.md` automatically:**

- After completing any task or code change, add a row to the **Recent Changes**
  table (`Date | Change | Files`).
- When you make an architectural or implementation decision, add a **Decision Log**
  entry (context, decision, rationale, consequences).
- Before a session ends (the developer says goodbye, thanks you, or signals
  they're done), update **Session Handoff** with incomplete work, temporary state,
  and clear next steps.

Never record secrets, credentials, or tokens in memory — summarize instead. When
`MEMORY.md` exceeds ~500 lines, archive completed sections to `MEMORY-ARCHIVE.md`.

`CLAUDE.md` is static project documentation; `MEMORY.md` is the dynamic session
record. Read both at session start; update `MEMORY.md` as you work.

Full protocol: `.claude/rules/memory-management.md`.
<!-- END MEMORY PROTOCOL -->
