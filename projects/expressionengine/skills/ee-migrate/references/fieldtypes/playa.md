---
fieldtype: playa
addon: playa 5.6.0 (EEHarbor, EE2-era; addon.json requires expressionengine/core >= 2.11)
origin: legacy
verified: 7.5.27 (read-only: existing fields only)
fixture: 2099_02_01_000029_cpsref_playa
fixture_site: cpsp
grid: n/a
fluid: n/a
---
# playa

**Legacy — do not create. Read existing data and migrate away.**

A migration must never create a `playa` field, a `playa` Matrix column, or write to `exp_playa_relationships`. The
fixture is read-only (`up()` and `down()` are empty; `verify()` reads the existing fields), so `run-fixtures.sh <site> playa`
only runs on cpsp and is skipped everywhere else. Evidence: `system/user/addons/playa/` on cpsp (`ft.playa.php`,
`upd.playa.php`, `addon.setup.php`, `addon.json`), the cpsp database (read-only SELECTs), `cps:schema-check` on cpsp, and the passing
read-only fixture. Official docs: see `EE-DOCS-NOTES.md`.

Version and state on cpsp: Playa 5.6.0, six fields (`cf_pubfile_related_studies_en/_fr`, `cf_pubfile_related_surveys_en/_fr`,
`cf_surveys_related_studies_en/_fr`; ids 1407, 1408, 1420, 1421, 1433, 1434) plus one Playa column inside each of the two
Matrix fields (`matrix_cols` 276 and 278). 1,336 relationship rows across the six channel fields (534/533, 126/118, 13/12), every
child entry exists. `cps:schema-check` on cpsp: `smoke` PASS for all six ("validate/display ran without exceptions");
`settings_contract` WARN "contract unavailable" for all six (no CPS contract exists for a third-party type, so settings are not validated).
No sign Playa is broken on EE 7.5.27 / PHP 8, but it is unmaintained for this stack (see Gotchas) and cpsp's table has already drifted from
the add-on's own `_create_table()`.

## Settings contract

`field_settings` is `base64_encode(serialize($array))`, like every channel field. `save_settings()` takes the `playa` POST array,
drops "Any" filters, drops `limit` when "All", then forces `field_wide = true`, `field_fmt = 'none'`, `field_show_fmt = 'n'`,
`field_type = 'playa'`. `_update_settings()` merges these defaults over whatever is stored:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `multi` | `'y'`/`'n'` | `'y'` | multiple selections (`'n'` = single select) |
| `sites` | array | `[]` | MSM sites to list from |
| `channels` | array of channel id strings | `[]` (any) | channels whose entries can be picked; legacy name `blogs` is renamed to this |
| `cats` | array | `[]` | category ids |
| `member_groups`, `authors` | array | `[]` | filter by member group / author |
| `statuses` | array | `[]` | statuses |
| `limit` | string | `'0'` (all) | maximum selections; removed when 0 |
| `limitby` | string | `''` | what `limit` counts; removed with `limit` |
| `orderby` | string | `'title'` | picker order column |
| `sort` | `'ASC'`/`'DESC'` | `'ASC'` | picker order direction |
| `expired`, `future` | `'y'`/`'n'` | `'n'`, `'y'` | include expired / future entries |
| `editable` | `'y'`/`'n'` | `'n'` | allow editing selected entries |
| `field_wide` | bool | `true` | added by `save_settings()` and by `Playa_upd::update()` |

On cpsp all six fields hold `multi, expired, future, channels, orderby, sort, field_wide` plus the `field_show_*` formatting flags EE adds
to every field (all `'n'`); `channels` is `["133"]` (`studies`) or `["145"]` (`surveys`), `orderby = title`, `sort = ASC`. The Matrix
column settings (`matrix_cols.col_settings`, same base64-serialize encoding) are the same shape plus `editable`, with `channels = ["138"]` (`pub_adrtips`).

## Storage

- **The relationships are not in the field's column.** `exp_playa_relationships` holds them:

  | Column | Meaning |
  |---|---|
  | `rel_id` | primary key |
  | `parent_entry_id` | the entry that owns the selection |
  | `parent_field_id` | the Playa field id (0/NULL when the Playa is a Matrix cell or variable) |
  | `parent_col_id`, `parent_row_id` | Matrix column id and `matrix_data.row_id` for a Matrix cell |
  | `parent_var_id` | Low Variables id |
  | `parent_is_draft` | 1 for a Better Workflow draft; all 0 on cpsp |
  | `child_entry_id` | the selected entry |
  | `rel_order` | position, from 0 in `_save_rels()` (array index of the submitted selections) |

  The add-on's own `_create_table()` also defines `parent_element_id` (Content Elements); the cpsp table does NOT have that column.
  Nothing on cpsp needs it.
