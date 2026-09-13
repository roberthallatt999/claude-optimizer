---
paths:
  - "MEMORY.md"
  - "MEMORY-ARCHIVE.md"
---

# Memory Management

Formats for `MEMORY.md`. The when-to-update protocol lives in `CLAUDE.md`
(Project Memory Protocol).

## Structure

```
MEMORY.md
├── Project Identity   # name, purpose, stakeholders
├── Architecture       # stack, patterns, key decisions
├── Active Context     # current focus, Recent Changes
├── Decision Log       # why choices were made
└── Session Handoff    # what the next session needs
```

## Recent Changes (one row per meaningful change)

```markdown
| Date | Change | Files |
|------|--------|-------|
| 2026-01-25 | Added user authentication | auth.ts, middleware.ts |
```

## Decision Log

```markdown
### DEC-001: Decision title
- **Date:** 2026-01-25
- **Context:** why a decision was needed
- **Decision / Rationale:** what was chosen and why over alternatives
- **Consequences:** trade-offs worth remembering
```

## What to record

- Architectural decisions, project conventions, known issues and workarounds, key file
  locations.
- Web projects: new UI components (Component Registry), third-party integrations,
  required environment variable **names**, API routes/procedures, design-token
  decisions.

## What not to record

- Secret values (record the variable name only), personal preferences, raw error
  output (summarize), or anything already obvious from the code or git history.

## Compression

Past ~500 lines: move completed sections to `MEMORY-ARCHIVE.md`, leave a one-line
summary in their place, and keep only active context in `MEMORY.md`.
