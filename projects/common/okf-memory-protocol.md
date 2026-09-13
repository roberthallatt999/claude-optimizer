<!-- BEGIN OKF MEMORY PROTOCOL (managed by ai-config; do not edit between markers) -->
## Project Memory Protocol (OKF)

Project knowledge lives in `.okf/`, an Open Knowledge Format bundle: one markdown file per
concept, each with YAML frontmatter. `CLAUDE.md` is static documentation; `.okf/` is the
running record of what changed and why. Where this file mentions `MEMORY.md`, use `.okf/`.

- **Before substantive work**, read `.okf/index.md`, then open only the concepts the task
  needs — never the whole bundle. Quick self-contained questions don't need it.
- **After a meaningful change** (feature, fix, refactor, config change), add one bullet under
  today's `## YYYY-MM-DD` heading in `.okf/log.md`.
- **For durable knowledge** — a decision, convention, integration, or known issue — create or
  update one concept file and link it from `.okf/index.md`. Set `type`, `title`,
  `description`, and `generated: { by: claude-code/<model>, at: <ISO 8601> }`. Add a
  `verified` entry (`human:<id>`) only when the developer confirms the concept.
- **When the developer signals they're done**, update `.okf/handoff.md`.

Never record secret values — variable names only. After editing the bundle, run
`bash .claude/scripts/okf-check.sh`. A legacy `MEMORY.md`, if present, is read-only history.
Formats: `.claude/rules/okf-memory.md`.
<!-- END OKF MEMORY PROTOCOL -->
