# Token Optimization Rules

## Purpose

Minimize token consumption while maintaining response quality and context accuracy.

## Context Window Management

### Reading Files

**Prefer targeted reads over full files:**
```
# Good - Read specific section
Read file.ts lines 50-100

# Avoid - Reading entire large files
Read file.ts (2000+ lines)
```

**Use search before reading:**
```
# Good - Find then read
Grep for "handleAuth" → Read surrounding context

# Avoid - Reading files hoping to find something
Read auth.ts, then user.ts, then session.ts...
```

### Code Generation

**Generate minimal diffs:**
```
# Good - Targeted edit
Edit: Replace function X with optimized version

# Avoid - Rewriting entire files
Write: Complete new version of file
```

**Batch related changes:**
```
# Good - Single coherent change
Edit auth.ts: Update login, logout, and refresh together

# Avoid - Multiple round trips
Edit auth.ts: Update login
Edit auth.ts: Update logout
Edit auth.ts: Update refresh
```

## Response Efficiency

### Answer Structure

**Lead with the answer:**
```
# Good
The error is in line 42: missing null check.
Here's why...

# Avoid
Let me analyze the code...
Looking at the structure...
The error might be...
Actually, it's in line 42.
```

**Summarize before detail:**
```
# Good
Summary: 3 files need changes (auth.ts, user.ts, types.ts)
Details follow...

# Avoid
First, let's look at auth.ts... [500 tokens]
Now user.ts... [500 tokens]
And types.ts... [500 tokens]
So in summary, 3 files need changes.
```

### Avoiding Repetition

**Reference previous context:**
```
# Good
Using the auth pattern from earlier...

# Avoid
As I mentioned, the authentication system uses JWT tokens
which are stored in httpOnly cookies and refreshed...
[repeating 200 tokens of context]
```

**Use file references:**
```
# Good
See auth.ts:42 for the implementation

# Avoid
The implementation looks like this:
[pasting 50 lines of existing code]
```

## Tool Usage Optimization

### Parallel Operations

**Batch independent reads:**
```
# Good - Single turn, multiple reads
Read: package.json, tsconfig.json, .env.example

# Avoid - Sequential reads
Read: package.json
Read: tsconfig.json
Read: .env.example
```

### Search Strategy

**Use appropriate search scope:**
```
# Good - Scoped search
Grep "handleAuth" in src/auth/

# Avoid - Full codebase search
Grep "handleAuth" in ./
```

**Filter by file type:**
```
# Good
Glob "**/*.ts" then Grep

# Avoid
Grep everything, filter results
```

## Memory Integration

### Before Starting Work

1. Check `MEMORY.md` for existing context
2. Skip re-reading files already summarized
3. Use cached architectural decisions

### During Work

1. Build mental model incrementally
2. Don't re-explain established patterns
3. Reference decisions by ID from memory

### After Work

1. Update `MEMORY.md` with new context
2. Compress verbose findings to summaries
3. Remove temporary debugging context

## Anti-Patterns to Avoid

| Pattern | Problem | Solution |
|---------|---------|----------|
| Reading all project files | Token waste | Search first, read targeted |
| Explaining known patterns | Redundant | Reference MEMORY.md |
| Full file rewrites | Large diffs | Minimal edits |
| Repeating user request | Echo waste | Start with action |
| Verbose error analysis | Token heavy | Structured diagnosis |
| Re-reading unchanged files | Redundant | Trust memory |

## Context Efficiency Guidelines

| Task Type | Strategy |
|-----------|----------|
| Quick fix | Direct answer; read only the relevant file section |
| Feature add | Focused reads, batch edits, single coherent commit |
| Architecture | Memory-first, summarize findings before diving deep |
| Debug session | Systematic: reproduce → isolate → fix; avoid re-reads |
| Major refactor | Plan first with `/write-plan`, then `/execute-plan` in batches |

Claude Code manages its own context window automatically. Focus on strategies that avoid redundant reads and edits rather than trying to count tokens.
