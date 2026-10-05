# EE Migrate Tooling (Plan 1) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the safety tooling from the EE Migrate spec — the `cps_tools` add-on (`migrate-status`, `migrate-verify`, `schema-check`), the `ee-migrate.sh` runner, guard rules + permissions, the `ee-migrate` skill and `ee-migration-author` agent — and roll it out to all six CPS EE sites.

**Spec:** `docs/superpowers/specs/2026-10-05-ee-migrate-design.md` (read it first; section numbers below refer to it).

**Architecture:** Canonical source for everything lives in claude-config-repo under `projects/expressionengine/`. The add-on and runner are *templates* copied into each site repo by a small installer (they run on servers, so each repo commits its own copy); the skill, agent, guard rule and permissions ship through `ai-config --refresh` as usual. Development loop: edit the template → install into cps → test in cps DDEV.

**Tech Stack:** PHP 8.2 / ExpressionEngine 7.5.27 CLI commands; Bash (runner, installer, tests); the existing ai-config safety guard (`projects/common/hooks/safety-guard.sh`) and its Bash test harness.

---

## Ground rules for every task

- Repos: claude-config-repo `/Users/webdeveloper/Web/code/github.com/canadian-paediatric-society/claude-config-repo` (branch `feature/ee-migrate`, already exists); cps `/Users/webdeveloper/Web/code/github.com/canadian-paediatric-society/cps` (create branch `feature/ee-migrate-tooling` from `staging` in Task 1).
- **Never push, never touch a server, never commit in a repo other than the one the task names.** Pushes and server runs happen only in Chunk 6, each with Robert's explicit approval.
- Never read `.env*`, `system/user/config/config.php`, `*.cnf`, `*.sql*`, `~/.ssh/*`. The safety guard blocks these; do not route around it — stop and report.
- Local DB for cps is `admin_cps` (`ddev mysql admin_cps …`). Back up before any local migration run: `ddev ee backup:database` (writes to `system/user/cache/`).
- PHP: PSR-12, 4-space indent, typed params/returns, single quotes. Bash: 2-space indent, `set -uo pipefail`, functions over inline blocks.
- Commit messages: conventional commits, ending with the `Co-Authored-By:` trailer given in the session's attribution reminder (at time of writing `Claude Opus 5.5 <noreply@anthropic.com>`). Avoid the words "credentials"/"password" in commit messages (the guard flags them).

- **Local eecli form.** Sites whose EE lives in `ee/` (diabetes, intranet-backend) only load their CLI DB config through `ddev ee`; the others use `ddev exec php system/ee/eecli.php`. Every test harness and the runner use one variable from the start: `LOCAL_EECLI` — test harness default: `ddev ee` if `ee/system/user` exists, else `ddev exec php system/ee/eecli.php`; runner: a config-block entry (Task 10).
- **Facts verified 2026-10-05 (no need to re-check):** `decide()` in the guard exits immediately; `getNewMigrations('ExpressionEngine')` returns sorted names without paths; `ee('Migration', $model)->getMigrateInstance()` works; `Cli::$arguments` is argv from index 2, so pass the migration name **before** options; `backup:database --absolute_path --file_name` writes exactly the given name (no suffix added); every deploy writes `.commit_hash` at the release root (seen on staging); stack `agents/*.md` are auto-copied by `setup-project.sh`; cps has **no** locally pending migrations and the antiracism migration files no longer exist in the repo.

## File map

claude-config-repo (canonical):

| Path | Responsibility |
|---|---|
| `projects/expressionengine/templates/cps_tools/addon.setup.php` | Registers the four commands |
| `…/cps_tools/upd.cps_tools.php` | No-op installer (harmless if clicked) |
| `…/cps_tools/language/english/cps_tools_lang.php` | Option descriptions |
| `…/cps_tools/Commands/CommandLogs.php` | `cps:logs` (moved from cps_logs, namespace changed) |
| `…/cps_tools/Commands/CommandMigrateStatus.php` | `cps:migrate-status` |
| `…/cps_tools/Commands/CommandMigrateVerify.php` | `cps:migrate-verify` |
| `…/cps_tools/Commands/CommandSchemaCheck.php` | `cps:schema-check` — CLI wiring only |
| `…/cps_tools/Library/Checks/SettingsContract.php` | Settings-contract check (stored settings vs fieldtype `save_settings([])`) |
| `…/cps_tools/Library/Checks/Storage.php` | Data tables/columns exist |
| `…/cps_tools/Library/Checks/Orphans.php` | Grid/Fluid/relationship orphans |
| `…/cps_tools/Library/Checks/Layouts.php` | Publish layouts vs attached fields |
| `…/cps_tools/Library/Checks/References.php` | Relationship targets, field/category groups, statuses |
| `…/cps_tools/Library/SmokeTest.php` | Fieldtype validate/display smoke test (DDEV only) |
| `…/cps_tools/Library/Report.php` | Result collection, baseline write/compare, exit code |
| `…/cps_tools/README.md` | Usage + limits |
| `…/cps_tools/tests/test-cps-tools.sh` | Integration tests, run inside a site's DDEV |
| `…/cps_tools/tests/fixtures/*.php` | Fixture migrations reproducing the six defects |
| `projects/expressionengine/templates/ee-migrate/ee-migrate.sh` | Runner (config block + logic) |
| `projects/expressionengine/templates/ee-migrate/tests/test-ee-migrate.sh` | Runner unit tests (stubbed `ssh`/`ddev`) |
| `projects/expressionengine/templates/ee-migrate/tests/stubs/{ssh,ddev}` | Stubs used by the tests |
| `ee-migrate-install.sh` (repo root) | Copies templates into a site repo; preserves the runner's config block |
| `test-ee-migrate-install.sh` (repo root) | Installer tests (config-block preservation on re-install) |
| `projects/expressionengine/skills/ee-migrate/SKILL.md` | The process |
| `projects/expressionengine/skills/ee-migrate/references/fieldtypes/README.md` | Reference template + status table (Plan 2 fills it) |
| `projects/expressionengine/agents/ee-migration-author.md` | Author agent |
| `projects/common/hooks/safety-guard.sh` | New "EE migration runner" section |
| `projects/expressionengine/settings.local.json` | allow + ask entries |
| `projects/expressionengine/gitignore-security.txt` | ignore `.admin-scripts/.ee-migrate/` |
| `setup-project.sh` | copy `ee-migrate` skill; `--doctor` drift check |
| `test-safety-guard.sh` | runner cases |