- **The field's own column** (`channel_data.field_id_N`, `legacy_field_data = 'y'` on cpsp) holds search keywords written by
  `save()`: one line per selection, `[<entry_id>] [<url_title>] <title>`, apostrophes stripped. Example shape: `[3264] [childhood-tuberculosis] Childhood tuberculosis`.
  It is a search index, not the source of truth, and can be stale; the table is authoritative.
- Settings: base64-serialized `field_settings`.

## Create / change / remove

**Migrating away** (the only supported action). Never create Playa. Move each Playa field to the native `relationship` fieldtype,
which stores `parent_id`, `child_id`, `field_id`, `order` (from 1), plus Grid/Fluid keys in `exp_relationships`; see `relationship.md`
for the create recipe, the `getAssociation()->add()` write path and its post_save pitfall.

1. Back up the database (verify the dump; `backup-only rollback`).
2. Create the replacement `relationship` field (same name with a temporary suffix, e.g. `_rel`) in the same field group via the
   `relationship.md` recipe. Map settings: `channels` -> `channels` (ids, as strings), `multi 'y'` -> `allow_multiple` true,
   `expired`/`future` -> `expired`/`future`, `orderby`/`sort` -> `order_field`/`order_dir`, `limit` -> `rel_max`. Playa's
   `cats`, `authors`, `statuses`, `member_groups`, `sites`, `editable` have no or different native equivalents: check each against `relationship.md`.
3. For each entry, copy rows: `SELECT parent_entry_id, child_entry_id, rel_order FROM exp_playa_relationships WHERE parent_field_id = <playa field id> ORDER BY parent_entry_id, rel_order`
   and write them as the new field's value (`order` = `rel_order + 1`, because Playa counts from 0 here). Use the Model write path from
   `relationship.md` and read the rows back; fall back to a direct `exp_relationships` insert as that file documents.
4. Verify counts match per entry and every child still exists (the fixture's check is the starting query).
5. Switch templates from the Playa tags (`{field}{title}{/field}`, `{field:total_children}`, `{field:entry_ids}`) to relationship tags, deploy,
   then retire the old field (`$field->delete()` clears that field's `playa_relationships` rows via `settings_modify_column`).
6. Playa columns inside Matrix: migrate Matrix first (see `matrix.md`); in a Grid, the Playa column becomes a `relationship` column.
7. When no Playa field remains and no template uses it, uninstall the add-on; that removes the module and action only, and `exp_playa_relationships` is left behind.

## Content writes

Not done. Do not write to `exp_playa_relationships`. To read the selection of an entry:

```sql
SELECT child_entry_id, rel_order FROM exp_playa_relationships
WHERE parent_entry_id = :entry AND parent_field_id = :field AND parent_is_draft = 0 ORDER BY rel_order;
```

(Matrix cells: `parent_col_id = <col id>` and `parent_row_id = <row id>` instead of `parent_field_id`.) From PHP use `ee()->db`, never the add-on class.

## Rollback

The fixture changes nothing, so there is nothing to roll back. For a migrate-away migration: `down()` deletes the new `relationship` field (its
`exp_relationships` rows go with it) and leaves the Playa field and `exp_playa_relationships` untouched, which is why the Playa field must be
removed only in a later, separate migration. Deleting the Playa field is `backup-only rollback`: `settings_modify_column()` deletes its relationship rows.

## Verification

- Read-only fixture: `run-fixtures.sh <cpsp repo> playa` prints `PASS playa` (checks the settings keys, the table's columns, `channels` ids exist,
  every field has relationship rows, no relationship points at a missing entry, and the keyword text shape).
- `SELECT field_id, field_name FROM exp_channel_fields WHERE field_type = 'playa';`
- `SELECT parent_field_id, COUNT(*), COUNT(DISTINCT parent_entry_id) FROM exp_playa_relationships GROUP BY 1;` (the table also holds rows for
  long-deleted fields; only count rows for existing field ids).
- Orphans: `SELECT COUNT(*) FROM exp_playa_relationships r LEFT JOIN exp_channel_titles t ON t.entry_id = r.child_entry_id WHERE t.entry_id IS NULL;` is 0 for current fields.
- `cps:schema-check`: `smoke` pass, `settings_contract` warn "contract unavailable" is expected.

## Gotchas

- Playa's `delete($entry_ids)` runs `parent_entry_id IN (...) OR child_entry_id IN (...)`: deleting an entry removes every selection that points at it.
- `rel_order` starts at 0 (array index), native `relationship` `order` starts at 1; do not copy it unchanged.
- `playa_relationships` has no foreign keys and keeps rows for deleted fields (the cpsp table holds rows for dozens of field ids that no longer exist).
- The add-on targets PHP >= 5.3 and EE >= 2.11 and uses the legacy FluxCapacitor wrapper; it works on EE 7.5.27 / PHP 8 on cpsp today (smoke passes) but
  each EE upgrade should re-run this fixture.
- Playa is a Matrix celltype too: removing Playa before Matrix breaks the Matrix column definitions that name it.
