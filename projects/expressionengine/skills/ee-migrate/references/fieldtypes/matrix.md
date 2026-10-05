---
fieldtype: matrix
addon: matrix 3.8.1 (EEHarbor, EE2-era; addon.json requires expressionengine/core >= 2.11)
origin: legacy
verified: 7.5.27 (read-only: existing fields only)
fixture: 2099_02_01_000030_cpsref_matrix
fixture_site: cpsp
grid: n/a
fluid: n/a
---
# matrix

**Legacy — do not create. Read existing data and migrate away.**

A migration must never create a `matrix` field, add `matrix_cols` rows, or alter `exp_matrix_data`. The fixture is read-only (`up()` and `down()`
are empty; `verify()` reads the existing fields), so `run-fixtures.sh <site> matrix` only runs on cpsp. Evidence: `system/user/addons/matrix/`
on cpsp (`ft.matrix.php`, `upd.matrix.php`, `addon.setup.php`, `addon.json`), the cpsp database (read-only SELECTs), `cps:schema-check` on cpsp, and the
passing read-only fixture. Official docs: see `EE-DOCS-NOTES.md`.

Version and state on cpsp: Matrix 3.8.1, two fields, `cf_impacts_docs_en` (1431) and `cf_impacts_docs_fr` (1432), each with two columns:
`info` (`wygwam`, col 275/277) and `publication` (`playa`, col 276/278). **`exp_matrix_data` holds zero rows**, so no
structured Matrix data exists on cpsp. `channel_data.field_id_1431/1432` is non-empty for 7 entries but only as the add-on's keyword/flag text (a literal `1`, or
flattened HTML of the cells); the cells themselves are gone. `exp_matrix_cols` also holds 8 rows with `field_id` NULL (Low Variables columns, `var_id` set).
`cps:schema-check` on cpsp: `smoke` PASS for both fields; `settings_contract` WARN "contract unavailable" (no CPS contract for a third-party type).
No sign Matrix is broken on EE 7.5.27 / PHP 8, but there is no data to lose and no reason to keep it.

## Settings contract

Field `field_settings` (`base64_encode(serialize())`), written by `_save_settings()` (called from `post_save_settings()`, because the column ids are only known after the
column rows are inserted):

| Key | Type | Meaning |
|---|---|---|
| `min_rows` | string | minimum rows; `'0'` default |
| `max_rows` | string | maximum rows; `''` = no maximum |
| `col_ids` | array of id strings | ordered list of `exp_matrix_cols.col_id` for this field |
| `field_wide` | bool | always `true` |

`save_settings()` also forces `field_fmt = 'none'`, `field_show_fmt = 'n'`, `field_type = 'matrix'`. The columns are NOT in `field_settings`: each is a row in
`exp_matrix_cols` (`col_id, site_id, field_id, var_id, col_name, col_label, col_instructions, col_type, col_required, col_search, col_order, col_width, col_settings`);
`col_settings` is `base64_encode(serialize($array))` like `field_settings` (not JSON, unlike `grid_columns.col_settings`). `col_type` is a celltype name
(`text, textarea, select, date, wygwam, playa, ...`; the celltype classes live in `matrix/celltypes/` and third-party add-ons).

## Storage

- `exp_matrix_cols`: column definitions as above (cpsp: 12 rows; `cf_impacts_docs_*` use cols 275-278).
- `exp_matrix_data`: one row per Matrix row: `row_id, site_id, entry_id, field_id, var_id, row_order` plus one `col_id_<col_id>` TEXT column per Matrix column
  (cpsp: the table has ~250 such columns, including `col_id_275`..`col_id_278`). Celltypes may add extra columns through `settings_modify_matrix_column()`.
  Row values are the celltype's raw string (HTML for `wygwam`, `[id] [url_title] title` for `playa`, whose real rows are in `exp_playa_relationships` with `parent_col_id`/`parent_row_id`).
- `channel_data.field_id_N` (cpsp `legacy_field_data = 'y'`): search keywords from `post_save()` (`_updateChannelData()`), not the rows.
- Settings are base64-serialized, rows live only in `exp_matrix_data`.

## Create / change / remove

