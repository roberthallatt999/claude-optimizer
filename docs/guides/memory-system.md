# How Claude remembers

Claude Code forgets everything when a session ends. ai-config gives each project a notes file, `MEMORY.md`, and
tells Claude when to read it and when to add to it.

## What Claude does with it

| When | Claude… |
|---|---|
| Before real work (a design choice, a core change, an architecture question) | Reads `MEMORY.md`. Quick questions skip it |
| After a meaningful change (a feature, fix, refactor or config change) | Adds one line under **Recent Changes**: date, what changed, which files |
| After an architectural decision | Adds a short entry under **Decision Log**: the situation, the decision, the reason |
| When you say you're done for now | Updates **Session Handoff**: what's unfinished and what's next |

Entries stay short. Claude never writes a password or key in it. It writes the variable's name, never its value.
The safety guard blocks it if it tries.

## What's in the file

The template starts with these sections. Claude fills them in as it learns the project:

- **Project Identity**: name, type, language, framework
- **Architecture**: the main pieces, patterns and where they live
- **Decision Log**: decisions and why they were made
- **Active Context**: current focus, blockers, recent changes
- **Session Handoff**: where the last session stopped
- For websites, also **Design System**, **Third-Party Integrations** and **Knowledge Base**

You can edit it too. It's a plain Markdown file.

## It's never overwritten

ai-config creates `MEMORY.md` only when the project doesn't have one. Refresh, clean setup and uninstall all
leave it alone. The only way to reset it is to edit or delete it yourself.

When it passes about 500 lines, Claude moves finished sections to `MEMORY-ARCHIVE.md`.

## Keep decisions in git

`MEMORY.md` isn't committed. To keep decisions in a file you commit instead, add this to `ai-config.conf`:

```ini
[decisions]
path = docs/decisions.md
```

Then refresh. See [The project settings file](project-policy.md#decisions-where-decisions-are-written-down).

## The alternative: a `.okf/` folder

`MEMORY.md` is one file that grows. With `--okf-memory`, Claude keeps its notes in a folder instead, one small
file per topic. It reads a short index first and opens only the topics a task needs, which saves tokens on big
projects. The format is Google's
[Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md), so other
AI tools can read it too.

Turn it on for a project:

```bash
ai-config --refresh --okf-memory --project=.
```

The first run copies what `MEMORY.md` already holds into the folder. Nothing is rewritten by AI, and `MEMORY.md`
itself is kept unchanged as history. After that the project stays in this mode without the option.

| In `MEMORY.md` | In `.okf/` |
|---|---|
| Recent Changes | `log.md` |
| Decision Log | `decisions/`, one file per decision |
| Architecture | `architecture/` |
| Integrations | `integrations/` |
| Conventions and patterns | `conventions/` |
| Common Issues | `issues/` |
| Session Handoff | `handoff.md` |

Each file records who wrote it and whether a person has checked it, so you can tell trusted notes from
guesses.

**Template map.** On ExpressionEngine, Coilpack, Craft and Bedrock (WordPress) sites, headless ones included, `--okf-memory` also builds
`.okf/architecture/templates.md`. It lists which templates include or extend which, and which channels or
sections each one uses. It's built by plain pattern matching, so it costs no tokens, and it updates on every
refresh.

## Saving tokens

One rule, `.claude/rules/token-optimization.md`, loads in every session. It tells Claude to:

- search before reading, and read only the part of a big file it needs
- skip generated files: lockfiles, `node_modules/`, build output
- read a library note only when the task involves that library
- keep answers short (the **Response Style** section of `CLAUDE.md`)
