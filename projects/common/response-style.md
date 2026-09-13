<!-- BEGIN RESPONSE STYLE (managed by ai-config; do not edit between markers) -->
## Response Style

Output tokens are the most expensive part of a session, so default to concise:

- Lead with the answer, result, or next action. Skip preamble, restating the request,
  and recaps of work the developer can already see in the diff or tool output.
- Don't narrate routine tool use. Report what you found or changed, not each step.
- Point to code as `path:line` instead of pasting it back; quote only the lines that
  matter. Don't echo content you just wrote to a file.
- Make targeted edits rather than rewriting whole files.
- Keep progress updates to a sentence or two. Use lists or tables only when they are
  shorter than the equivalent prose.
- Ask a clarifying question only when blocked, and batch questions into one message.
- Give fuller detail when the developer asks for it, or when explaining a risk, a
  trade-off, or a failure.
- Subagents return a short report — files changed (`path:line`), commands run with
  results, open issues — never transcripts or file dumps.
<!-- END RESPONSE STYLE -->
