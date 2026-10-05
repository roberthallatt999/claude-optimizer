# EE Fieldtype References (Plan 2) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One evidence-based reference per ExpressionEngine fieldtype (34), each proven by a fixture migration, so `ee-migration-author` never has to guess a fieldtype's settings, storage or write path.

**Spec:** `docs/superpowers/specs/2026-10-05-ee-migrate-design.md` §2 (scope), §5 (reference template, evidence standard, exceptions), §13 (success criteria).

**Architecture:** References and fixtures live inside the shipped skill: `projects/expressionengine/skills/ee-migrate/references/fieldtypes/<type>.md` and `…/fixtures/<migration>.php`. A fixture is an ordinary EE migration (`up`/`down`/`verify`) that creates the field in a throwaway channel, writes a value, and removes everything. `run-fixtures.sh` runs fixtures against a site's DDEV using the Plan 1 tooling (`cps:migrate-verify`, `cps:schema-check`) and is re-run after every EE upgrade.

**Tech Stack:** PHP 8.2 / EE 7.5.27, Bash, the `cps_tools` add-on and `ee-migrate.sh` runner from Plan 1.

---

## Ground rules

- Repo: claude-config-repo, branch `feature/ee-fieldtype-references`. **Do not commit** — the controller commits after reviewing each batch. Never push. Never touch a server.
- Fixtures run only in DDEV. Stream 1 uses the cps site (`…/cps`, DB `admin_cps`); stream 2 uses cfk (`…/cfk`, DB `admin_cfk`). An agent works in exactly one stream and never runs anything in the other site.
- Never read `.env*`, `config.php`, `*.cnf`, dump files, `~/.ssh/*`. If the safety guard blocks a command, rephrase or use the Write tool; never route around it.
- Evidence, not memory: every statement in a reference comes from (a) the fieldtype's PHP source in `system/ee/ExpressionEngine/Addons/<addon>/ft.<type>.php` (and its libraries/models) for 7.5.27, (b) the official docs at `https://docs.expressionengine.com/latest/fieldtypes/<type>.html`, `…/development/fieldtypes/fieldtypes.html`, `…/development/fieldtypes/enhanced.html` (Grid/Fluid compatibility), `…/cli/built-in-commands/` (migrations), or vendor docs for third-party types; (c) what the fixture proved. Cite source file and method names (`ft.url.php::validate()`), not line numbers alone.
- A reference may say `verified: 7.5.27` only if its fixture passed `run-fixtures.sh`. Otherwise `verified: no` with the reason.

## File map

| Path | Responsibility |
|---|---|
| `skills/ee-migrate/references/fieldtypes/README.md` | Template + status table (controller updates the table) |
| `…/fieldtypes/<type>.md` | One reference per fieldtype |
| `…/fieldtypes/fixtures/2099_02_01_0000NN_cpsref_<type>.php` | Fixture migration for that type |
| `…/fieldtypes/fixtures/CpsRefFixture.php` | Shared helpers the fixtures `require_once` (channel/field-group/entry create+remove, by name) |
| `…/fieldtypes/run-fixtures.sh` | Runs fixtures in a site's DDEV; one backup, then per fixture: up → verify → schema-check compare → down → byte-identical check |

## Reference file format

Front matter, then the seven sections of spec §5 in this order and with these headings:

```markdown
---
fieldtype: url
addon: url            # folder under Addons/ (or third-party add-on name)
origin: core          # core | third-party | legacy
verified: 7.5.27      # or "no — <reason>"
fixture: 2099_02_01_000005_cpsref_url
fixture_site: cps
grid: yes             # usable as a Grid column
fluid: yes            # usable inside Fluid
---
# url

## Settings contract
## Storage
## Create / change / remove
## Content writes
## Rollback
## Verification
## Gotchas
```

Each section is concrete: the settings table lists every key with PHP type, default, and "required for validate()/display?" ; "Create" contains a minimal, complete, copy-pasteable PHP snippet (taken from the passing fixture) for top-level, Grid column and Fluid use where supported; "Verification" gives the exact SQL/CLI that proves it.

## Fixture contract

