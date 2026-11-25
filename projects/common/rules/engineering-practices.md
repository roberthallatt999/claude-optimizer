---
paths:
  - "**/*.{php,twig,html,js,mjs,cjs,ts,tsx,jsx,vue,svelte,astro,css,scss}"
  - "**/{tests,test,__tests__,spec,e2e}/**"
  - "**/.github/workflows/**"
  - "**/{composer.json,package.json,phpstan.neon,phpstan.neon.dist,phpunit.xml,phpunit.xml.dist}"
---

# Engineering Practices

Detail for the Engineering Practices block in `CLAUDE.md`. Part of it came from a security
review of an AI-built Laravel app: most findings sat in hand-written login, sanitising and
access-check code; two comments promised protection the code didn't give; a 2,300-line
component was too big to check; and nothing in the pipeline noticed packages going out of
date between sessions. The working-method rules adapt Andrej Karpathy's notes on common LLM
coding mistakes.

## Working method

### Think before coding

- State assumptions explicitly. If unsure, ask.
- If the request has more than one reading, lay them out; don't pick one silently.
- If there's a simpler approach than the one asked for, say so. Push back when it's warranted.
- If something is unclear, stop, name what's confusing and ask. Don't ask for information
  already in the conversation or the code.

### Read before you write

- Before adding code to a file, read its exports, the immediate caller and any obvious shared
  helpers. Reuse a helper before writing a new one.
- If you don't understand why existing code is shaped the way it is, ask before adding to it.
  "Looks unrelated" is how regressions start.
- Match the codebase's conventions (naming, structure, component style) even where you'd choose
  differently. Disagreement is a separate conversation: raise it, don't fork the style silently.
- When two existing patterns contradict, don't average them. Pick one (the newer or
  better-tested), explain why, and flag the other for cleanup.

### Simplicity

- Minimum code that solves the problem. No features, options or configurability beyond the
  request, no abstractions for code used once, no error handling for cases that can't happen.
- If 200 lines could be 50, rewrite it. Would a senior engineer call it overcomplicated?

### Surgical changes

- Every changed line should trace to the request. Don't "improve" adjacent code, comments or
  formatting, and don't suggest whitespace-only changes.
- Don't remove unrelated code or behaviour. Preserve existing structure.
- Remove imports, variables and functions *your* change made unused. Mention pre-existing dead
  code or debt; don't delete it unless asked.
- "Leave it cleaner" applies to the lines you're already changing. A wider cleanup is a
  separate, proposed change with its own commit.

### Verifiable goals

| Task | Becomes |
|---|---|
| Add validation | Tests for invalid input, then make them pass |
| Fix a bug | A test that reproduces it, then the fix |
| Refactor | Tests green before and after, no behaviour change |

For multi-step work, state the plan as `step → how it's verified`, and after each significant
step say what's done, what's verified and what's left. Don't continue from a state you can't
describe. For changes across several files, name the files first and edit one file at a time,
with all of a file's edits in one pass.

### No hacks; fail loud

- If the only way to deliver is a workaround, monkey patch or partial fix, stop. Either fix the
  underlying flaw properly, or say plainly: "I couldn't do this cleanly because the code lacks
  X", with the proper fix proposed.
- A breaking change is fine when it's the right design, but these are live sites: name what
  breaks, update every caller, and plan any data migration. Never break something silently.
- Report only what you verified. "Tests pass" is wrong if some were skipped; "migration done" is
  wrong if rows were skipped. After a change, name anything you're not confident in or that
  could be fragile.
- Verify facts (APIs, versions, config keys) against the code or official docs before stating
  them. Use the Context7 MCP server for library documentation when it's available.

## Code quality

- **Names** say what something is for and why it exists. No abbreviations unless universal
  (`id`, `url`, `html`).
- **Constants over magic numbers.** Name hard-coded values; keep them at the top of the file
  or in the project's constants/config file.
- **Single responsibility.** A function does one thing. If it needs a comment to explain what
  it does, split it. Move nested conditionals into well-named functions.
- **Comments explain why**, not what: the reason, the constraint, the non-obvious side effect.
  Document public APIs and complex algorithms. No comments about having understood a request.
- **DRY with judgement.** Extract when the same rule appears a third time, or when two copies
  must change together. Duplicated code that only looks alike can stay.
- **Encapsulation.** Hide implementation details behind a clear interface. Keep related code
  together and follow the project's file and folder naming.
- **File size.** A 2,300-line component can't be checked for access control by anyone, human
  or AI. Over ~500 lines of code, propose a split before adding more. Over ~1,000, split first
  (separate commit, no behaviour change, tests green), then add the feature, unless the
  developer says otherwise. Split along responsibilities: each action that changes data, with
  its authorisation, should be readable on one screen. Generated, vendored, data and migration
  files don't count.
- **Tests encode intent.** A test states why the behaviour matters and fails when the business
  rule changes. `expect(getUserName()).toBe('Ann')` is worthless if the function returns a
  hard-coded value. Cover edge cases and error paths. Keep tests readable.
- **Version control.** Small, focused commits with clear messages; meaningful branch names.

## Security

### Framework first

