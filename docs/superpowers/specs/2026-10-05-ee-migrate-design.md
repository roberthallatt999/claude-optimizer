# EE Migrate: safe ExpressionEngine migrations across the CPS fleet

- **Status:** approved design (2026-10-05), not yet planned
- **Owner:** Robert Hallatt
- **Applies to:** every ExpressionEngine project configured by ai-config — today cps, cfk, cpsp,
  cyntc, diabetes, intranet-backend (all EE 7.5.27)

## 1. Problem

Channel and field work is built locally in DDEV and has to reach staging and production through EE's
native migrations (`eecli.php make:migration` / `migrate` / `migrate:rollback`, tracked in
`exp_migrations`). Migrations written so far (28, all in cps) have shipped six distinct defects that
EE did not catch, each found only after deploy:

| Defect | Root cause |
|---|---|
| URL field / Grid column 500 on save (`in_array()` on `false`, `ft.url.php:63`) | settings missing `allowed_url_schemes` |
| Relationship publish screen 500 | `channels` stored as ints, `order_field` not a column name |
| Orphan Grid columns with NULL `field_id` | `grid_model::save_col_settings` called with positional args |
| Grid columns created without data columns | fieldtypes not loaded before `grid_model` use |
| Relationship rows written locally, zero on staging | `post_save` no-op for a field created earlier in the same run |
| False "table missing" | `table_exists()` caches per request |

Every one was a migration that ran without error and left the database subtly wrong. The goal is a
process where that is close to impossible: knowledge of each fieldtype's real contract, an automated
check that proves the result, rehearsal against a copy of the target, and a single gated path to the
servers that the safety guard enforces.

## 2. Scope

**In:** structure migrations (channels, fields, field groups, Grid/Fluid/File Grid columns, publish
layouts, category groups, statuses, channel–field assignments) and content migrations (seed, copy,
move, retire, relate entries).

**Fieldtypes — all 34 present today:**

- **27 shipped with EE 7.5.27:** checkboxes, colorpicker, date, duration, email_address, file,
  file_grid, fluid_field, grid, hidden, member, multi_select, notes, number, pro_variables, radio,
  range_slider, relationship, rte, select, selectable_buttons, slider, structure, text, textarea,
  toggle, url.
- **7 third-party types installed across the fleet:** wygwam, ansel, publish_sections,
  category_entry_picker, and the EE2-era playa, matrix, image_cropper (cpsp).

**Out:** moving content between different CMSs (stays with `data-migration-specialist`), EE core
upgrades (stay with `ee-upgrade`), template changes.

## 3. Decisions taken

| Question | Decision |
|---|---|
| Packaging | claude-config-repo is the single source of truth; shipped per project by `ai-config --refresh` (option A). A global `~/.claude/skills` symlink may be added later as a convenience. |
| Skill vs agent | Both: `ee-migrate` skill orchestrates in the main thread (approvals live there); `ee-migration-author` agent (Sonnet) writes migrations. |
| Who runs production | Claude, through one gated script, with Robert's approval on every production run. Raw `eecli migrate` on production stays denied. |
| Pre-flight depth | Local round-trip gate **plus** rehearsal on a fresh copy of the target database. |
| Content migrations | Included. |
| Sites without staging | Local gate + rehearsal on a production copy is the full gate (§7.3). |

## 4. Component overview

| Component | Purpose | Lives in | Reaches a site via |
|---|---|---|---|
| `ee-migrate` skill | The end-to-end process and approval stops | `projects/expressionengine/skills/ee-migrate/` | `--refresh` |
| Fieldtype references (34) | Per-type contract: settings, storage, create/change/remove, content writes, rollback, verification, gotchas | `…/ee-migrate/references/fieldtypes/<type>.md` | `--refresh` |
| `ee-migration-author` agent | Writes `up`/`down`/`verify` from a spec | `projects/expressionengine/agents/` | `--refresh` |
| `cps_tools` add-on | `cps:logs`, `cps:migrate-status`, `cps:schema-check` (read-only) | template in `projects/expressionengine/templates/cps_tools/`; committed per site under `system/user/addons/cps_tools/` | copied once, then updated by copy |
| `ee-migrate.sh` runner | The only path a migration takes to a server | template; committed per site as `.admin-scripts/ee-migrate.sh` with a site config block | copied once, then updated by copy |
| Guard rule + permissions + tests | Pre-approve / ask / deny the runner by mode and target | safety guard, EE `settings.local.json`, `test-safety-guard.sh` | `--refresh` |