Site repos (installed copies): `system/user/addons/cps_tools/` (or `ee/system/user/addons/cps_tools/`), `.admin-scripts/ee-migrate.sh`.

---

## Chunk 1: `cps_tools` add-on — rename, `migrate-status`, `migrate-verify`

### Task 1: Scaffold the template from `cps_logs` and install into cps

**Files:**
- Create: `projects/expressionengine/templates/cps_tools/` (all files listed above except Library/, SchemaCheck, tests)
- Create: `ee-migrate-install.sh`
- Modify (cps): delete `system/user/addons/cps_logs/`, add `system/user/addons/cps_tools/`

- [ ] **Step 1: Branch cps.**
  ```bash
  cd /Users/webdeveloper/Web/code/github.com/canadian-paediatric-society/cps
  git switch staging && git pull --ff-only && git switch -c feature/ee-migrate-tooling
  ```
- [ ] **Step 2: Copy `cps_logs` into the template folder and rename.** `cp -R cps/system/user/addons/cps_logs claude-config-repo/projects/expressionengine/templates/cps_tools`, then:
  - rename `upd.cps_logs.php` → `upd.cps_tools.php`, class `Cps_logs_upd` → `Cps_tools_upd`;
  - rename `language/english/cps_logs_lang.php` → `cps_tools_lang.php`; keep keys, prefix stays `cps_logs_option_*` for `cps:logs` options;
  - `Commands/CommandLogs.php`: namespace `CPS\Tools\Commands`; its `loadAddonLang()` path → `cps_tools_lang.php`;
  - `addon.setup.php`: name `CPS Tools`, version `2.0.0`, namespace `CPS\Tools`, description `Read-only CLI tools: logs, migration status/verify, schema check.`, commands map (add the other three now; their classes come in Tasks 2–3 and Chunk 2):
    ```php
    'commands' => [
        'cps:logs' => CPS\Tools\Commands\CommandLogs::class,
        'cps:migrate-status' => CPS\Tools\Commands\CommandMigrateStatus::class,
        'cps:migrate-verify' => CPS\Tools\Commands\CommandMigrateVerify::class,
        'cps:schema-check' => CPS\Tools\Commands\CommandSchemaCheck::class,
    ],
    ```
  - README: replace "cps_logs" with "cps_tools"; add a "Canonical source: claude-config-repo `projects/expressionengine/templates/cps_tools`; install with `ee-migrate-install.sh`" line; remove the "copy to all repos" paragraph.
- [ ] **Step 3: Write `ee-migrate-install.sh`** (repo root, executable):
  ```bash
  #!/usr/bin/env bash
  # ee-migrate-install.sh <site-repo-path> — copy the cps_tools add-on and ee-migrate.sh runner
  # templates into an EE site repo. The runner's CONFIG block (between the
  # "# >>> site config" and "# <<< site config" markers) is preserved when the file exists.
  set -uo pipefail
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TPL="${EE_MIGRATE_TEMPLATES:-$SCRIPT_DIR/projects/expressionengine/templates}"
  repo="${1:?usage: ee-migrate-install.sh <site-repo-path>}"
  [[ -d "$repo/.git" ]] || { echo "not a git repo: $repo" >&2; exit 2; }

  sub=""; [[ -d "$repo/ee/system/user" ]] && sub="ee/"
  addons="$repo/${sub}system/user/addons"
  [[ -d "$addons" ]] || { echo "no EE addons dir under $repo" >&2; exit 2; }

  rm -rf "$addons/cps_tools"
  cp -R "$TPL/cps_tools" "$addons/cps_tools"
  rm -rf "$addons/cps_tools/tests"      # tests stay in claude-config-repo
  [[ -d "$addons/cps_logs" ]] && rm -rf "$addons/cps_logs" && echo "removed superseded cps_logs/"

  mkdir -p "$repo/.admin-scripts"
  runner="$repo/.admin-scripts/ee-migrate.sh"
  if [[ -f "$TPL/ee-migrate/ee-migrate.sh" ]]; then
    if [[ -f "$runner" ]]; then
      # Multi-line values break BSD awk -v, so carry the block through a temp file.
      cfg_file=$(mktemp)
      sed -n '/^# >>> site config/,/^# <<< site config/p' "$runner" > "$cfg_file"
      [[ -s "$cfg_file" ]] || { echo "existing runner has no site config block — not overwriting" >&2; rm -f "$cfg_file"; exit 2; }
      sed -e "/^# >>> site config/r $cfg_file" \
          -e '/^# >>> site config/,/^# <<< site config/d' \
          "$TPL/ee-migrate/ee-migrate.sh" > "$runner.new" && mv "$runner.new" "$runner"
      rm -f "$cfg_file"
    else
      cp "$TPL/ee-migrate/ee-migrate.sh" "$runner"
      echo "NEW runner: fill in the site config block in $runner"
    fi
    chmod +x "$runner"
  fi
  grep -q '^\.admin-scripts/\.ee-migrate/' "$repo/.gitignore" 2>/dev/null \
    || printf '\n# ee-migrate rehearsal stamps (local only)\n.admin-scripts/.ee-migrate/\n' >> "$repo/.gitignore"
  echo "installed cps_tools $(grep -o "'version' *=> *'[^']*'" "$addons/cps_tools/addon.setup.php" | grep -o "[0-9.]*") into ${repo##*/}"
  ```
- [ ] **Step 3b: Installer test (`test-ee-migrate-install.sh`).** In a `mktemp -d` fake repo (`git init`, `mkdir -p system/user/addons/cps_logs .admin-scripts`) with a runner whose config block says `SITE="kept-value"`, and a fake template dir (passed via `EE_MIGRATE_TEMPLATES`) whose runner block says `SITE=""`: run the installer twice; assert `cps_logs/` is gone, `cps_tools/` exists without `tests/`, the runner contains `SITE="kept-value"` exactly once and no `SITE=""`, and `.gitignore` contains `.admin-scripts/.ee-migrate/` exactly once. Also: an existing runner with no markers → exit 2 and file unchanged. Run it — FAIL before Step 3, PASS after.
- [ ] **Step 4: Install into cps and confirm `cps:logs` still works.**
  ```bash
  cd claude-config-repo && ./ee-migrate-install.sh ../cps
  cd ../cps && ddev exec php system/ee/eecli.php cps:logs -l 1 --source=devlog
  ```
  Expected: header line `cps:logs — https://cps.test — showing 1 of …`. `php -l` every PHP file. (`cps:migrate-status` etc. will error "class not found" until Tasks 2–3 — that is expected; do not run them yet.)