Ask "what does the framework, or its official package, already do for this?" before writing
any of the following, and use the answer:

| Need | Laravel / Coilpack | Craft CMS | ExpressionEngine | WordPress | JS frameworks |
|---|---|---|---|---|---|
| Login, reset, 2FA | Fortify / Breeze / Jetstream | Craft users & `UserController` | Member module | core login, `wp_signon` | Auth.js, the framework's auth adapter |
| Access checks | Gates, Policies, `authorize()`, `can` middleware | `requireLogin()`, `requirePermission()` | `ee('Permission')->can()` | `current_user_can()` | server-side checks in loaders/actions/route handlers |
| Input validation | Form Requests, `validate()` | model rules | form validation library | `sanitize_*()` | Zod / Valibot on the server |
| HTML from users | HTMLPurifier package, not regex | HTML Purifier field config | `ee('Security/XSS')->clean()` | `wp_kses()` | DOMPurify / sanitize-html |
| Output escaping | Blade `{{ }}` (never `{!! !!}` on user data) | Twig auto-escape (no `|raw` on user data) | template parser defaults | `esc_html()`, `esc_attr()`, `esc_url()` | framework escaping (no `dangerouslySetInnerHTML`, `v-html`, `{@html}` on user data) |
| CSRF | `@csrf`, `VerifyCsrfToken` | `{{ csrfInput() }}` | `{csrf_token}` | nonces | framework CSRF / same-site cookies |
| Rate limits | `RateLimiter`, `throttle` | plugin or web server | web server | plugin or web server | platform/edge limits |
| Client-side state | Livewire `#[Locked]`, re-authorise in every action | — | — | — | never trust hidden fields or client state |

When nothing fits, say so and get the developer's agreement before writing custom security
code. Record why the framework option didn't work, not a claim that the code is safe.

### Checklist for anything that handles data

- Check identity and permission in **every** endpoint, controller action, Livewire/component
  action and API route, not only in the UI that links to it.
- Return sensitive data only after the server has checked who is asking.
- Browser code never talks to the database: data goes through server code (controller, API
  route, server action) that checks access.
- API keys and secrets stay on the server. Only variables meant to be public reach client
  bundles (`NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`, `NUXT_PUBLIC_`); nothing else from `.env` is
  imported into client code.
- Prices, totals, permissions and other sensitive calculations run on the server. Client
  values are input, never truth.
- Validate and sanitise all input on the server, whatever the client already checked.
- Rate-limit login, password reset, forms, and anything that sends email or calls a paid API.
- Never log passwords, tokens, session IDs or full request bodies that may hold them.
- Dependencies get security patches promptly. Major or CMS upgrades go through the planned
  upgrade workflow (staging first), not ad-hoc bumps during feature work.

### Every security claim has a test

A security claim is any comment, docblock, commit message, PR text or MEMORY.md entry that says
code blocks, escapes, restricts or can't be tampered with.

- The test exercises the claim **the way an attacker would**: an HTTP request
  (`$this->post(...)`, `actingAs($otherUser)`), a Livewire `Livewire::test()->set()/call()` on
  a property the UI never exposes, a form post without the nonce, a fetch to the API route.
- Calling the helper directly doesn't count: it skips routing, middleware and binding, which is
  where gaps usually are.
- Point to the test when it isn't obvious: `// Covered by tests/Feature/EditorAccessTest.php`.
- No test and no time to write one: delete the claim. An untested comment is worse than none,
  because the next session trusts it.

### Attack test before the fix

1. Write the test that performs the attack.
2. Run it against the current code. It must **fail** (the attack succeeds).
3. If it passes, the test is wrong or the gap is somewhere else. Rewrite it until it fails.
4. Fix the code. Run it again: now it passes.
5. Report both runs (fail before, pass after).

### Earlier sessions' comments are claims, not evidence

Feature sessions trust what earlier sessions wrote. Near access control or input handling,
check that the code does what its comments say and that a test proves it. Report a mismatch
rather than quietly fixing around it.

## The pipeline checks things

These belong in CI (the deploy workflow, or a test job it depends on), so they run on every push
whether or not a session remembers:

| Project has | Pipeline step |
|---|---|
| `composer.lock` | `composer audit` |
| `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` | `npm audit --audit-level=high` (or the pnpm/yarn equivalent) |
| tests | `php artisan test`, `vendor/bin/phpunit`, `vendor/bin/pest`, `npm test` |
| PHPStan / Larastan config | `vendor/bin/phpstan analyse` |

`ai-config --doctor` reports which of these a project's workflows don't run. A project with no
CI (it only runs under DDEV) sets `ci-checks = false` in `ai-config.conf` to skip that check.
When you add a dependency, change CI, or finish a security fix, check the list and say what's
missing. Don't
add or change a deploy workflow without asking: a push to a deploy branch deploys.

## Review with fresh eyes on a schedule

A session briefed only to attack the app finds what months of feature sessions miss, because
those sessions trusted earlier comments. Once a quarter, or before a big release, suggest one:
a fresh session or a different model, told to ignore comments, list every route, action and
component that changes data, and try to reach each as the wrong user. `/security-review` is a
starting point. Record the date of the last review in MEMORY.md.
