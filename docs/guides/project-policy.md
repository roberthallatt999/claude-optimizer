# Project Policy (`ai-config.conf`)

`ai-config.conf` is a small file at a project's root that records what *that project* has
decided about its own AI configuration. ai-config reads it on every run, before it writes
anything. It is meant to be committed.

## Why it exists

Everything else ai-config produces — `.claude/`, `CLAUDE.md`, `MEMORY.md`, `.okf/` — is
gitignored in most projects. That is usually the right call: the config is reproducible from
this script, so there is no reason to review it in a PR. The problem is what happens to the
parts that *aren't* reproducible.

Three kinds of local decision used to live only in those ignored files:

| Decision | Where the evidence lived | What happened next |
|---|---|---|
| A curated library set (framework references pruned after analysis) | the files' absence, plus `.claude/ai-config/manifest.tsv` | a fresh deploy re-added all of them |
| A decision log moved to a tracked file under `docs/` | a hand edit to `.claude/rules/memory-management.md` | the managed Memory Protocol block still said to write decisions to project memory, and re-asserted that on every run |
| Sticky flags (`--okf-memory`, `--orchestrator`, `--shared-policy`) | the presence of `.okf/`, `.claude/settings.json`, model keys in `settings.local.json` | a fresh clone has none of them, so the next run deployed the default |

The common thread is that the evidence for a decision sat inside the ignored tree. A fresh
clone — a new machine, a teammate, a rebuilt container — has no manifest and no stickiness
markers, so `ai-config --project=.` is a *first* deploy and rebuilds the stock config. Nothing
warns you; the pruned libraries are simply back and the decision log has quietly moved.

`ai-config.conf` is the one file that survives that, so it is where those decisions belong.

## Creating it

```bash
ai-config --save-policy --project=.
```

This inspects the project as it stands now and writes the file: the detected stack, the flags
currently in effect, and every file the manifest says ai-config installed that is no longer on
disk. Then commit it.

```bash
git add ai-config.conf && git commit -m "chore: record ai-config project policy"
```

Re-run `--save-policy` any time you prune more files. It keeps what is already in the file and
adds to it — hand-written values are never discarded, and a run that finds nothing new leaves
the file untouched rather than churning the timestamp.

## Format

```ini
[options]
# Flags this project always wants. An explicit command-line flag still wins.
stack = craftcms
okf-memory = true

[decisions]
# Architectural decisions are recorded here, not in project memory.
path = docs/decisions.md

[exclude]
# Shipped files this project removed on purpose, or has taken over.
.claude/libraries/react.md
.claude/libraries/vue.md
.claude/rules/my-own-rule.md
```

Blank lines are ignored, and so is anything after `#` at the start of a line or after ` #`
mid-line. An unknown section, a malformed line or an unknown key is reported and skipped — a
typo in a committed file can never block a deploy.

### `[options]`

Supplies defaults for the flags ai-config would otherwise have to infer. An explicit
command-line flag always wins, so `--stack=custom` still overrides `stack = craftcms` for that
one run.

| Key | Values | Equivalent flag |
|---|---|---|
| `stack` | any stack id | `--stack=` |
| `name`, `slug` | text | `--name=`, `--slug=` |
| `effort` | `low`…`max` | `--effort=` |
| `okf-memory` | `true`/`false` | `--okf-memory` |
| `orchestrator` | `true`/`false` | `--orchestrator` |
| `shared-policy` | `true`/`false` | `--shared-policy` |
| `with-openai` | `true`/`false` | `--with-openai` |
| `superpowers` | `true`/`false` | `--no-superpowers` |
| `eager-libraries` | `true`/`false` | `--eager-libraries` |
| `response-style` | `false` | `--no-response-style` |
| `claudeignore` | `false` | `--no-claudeignore` |
| `skip-vscode` | `true`/`false` | `--skip-vscode` |

`true`/`yes`/`on`/`1` and `false`/`no`/`off`/`0` are all accepted.

### `[decisions]`

```ini
[decisions]
path = docs/decisions.md
```

Where architectural decisions are recorded. Set it when decisions should live in a
version-controlled file rather than in project memory — so they land through review, and a bad
edit can be undone with `git checkout`.

The path is rendered into the managed **Project Memory Protocol** block in `CLAUDE.md` on every
run, which is the point: that block is regenerated from a template each time, so a hand edit to
it would not have survived. It is also rendered into `.claude/rules/memory-management.md` and
`.claude/rules/okf-memory.md`, including their `paths:` frontmatter, so the decision-record
format rule actually loads when Claude opens that file.

With `--okf-memory` the two settings compose: conventions, integrations and known issues still
go into the `.okf/` bundle, while decisions go to the path given here.

Unset, decisions default to `MEMORY.md`, or to a `type: Decision` concept file with
`--okf-memory`.

### `[exclude]`