Each unit has one job and a stated interface; the skill composes them and none of them depends on the
skill.

## 5. Fieldtype knowledge base

One markdown file per fieldtype, loaded only when a migration touches that type. Fixed template:

1. **Settings contract** — every key the fieldtype's `save_settings()` (and `grid_save_settings()`
   where different) writes, with PHP type and default; which keys are required for the publish form
   and `validate()` not to error.
2. **Storage** — columns added to `channel_data_field_N` (`settings_modify_column`), plus side tables
   (`exp_relationships`, `exp_grid_columns` + `channel_grid_field_N`, Fluid's
   `exp_fluid_field_data`, file usage tables) and how settings are encoded (base64-serialized for
   channel fields, JSON for Grid columns).
3. **Create / change / remove** — the supported call path as a top-level field, as a Grid column and
   inside Fluid, attaching to field groups and channels; each marked model API, legacy library, or
   "never raw SQL"; prerequisites (e.g. `fetch_installed_fieldtypes()` before `grid_model`).
4. **Content writes** — how to set a value on an entry so it persists, including relationships
   (`getAssociation()->add()`), Grid/Fluid rows and files.
5. **Rollback** — what `down()` must reverse, and what cannot be reversed without data loss (those
   migrations declare `backup-only rollback`).
6. **Verification** — exact queries and schema-check rules proving the change.
7. **Gotchas** — including the six in §1.

**Evidence standard.** Each file is written from the 7.5.27 PHP source of the fieldtype, the official
EE documentation (fieldtypes, Grid/Fluid, CLI, migrations, Model service) and vendor docs for
third-party types — never from memory. A file is marked `verified: <EE version>` only after its
**fixture migration** passes on cps.test: create the field (top-level, and as a Grid column and Fluid
child where the type allows), attach it, write a value, pass schema-check and `verify()`, roll back to
a byte-identical schema. Fixtures live beside the references and are re-run after every EE upgrade;
a failing fixture flags that recipe as unverified for the new version.

**Where fixtures run.** Core types run on cps.test. Third-party types run in the DDEV site that has
them installed: wygwam, ansel, publish_sections on cps.test; category_entry_picker on cyntc. Each
fixture is self-contained (creates and removes its own test channel) and is run inside the
`local test` round trip.

**Exceptions to "verified by fixture":**

- **playa, matrix, image_cropper** (EE2-era, cpsp only) get a "do not create; read and migrate-away
  only" reference. Their verification is a read-only fixture on cpsp: read existing values and
  confirm schema-check passes on the existing fields. No create recipe is offered.
- **structure** ships in EE 7.5.27 but the Structure add-on is not installed on any CPS site. Its
  reference documents the contract from source and states "requires the Structure module installed;
  not fixture-verified on this fleet". The runner refuses a migration that creates a `structure`
  field on a site without the module.

## 6. `cps_tools` add-on

Today's `cps_logs` add-on is renamed `cps_tools` (version 2.0.0); `cps:logs` keeps its behaviour. All
commands are read-only, need no add-on install, and run through EE's own DB connection.

**Rename from `cps_logs`.** One commit per site: new folder `system/user/addons/cps_tools/`
(namespace `CPS\Tools`, `upd.cps_tools.php`, `language/english/cps_tools_lang.php`), old
`cps_logs/` folder deleted. `cps_logs` was never installed on any site (no `exp_modules` /
`exp_extensions` row — commands register from `addon.setup.php` for every add-on on disk, verified
2026-10-05), so there is no database clean-up; the deploy's fresh release directory drops the old
folder.

### 6.1 `cps:migrate-status`

Lists pending core migrations **in the order EE will run them** (files not in `exp_migrations`,
sorted by filename) and recorded migrations whose file is missing. `--json` for the runner.

### 6.1a `cps:migrate-verify <migration-name>`

Loads the named migration class and calls its `verify()` (§6.3); prints failures and exits non-zero
on any. Exits 0 with "no verify()" when the method is absent.

### 6.2 `cps:schema-check [--channel=] [--field=] [--json] [--baseline=<file>] [--compare=<file>]`

