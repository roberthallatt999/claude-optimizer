---
name: ee-migrate
description: >
  Create and ship ExpressionEngine migrations safely on CPS sites — new channels, fields, Grid/Fluid
  columns, field groups, layouts, categories, statuses, or entry content changes. Use whenever a
  change built in DDEV must reach staging/production, or Robert asks to add/change/reuse a field,
  channel or field group, write a migration, or run migrations on staging or production.
---

# EE Migrate

Robert is the sole developer. Anything drafted for him is first person singular ("I applied", never "we").
EE migrations that run without error can still leave the database subtly wrong, so every change goes through
the same gates. Do the steps in order; never skip one to save time.

## Procedure

1. **Capture.** If the change was built by hand in the DDEV control panel, diff the local schema against the
   last baseline (`cps:schema-check --compare=<file>`) so nothing clicked in the CP is missed. Otherwise
   write the change as a spec.
2. **Plan.** List the migrations, fieldtypes and content touched. One concern per migration; structure before
   content. Load `references/fieldtypes/<type>.md` for each type involved, only those; every fieldtype on the
   fleet has one (status table in `references/fieldtypes/README.md`). Where a reference says `verified: no`,
   the author agent also reads that fieldtype's `ft.*.php` (`save_settings`, `grid_save_settings`,
   `settings_modify_column`, `validate`) before writing settings. playa, matrix and image_cropper are
   read-and-migrate-away only. Fields of type `structure` need the Structure module, which no CPS site has;
   do not create one.
3. **Author.** Give `ee-migration-author` a self-contained spec: repo path, change, reference files to
   load, migration name. It writes `up`, `down` and `verify` and runs the local gate.
4. **Review, then gate (main thread).** Review the diff using the checklist below. Then run the local gate
   yourself and read the output:
   `.admin-scripts/ee-migrate.sh local test <migration>`
   Commit on the repo's branch convention (feature branch from `staging`; cfk and intranet-backend from `main`).
5. **Ship.** See "Shipping" below.
6. **Record.** Add an `.okf/log.md` entry and a memory note. Any new EE gotcha goes into the fieldtype
   reference in claude-config-repo so every site gets it.

## Runner commands

Run from the repo root, plainly (see "Guard and permissions"):

```
.admin-scripts/ee-migrate.sh local test <migration>
.admin-scripts/ee-migrate.sh <staging|prod> status
.admin-scripts/ee-migrate.sh <staging|prod> rehearse
.admin-scripts/ee-migrate.sh <staging|prod> apply --expect=<m1,m2,...>
```

- `local test` needs the named migration to be the only pending local file. It backs up, baselines
  schema-check, migrates, runs `verify()`, schema-checks (with smoke test), rolls back, requires a
  byte-identical schema, migrates again and re-checks.
- `local test`, `rehearse` and `run-fixtures.sh` refuse (exit 2) when `LOCAL_DB` is not the database EE is
  connected to (the `database` key of `cps:migrate-status --json`).
- `status` is read-only: the remote pending list plus a structural schema-check summary.
- `rehearse` snapshots the local DB, imports a fresh copy of the target database, runs the pending set one
  file at a time with `verify()` after each, schema-checks, then restores the snapshot. It writes a stamp
  (target, pending set, `pending_hash`, time) under `.admin-scripts/.ee-migrate/stamps/` (local, gitignored).
- `apply` refuses unless the remote pending set equals `--expect` exactly, a passing stamp for that set and
  `pending_hash` is under 24 hours old, and the release contains those files. It then takes and verifies a
  backup, migrates one file at a time (`migrate --core --steps=1`), runs `verify()`, schema-checks
  structurally, and prints the backup name plus the rollback and restore commands. Paste those in the session.
- Rehearsal never uses `sync.sh` (its `dev` mode uploads the local DB to staging). The runner calls only the
  read-only `export_db` / `download_db` / `import_db` functions from the shared library.

### Backup rule (every mode that changes a database)

No `migrate` or `migrate:rollback` call is ever made until a backup of that database has been taken and
verified in the same run: the file exists, is non-empty, is at least 90% of the size of the previous backup in
the same directory (first run: at least 1 MB), and for server backups is `chmod 600`. The exit code alone is
never trusted. Any failure aborts before the first `migrate` call. There is no flag to skip the backup.

## Shipping

- **Sites with staging (cps, cpsp, cyntc):** local gate, then staging `rehearse`, staging `apply`, push to
  production, then production `apply`. Production `apply` requires the staging success for the same set and
  `pending_hash`; a production rehearsal is optional.
- **Production-only sites (cfk, diabetes, intranet-backend; `HAS_STAGING=no`):** staging modes are rejected.
  Local gate, then a mandatory `prod rehearse` on a fresh production copy (same set, < 24 h), then production
  `apply`.
- **Order (two-stage):** push the code containing the migration file, then `apply`, then push the templates
  that read the new structure. Deploys ship code only; the database moves only through `apply`.