Project-relative paths that ai-config must not create, update or stage. This is the one case
where a missing file does **not** mean "add it" — the additive model otherwise treats absence
as something to fix.

```ini
[exclude]
.claude/libraries/react.md      # one file
.claude/skills/brainstorming/   # everything under a directory
.claude/libraries/*.md          # a glob
```

A path listed here is left entirely alone, whether it exists or not. Use it for two things:

- **Files you deleted on purpose.** Framework library references pruned after analysis, skills
  you don't want, rules that don't apply.
- **Files you have taken over.** Listing a file stops ai-config touching it at all, including
  staging a new version in `pending/`. Note that on a fresh clone an excluded file that isn't
  tracked simply won't exist — if you have rewritten a shipped file and want to keep it, commit
  it or use `[decisions]` instead of excluding it.

### `[remote]`

```ini
[remote]
production = /var/www/vhosts/example.org/members.example.org
production = members_prod, websvr-members-prod, @production
staging    = /var/www/vhosts/example.org/stg.members.example.org, members_stage
```

What production and staging look like inside a command: vhost paths, SSH host aliases,
database names, WP-CLI `@aliases`. Values are case-insensitive substrings; repeat a key or
separate values with commas; a trailing slash is ignored.

`.claude/hooks/safety-guard.sh` reads this section directly on every Bash call. It parses
each remote invocation (`ssh`, `scp`/`rsync`, `wp @alias`/`--ssh=`, a database client with a
non-local host, any tool handed a remote database URI), following quotes, heredocs,
`bash -c` and `VAR=…; $VAR` indirection. It then classifies what the command would run:

| What the command does | Staging / undeclared | Production |
|---|---|---|
| Read-only, output-safe: versions, status, listings, `COUNT(*)`, hashes | runs | runs |
| Returns contents: `cat`/`tail`, `wp option get`, `config get`, `SELECT` rows, logs | asks | asks |
| Writes, or isn't recognised | asks | **denied** |
| Can't be inspected: interactive shell, script file, `< file`, tunnel | asks | **denied** |

Three rules decide the target:

- **The alias isn't a boundary.** A command matches production if a production marker
  appears anywhere in it: the host, the path, the database or a variable it assigns. The
  staging alias with a production path is production.
- **Longest marker first.** A staging path that contains the production one
  (`stg.members.example.org` contains `members.example.org`) is matched as staging before
  the production marker is tried, so it isn't mistaken for production.
- **Production wins.** If any production marker remains, the command is production.

"Runs" means the hook stops forcing a prompt for that command. The shared safety policy
allows `Bash(ssh:*)`, so read-only checks then run unprompted while the hook keeps gating
everything else. If the hook can't read the call (no `jq` or `python3` on PATH), it asks
before any `ssh` rather than letting the allow rule through unchecked.
Without a `[remote]` section the classifier still applies, but nothing counts as production,
so remote writes ask instead of being denied.

`assert-database = true` adds one rule for projects whose staging and production share a
database server: a write to staging is **denied** unless the same command runs
`SELECT DATABASE()` before it, so the target is proven, not assumed.

Server-side MySQL credential files (`~/.mysql-<site>-prod.cnf`, `.my*.cnf`) are secrets:
reading one is denied, while passing one to `mysql --defaults-extra-file=` is allowed.
`--doctor` probes every production marker, and `--save-policy` warns about a marker that
contains a space or `|`, since it could never match.

Edits to `ai-config.conf` itself ask for confirmation, because this section is part of the
safety policy.

## Health checks

`ai-config --doctor --project=.` reports:

- whether `ai-config.conf` exists, and whether it is **committed** — an uncommitted policy file
  does nothing for a fresh clone
- shipped files removed on purpose but **not** recorded, with the `--save-policy` command to fix
  it
- a `[decisions] path` that doesn't exist yet
- `[exclude]` entries that are still present on disk (informational — they are left alone)
- with `[remote] production` declared: a live test that the deployed hook denies a
  production write, and any marker under 4 characters (it would match unrelated commands)
- without it: a warning when `CLAUDE.md`, `MEMORY.md`, `.claude/` or `.okf/` show the
  project using `ssh`/`rsync`/`scp`

## What it does not cover

`ai-config.conf` records *policy*, not content. `MEMORY.md`, `.okf/` and any file you have
edited are still only as safe as your backups and your `.gitignore`. If the content of a file
matters — a decision log is the usual case — put it somewhere tracked and point `[decisions]`
at it, rather than relying on an ignored file surviving.

`--uninstall` leaves `ai-config.conf` in place. It is the project's file, not ai-config's.

## See also

- [Updating Projects](updating-projects.md) — how additive refresh decides what to write
- [Memory System](memory-system.md) — `MEMORY.md`, the OKF bundle, and the memory protocol block
- [Setup Script Guide](setup-script.md) — every flag