- [ ] **Step 5: Commit both repos.**
  ```bash
  cd claude-config-repo && git add ee-migrate-install.sh projects/expressionengine/templates/cps_tools \
    && git commit -m "feat(ee): add cps_tools add-on template and installer"
  cd ../cps && git add -A system/user/addons/cps_logs system/user/addons/cps_tools .gitignore \
    && git commit -m "refactor(addons): rename cps_logs to cps_tools"
  ```

### Task 2: `cps:migrate-status`

**Files:**
- Create: `templates/cps_tools/Commands/CommandMigrateStatus.php`
- Create: `templates/cps_tools/tests/test-cps-tools.sh`

- [ ] **Step 1: Write the failing test.** `tests/test-cps-tools.sh` runs *from the site repo root* and drives eecli through DDEV. Skeleton plus the first cases:
  ```bash
  #!/usr/bin/env bash
  # test-cps-tools.sh — integration tests for cps_tools. Run from a site repo root:
  #   bash <config-repo>/projects/expressionengine/templates/cps_tools/tests/test-cps-tools.sh
  set -uo pipefail
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  sub=""; [[ -d ee/system/user ]] && sub="ee/"
  MIG="${sub}system/user/database/migrations"
  if [[ -n "${LOCAL_EECLI:-}" ]]; then :; elif [[ -n "$sub" ]]; then LOCAL_EECLI="ddev ee"; else LOCAL_EECLI="ddev exec php system/ee/eecli.php"; fi
  EE() { $LOCAL_EECLI "$@" 2>&1; }
  PASS=0; FAIL=0
  ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
  bad() { echo "FAIL $1 :: $2"; FAIL=$((FAIL+1)); }
  FIXTURE=2099_01_01_000000_cps_tools_status_fixture
  cleanup() { rm -f "$MIG/$FIXTURE.php"; }
  trap cleanup EXIT

  # --- migrate-status ---------------------------------------------------------
  out=$(EE cps:migrate-status --json)
  echo "$out" | jq -e '.pending and .missing_files and .counts.tables and .counts.channel_titles and .counts.channel_fields' >/dev/null \
    && ok "status json has pending/missing_files/counts" || bad "status json shape" "$out"

  cp "$HERE/fixtures/$FIXTURE.php" "$MIG/"
  out=$(EE cps:migrate-status --json)
  [[ "$(echo "$out" | jq -r '.pending[-1]')" == "$FIXTURE" ]] \
    && ok "fixture is last pending (EE order)" || bad "fixture last pending" "$out"
  cleanup

  echo "---"; echo "$PASS passed, $FAIL failed"; [[ $FAIL -eq 0 ]]
  ```
  And `tests/fixtures/2099_01_01_000000_cps_tools_status_fixture.php`:
  ```php
  <?php

  use ExpressionEngine\Service\Migration\Migration;

  /** Test fixture: never run. Exists only to appear in the pending list. */
  class CpsToolsStatusFixture extends Migration
  {
      public function up()
      {
      }

      public function down()
      {
      }
  }
  ```
- [ ] **Step 2: Run it — expect FAIL** (`cd ../cps && bash ../claude-config-repo/projects/expressionengine/templates/cps_tools/tests/test-cps-tools.sh`). Expected: both cases FAIL (class not found).
- [ ] **Step 3: Implement `CommandMigrateStatus`.** Model on `CommandLogs` (same lang loading). Behaviour (spec §6.1):
  ```php
  public function handle()
  {
      $this->loadAddonLang();
      $migration = ee('Migration');
      $migration->ensureMigrationTableExists();

      // EE's own list, in the order `migrate --core` will run them.
      $pending = array_values($migration->getNewMigrations('ExpressionEngine')); // sorted names

      $dir = SYSPATH . 'user/database/migrations/';
      $missing = [];
      foreach (ee()->db->select('migration')->where('migration_location', 'ExpressionEngine')
          ->get('migrations')->result_array() as $row) {
          if (! is_file($dir . $row['migration'] . '.php')) {
              $missing[] = $row['migration'];
          }
      }

      $hashFile = $this->releaseRoot() . '.commit_hash';
      $data = [
          'pending' => $pending,
          'missing_files' => $missing,
          'commit' => is_file($hashFile) ? trim((string) file_get_contents($hashFile)) : null,
          'counts' => [
              'tables' => (int) ee()->db->query(
                  'SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = DATABASE()'
              )->row('n'),
              'channel_titles' => (int) ee()->db->count_all('channel_titles'),
              'channel_fields' => (int) ee()->db->count_all('channel_fields'),
          ],
      ];

      if ($this->option('--json', false)) {
          $this->write(json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
          return;
      }
      // Human output: one line per pending file, then missing files, then counts and commit.
  }

  /** Release root = parent of `system/` (or of `ee/system/`). */
  private function releaseRoot(): string
  {
      $root = dirname(rtrim(SYSPATH, '/')) . '/';
      return basename(rtrim($root, '/')) === 'ee' ? dirname(rtrim($root, '/')) . '/' : $root;
  }
  ```
  Options: `'json' => 'cps_tools_option_json'` (add lang key).
- [ ] **Step 4: Run tests — expect PASS** for both cases.
- [ ] **Step 5: Commit** (claude-config-repo; re-run installer into cps and commit there too):
  `feat(cps_tools): add cps:migrate-status`

### Task 3: `cps:migrate-verify`

**Files:**
- Create: `templates/cps_tools/Commands/CommandMigrateVerify.php`
- Create: `tests/fixtures/2099_01_01_000001_cps_tools_verify_pass.php`, `…000002_cps_tools_verify_fail.php`, `…000003_cps_tools_no_verify.php`
- Modify: `tests/test-cps-tools.sh`

