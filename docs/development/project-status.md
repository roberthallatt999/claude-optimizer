# Project status

ai-config is in everyday use. It runs on about 30 projects.

## What's finished

| Area | State |
|---|---|
| Stacks | 19, including discovery mode for anything else. See [Supported stacks](../reference/stacks.md) |
| Safety | Secrets blocked by name and by content, risky actions ask first, live servers protected, secret check on every commit, a guard for the whole computer |
| Updates | Refreshes never overwrite your edits, and every change is backed up |
| Memory | `MEMORY.md`, or a `.okf/` folder with a template map for CMS sites |
| Project settings | `ai-config.conf` keeps a project's choices through a fresh clone |
| Sandboxes | Dev container, Enclave and Claude Code's own sandbox, all from one allow list |
| Many projects | `ai-config-fleet` checks or refreshes a whole folder |
| Tests | 29 suites, run on macOS and Ubuntu for every push |

## What's changed recently

The **Recent Changes** section of [`CLAUDE.md`](../../CLAUDE.md) describes each change and why it was made. For
the full history, run this in the ai-config folder:

```bash
git log --oneline
```

## Known limits

- `.claudeignore` protects nothing yet, because Claude Code doesn't read it
  ([open request](https://github.com/anthropics/claude-code/issues/29455)). The real protection comes from the deny
  rules and the safety guard.
- A refresh doesn't add `.vscode/` changes, or the Tailwind, Alpine.js and bilingual rules, to an existing
  project. See [Keep projects up to date](../guides/updating-projects.md#things-a-refresh-doesnt-add).
- Enclave has no block list, and only passes the GitHub token through.
