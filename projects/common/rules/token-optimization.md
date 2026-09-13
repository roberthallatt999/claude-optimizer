# Token Efficiency

Every turn re-sends the context, and output tokens cost more than input. These habits
keep sessions cheap without cutting corners on correctness.

## Context (input tokens)

- Locate before reading: Grep/Glob first, then Read the relevant range of large files.
- Don't re-read a file you already read this session unless it has changed.
- Skip generated or vendored content: lockfiles, `node_modules/`, `vendor/`, build
  output, minified bundles, DB dumps, and logs (use `tail`/`grep` on logs if needed).
- Filter noisy commands (`| tail -50`, `| grep -i error`, quiet/silent flags) instead
  of dumping full test, build, or install output.
- `.claude/libraries/*.md` are reference docs loaded on demand — read one only when
  the task actually involves that library. Path-scoped rules load automatically when
  you touch matching files.
- Hand broad exploration or large-output triage to a subagent so only its summary
  lands in the main context.
- In long sessions, `/compact` at natural breakpoints; start a fresh session for
  unrelated work.

## Output tokens

- Follow the **Response Style** section in `CLAUDE.md`.
- Prefer small targeted edits over full-file rewrites.
- Batch independent tool calls into a single turn.

## Memory

- Check `MEMORY.md` before rediscovering context; keep new entries to one line.
