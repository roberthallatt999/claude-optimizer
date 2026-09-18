# Memory System Guide

The memory system provides persistent context across Claude Code sessions, reducing token usage and improving response consistency.

## Overview

The memory system consists of three components:

| Component | File | Purpose |
|-----------|------|---------|
| Memory Bank | `MEMORY.md` | Persistent project context |
| Memory Rules | `.claude/rules/memory-management.md` | Update protocols |
| Token Rules | `.claude/rules/token-optimization.md` | Efficiency guidelines |
| Memory Protocol | `CLAUDE.md` managed block | Always-on read/update instructions |

## MEMORY.md Structure

The memory bank template (`projects/common/MEMORY.md.template`) includes these core
sections, plus Design System, Third-Party Integrations, and Knowledge Base for web
projects:

### Project Identity
```markdown
## Project Identity

### Overview
- **Name:** Project Name
- **Type:** Web app / API / Library
- **Primary Language:** TypeScript / PHP
- **Framework:** Next.js / Laravel
```

### Architecture
```markdown
## Architecture

### Tech Stack
| Layer | Technology | Notes |
|-------|------------|-------|
| Frontend | React | Next.js App Router |
| Backend | Node.js | Express API |
| Database | PostgreSQL | Prisma ORM |

### Key Patterns
1. **Repository Pattern**
   - Where: `src/repositories/`
   - Why: Decouple data access from business logic
```

### Decision Log
```markdown
## Decision Log

### DEC-001: JWT vs Session Tokens
- **Date:** 2024-01-25
- **Context:** Needed stateless auth for API scalability
- **Decision:** JWT with refresh tokens
- **Rationale:** Enables horizontal scaling
- **Consequences:** Must handle token refresh
```

### Active Context
```markdown
## Active Context

### Current Focus
- [ ] Implementing user authentication
- [ ] Adding rate limiting

### Blockers
- Waiting on OAuth provider credentials

### Recent Changes
| Date | Change | Files |
|------|--------|-------|
| 2024-01-25 | Added login endpoint | auth.ts |
```

### Session Handoff
```markdown
## Session Handoff

### Last Session Summary
Implemented login endpoint, started logout.

### Next Steps
1. Complete logout endpoint
2. Add refresh token logic

### Temporary State
- Debug logging enabled in auth.ts (remove before PR)

### Open Questions
- Should refresh tokens be stored in Redis or DB?
```

## Memory Behaviors

This is the always-on **Project Memory Protocol** block ai-config appends to
`CLAUDE.md` (source: `projects/common/memory-protocol.md`), kept in sync with
`.claude/rules/memory-management.md` for formats:

### Before Substantive Work

Read `MEMORY.md` before design decisions, core changes, or architecture questions.
Quick, self-contained questions don't need it.

### After a Meaningful Change

Not trivial edits — a feature, fix, refactor, or config change gets one row in
**Recent Changes**: `Date | Change | Files`.

### After an Architectural Decision

Add a short **Decision Log** entry: context, decision, rationale.

### When the Developer Signals They're Done

Update **Session Handoff** with unfinished work and next steps.

Entries stay terse and never record secret values (variable names only). Past ~500
lines, archive completed sections to `MEMORY-ARCHIVE.md`.

## Token Optimization

`.claude/rules/token-optimization.md` is always loaded (unlike the path-scoped rules)
and kept compact for that reason:

### Context (input tokens)
- Grep/Glob before reading; read targeted ranges of large files, not whole files
- Don't re-read a file already read this session unless it changed
- Skip generated/vendored content (lockfiles, `node_modules/`, build output, logs)
- Filter noisy command output instead of dumping it in full
- Read a `.claude/libraries/*.md` reference only when the task involves that library
- Hand broad exploration or large-output triage to a subagent
- `/compact` at natural breakpoints in long sessions

### Output tokens
- Follow the **Response Style** block in `CLAUDE.md`
- Prefer small targeted edits over full-file rewrites
- Batch independent tool calls into a single turn

### Memory
- Check `MEMORY.md` before rediscovering context; keep new entries to one line

## Memory Compression

When `MEMORY.md` exceeds 500 lines:

1. Create `MEMORY-ARCHIVE.md`
2. Move old Decision Log entries (>30 days)
3. Summarize archived work
4. Keep only recent context in main file

```markdown
## Historical Context (Archived)

### Q4 2023: Authentication System
- Implemented JWT auth (DEC-001 through DEC-005)
- Added OAuth providers
- See MEMORY-ARCHIVE.md for details
```

## Deployment

Memory files are deployed automatically with every stack:

```bash
# Full deployment includes memory
ai-config --project=. 

# MEMORY.md is never modified once it exists
ai-config --refresh --project=.
ai-config --clean --force --project=.
```

`MEMORY.md` is created only if it doesn't already exist. No flag combination
overwrites, recreates, or deletes it: `--refresh` leaves it untouched, and `--clean`
moves aside `CLAUDE.md` and `.claude/` (to a timestamped backup under
`.claude/ai-config/backups/`) without touching `MEMORY.md` at all. The only way to
reset it is to delete or edit the file yourself. `--uninstall` also leaves it in place.

## Files in .gitignore

`ai-config` maintains these entries automatically; add them yourself if you manage
`.gitignore` differently:

```
CLAUDE.md
MEMORY.md
MEMORY-ARCHIVE.md
.claude/
```

`.claude/` already covers `.claude/ai-config/` (manifest, backups, staged updates) and,
with `--okf-memory`, `.okf/` is added as its own entry since it lives at the project
root. Memory and update-state files are personal/local context and shouldn't be
committed — the exception is `--shared-policy`, which carves `.claude/settings.json`
and `.claude/hooks/safety-guard.sh` back out of `.claude/` so teammates get the safety
policy too (see [Setup Script → --shared-policy](setup-script.md#--shared-policy)).

## OKF Memory Bundle (`--okf-memory`)

Opt-in alternative to `MEMORY.md` that stores project memory in Google's
[Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
(v0.2): a `.okf/` folder with one markdown file per concept, each with YAML frontmatter.
It works for every stack.

```bash
ai-config --project=. --okf-memory             # new project
ai-config --refresh --okf-memory --project=.   # existing project (MEMORY.md is kept, not migrated)
```

| MEMORY.md section | OKF bundle |
|---|---|
| Recent Changes | `.okf/log.md` (`## YYYY-MM-DD`) |
| Decision Log | `.okf/decisions/*.md` (`type: Decision`) |
| Architecture / Directory Map | `.okf/architecture/*.md` |
| Integrations, env var names, MCP servers | `.okf/integrations/*.md` |
| Component Registry, patterns, design tokens | `.okf/conventions/*.md` |
| Common Issues | `.okf/issues/*.md` |
| Session Handoff | `.okf/handoff.md` |

**Why use it**

- **Fewer tokens** — Claude reads the short `index.md` and opens only the concepts a task
  needs, instead of the whole `MEMORY.md`.
- **Trust signals** — `generated` (which agent wrote it), `verified` (`human:<id>` once you
  confirm it), `status`, and `stale_after` for facts that drift.
- **Portable** — plain files any agent can read (Claude Code, Codex via `AGENTS.md`, Cursor).

**What gets deployed**

- `.okf/index.md`, `log.md`, `handoff.md` — created only when missing, never overwritten
- An **OKF Memory Protocol** block in `CLAUDE.md` (replaces the MEMORY.md protocol block)
- `.claude/rules/okf-memory.md` — formats; loads only when Claude works in `.okf/`
- `.claude/scripts/okf-check.sh` — conformance errors (frontmatter, `type`, log dates) and
  hygiene warnings (stale concepts, broken links, credential-looking text); also runs on refresh
- `.okf/` added to `.gitignore`

**Template map (ExpressionEngine, Coilpack, Craft, Sage).** No code index parses EE tags,
Twig, or Blade, so for these stacks `--okf-memory` also generates
`.okf/architecture/templates.md` on every deploy and refresh: which templates extend, include,
embed, or use partials/components; the channels, sections, and add-ons each queries; a
reverse "included by" index; and Craft section → entry-template routes from
`config/project/sections/*.yaml`. It is plain pattern matching (no LLM tokens), multi-line tags
are handled, and `?` marks targets with no matching template file. The map is only rewritten
when relationships change, previous versions are backed up, and a map you edited is kept with
the new version staged. It is linked from `.okf/index.md` once.

Once a project has `.okf/index.md`, refreshes stay in OKF mode without the flag. Claude
maintains the bundle as it works; there is deliberately no per-commit LLM pipeline, which
would spend tokens on every commit and send source code to an API from a git hook.

## Integration with CLAUDE.md

| File | Type | Content |
|------|------|---------|
| `CLAUDE.md` | Static | Commands, structure, rules |
| `MEMORY.md` | Dynamic | Decisions, progress, state |

`CLAUDE.md` is always loaded; `MEMORY.md` is read before substantive work (see
[Memory Behaviors](#memory-behaviors) above). Update only `MEMORY.md` during work.