**Migrating away** (the only supported action). Never create Matrix; move each Matrix field to the native `grid` fieldtype (see `grid.md` for the create recipe, the
`grid_model` prerequisites and the `save_col_settings()` signature).

1. Back up the database (verify the dump).
2. If `exp_matrix_data` has no rows for the field (the case on cpsp), there is nothing to copy: create the replacement `grid` field from the column list, switch
   templates, delete the Matrix field. Anything you still need from the 7 flagged entries must come from the keyword text or the source system, not the table.
3. Otherwise create a `grid` field named for the Matrix field (temporary suffix) and one Grid column per `exp_matrix_cols` row in `col_order`. Map `col_type`:
   `text`->`text`, `textarea`->`textarea`, `wygwam`->`wygwam` (see `wygwam.md`), `date`->`date`, `select`->`select`, `playa`->`relationship` column (see `playa.md`,
   `relationship.md`), `file`/image celltypes->`file` column (`file.md`). `col_name`, `col_label`, `col_required`, `col_search`, `col_width` copy across; `col_settings` is NOT
   transferable, rebuild it from the target fieldtype's contract. Grid `min_rows`/`max_rows` come from `min_rows`/`max_rows`.
4. Copy rows: `SELECT * FROM exp_matrix_data WHERE field_id = <field> ORDER BY entry_id, row_order` and write each entry through the Grid Model path
   (`['rows' => ['new_row_1' => ['col_id_<new col id>' => value]]]`, in `grid.md`), mapping `col_id_<matrix col>` to the new column id; read the Grid table
   (`exp_channel_grid_field_<id>`) back and compare counts. Playa cells must be migrated as relationships keyed by the Grid column and row id.
5. Switch templates (`{field}{col_name}{/field}` pair syntax carries over to Grid with the same names, but `{field:total_rows}` etc. differ), deploy, then
   delete the Matrix field (`settings_modify_column()` with `ee_action = 'delete'` calls `_delete_field()`, which drops its columns and rows: `backup-only rollback`).
6. When no Matrix field remains, uninstall the add-on; `exp_matrix_data`'s `col_id_N` columns and `exp_matrix_cols` rows are cleaned by field deletion, the tables themselves by the uninstall.

## Content writes

Not done. Do not write to `exp_matrix_data`. To read rows:

```sql
SELECT row_id, entry_id, row_order, col_id_275, col_id_276 FROM exp_matrix_data
WHERE field_id = :field ORDER BY entry_id, row_order;
```

(Resolve `col_id_N` names from `exp_matrix_cols`; `var_id` rows belong to Low Variables.)

## Rollback

The fixture changes nothing. A migrate-away migration's `down()` deletes the new Grid field and leaves Matrix untouched; delete the Matrix field in a later migration
only. Deleting a Matrix field drops its `exp_matrix_data` rows and its `col_id_N` columns, so it is `backup-only rollback`.

## Verification

- Read-only fixture: `run-fixtures.sh <cpsp repo> matrix` prints `PASS matrix` (checks the four settings keys, `col_ids` equals the `matrix_cols` rows in `col_order`,
  each `col_settings` decodes, each `col_id_N` column exists in `exp_matrix_data`, and that any rows have `row_order >= 1` and a real entry). It does NOT require rows.
- `SELECT field_id, field_name FROM exp_channel_fields WHERE field_type = 'matrix';`
- `SELECT col_id, field_id, col_name, col_type, col_order FROM exp_matrix_cols WHERE field_id IN (...) ORDER BY field_id, col_order;`
- `SELECT field_id, COUNT(*) FROM exp_matrix_data GROUP BY 1;`
- `cps:schema-check`: `smoke` pass; `settings_contract` warn "contract unavailable" is expected.

## Gotchas

- Column definitions are in `exp_matrix_cols`, not `field_settings`; `col_ids` must stay in step with it.
- `col_settings` is base64-serialized PHP, `grid_columns.col_settings` is JSON.
- A Matrix field whose `exp_matrix_data` is empty still renders and passes schema-check, so "the field is there" does not mean "the data is there".
- A Playa celltype's rows live in `exp_playa_relationships`, not in `exp_matrix_data` (the cell only has the keyword text).
- The add-on cleans up its own columns when a field is deleted; deleting it by raw SQL leaves orphan `col_id_N` columns.