- [ ] **Step 1: Write failing tests.** Fixtures: `verify()` returning `[]`; returning `['expected 4 events, found 0']`; and no `verify()`. Tests copy each fixture in, call `EE cps:migrate-verify <name>`, assert exit codes 0 / 1 / 0 and output contains `PASS`, the failure text, `no verify()` respectively; then delete the fixture. Also: unknown name → exit 2 and `not found`. The fixtures are never migrated — `migrate-verify` must work on a file that is pending (it only loads the class).
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement.**
  ```php
  public function handle()
  {
      $this->loadAddonLang();
      $name = (string) ($this->arguments[0] ?? '');
      $file = SYSPATH . 'user/database/migrations/' . $name . '.php';
      if ($name === '' || ! is_file($file)) {
          $this->error('Migration not found: ' . $name);
          exit(2);
      }

      $model = ee('Model')->make('Migration', ['migration' => $name, 'migration_location' => 'ExpressionEngine']);
      $instance = ee('Migration', $model)->getMigrateInstance();

      if (! method_exists($instance, 'verify')) {
          $this->info('no verify() — nothing to check');
          return;
      }

      $failures = (array) $instance->verify();
      if ($failures === []) {
          $this->info('PASS verify() ' . $name);
          return;
      }
      foreach ($failures as $failure) {
          $this->error('FAIL ' . $failure);
      }
      exit(1);
  }
  ```
  Keep the raw `exit(1)` / `exit(2)` (tests assert those exact codes; `Cli::fail()`'s code is not guaranteed to match). Usage is `cps:migrate-verify <name> [options]` — name first.
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** `feat(cps_tools): add cps:migrate-verify`.

---

## Chunk 2: `cps:schema-check`

TDD here is driven by **fixture migrations that reintroduce the spec §1 defects** inside a throwaway channel. Each test: back up nothing (fixtures self-clean via `down()`), baseline → run fixture `up` → `schema-check --compare` must FAIL naming the defect → `down` → `--compare` passes.

Shared test helpers to add to `test-cps-tools.sh`:
```bash
run_fixture() {  # run_fixture <name>: copy in, migrate exactly one step
  cp "$HERE/fixtures/$1.php" "$MIG/"
  out=$(EE cps:migrate-status --json); [[ "$(echo "$out" | jq -r '.pending|length')" == 1 ]] \
    || { echo "ABORT: other migrations pending locally — resolve first"; exit 3; }
  EE migrate --core --steps=1 >/dev/null
}
undo_fixture() { EE migrate:rollback --steps=1 >/dev/null; rm -f "$MIG/$1.php"; }
```
Fixtures create channel `cpstools_fixture` + their own fields named `cpstools_fx_*` and remove them in `down()`, resolving everything by name. They write deliberately broken settings with direct `ee()->db` updates *after* creating the field correctly (that is how the real defects looked in the DB).

### Task 4: Report + baseline/compare plumbing

**Files:** Create `Library/Report.php`, `Commands/CommandSchemaCheck.php`.

- [ ] **Step 1: Failing test:** `EE cps:schema-check --no-smoke --json` returns JSON `{ "results": [ {check, subject, status, message} ], "summary": {pass, warn, fail} }`; `--baseline=/tmp/cpstools-base.json` writes the file; `--compare=/tmp/cpstools-base.json` on an unchanged DB exits 0 with `new_failures: 0`.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.** `Report` holds results; `fingerprint(result) = check|subject|message`; `compare(baseline)` returns results with status `fail` whose fingerprint is absent from the baseline. Exit codes: 0 = no (new) failures, 1 = (new) failures, 2 = could not run (exception at top level). Paths for `--baseline/--compare` are written/read inside the DDEV container — use `/tmp/…` or a path under the site root that is gitignored (`.admin-scripts/.ee-migrate/`).
- [ ] **Step 4: Run — PASS.**  **Step 5: Commit** `feat(cps_tools): schema-check report and baseline compare`.

### Task 5: Settings-contract check (catches defects 1 and 2)

**Files:** Create `Library/Checks/SettingsContract.php`, fixtures `2099_…_cpstools_fx_url_missing_schemes.php`, `…_fx_relationship_bad_shape.php`.

- [ ] **Step 1: Failing tests.** Fixture A creates a URL field + a Grid field with a `url` column, then strips `allowed_url_schemes`/`url_scheme_placeholder` from both (field settings are base64-serialized in `exp_channel_fields.field_settings`; Grid column settings are JSON in `exp_grid_columns.col_settings`). Fixture B creates a relationship field and rewrites `channels` to ints and `order_field` to `'nonexistent'`. Assert `--compare` exits 1 and the JSON has `check == "settings_contract"` failures naming `cpstools_fx_url` (missing `allowed_url_schemes`), the Grid column, and the relationship field (type mismatch / invalid value).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.** For each channel field and each Grid column: load the fieldtype handler the same way EE does (`ee()->load->library('api'); ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes(); $ft = ee()->api_channel_fields->setup_handler($type, true);`). Contract = keys/types of `$ft->grid_save_settings([])` for Grid columns when that method exists, else `$ft->save_settings([])`. Wrap in try/catch `\Throwable`: if the contract cannot be computed, record `warn` "contract unavailable" (never fail). Compare: every contract key must exist in stored settings; where the contract value is an array the stored value must be an array. Add type rules the defaults cannot express as a small per-type table in the class — in Plan 1 exactly one entry: relationship (`channels` must be an array of numeric **strings** naming existing channels, or empty for any; `order_field` ∈ `title|entry_date`). Further rules come from the Plan 2 references. Unknown third-party types → contract from `save_settings([])` only.
- [ ] **Step 3b: Prove the contract path itself.** Add a test that fails if the URL defect is caught *only* by the smoke test: with fixture A run `schema-check --no-smoke --json` and assert `.results[] | select(.check=="settings_contract" and .status=="fail" and (.message|test("allowed_url_schemes")))` exists for both the field and the Grid column. Also assert there are 0 `settings_contract` results with status `warn` and message `contract unavailable` whose `subject_type` is one of the 27 core types — a core type silently falling back to warn is a test failure.
- [ ] **Step 4: Run — PASS** (both fixtures fail before `down`, pass after).
- [ ] **Step 5: Commit** `feat(cps_tools): settings-contract check`.

### Task 6: Storage + orphan checks (defects 3 and 4)

**Files:** `Library/Checks/Storage.php`, `Library/Checks/Orphans.php`; fixtures `…_fx_grid_orphan_column.php` (insert an `exp_grid_columns` row with `field_id = NULL`), `…_fx_grid_missing_data_column.php` (create Grid field properly, then `ALTER TABLE exp_channel_grid_field_N DROP COLUMN col_id_M`; `down()` re-adds before dropping the field).

- [ ] **Step 1: Failing tests** (each: `run_fixture`, then `out=$(EE cps:schema-check --no-smoke --json --compare=/tmp/cpstools-base.json)`, then `undo_fixture` and re-check exit 0):
  - orphan fixture: exit 1 and `jq -e '.results[]|select(.check=="orphans" and .status=="fail" and (.subject|test("grid_columns")))'`.
  - missing-column fixture: exit 1 and `jq -e '.results[]|select(.check=="storage" and .status=="fail" and (.message|test("col_id_")))'`.
  - relationship orphan rows: the orphan fixture's `up()` also inserts one `exp_relationships` row pointing at a non-existent `child_id` (removed in `down()`); assert `check=="orphans" and status=="warn"` for it, and that warns alone never change the exit code.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement:**
  - storage: for each field, `exp_channel_data_field_<id>` exists (`SHOW TABLES LIKE`, never `table_exists()` — it caches) and has `field_id_<id>`; for Grid/File Grid fields, `exp_channel_grid_field_<id>` exists and has `col_id_<col>` for every column row.
  - orphans: `exp_grid_columns` rows whose `field_id` is NULL or not in `exp_channel_fields`; Fluid: rows in `exp_fluid_field_data` whose `field_id` or `fluid_field_id` no longer exists; `exp_relationships` rows whose `parent_id`/`child_id` are not in `exp_channel_titles` (count + first 5 ids, `warn` not `fail` — live sites accumulate these).
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(cps_tools): storage and orphan checks`.

### Task 7: Layout, relationship-target and reference checks

**Files:** `Library/Checks/Layouts.php`, `Library/Checks/References.php`; fixtures:
- `…_fx_layout_stale_field.php` — channel `cpstools_fixture` with fields A and B attached and a layout placing both; then detaches B (layout still lists it) and attaches field C without placing it.
- `…_fx_bad_relationship_target.php` — relationship field whose `channels` setting names channel id `"999999"`.
- `…_fx_missing_cat_group.php` — channel whose `cat_group` lists a non-existent category group id.

- [ ] **Step 1: Failing tests** (pattern as Task 6):
  - stale layout: exit 1; `check=="layouts" and status=="fail" and (.message|test("not attached"))` for B; `check=="layouts" and status=="warn" and (.message|test("not placed"))` for C.
  - bad target: exit 1; `check=="references" and status=="fail"` naming the field and `999999`.
  - missing category group: exit 1; `check=="references" and status=="fail"` naming the channel.
  - after each `undo_fixture`: exit 0.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** (spec §6.2 rows 5–7): layout `field_layout` JSON may reference only core fields and fields attached to that channel (directly or via a field group); attached-but-unplaced → `warn`; relationship `channels` ids must exist; channel `cat_group`, field groups and status groups referenced by channels must exist.
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(cps_tools): layout and reference checks`.

### Task 8: Smoke test (DDEV only) + read-only guard

**Files:** `Library/SmokeTest.php`; wire into `CommandSchemaCheck` (on by default, `--no-smoke` disables).

- [ ] **Step 1: Failing tests.**
  - With fixture A (URL schemes stripped), `schema-check` (smoke on) reports `check == "smoke"` failure for the URL field and Grid column whose message contains `in_array` — the real crash, caught.
  - Running `schema-check` twice leaves every `exp_*` table row count unchanged (test compares `SELECT table_name, table_rows`… — use exact `COUNT(*)` for `exp_channel_titles`, `exp_channel_data`, `exp_relationships`, `exp_grid_columns`, `exp_channel_fields`, `exp_migrations` — **not** `exp_developer_log`, which `validate()`/`display_field()` may legitimately write deprecation notices to).
  - Smoke refuses to run off DDEV: with env `IS_DDEV_PROJECT` unset it records `warn` "smoke skipped: not DDEV" (simulate via `ddev exec env -u IS_DDEV_PROJECT php …`).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.** Only when `getenv('IS_DDEV_PROJECT') === 'true'`. `ee()->db->trans_begin()` at start, `trans_rollback()` in `finally`. Snapshot the row counts above before; compare after; any difference → `fail` "smoke test changed data" (spec §6.2). First read `system/ee/legacy/libraries/api/Api_channel_fields.php` for the exact signatures of `set_settings`, `setup_handler` and `apply`, and mirror the path in the 2026-10-05 stack trace (`FieldFacade.php:244` → `Api_channel_fields.php:444`). For each field: `set_settings($field_id, $settings)`, `setup_handler($field_id)`, then for each sample value in `['', 'Sample text', 'www.example.ca', '/relative/path', '999999999', 'not-an-option']` call `apply('validate', [$value])` inside try/catch `\Throwable` — an exception/TypeError is `fail` with the exception message; a returned validation message is fine. For Grid columns mirror `Grid_lib::_process_field_data` (see `system/ee/ExpressionEngine/Addons/grid/libraries/Grid_lib.php:295` and the stack trace in the 2026-10-05 incident) — set the column's settings on the handler and call `validate`. Call `display_field('')` likewise inside output buffering (discard output). Never call `save`, `post_save`, `delete`.
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(cps_tools): DDEV-only fieldtype smoke test`.

### Task 9: First-run audit on cps (report only)

- [ ] Run `EE cps:schema-check --json > /tmp/cps-audit.json` in cps DDEV (outside the repo) and summarise counts per check and the first 10 failures by subject. **Do not fix anything.** Paste the summary into the task report for Robert. Re-run the whole `test-cps-tools.sh`; all PASS.

---

## Chunk 3: `ee-migrate.sh` runner

The runner is tested **without DDEV or a server**: `tests/stubs/ssh` and `tests/stubs/ddev` are executables placed first on `PATH`. They append every invocation to `$STUB_LOG` and answer from canned files in `$STUB_DIR` (e.g. `migrate-status.json`, `backup-size`, `migrate-exit`). The runner must source `functions-websavers.sh` from `EE_MIGRATE_FUNCTIONS` (default `~/Web/code/_scripts/functions-websavers.sh`) so tests can point it at a stub library.

### Task 10: Runner skeleton, config block, argument parsing

**Files:** Create `templates/ee-migrate/ee-migrate.sh`, `tests/test-ee-migrate.sh`, `tests/stubs/{ssh,ddev,functions-websavers.sh}`.

- [ ] **Step 1: Failing tests:** usage with no args → exit 2; unknown mode → exit 2; `HAS_STAGING=no` + `staging status` → exit 2 with `has no staging`; `BACKUP_DIR` inside `…/httpdocs/current` or `…/releases` → exit 2 with `outside the release tree`.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** the top of the script:
  ```bash
  #!/usr/bin/env bash
  # ee-migrate.sh — the only path an EE migration takes to a server. See the EE Migrate spec.
  #   local test <migration>
  #   <staging|prod> status | rehearse | apply --expect=<m1,m2,…>
  set -uo pipefail
  # >>> site config (preserved by ee-migrate-install.sh)
  SITE=""                 # e.g. cps
  SSH_HOST=""             # e.g. websvr-cps
  REMOTE_PHP=""           # e.g. /opt/plesk/php/8.2/bin/php
  PROD_PATH=""            # release symlink, e.g. /var/www/vhosts/cps.ca/httpdocs/current
  STAGING_PATH=""         # empty when HAS_STAGING=no
  PROD_DB=""              # database name (for export_db)
  STAGING_DB=""
  PROD_MYSQL_DEFAULTS=""  # server-side defaults file path, same value sync.sh uses
  STAGING_MYSQL_DEFAULTS=""
  PROD_BACKUP_DIR=""      # outside the release tree, e.g. /var/www/vhosts/cps.ca/db-backups
  STAGING_BACKUP_DIR=""
  LOCAL_DB=""             # DDEV database, e.g. admin_cps
  EE_SUBDIR=""            # "ee/" for diabetes and intranet-backend
  LOCAL_EECLI="ddev exec php system/ee/eecli.php"   # "ddev ee" for diabetes and intranet-backend
  HAS_STAGING="yes"
  # <<< site config
  ```
  Then: `die() { echo "ee-migrate: $*" >&2; exit 2; }`; `fail() { echo "ee-migrate: FAIL $*" >&2; exit 1; }`; `parse_args`; `require_config`; `check_backup_dir` (reject paths containing `/httpdocs/current`, `/releases/` or equal to the release path); `target_path/target_db/target_defaults/target_backup_dir` helpers keyed on `staging|prod`.
- [ ] **Step 4: PASS.** **Step 5: Commit** `feat(ee-migrate): runner skeleton and config validation`.

### Task 11: Backup step (spec §7.1a)

- [ ] **Step 1: Failing tests:** stub backup produces a file of size S. Cases: previous dump 100 MB and new 95 MB → OK; new 80 MB → FAIL `backup too small` and **the stub log contains no `migrate`**; no previous dump and new 0.5 MB → FAIL (`< 1 MB`); backup command exit 0 but no file → FAIL; server file not `600` after chmod → FAIL.
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Implement** `backup_remote <target>`: one ssh call that runs `"$REMOTE_PHP" system/ee/eecli.php backup:database --absolute_path=<dir>/ --file_name=pre_migrate_<UTC timestamp>` plus the same dump suffix EE's own backups use (so the "newest previous `pre_*`" comparison and any pruning globs match) in the release dir, then `chmod 600`, then prints `stat -c '%s %a'` of the new file and the size of the newest *previous* `pre_*` file in that dir. Local check of the 90 % / 1 MB rule. Echo the backup name; store it for the stamp. `backup_local`: `$LOCAL_EECLI backup:database` and check the newest file in `${EE_SUBDIR}system/user/cache/` by size the same way (via `find -newer` a marker file, never naming `*.sql` on a command line Claude runs — this script runs it, which is fine).
- [ ] **Step 4: PASS.** **Step 5: Commit** `feat(ee-migrate): verified non-skippable backups`.

### Task 12: Pending-set guard + per-file loop (spec §7.0)

- [ ] **Step 1: Failing tests:** remote status JSON `pending: [a,b]` with `--expect=a,b` → runs exactly: backup, `migrate --core --steps=1`, `cps:migrate-verify a`, `migrate --core --steps=1`, `cps:migrate-verify b`, `cps:schema-check --no-smoke --json` in that order (assert from stub log). `--expect=a` (extra pending b) → FAIL `pending set differs`, no backup, no migrate. `--expect=b,a` (order) → FAIL. remote `cps:migrate-status` not registered (stub returns EE's "command not found" text) → exit 2 with `cps_tools is not deployed on <target> — deploy it first`, and no backup. `migrate-verify b` exits 1 → FAIL with `rollback: … migrate:rollback --steps=1` and `restore:` lines printed, and no further steps.
- [ ] **Step 2: FAIL. Step 3: Implement** `remote_status`, `assert_pending_equals`, `apply_loop`. Every eecli call passes `--core` for migrate. **Step 4: PASS. Step 5: Commit** `feat(ee-migrate): exact pending set and one-group-per-file loop`.

### Task 13: Stamps, rehearsal, production gate (spec §7.0a–7.0b, 7.2, 7.3)

- [ ] **Step 1: Failing tests:**
  - `staging apply` without a stamp → FAIL `no rehearsal`; with stamp for other commit / other pending set / older than 24 h → FAIL naming which.
  - `rehearse`: calls stub `export_db`, `download_db`, `import_db` (never `dev_upload_db`/`dev_import_db` — assert absent), `ddev snapshot` before import and `ddev snapshot restore` after (also on failure), compares counts against remote status JSON (mismatch → FAIL, snapshot still restored), runs the local per-file loop with `cps:migrate-verify` and `cps:schema-check` (smoke on), writes `.admin-scripts/.ee-migrate/stamps/<target>.json` with `rehearsal: pass`.
  - `prod apply` on `HAS_STAGING=yes` without `staging.json` `apply: pass` for the same set+commit → FAIL; on `HAS_STAGING=no` only the prod rehearsal stamp is needed.
  - Successful apply updates the stamp with `applied_at`, `apply: pass`, `backup`.
  - Preflight: `EE_MIGRATE_FUNCTIONS` pointing at a missing file → exit 2 `shared sync library not found`; at a stub library lacking `download_db` → exit 2 naming the missing function; neither case calls `ddev snapshot`.
- [ ] **Step 2: FAIL. Step 3: Implement** with `jq` for stamps. **Step 4: PASS. Step 5: Commit** `feat(ee-migrate): rehearsal and stamp-gated apply`.

### Task 14: `local test <migration>` (spec §7.1)

- [ ] **Step 1: Failing tests (stub ddev):** other pending locally → FAIL listing them; happy path runs in order: local backup, schema dump A (`cps:schema-check --json --baseline=…`) plus a settings dump (`mysqldump --no-data` is NOT used — use `ddev mysql $LOCAL_DB -N -e "SELECT field_id, field_name, field_type, field_settings FROM exp_channel_fields ORDER BY field_id; SELECT col_id, field_id, col_name, col_type, col_settings FROM exp_grid_columns ORDER BY col_id; SHOW TABLES;"` into a file), migrate step, verify, schema-check `--compare`, rollback step, dump B must equal dump A (`cmp`), migrate step, schema-check `--compare`.
- [ ] Steps 2–5 as usual. Commit `feat(ee-migrate): local round-trip gate`.

### Task 15: Real-world dry run on cps (no server)

- [ ] Fill the cps config block from `.admin-scripts/sync.sh` / `upgrade.sh` values (names only — paths, host alias, PHP path, DB *names*; never open the `.cnf` files). Re-install into cps. Run `.admin-scripts/ee-migrate.sh local test 2099_01_01_000001_cps_tools_verify_pass` with that fixture copied in; expect PASS end to end, then remove the fixture and roll back if needed. Tell Robert you are about to run `.admin-scripts/ee-migrate.sh staging status` (read-only; reaches staging over SSH; it will report `cps_tools is not deployed` until Chunk 6 — expected here), then run it and report its output. Commit cps `feat(admin): add ee-migrate runner`.

---

## Chunk 4: Guard rule, permissions, tests

### Task 16: Guard cases first

**Files:** Modify `test-safety-guard.sh` (append a section), `projects/common/hooks/safety-guard.sh`.

- [ ] **Step 1: Add failing cases** (use `bash_expect`):
  ```bash
  echo -e "\n${CYAN}— EE migration runner —${NC}"
  bash_expect none '.admin-scripts/ee-migrate.sh local test 2026_10_05_090000_fix'
  bash_expect none '.admin-scripts/ee-migrate.sh staging status'
  bash_expect none '.admin-scripts/ee-migrate.sh prod rehearse'
  bash_expect none 'bash .admin-scripts/ee-migrate.sh staging apply --expect=2026_10_05_090000_fix'
  bash_expect none 'cd /Users/x/cps && .admin-scripts/ee-migrate.sh staging apply --expect=a,b'
  bash_expect ask  '.admin-scripts/ee-migrate.sh prod apply --expect=2026_10_05_090000_fix'
  bash_expect ask  'bash .admin-scripts/ee-migrate.sh prod apply --expect=a'
  bash_expect ask  'bash -c ".admin-scripts/ee-migrate.sh staging apply --expect=a"'
  bash_expect ask  '/Users/x/cps/.admin-scripts/ee-migrate.sh staging apply --expect=a'
  bash_expect ask  '.admin-scripts/ee-migrate.sh staging apply --expect=a; echo done'
  bash_expect ask  '.admin-scripts/ee-migrate.sh staging apply --expect=a | tee log'
  bash_expect ask  '.admin-scripts/ee-migrate.sh staging apply --expect=$(ls)'
  bash_expect ask  '.admin-scripts/ee-migrate.sh staging frobnicate'
  bash_expect ask  'eval .admin-scripts/ee-migrate.sh staging apply --expect=a'
  ```
  Production raw-migrate denial already has cases; add one if missing:
  `bash_expect deny "ssh websvr 'cd /var/www/vhosts/cps.ca/httpdocs/current && php system/ee/eecli.php migrate --core'"` (requires the prod path in the test's `ai-config.conf` fixture — follow how existing remote cases set it up).
- [ ] **Step 2: Run `./test-safety-guard.sh` — new `ask` cases FAIL** (guard currently returns none).
- [ ] **Step 3: Implement** a section inserted before `# --- Remote servers and databases` (around line 494):
  ```bash
  # --- EE migration runner -----------------------------------------------------
  # .admin-scripts/ee-migrate.sh is the only sanctioned path for EE migrations to reach a
  # server (EE Migrate spec §8). Its own checks gate staging; production apply always asks.
  # Only a plain, canonical invocation is recognised — anything wrapped or chained asks.
  if [[ "$lc" == *ee-migrate.sh* ]]; then
    EEM_CANON='^([[:space:]]*cd[[:space:]]+[^;&|`$()]+[[:space:]]*&&[[:space:]]*)?(bash[[:space:]]+)?\.admin-scripts/ee-migrate\.sh[[:space:]]+(local[[:space:]]+test[[:space:]]+[a-z0-9_]+|(staging|prod)[[:space:]]+(status|rehearse)|(staging|prod)[[:space:]]+apply[[:space:]]+--expect=[a-z0-9_,]+)[[:space:]]*$'
    if [[ ! "$lc" =~ $EEM_CANON ]]; then
      decide ask "ee-migrate.sh was called in a form the safety guard does not recognise (wrapped, chained, absolute path or unknown mode). Run it plainly from the repo root, or confirm this exact command."
    elif [[ "$lc" =~ (^|[[:space:]])prod[[:space:]]+apply([[:space:]]|$) ]]; then
      decide ask "Production migration: ee-migrate.sh will back up the production database and run the listed migrations. Approve only for this exact set."
    fi
  fi
  ```
  Check `decide`'s behaviour (line 53): if it exits after deciding, the `elif` ordering above is correct; if it only records, make sure a later rule cannot downgrade an `ask`.
- [ ] **Step 4: Run `./test-safety-guard.sh` — all PASS** (including every pre-existing case). Also run `./run-tests.sh` (full suite) — no regressions.
- [ ] **Step 5: Commit** `feat(safety-guard): recognise ee-migrate.sh; ask for production apply`.

### Task 17: Permissions template + gitignore

- [ ] **Step 1:** In `projects/expressionengine/settings.local.json` add to `allow`: `"Bash(.admin-scripts/ee-migrate.sh:*)"`, `"Bash(bash .admin-scripts/ee-migrate.sh:*)"`; add to `ask`: `"Bash(.admin-scripts/ee-migrate.sh prod apply:*)"`, `"Bash(bash .admin-scripts/ee-migrate.sh prod apply:*)"`. Add `.admin-scripts/.ee-migrate/` to `projects/expressionengine/gitignore-security.txt`.
- [ ] **Step 2:** `./test-refresh-additive.sh` and `./test-security-policy.sh` — PASS (the union merge must add the entries to an existing project without removing anything). Add a case to `test-security-policy.sh` asserting both `ask` entries are present in `projects/expressionengine/settings.local.json` (`jq -e '.permissions.ask | index("Bash(.admin-scripts/ee-migrate.sh prod apply:*)")'`).
- [ ] **Step 3: Commit** `feat(ee): permissions and gitignore for ee-migrate`.

---

## Chunk 5: Skill, agent, setup wiring, doctor

### Task 18: `ee-migrate` skill

**Files:** Create `projects/expressionengine/skills/ee-migrate/SKILL.md`, `references/fieldtypes/README.md`.

- [ ] Write `SKILL.md` (≤ 250 lines) with front matter:
  ```yaml
  ---
  name: ee-migrate
  description: >
    Create and ship ExpressionEngine migrations safely on CPS sites — new channels, fields, Grid/Fluid
    columns, field groups, layouts, categories, statuses, or entry content changes. Use whenever a
    change built in DDEV must reach staging/production, or Robert asks to add/change/reuse a field,
    channel or field group, write a migration, or run migrations on staging or production.
  ---
  ```
  Body = spec §9 steps 1–6 as an operating procedure, with: the exact runner commands; the two production gates (§7.2/7.3, with the per-site `HAS_STAGING` table: cps/cpsp/cyntc yes; cfk/diabetes/intranet-backend no); the backup rule (§7.1a) verbatim; "never call `sync.sh` for rehearsal"; push ordering (§7.4); the `verify()` convention with an example; review checklist for the author's output (ids by name, `down()` complete or declared `backup-only rollback`, no raw SQL where an API exists, settings written in full per the fieldtype reference); what to do when the guard asks/denies (stop, tell Robert, never route around). Point to `references/fieldtypes/<type>.md` and say: "until a reference exists for a type, instruct the author agent to read that fieldtype's `ft.*.php` (`save_settings`, `grid_save_settings`, `settings_modify_column`, `validate`) before writing settings".
- [ ] `references/fieldtypes/README.md`: the reference template from spec §5 (seven headings) and a status table of all 34 types with `status: not yet written` (Plan 2 fills these).
- [ ] Commit `feat(ee): add ee-migrate skill`.

### Task 19: `ee-migration-author` agent

- [ ] Create `projects/expressionengine/agents/ee-migration-author.md`:
  ```yaml
  ---
  name: ee-migration-author
  description: "Writes ExpressionEngine migrations (up/down/verify) from a self-contained spec, following the ee-migrate skill's fieldtype references, and proves them with the local round-trip gate. Never commits, pushes or touches a server. Returns a short report."
  model: sonnet
  ---
  ```
  Body: inputs it requires (repo path, change description, reference files to load, naming); rules (spec §10; resolve ids by name; `--core` migrations only; `make:migration` naming; one concern per migration; content migrations must implement `verify()`; settings written in full from the reference/fieldtype source; forbidden: raw `ALTER`/`INSERT` on EE core tables where a model/legacy API exists, `table_exists()`, `Collection::add()` on relationships); the required finish: run `.admin-scripts/ee-migrate.sh local test <name>` and paste its output; report format (files changed, gate output, open questions).
- [ ] Commit `feat(ee): add ee-migration-author agent`.

### Task 20: Ship the skill; doctor drift check

- [ ] In `setup-project.sh` §2c (line ~4177) add `ee-migrate` to the "Core skills - ALWAYS copy" loop for the expressionengine stack.
- [ ] In the `--doctor` section add, for EE projects: if `system/user/addons/cps_tools/addon.setup.php` (or `ee/…`) exists, compare its `version` with the template's and `hc_warn "cps_tools is older than the template — run ee-migrate-install.sh"`; same for a `EE_MIGRATE_VERSION=` line you add near the top of `ee-migrate.sh` (outside the config block).
- [ ] Add/extend a test in `test-lifecycle.sh` (or the closest existing doctor test) for the warning. Run `./run-tests.sh` — all PASS.
- [ ] Commit `feat(ee): install ee-migrate skill; doctor reports stale cps_tools/runner`.

---

## Chunk 6: Fleet rollout (each push and server run needs Robert's explicit approval)

### Task 21: cps

- [ ] `ai-config --project=../cps --refresh` (adds skill, agent, permissions, guard). Review `.claude/ai-config/pending/` for anything staged rather than applied; report it.
- [ ] Re-run `test-cps-tools.sh` and `local test` on a fixture in cps. Commit.
- [ ] Order matters: `cps_tools` must be deployed to a server before `ee-migrate.sh <target> status/apply` can work there (the runner refuses with "deploy it first").
- [ ] Merge `feature/ee-migrate-tooling` → `staging` locally. **Ask Robert** to push `staging`. After the deploy: read-only check that no server has a `cps_logs` row (`cps:migrate-status` cannot see `exp_modules`; use `.admin-scripts/ee-migrate.sh staging status` plus `ssh websvr-cps '<php> system/ee/eecli.php addons:list'` filtered for `cps_`). Run `ee-migrate.sh staging status` and paste output.
- [ ] Production for cps waits for Robert's normal promotion of `staging` → `main`.

### Task 22: cfk, cpsp, cyntc, diabetes, intranet-backend

For each repo, on its branch convention (cfk and intranet-backend: `feature/ee-migrate-tooling` from `main`; cpsp, cyntc, diabetes: from `staging`):
- [ ] `./ee-migrate-install.sh ../<repo>`; fill the runner config block from that repo's `.admin-scripts/sync.sh` (names and paths only); set `HAS_STAGING=no` for cfk, diabetes, intranet-backend. Set `LOCAL_EECLI="ddev ee"` and `EE_SUBDIR="ee/"` for diabetes and intranet-backend.
- [ ] `ai-config --project=../<repo> --refresh`.
- [ ] Run `test-cps-tools.sh` in that site's DDEV; run `cps:schema-check --json` and summarise as the first-run audit (report, don't fix).
- [ ] Commit in that repo. **Ask Robert** before each push; pushing `main` on cfk, diabetes and intranet-backend deploys production.

### Task 23: Wrap-up

- [ ] claude-config-repo: update `README.md` feature list and `docs/` (one page: "EE migrations"), commit. **Ask Robert** before pushing `feature/ee-migrate` / merging to `main`.
- [ ] cps `.okf/log.md` entry; memory note pointing at the skill; report the six first-run audits to Robert in one table.
