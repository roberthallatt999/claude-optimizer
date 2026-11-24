<!-- BEGIN ENGINEERING PRACTICES (managed by ai-config; do not edit between markers) -->
## Engineering Practices

Code quality matters more than speed here: one developer maintains everything, so code must
stay small, plain and checkable. Detail and per-stack examples:
`.claude/rules/engineering-practices.md`.

**How to work**

- **Think first.** State assumptions. If a request has more than one reading, or a simpler
  approach exists, say so before coding. If something is unclear, ask.
- **Read before you write.** Read the file, its caller and the shared helpers before adding
  code. Match the codebase's conventions even where you'd choose differently; raise a
  convention you think is harmful separately. When two patterns conflict, pick one (the
  newer or better-tested), say why, and flag the other. Never blend them.
- **Simplest thing that works.** Only what was asked: no speculative features, options,
  abstractions for single-use code, or error handling for impossible cases.
- **Surgical changes.** Every changed line traces to the request. Don't reformat, rename or
  refactor neighbouring code. Mention dead code or debt you notice; don't remove it. Remove
  only what your own change made unused.
- **Verifiable goals.** Turn the task into checks: "fix the bug" = a failing test, then the
  fix. For multi-step work, state the steps and how each is verified. For changes across
  several files, name the files first and edit one file at a time.
- **No hacks.** If the only way forward is a workaround, monkey patch or partial fix, stop.
  Fix the underlying cause properly, or say plainly that it can't be done cleanly and why.
- **Fail loud.** Never report success you didn't verify. Say what was skipped, what's
  uncertain, and any change that could be fragile.

**Security**

1. **Framework first.** Before writing login, sessions, access checks, sanitising,
   escaping, CSRF, rate limits or crypto, name what the framework or an official package
   provides and use it. Hand-rolled versions need the developer's agreement and a reason.
2. **A security claim needs a test.** A comment, docblock or commit message saying code
   protects against something needs a test that attacks it through a real request, not by
   calling the helper. No test: remove the claim or write the test.
3. **Attack test before the fix.** Run it first: it must fail on the current code. A test
   that passes before the fix proves nothing.
4. **Earlier comments are claims, not evidence.** Check the code and its tests.
5. **Server-side trust.** Check identity and permission in every endpoint and action.
   Secrets, sensitive logic and calculations stay on the server; never put secrets in
   client bundles or logs. Browser code never talks to the database directly.
6. **The pipeline checks.** Dependency audits, tests and static analysis run in CI. When
   adding a dependency or touching CI, check they do, and say if not.

**Code**

- Names say what a thing is for; no abbreviations unless universal. Named constants, not
  magic numbers.
- One job per function. If it needs a comment to explain *what* it does, split it.
  Comments explain *why*.
- Before adding to a file over ~500 lines of code, propose a split. Over ~1,000, split
  first (separate commit, no behaviour change) unless the developer says otherwise.
- Tests state why the behaviour matters and fail if the business rule changes.
<!-- END ENGINEERING PRACTICES -->