| Check | Catches |
|---|---|
| Field and Grid column settings contain every key, with correct types, that the fieldtype's own `save_settings()` / `grid_save_settings()` produces (the contract is read from the fieldtype at runtime, cross-checked against the reference) | missing/mistyped settings |
| Every field has its `channel_data_field_N` table and the columns `settings_modify_column` requires; every Grid/File Grid field has `channel_grid_field_N` with a `col_id_N` per column | missing data columns |
| No Grid column with NULL/unknown `field_id`; no Fluid field referencing a deleted field | orphans |
| Smoke test: instantiate each fieldtype with stored settings; call `validate()` with sample values (empty, typical, scheme-less URL, out-of-range number, unknown option) and `display_field()` in try/catch — any error or exception fails | runtime crashes before an editor finds them |
| Publish layouts reference only attached fields; every attached field is placed or hidden | stale layouts |
| Relationship settings target existing channels; relationship and Fluid tables reference existing entries/fields | broken pickers |
| Field groups, channel assignments, category groups and statuses referenced by channels/fields exist | half-built channels |

Exit codes: 0 pass, 1 new failures, 2 could not run. Pre-existing issues are expected on live sites,
so gating uses `--compare` against a baseline: **no new failures**. The first run on each site is
reported to Robert as an audit and not fixed unasked.

**Read-only guarantee.** The structural checks (every row above except the smoke test) are pure
`SELECT`s and run anywhere, including servers. The **smoke test** calls fieldtype code
(`validate()` / `display_field()`, including third-party types such as wygwam and ansel, which may
load models or touch caches), so it runs **only in DDEV** — the local gate and rehearsals on a target
copy — and is skipped on servers (`--no-smoke` is forced when the runner calls it remotely). In DDEV
it is additionally wrapped in a transaction that is rolled back; that protects row changes only
(MySQL commits DDL implicitly), so the check also compares row counts of the `exp_*` tables before
and after and fails if any changed.

### 6.3 Migration `verify()` convention

A migration may define `public function verify(): array` returning failure messages (empty = pass),
asserting what must be true after `up()` — for content migrations, counts and relationships (e.g.
"4 `events` entries, each with 1 category and 2 relationship rows"). EE's abstract `Migration`
defines only `up()`/`down()`, so the extra method is ignored by EE; the runner calls it through
`cps:migrate-verify`. Required for content migrations, optional for structure-only ones.

`verify()` runs after `up()` has committed, so it is a **detector, not a gate**: locally and in
rehearsal a failure stops the process before any server is touched; on a server a failure means
`migrate:rollback --steps=1` where `down()` is trustworthy, otherwise restore from the backup taken
seconds earlier. That is why rehearsal on a target copy precedes every server run.

## 7. `ee-migrate.sh` runner

Identical script in every repo; only a config block differs: SSH host, remote paths, PHP binary,
database name, `EE_SUBDIR` (`ee/` for diabetes and intranet-backend), local CLI form (`ddev exec php`
vs `ddev ee`), `HAS_STAGING`, and the existing sync route for pulling a database copy.

### 7.0 How the runner drives EE's `migrate`

EE cannot target a single migration file: `migrate --core` runs every pending core file in filename
order, and `migrate:rollback` reverses files from the **last migration group** only. The runner
therefore never calls `migrate` blind:

1. It reads the ordered pending list (`cps:migrate-status --json`).
2. It requires that list to **equal** the expected set exactly, in order — no extra and no missing
   files. Anything else is a refusal, never a partial run.
3. It runs `migrate --core --steps=1` once per expected file, so each migration is its own group,
   and `migrate:rollback --steps=1` reverses exactly that one. `--core` is always passed (without a
   location flag EE prompts, which would hang a non-interactive run).

