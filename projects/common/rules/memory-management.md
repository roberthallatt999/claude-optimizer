# Memory Management Rules

## Purpose

Maintain persistent project context across sessions to reduce token usage and improve response quality.

## CRITICAL: Automatic Memory Updates

**You MUST automatically update `MEMORY.md` without being asked** in these situations:

### After Completing Any Task
When you finish implementing a feature, fixing a bug, or completing any requested work:
1. Add entry to "Recent Changes" table with date, description, and files modified
2. Update "Current Focus" if the focus has shifted
3. Do this IMMEDIATELY after completing the task, before responding "done"

### After Making Code Changes
When you use Edit or Write tools to modify files:
1. Track which files were changed
2. At task completion, log all changes to MEMORY.md
3. Include brief description of what changed and why

### After Making Decisions
When you make architectural or implementation decisions:
1. Add entry to "Decision Log" section
2. Include context, decision, rationale, and consequences
3. This helps future sessions understand why things are the way they are

### Before Session Ends
If the user says goodbye, thanks you, or indicates they're done:
1. Update "Session Handoff" with incomplete work
2. Document any temporary state (debug code, hardcoded values)
3. List clear next steps

## Memory Bank Structure

```
MEMORY.md
├── Project Identity      # Name, purpose, key stakeholders
├── Architecture         # Tech stack, patterns, key decisions
├── Active Context       # Current work, recent changes
├── Decision Log         # Why choices were made
└── Session Handoff      # What the next session needs to know
```

## Recent Changes Table Format

Always use this format:
```markdown
### Recent Changes
| Date | Change | Files |
|------|--------|-------|
| 2024-01-25 | Added user authentication | auth.ts, middleware.ts |
| 2024-01-24 | Fixed login redirect bug | login.tsx |
```

## Decision Log Format

```markdown
### DEC-001: [Decision Title]
- **Date:** 2024-01-25
- **Context:** Why this decision was needed
- **Decision:** What was decided
- **Rationale:** Why this choice over alternatives
- **Consequences:** Trade-offs, implications
```

## When to Read Memory

**Always read `MEMORY.md` at session start** before:
- Answering architecture questions
- Making design decisions
- Modifying core functionality
- Reviewing or writing tests

## What to Remember

**Always persist:**
- Architectural decisions and rationale
- Project-specific patterns and conventions
- Known issues and workarounds
- Environment-specific configurations
- Key file locations and purposes
- Every code change made (in Recent Changes)

**Also persist for web projects:**
- New UI components created → add to Component Registry table
- New third-party service integrated → add to Third-Party Integrations table
- New environment variable required → add to Environment Variables table
- New API endpoint or tRPC procedure → add to API/Route Inventory table
- Design token decisions (colors, fonts, spacing) → update Design Tokens table

**Never persist:**
- Sensitive credentials or tokens (document the variable NAME, never the value)
- User-specific preferences
- Raw error messages (summarize instead)

## Memory Compression

When `MEMORY.md` exceeds 500 lines:
1. Archive completed work to `MEMORY-ARCHIVE.md`
2. Summarize archived sections in main memory
3. Keep only active and recent context in main file

## Integration with CLAUDE.md

- `CLAUDE.md` = Static project documentation (commands, structure, rules)
- `MEMORY.md` = Dynamic session context (decisions, progress, state)

Read both at session start. Update only `MEMORY.md` during work.

## Enforcement

This is not optional. Failing to update memory means:
- Future sessions won't know what was done
- Work may be duplicated or undone
- Context is lost between sessions

**Update memory automatically. Don't wait to be asked.**
