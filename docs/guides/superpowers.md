# Superpowers Workflow Skills

Superpowers is an agentic skills framework that provides structured workflows for Claude Code. It transforms ad-hoc coding into disciplined, systematic development.

**Source:** [github.com/obra/superpowers](https://github.com/obra/superpowers)

## Overview

Superpowers combines composable "skills" with specialized instructions to guide Claude through structured development processes:

1. **Discovery** - Understand requirements through conversation before coding
2. **Design Review** - Present specifications in digestible sections for validation
3. **Planning** - Create implementation strategies with TDD and YAGNI principles
4. **Execution** - Tackle tasks systematically with quality checkpoints
5. **Verification** - Ensure completeness before marking work done

## Installation

Superpowers is automatically deployed with every AI Config setup:

```bash
ai-config --project=/path/to/project 
```

**What gets deployed:**
- `.claude/skills/superpowers/` - 15 workflow skills
- `.claude/commands/` - Slash commands (brainstorm, write-plan, execute-plan)
- `.claude/hooks/` - Session hooks for auto-bootstrap

### Disable Superpowers

If you don't want Superpowers:

```bash
ai-config --project=/path/to/project --no-superpowers
```

## Available Skills

### Core Workflow Skills

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `brainstorming` | Turn ideas into designs | Before any creative work |
| `writing-plans` | Create implementation plans | After design is validated |
| `executing-plans` | Execute in batches with checkpoints | When implementing a plan |
| `verification-before-completion` | Quality checks | Before marking work done |

### Testing & Debugging

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `systematic-debugging` | Root cause analysis | Any bug, test failure, or unexpected behavior |
| `test-driven-development` | TDD workflow | Writing new functionality |

### Collaboration

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `requesting-code-review` | Request reviews | When code is ready for review |
| `receiving-code-review` | Handle feedback | When receiving review comments |
| `dispatching-parallel-agents` | Multi-agent coordination | Complex tasks needing parallelization |
| `subagent-driven-development` | Agent orchestration | Large-scale development |

### Git Workflows

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `using-git-worktrees` | Isolated workspaces | Feature development |
| `finishing-a-development-branch` | Branch completion | Merging finished work |

### Meta Skills

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `using-superpowers` | Skill system guide | Understanding how to use skills |
| `writing-skills` | Create custom skills | Building new skills |
| `memory-management` | Persistent context | Managing project memory |

## Slash Commands

Three commands are deployed for quick access:

### /brainstorm

**Use before any creative work** - creating features, building components, adding functionality.

```
/brainstorm Add user authentication to the app
```

**What it does:**
1. Explores requirements through questions (one at a time)
2. Proposes 2-3 approaches with trade-offs
3. Presents design in small sections for validation
4. Documents validated design to `docs/plans/`

### /write-plan

**Use after design is validated** - creates detailed implementation plan.

```
/write-plan
```

**What it does:**
1. Breaks design into bite-sized tasks
2. Identifies dependencies and order
3. Creates test-first approach
4. Outputs plan for review

### /execute-plan

**Use when ready to implement** - executes plan with checkpoints.

```
/execute-plan
```

**What it does:**
1. Works through tasks in batches
2. Pauses at review checkpoints
3. Handles blockers systematically
4. Verifies completion

## The Iron Rules

Superpowers enforces disciplined development:

### 1. Skills Are Mandatory

If a skill applies (even 1% chance), it MUST be invoked:

> "If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill."

### 2. No Fixes Without Investigation

The systematic-debugging skill enforces:

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

Random fixes waste time and create new bugs.

### 3. One Question at a Time

During brainstorming, Claude asks ONE question per message to avoid overwhelming.

### 4. Incremental Validation

Designs are presented in 200-300 word sections, validating each before continuing.

## Red Flags

These thoughts mean STOP - you're rationalizing skipping the process:

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "This doesn't need a formal skill" | If a skill exists, use it. |
| "Quick fix for now, investigate later" | First fix sets the pattern. Do it right. |
| "Just try changing X and see if it works" | Systematic debugging is faster than thrashing. |

## Workflow Examples

### Building a New Feature

1. **User:** "Add a dark mode toggle"
2. **Claude:** Invokes `brainstorming` skill
3. **Claude:** Asks questions one at a time about requirements
4. **Claude:** Proposes approaches (CSS variables vs. Tailwind dark: vs. etc.)
5. **Claude:** Presents design in sections for validation
6. **User:** Approves design
7. **Claude:** Invokes `writing-plans` to create implementation plan
8. **Claude:** Invokes `executing-plans` to implement
9. **Claude:** Invokes `verification-before-completion` to ensure quality

### Debugging a Bug

1. **User:** "Tests are failing in the auth module"
2. **Claude:** Invokes `systematic-debugging` skill
3. **Phase 1:** Reads error messages, reproduces issue, checks recent changes
4. **Phase 2:** Finds working examples, compares differences
5. **Phase 3:** Forms hypothesis, tests minimally
6. **Phase 4:** Creates failing test, implements fix, verifies

## Customizing Skills

Skills are markdown files in `.claude/skills/superpowers/`. Each has:

```markdown
---
name: skill-name
description: When to use this skill
---

# Skill Title

## Overview
...

## The Process
...
```

### Adding Custom Skills

1. Create directory in `.claude/skills/`
2. Add `SKILL.md` with frontmatter
3. Document the workflow

See `writing-skills` skill for detailed guidance.

## Integration with Memory System

Superpowers works with the [Memory System](memory-system.md):

- Memory bank provides project context for skills
- Skills reference memory for project-specific knowledge
- Decisions from brainstorming sessions update memory

## Disabling for Specific Sessions

If you need to work without Superpowers for a session:

```
Please work without invoking skills for this session
```

## Maintaining Superpowers (Upstream Updates)

Superpowers is a **third-party repository** vendored into `superpowers/` as a
**squashed git subtree** — not a submodule. There is no `.gitmodules` file; the
files live directly in this repo's history, which is why deployment can copy them
without any extra clone or checkout step.

- **Source fork:** [github.com/roberthallatt999/superpowers](https://github.com/roberthallatt999/superpowers) (branch `main`) — tracks [obra/superpowers](https://github.com/obra/superpowers) upstream
- **Vendored prefix:** `superpowers/`
- **Current version:** see `version` in `superpowers/.claude-plugin/plugin.json`

### Automatic updates on deploy/refresh

Every `ai-config` deploy or `--refresh` (when Superpowers is enabled) runs
`update-superpowers.sh` **before** copying skills into the target project, so each
deployment ships the current set. This is **best-effort**: if the optimizer repo
has uncommitted changes, you're offline, or `git` is unavailable, it prints a
warning and falls back to the already-vendored copy — it never blocks the deploy.

> **Note:** the update targets the **claude-optimizer repo itself** (where the
> subtree lives), not the project being configured. A successful pull creates a
> squashed merge commit in this repo.

Opt out for a single run:

```bash
ai-config --refresh --project=. --skip-superpowers-update
```

### Manual update

Run the helper directly from the repository root (clean working tree required):

```bash
./update-superpowers.sh           # verbose
./update-superpowers.sh --quiet   # only warnings (how setup-project.sh calls it)
```

The script pulls from the fork with `git subtree pull --prefix=superpowers … --squash`,
collapsing upstream history into a single merge commit (matching how the subtree
was originally added). It preflight-checks for a clean tree and a reachable remote,
and on a conflict it aborts the merge to leave the tree clean.

### After updating

1. **Review the diff** — the script prints the exact `git diff <before> <after> -- superpowers/` command to run.
2. **Check the skill count** — the setup script and docs reference a specific number
   of deployed skills. If upstream adds or removes skills, update those references
   (`CLAUDE.md`, this guide, `docs/reference/commands.md`).
3. **Verify deployment** — run a `--dry-run` against a test project to confirm the
   skills still copy into `.claude/skills/superpowers/` as expected:
   ```bash
   ai-config --dry-run --project=/path/to/test-project
   ```

### Resolving conflicts

Because this repo only **reads** from `superpowers/` (deployment copies files out;
we don't edit them in place), conflicts are rare. If you have local modifications
inside `superpowers/`, prefer making them as deploy-time overrides in the stack
templates instead — keeping `superpowers/` a pristine mirror of the fork makes
future `subtree pull`s conflict-free.

## Next Steps

- **[Memory System](memory-system.md)** - Persistent context guide
- **[Setup Script](setup-script.md)** - Deployment options
- **[Commands Reference](../reference/commands.md)** - All available commands