- Class name = camel-cased migration name; file requires `__DIR__ . '/CpsRefFixture.php'`… but EE loads the migration from the site's migrations folder, so `run-fixtures.sh` copies the helper alongside the fixture and the fixture requires it via `__DIR__`.
- Creates channel `cpsref_fixture` (+ field group of the same name where the site's schema has `short_name`, set it), a field `cpsref_<type>`, where the type supports it a Grid field `cpsref_<type>_grid` with a column of that type and a Fluid field `cpsref_<type>_fluid` containing it; one entry `cpsref-<type>` with a representative value written through the supported path.
- `verify()` asserts: settings stored contain every key in the reference's contract; data table/columns exist; the entry's value reads back; Grid row / Fluid row exist where created.
- `down()` removes everything it created, resolved by name; afterwards 0 rows for `cpsref%` channels, fields, field groups, grid columns, entries.

---

## Chunk 1: Infrastructure and exemplar

### Task 1: `CpsRefFixture.php`, `run-fixtures.sh`, exemplar `url`

- [ ] Write `run-fixtures.sh <site-repo> [type…]`: reads `LOCAL_EECLI` and `LOCAL_DB` from the site's `.admin-scripts/ee-migrate.sh`; refuses if anything is pending locally; takes ONE backup (`$LOCAL_EECLI backup:database`, size-checked like the runner); writes a schema-check baseline and a settings dump (same queries as the runner's `local test`); then for each fixture (all, or the named types): copy fixture + helper into the migrations folder (creating it if absent; `ddev mutagen sync` when available), `migrate --core --steps=1`, `cps:migrate-verify`, `cps:schema-check --json --compare` (smoke on; no new failures), `migrate:rollback --steps=1`, settings dump byte-identical to baseline, remove the files; prints `PASS|FAIL <type>` and a summary, exits non-zero on any failure; always removes its files and checks no `cpsref%` rows and no `2099_02_01` migration rows remain.
- [ ] Write `CpsRefFixture.php` (plain PHP class, no EE base class) with the shared create/remove helpers, using the APIs proven in Plan 1's fixtures (`templates/cps_tools/tests/fixtures/2099_01_01_0000{10,11,20,21,30}_*.php` in this repo — read them first).
- [ ] Write `fixtures/2099_02_01_000001_cpsref_url.php` and `url.md` to the format above. The URL contract must include `allowed_url_schemes` and `url_scheme_placeholder` and record the 2026-10-05 incident under Gotchas.
- [ ] Run `bash …/run-fixtures.sh ../cps url` → `PASS url`; re-run to prove idempotence; confirm no leftovers.
- [ ] Report; controller reviews and commits.

## Chunk 2: Core fieldtypes (two parallel streams)

Each task: for every type in the batch write the fixture, get `run-fixtures.sh <site> <type>` to PASS, then write the reference from source + docs + fixture. If a type cannot be created as a Grid column or Fluid child, say so with the source evidence (`accepts_content_type()`, the `$has_array_data`/Grid `grid_*` methods, Fluid's compatibility list) rather than forcing it.

### Task 2 (stream cps): text, textarea, number, email_address, colorpicker, notes
### Task 3 (stream cfk): select, multi_select, radio, checkboxes, selectable_buttons, toggle
### Task 4 (stream cps): date, duration, slider, range_slider
### Task 5 (stream cfk): rte, file, member
### Task 6 (stream cps): grid, file_grid, relationship
### Task 7 (stream cps, after Task 6): fluid_field (uses Grid and relationship children)

## Chunk 3: Third-party, legacy, unverifiable

### Task 8 (stream cps): wygwam, ansel, publish_sections — fixtures on cps
### Task 9 (cyntc DDEV): category_entry_picker — fixture on cyntc (`fixture_site: cyntc`)
### Task 10 (cpsp DDEV, read-only): playa, matrix, image_cropper — `origin: legacy`; no create recipe; fixture only reads existing fields' settings/values and asserts `cps:schema-check` passes for them; reference says "do not create; migrate away" and how to read existing data
### Task 11 (source only): hidden, structure, pro_variables — not installed on any CPS site; reference from source, `verified: no — add-on/fieldtype not installed on this fleet`; no fixture

## Chunk 4: Wrap-up

### Task 12
- [ ] Controller: fill the README status table (34 rows: status, verified, fixture site); run `run-fixtures.sh ../cps` (all cps fixtures) end to end; `./run-tests.sh`.
- [ ] Update `SKILL.md`: remove the "until a reference exists" fallback wording for types that now have one; point to `run-fixtures.sh` as the post-EE-upgrade check (and add that step to the notes for the `ee-upgrade` skill owner — report to Robert, since that skill lives in `~/.claude/skills`).
- [ ] Re-install the skill into the six site repos (copy `skills/ee-migrate`), commit there; pushes need Robert's approval.
