<!-- BEGIN ORCHESTRATOR POLICY (managed by ai-config --orchestrator; do not edit between markers) -->
## Model & Delegation Policy

This project runs on an **Opus orchestrator + Sonnet implementer** setup.

- **Main session model:** Opus (pinned via `model` in `.claude/settings.local.json`).
- **Subagent model:** every subagent is forced to Sonnet via the
  `CLAUDE_CODE_SUBAGENT_MODEL` environment variable in `.claude/settings.local.json`.
  This wins over any subagent's own `model:` frontmatter, so delegated work never
  consumes the Opus quota.

Opus is the **manager**: it reasons, plans, architects, decides, and reviews. It
does not do the bulk of the typing.

- **Architecture, planning, and trade-off decisions:** handle here, in the main
  (Opus) thread.
- **Implementation, scaffolding, and routine refactors:** delegate to the
  `implementer` subagent (Sonnet). Give it a clear, self-contained spec — it
  starts with fresh context and cannot see this conversation.
- **Review:** review the implementer's output **here in the main thread** before
  accepting changes. Run `git diff`, check correctness, security, output
  escaping, and query safety, and send corrections back to the implementer as a
  new spec if needed. (Review stays in the main thread because the env var would
  otherwise pin a reviewer subagent to Sonnet too.)

Delegate implementation generously; keep judgment and review on Opus. Keep work
in the main thread only when it needs tight back-and-forth or shares a lot of
fast-evolving context.

> **Note:** `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` also pulls the built-in `Explore`
> agent up from Haiku to Sonnet. That stays on the Sonnet quota (never Opus), so
> it is harmless for cost — just slightly less efficient than letting Explore
> stay on the cheaper Haiku for file discovery.
<!-- END ORCHESTRATOR POLICY -->
