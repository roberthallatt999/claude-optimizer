# Workflow skills

Every project gets 16 workflow skills from [Superpowers](https://github.com/obra/superpowers). A skill is a
written procedure Claude follows for one kind of job. Debugging, for example, means finding the cause before
changing any code.

You don't need to call them. Describe the job and Claude picks the skill that fits. To ask for one by name, say
so: "use the systematic-debugging skill".

## The skills

| Skill | Use it for |
|---|---|
| `brainstorming` | Turning an idea into a design, one question at a time, before any code |
| `writing-plans` | Writing a step-by-step plan once the design is agreed |
| `executing-plans` | Working through a plan in batches, checking as it goes |
| `verification-before-completion` | Proving the work is done before saying so |
| `systematic-debugging` | Any bug or failing test: find the cause first, then fix |
| `test-driven-development` | Writing the test first, watching it fail, then writing the code |
| `requesting-code-review` | Getting finished work reviewed |
| `receiving-code-review` | Working through review comments |
| `dispatching-parallel-agents` | Splitting independent work across several helpers |
| `subagent-driven-development` | Running a whole plan through helper agents |
| `using-git-worktrees` | Working on a feature in a separate copy of the repo |
| `finishing-a-development-branch` | Wrapping up a branch: tests, merge, clean up |
| `using-superpowers` | How the skills system works |
| `writing-skills` | Writing a new skill |
| `component-scaffolder` | A new React, Vue or Svelte component with its test |
| `design-system-builder` | Auditing design tokens and building a component library |

The old `/brainstorm`, `/write-plan` and `/execute-plan` commands still exist, but only to point Claude at the
matching skill.

## Choose which skills a project gets

All of them:

```bash
ai-config --project=.
```

Only the core ones (testing, debugging, brainstorming):

```bash
ai-config --project=. --superpowers-core
```

Only the ones you name:

```bash
ai-config --project=. --superpowers-skill=systematic-debugging,test-driven-development
```

None:

```bash
ai-config --project=. --no-superpowers
```

If you've turned on the Superpowers plugin for your whole computer, ai-config skips the project copy so the
skills don't load twice.

## The start-of-session reminder (off by default)

Superpowers can remind Claude about the skills at the start of every session. That costs about 1,300 tokens a
session, and it makes Claude reach for a skill on almost every task. It's off unless you ask for it:

```bash
ai-config --refresh --project=. --superpowers-bootstrap
```

Without it, the skills are still listed and work when a task calls for them.

## Write your own skill

Make a folder in `.claude/skills/` with a `SKILL.md` file inside:

```markdown
---
name: my-skill
description: When Claude should use this skill
---

# My skill

The steps to follow.
```

ai-config never touches a skill folder it didn't ship. The `writing-skills` skill has more guidance.

## Keeping the skills current (for whoever maintains ai-config)

The skills live in this repository's `superpowers/` folder, copied from
[this fork](https://github.com/roberthallatt999/superpowers). Every setup and refresh first tries to download
the latest version. If you're offline or the repository has uncommitted changes, it quietly uses the copy it
has.

To update by hand, run this from the ai-config folder. It needs a clean working tree:

```bash
./update-superpowers.sh
```

It prints the `git diff` command to review what changed. If the number of skills changed, update the count in
`CLAUDE.md` and on this page.

To skip the download for one run:

```bash
ai-config --refresh --project=. --skip-superpowers-update
```