- `cps_tools` must already be deployed to a server before the runner can talk to it ("deploy it first").
- Pushes need Robert's explicit per-action approval, never implied. Production `apply` asks every run.
- `apply` refuses while any unexpected file is pending, including deliberately unrun ones. Naming them in
  `--expect` is not an escape hatch; resolve them first.

## Fixtures (after every EE upgrade)

`references/fieldtypes/run-fixtures.sh <site-repo> [type...]` (run from claude-config-repo) proves the
references against a site's DDEV: one verified backup, then per fixture migrate, `verify()`, schema-check,
roll back, byte-identical schema. Run it with no type list after every EE upgrade; a FAIL means a reference is
out of date for that version. It rolls back only a migration it recorded itself. If a run stops with
"cpsref rows already exist locally", run it once with `--cleanup`.

## cps_tools commands (add-on 2.1.0, no install needed)

- `cps:logs`; `cps:migrate-status [--json]`; `cps:migrate-verify <name>` (name before options; exit 0/1/2).
- `cps:schema-check [--json] [--no-smoke] [--baseline=F] [--compare=F]` (exit 0 pass, 1 new failures,
  2 could not run). `fail` means it breaks publish, save or a migration; leftovers are `warn`. The settings
  contract and the smoke test are DDEV-only; on servers they emit one "skipped: not DDEV" warning.
  Gating is "no new failures" against a baseline, since live sites carry old issues.

## Guard and permissions

- Run plainly from the repo root. `local test`, `status`, `rehearse` and `staging apply` run without
  prompting; `prod apply` always asks. Any wrapped, chained, piped or absolute-path form asks.
- Raw `eecli migrate*` on production is denied. If anything is blocked or asks unexpectedly, stop and tell
  Robert what you needed. Never route around the guard with another command or tool.
- Runner location: `.admin-scripts/ee-migrate.sh` (`/.admin-scripts` is gitignored on every site, so it is
  local to Robert's machine and never deployed). Install or update it with
  `ee-migrate-install.sh <repo>` from claude-config-repo; the config block is preserved. On a fresh machine
  refill the block (names and paths only) from that site's `sync.sh`. diabetes and intranet-backend (Laravel + EE, Coilpack) use
  `EE_SUBDIR="ee/"`, `REMOTE_ENV_EXPORT="yes"` (REMOTE_EECLI empty: the runner exports the release's
  dotenv, then calls `eecli.php`) and `LOCAL_EECLI="ddev exec .admin-scripts/eecli-local.sh"`, the same
  technique inside DDEV (the installer copies that script). `artisan eecli` rejects options on these
  sites and the `ddev ee` wrapper flattens exit codes, so neither is used.

## `verify()` convention

A migration may define `public function verify(): array` returning failure messages (empty means pass).
EE ignores it; `cps:migrate-verify` calls it after `up()`. Required for content migrations. It is a detector,
not a gate: a failure on a server means `migrate:rollback --steps=1` if `down()` is trustworthy, otherwise
restore the backup taken seconds earlier.

```php
public function verify(): array
{
    $failures = [];
    $channel = ee('Model')->get('Channel')->filter('channel_name', 'events')->first();
    if (! $channel) {
        return ['channel events does not exist'];
    }
    $count = ee('Model')->get('ChannelEntry')->filter('channel_id', $channel->channel_id)->count();
    if ($count !== 4) {
        $failures[] = "expected 4 events entries, found {$count}";
    }
    return $failures;
}
```

## Review checklist for the author's output

- Channel, field, group, category and status ids resolved by name, never hard-coded.
- `down()` complete, or the migration states `backup-only rollback` and why.
- No raw SQL where a model or legacy API exists; no `table_exists()`.
- Settings written in full per the fieldtype reference or `ft.*.php`.
- One concern per migration; `verify()` present for content migrations; `--core` migration (`make:migration`
  naming).
- The `local test` output is pasted in the report and shows every stage passing.

## Known EE pitfalls (each has shipped a defect)

- `eecli migrate` exits 0 when `up()` throws — check `cps:migrate-status`, never roll back blindly (an unrecorded
  migration has nothing to roll back; `migrate:rollback` would undo the previous, real one).
- URL fields and Grid columns need `allowed_url_schemes` and `url_scheme_placeholder`; without them the save
  500s (`in_array()` on `false`, `ft.url.php`).
- Relationship `channels` must be numeric strings, and `order_field` a real column name, or the publish
  screen 500s.
- Call `fetch_installed_fieldtypes()` before using `grid_model`, or columns are created without data columns.
- `grid_model::save_col_settings` takes `field_id` and `content_type` INSIDE the settings array; positional
  args leave orphan Grid columns with NULL `field_id`.
- Never `table_exists()`; it caches per request. Use `SHOW TABLES LIKE`.
- Relationship writes need `getAssociation()->add()`, not `Collection::add()` (silently writes nothing).
- A field created earlier in the same run may silently no-op relationship `post_save`; it can write rows
  locally and none on staging. Only rehearsal on a target copy, plus `verify()`, catches it.
- Field settings are base64-serialized; Grid column settings are JSON. Do not mix encodings.
- Server backups never go inside the release tree; the next deploy deletes them.
