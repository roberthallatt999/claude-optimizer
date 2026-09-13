---
paths:
  - ".okf/**"
---

# OKF Memory Bundle

Formats for `.okf/` ([OKF v0.2 spec](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)).
When to update it is in `CLAUDE.md` (Project Memory Protocol).

## Layout

```
.okf/
├── index.md        # entry point: links + one-line descriptions, grouped by heading
├── log.md          # dated change log (## YYYY-MM-DD)
├── handoff.md      # type: Session Handoff
├── decisions/      # type: Decision      one file per decision
├── architecture/   # type: Architecture  subsystems, data flow, directory map
├── integrations/   # type: Integration   third-party services, env var NAMES, MCP servers
├── conventions/    # type: Convention    patterns, components, design tokens
└── issues/         # type: Known Issue   bugs, workarounds, gotchas
```

Give a folder its own `index.md` (no frontmatter) once it holds more than ~10 concepts.

## Concept frontmatter

```yaml
---
type: Decision                      # required
title: Use Craft GraphQL for the Nuxt frontend
description: One sentence an agent can use to decide whether to open this file.
tags: [api, frontend]
status: stable                      # draft | stable | deprecated
generated: { by: claude-code/sonnet-5, at: 2026-09-13T14:30:00Z }
stale_after: 2027-03-13T00:00:00Z   # for facts that drift: versions, endpoints, hosting
sources:
  - id: gql-config
    resource: config/graphql.php
---
```

- `generated.by` names the agent (`claude-code/<model>`). `human:<id>` is only for the developer.
- `verified: { by: human:<id>, at: <ISO 8601> }` only when the developer confirms the concept.
- Cite where a claim came from with a footnote keyed to `sources[].id`:
  `Queries go through the GraphQL API.[^gql-config]`
- Link related concepts with bundle-relative links (`/decisions/…md`) and state the
  relationship in the sentence.
- Update a concept in place instead of adding a near-duplicate. Mark superseded concepts
  `status: deprecated` and link the replacement.

## Bodies

- Decision: `# Context`, `# Decision`, `# Consequences`.
- Integration: what it does, env var names (never values), where it is configured.
- Keep concepts short (roughly 20–60 lines); split rather than grow.

## log.md

```markdown
## 2026-09-13

- Added Stripe webhook handler ([integration](/integrations/stripe.md)) — `app/api/stripe/route.ts`
```

## Never

- Record secret values, credentials, customer data, or copied `.env` content.
- Add `verified` on the developer's behalf, or remove someone else's `verified` entry.

After editing, run `bash .claude/scripts/okf-check.sh`: fix ✗ errors, review ⚠ warnings.