Consequence for sites with deliberately-unrun migrations (cps's two antiracism files): they keep
`apply` refusing until they are resolved with their existing runner (mark as applied, or delete) —
they can never be run as a side effect, and naming them in `--expect` is not an escape hatch.

### 7.0a Rehearsal stamps

Stamps are local to the developer's machine:
`.admin-scripts/.ee-migrate/stamps/<target>.json` (gitignored; added to each repo's `.gitignore` and
to the ai-config EE gitignore template). Format:

```json
{ "target": "staging", "commit": "<sha>", "pending": ["2026_10_05_090000_…"],
  "rehearsed_at": "2026-10-05T13:30:00Z", "rehearsal": "pass",
  "applied_at": null, "apply": null }
```

`apply` re-reads the remote pending list and the deployed commit and compares all of target, commit,
pending set and age (< 24 h) against the stamp. Production on a staging site additionally requires a
`staging.json` stamp with `"apply": "pass"` for the same pending set and commit.

### 7.0b Database copies for rehearsal

Every site already has `.admin-scripts/sync.sh`, the route Robert uses today. Rehearsal calls it for
the database only, then — because `sync.sh` can mask a failed import behind a zero exit code — it
verifies the import independently: table count and `exp_channel_titles` / `exp_channel_fields` row
counts in DDEV must match the same counts read from the target by `cps:migrate-status --json`
(which reports them). Mismatch → rehearsal fails and the snapshot is restored.

### 7.1 Modes

| Mode | Behaviour |
|---|---|
| `local test <migration>` | Requires the named migration to be the only pending file locally (otherwise refuses and lists what is pending). Backup (`ddev ee backup:database`, verified by size) → schema-check baseline → `migrate --core --steps=1` → `cps:migrate-verify` → schema-check incl. smoke test (no new failures) → `migrate:rollback --steps=1` → schema + settings dump byte-identical to baseline → `migrate --core --steps=1` again → schema-check. Any failure stops with the restore command. |
| `<staging\|prod> status` | Remote pending set + schema-check summary. Read-only. |
| `<staging\|prod> rehearse` | `ddev snapshot` → import fresh copy of the target DB via the existing sync route → run the full pending set → `verify()` → schema-check → restore snapshot and delete the imported copy. Writes a rehearsal stamp (target, pending set, commit, time). |
| `<staging\|prod> apply --expect=<names>` | Refuses unless: remote pending set equals `--expect` exactly; a passing rehearsal stamp for that set and commit exists, < 24 h old; the deployed release contains those files. Then: backup to the site's out-of-release backup directory, `chmod 600`, size compared to the previous dump → `migrate` → `verify()` → schema-check on the server → print backup name, rollback command and restore command. Records success in the stamp file. |

### 7.2 Production gate — sites with staging (cps, cpsp, cyntc)

Local gate → staging rehearsal → staging apply (recorded) → push code → production rehearsal is
optional → production apply requires the staging success for the same set and commit.

### 7.3 Production gate — production-only sites (cfk, diabetes, intranet-backend)

`HAS_STAGING=no`. Staging modes are rejected. Local gate → **mandatory** rehearsal on a fresh
production copy (same set, same commit, < 24 h) → production apply. All other checks are identical.

### 7.4 Ordering

Unchanged CPS rule: deploys ship code only. For a migration, push the code (which only adds the
migration file), then run `apply`, then push any templates that read the new structure — the
two-stage pattern already used for the events work.

## 8. Approvals (safety guard + settings)

| Command | Staging | Production |
|---|---|---|
| `ee-migrate.sh local test`, `<target> status`, `<target> rehearse` | allowed | allowed |
| `ee-migrate.sh staging apply` | **allowed** | — |
| `ee-migrate.sh prod apply` | — | **ask, every run** |
| raw `eecli.php migrate*` over SSH | ask | **deny** (unchanged) |
| raw `mysql`, `.sql` paths, DB login files | unchanged | unchanged |

Pre-approving `staging apply` is a deliberate loosening of today's "staging changes need a
heads-up" rule, chosen by Robert on 2026-10-05; the runner's checks (§7.0–7.1) are the heads-up, and
each staging apply prints its backup and rollback commands in the session.

The guard recognises the runner only when the command **starts** with `.admin-scripts/ee-migrate.sh`
or `bash .admin-scripts/ee-migrate.sh` (optionally after `cd <repo> &&`), with no pipes, `;`, `&&`
continuations, redirections or command substitution after it, and with a mode and target from the
fixed vocabulary. Anything else — `bash -c '…'`, an absolute or symlinked path, `eval`, extra
arguments it cannot classify — falls back to **ask** (and a raw `migrate` on production stays
**deny** wherever it appears). New cases in `test-safety-guard.sh` cover each row, plus attempts to smuggle a raw
`migrate` through the runner's arguments.

The production rehearsal brings member data into DDEV. It reuses the existing sync route (no new
download path) and deletes the imported copy when the snapshot is restored.

## 9. `ee-migrate` skill workflow

1. **Capture** — if built by hand in DDEV, diff the local schema against the last baseline so nothing
   clicked into the control panel is missed; otherwise write the change as a spec.
2. **Plan** — list migrations, fieldtypes and content touched; load only those references; one concern
   per migration, structure before content.
3. **Author** — hand a self-contained spec to `ee-migration-author`.
4. **Review & gate** — main thread reviews the diff (security, `down()` completeness, ids resolved by
   name, no raw SQL where an API exists), then `local test`; commit on the repo's branch convention.
5. **Ship** — rehearse → staging apply (if any) → push in two-stage order → production apply with
   Robert's approval.
6. **Record** — `.okf` log and memory; any new gotcha is added to the reference in claude-config-repo
   so every site gets it.

Carries existing rules: database before code, backups verified by size not exit code, never route
around the guard, approvals per action.

## 10. `ee-migration-author` agent

Sonnet. Input: a self-contained spec naming the repo, the change, and the reference files to load.
Output: the migration file (`up`, `down`, `verify` where required) and a short report including the
`local test` output. Works only in the target repo; never commits, pushes or touches a server. The
generic `data-migration-specialist` is left unchanged for cross-CMS work.

## 11. Existing migrations

The 28 cps migrations are already applied everywhere they should be. Rollout records them as the
baseline (no re-run). The two antiracism migrations that cps deliberately never ran stay handled by
their existing runner until Robert decides; `migrate-status` will keep surfacing them and `apply`
refuses while they are pending (§7.0) — they must be resolved first, never run as a side effect.

## 12. Build phases

Two implementation plans, so the safety tooling does not wait for the full research effort:

- **Plan 1 — tooling (phases 2–5 below).** Ships the add-on, runner, guard rules, skill and agent.
  Until Plan 2 lands, the skill loads references only for types that already have one and tells the
  author agent to read the fieldtype source directly for the rest.
- **Plan 2 — fieldtype knowledge (phase 1).** The 34 references and fixtures; can run in parallel
  once Plan 1's `local test` mode exists, since fixtures use it.

Each phase is shippable on its own.

1. **Fieldtype research** — 34 references, each proven by a fixture on cps.test. Largest phase
   (~2–3 days of agent time, mostly Sonnet).
2. **Add-on** — `cps_tools` with `migrate-status` and `schema-check`; first-run audit on all six sites,
   reported not fixed.
3. **Runner** — `ee-migrate.sh`, its tests, guard rule and permissions.
4. **Skill and agent.**
5. **Fleet rollout** — cps first, then cfk, cpsp, cyntc, diabetes, intranet-backend.

## 13. Success criteria

- Each of the six defects in §1, reintroduced as a test migration, is caught before anything reaches
  a server, by the named detector:

  | Defect | Detector |
  |---|---|
  | URL settings missing | schema-check settings contract + smoke test |
  | Relationship settings shape | schema-check settings contract + smoke test |
  | Orphan Grid columns | schema-check orphan check; round-trip byte-identical check |
  | Grid data columns missing | schema-check storage check |
  | Relationship `post_save` no-op (environment-dependent) | `verify()` — reliably only in **rehearsal on the target copy**, which is the reason rehearsal is mandatory before every server run |
  | `table_exists()` cache | round-trip (`down` then `up` in one process exposes it) + references forbid the call |

- All 27 core references and the 4 current third-party references carry `verified: 7.5.27` with a
  passing fixture; the 3 legacy references pass their read-only fixture on cpsp; `structure` is
  documented as unverified (§5).
- `apply` cannot run on a server without an exact pending-set match, a fresh passing rehearsal, and a
  verified backup; `test-safety-guard.sh` proves the approval table.
- A production-only site can ship a migration end to end with only DDEV as the test environment.

## 14. Risks

| Risk | Mitigation |
|---|---|
| Smoke test calls fieldtype code with side effects | Only `validate()`/`display_field()`; transaction always rolled back; fixtures prove no writes. |
| Third-party fieldtype behaviour undocumented | Source is the evidence; fixture must pass before the reference is trusted. |
| Rehearsal stamp spoofed or stale | Stamp binds target, pending set, commit and time; runner re-checks all four. |
| Baseline masks a real pre-existing defect | First-run audit is reported to Robert explicitly. |
| Runner and add-on copies drift between repos | Version in each; ai-config's existing `--doctor` health check gains a check that reports a copy older than the template. |
