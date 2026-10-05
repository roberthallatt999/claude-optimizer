---
fieldtype: grid
addon: grid
origin: core
verified: 7.5.27
fixture: 2099_02_01_000021_cpsref_grid
fixture_site: cfk
grid: no
fluid: yes
---
# grid

Evidence: `system/ee/ExpressionEngine/Addons/grid/ft.grid.php` (`save_settings()`, `post_save_settings()`,
`save()`, `post_save()`, `accepts_content_type()`, `settings_modify_column()`), `Addons/grid/libraries/Grid_lib.php`
(`apply_settings()`, `_save_settings()`, `validate()`, `getSearchableData()`, `get_grid_fieldtypes()`),
`legacy/models/grid_model.php` (`create_field()`, `save_col_settings()`, `delete_columns()`, `delete_field()`,
`update_grid_search()`), `legacy/libraries/Grid_parser.php::instantiate_fieldtype()`,
`Addons/fluid_field/ft.fluid_field.php::removeField()`, `Model/Content/ContentModel.php`,
`Model/Channel/Channel.php::getAllCustomFields()`, EE 7.5.27, and the fixture
`fixtures/2099_02_01_000021_cpsref_grid.php` (`run-fixtures.sh <site> grid`). Official docs: see `EE-DOCS-NOTES.md`
(they list the settings by label only, no keys, no storage and nothing about creating Grid from a migration).
`file_grid` is the same class family: see `file_grid.md`.

## Settings contract

### Field settings (`ft.grid.php::save_settings()`)

It returns exactly five keys; anything else in the array is dropped when the field is saved through the control panel:

| Key | PHP type | Default | Notes |
|---|---|---|---|
| `grid_min_rows` | int (`0` if empty) | `0` | `validate_settings()`: `isNatural`. Enforced by `Grid_lib::validate()` |
| `grid_max_rows` | string (`''` if empty) | `''` | `isNaturalNoZero`. Fixture round-trips `'3'` as a string |
| `allow_reorder` | string `'y'`/`'n'` | `'y'` | an empty value becomes `'y'`, so `'n'` must be passed explicitly |
| `vertical_layout` | string | `'n'` | `'n'` auto, `'y'` vertical, `'horizontal'` (legacy value `'horizontal_layout'`) |
| `row_counter` | string `'y'`/`'n'` | `'n'` | show row numbers |

Write all five: the control panel always does, and nothing in the source promises defaults for missing keys.
`channel_fields.field_search` (`'y'`/`'n'`) is a native column, not a setting; see Storage for what it controls.

### Column settings (`exp_grid_columns`, one row per column)

| Column | Type | Notes |
|---|---|---|
| `col_id` | int, auto | names the data column `col_id_N` |
| `field_id` | int, **nullable** | the Grid field. NULL means an orphan row (see Gotchas) |
| `content_type` | varchar(50), nullable | `'channel'` for a channel Grid |
| `col_order` | int | 0-based |
| `col_type` | varchar(50) | any fieldtype whose `accepts_content_type('grid')` is true |
| `col_label` / `col_name` | varchar(50) / varchar(32) | `col_name`: alphaDash, unique per Grid, not reserved |
| `col_instructions` | text | |
| `col_required` / `col_search` | char(1) `'y'`/`'n'` | |
| `col_width` | int | percent, 0 for auto |
| `col_settings` | text, **JSON** | the column fieldtype's own settings (NOT base64-serialized like field settings) |

`Grid_lib::apply_settings()` (the control-panel path) runs the column fieldtype's `save_settings()` through
`_save_settings()` to fill defaults and then adds `field_required` (= `col_required`) to `col_settings`.
`grid_model::save_col_settings()` does NOT: it stores `col_settings` verbatim. A migration must therefore pass the
complete settings of the column fieldtype itself, plus `field_required`. For a `url` column that means
`allowed_url_schemes` and `url_scheme_placeholder` (see `url.md`); for `relationship` all fifteen keys
(`relationship.md`); for `text` `field_fmt`, `field_content_type`, `field_text_direction`, `field_maxl`.

Which fieldtypes can be a column: `Grid_lib::get_grid_fieldtypes()` keeps those whose `accepts_content_type('grid')`
is true. `grid_ft::accepts_content_type($name)` returns `$name != 'grid'`, so neither Grid nor File Grid can be a
column (fixture asserts this for both), and Fluid is excluded by its own class. `relationship` is excluded for any
content type other than `channel`. `date` works as a column; its localization options exist only as a field.

## Storage

- Field row: `exp_channel_fields.field_type = 'grid'`, `field_settings` = `base64_encode(serialize($five))`.
- Data table: `exp_channel_grid_field_G` (G = field id), created by `grid_model::create_field()`: `row_id` int(10)
  unsigned auto-increment PK, `entry_id` int(10) unsigned, `row_order` int(10) unsigned, `fluid_field_data_id`
  int(10) unsigned default 0, then one `col_id_C` column per column. Fixture proof, `col_id_C` types by `col_type`:
  `text` to `text`, `number` to `float`, `date` to `varchar(60)`, `toggle` to `tinyint(4)`, `relationship` to
  `varchar(8)` (a dummy; the data is in `exp_relationships`). The type is whatever the column fieldtype's
  `grid_settings_modify_column()` or `settings_modify_column()` returns.
- Every Grid field also has `exp_channel_data_field_G` with a `field_id_G` column (default fieldtype columns). It is
  NULL unless the field is searchable: `Grid_ft::save()` writes the compound searchable text there only when
  `field_search` is true, as `encode_multi_field()` of the `col_search = 'y'` cells (fixture: `'gamma|delta'`).
- `grid_model::save_col_settings()` for a NEW column inserts the settings row, then calls
  `api_channel_fields->set_datatype()` to add `col_id_C` to the data table; existing rows get `''` (fixture:
  `["",""]`).
- Fluid: a Grid child's rows carry `fluid_field_data_id` = `exp_fluid_field_data.id` (fixture asserts equality).
- Relationship cells: `exp_relationships` rows with `grid_field_id`, `grid_col_id`, `grid_row_id` set (see
  `relationship.md`).

## Create / change / remove

Prerequisites, in this order (the fixture's `CpsRefFixture::bootstrap()`):

```php
ee()->load->library('api');
ee()->legacy_api->instantiate('channel_fields');
ee()->api_channel_fields->fetch_installed_fieldtypes();   // BEFORE grid_model is used
ee()->load->model('grid_model');
```

Create the field, its table, then the columns. `field_id` and `content_type` go INSIDE the column array:

```php
$grid = ee('Model')->make('ChannelField');
$grid->site_id = (int) ee()->config->item('site_id');
$grid->field_name = 'example_grid';
$grid->field_label = 'Example grid';
$grid->field_type = 'grid';
$grid->field_instructions = '';
$grid->field_required = 'n';
$grid->field_search = 'n';            // 'y' also makes the field's own column hold compound search text
$grid->field_is_hidden = 'n';
$grid->field_order = 1;
$grid->legacy_field_data = 'n';
$grid->field_settings = [
    'grid_min_rows' => 0, 'grid_max_rows' => '', 'allow_reorder' => 'y',
    'vertical_layout' => 'n', 'row_counter' => 'n',
];
$grid->ChannelFieldGroups = $group;
$grid->save();

ee()->grid_model->create_field($grid->field_id, 'channel');   // the data table; once per Grid field

$columnId = ee()->grid_model->save_col_settings([
    'field_id' => $grid->field_id,
    'content_type' => 'channel',
    'col_order' => 0,
    'col_type' => 'text',
    'col_label' => 'Text',
    'col_name' => 'example_text',
    'col_instructions' => '',
    'col_required' => 'n',
    'col_search' => 'n',
    'col_width' => 0,
    'col_settings' => json_encode([
        'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr',
        'field_maxl' => 256, 'field_required' => 'n',
    ]),
], false, 'channel');                                           // returns the new col_id
```

`CpsRefFixture::makeGridField($group, $name, $columns, $order)` wraps this. Grid inside Fluid: create the Grid as
above, then a `fluid_field` whose `field_settings` are
`['field_channel_fields' => [(int) $grid->field_id], 'field_channel_field_groups' => []]` (Grid first, Fluid after).

Change a column (fixture-proved on a Grid that already held rows; the data column is named by id, so nothing moves):

- Add: `save_col_settings($array, false, 'channel')` as above; existing rows get `''`.
- Rename or relabel: `save_col_settings($array, $colId, 'channel')` with the new `col_name`; same `col_id`, data kept.
- Change type (text to textarea): the same call with the new `col_type` and settings. `edit_datatype()` runs the old
  type's delete hook, then modifies the single data column in place; fixture: `text` to `mediumtext`, values kept.
- Delete a column: `ee()->grid_model->delete_columns([$colId], [$colId => $colType], $fieldId, 'channel')`; removes the
  settings row and the data column and calls the column fieldtype's delete hook (a relationship column's
  `exp_relationships` rows go; fixture: 0 left). Sibling data stays.
- Change Grid settings: merge into `field_settings` and `save()`.
- Search: after adding or changing `col_search` or `field_search`, run
  `ee()->grid_model->update_grid_search([$fieldId])`; it rebuilds the compound value for every entry from the row
  table (fixture: filled an entry that had been saved without it). It only handles `field_type = 'grid'`.

Remove the field: `$field->delete()` (`Grid_ft::settings_modify_column()` with `ee_action = delete` deletes the
columns and the data table through `grid_model::delete_field()`). Delete a Fluid parent before its Grid children.
See Gotchas for the same-request trap.

## Content writes

Through the Model, the same path the control panel uses:

```php
$entry->{'field_id_' . $gridId} = ['rows' => [
    'new_row_1' => ['col_id_' . $textCol => 'first', 'col_id_' . $numCol => '1.5'],
    'new_row_2' => ['col_id_' . $textCol => 'second', 'col_id_' . $numCol => '2'],
]];
$entry->edit_date = ee()->localize->now;     // see the existing-entry rule below
$entry->save();
```

`Grid_ft::save()` only caches the value; the rows are written in `post_save()` by `Grid_lib::save()`. Fixture-proved
row contract:

- Keys: `new_row_N` creates a row; `row_id_R` updates row R. `row_order` is 0-based and follows array position.
- Append without destroying: resubmit every existing row (with its current cell values) under `row_id_R` plus the new
  `new_row_N`. Existing row ids are kept (fixture asserted).
- A row left out of the submitted array is DELETED. `['rows' => []]` deletes every row.
- An existing row submitted without a cell stores NULL for that cell (every column is saved). Send every cell.
- Reorder: submit the same `row_id_R` keys in the new order; ids unchanged, `row_order` rewritten.
- Relationship cell: `'col_id_C' => ['data' => [$entryId, ...]]`. Fluid child:
  `$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_G' => ['rows' => [...]]]]]`.
- `save()` does not call `validate()`. `$entry->validate()` is what gathers searchable data: with `field_search = 'y'`
  a plain `save()` stores NULL in the field's own column (fixture), `validate()` then `save()` stores `'a|b'`, and
  `update_grid_search()` is the migration-safe way to fill it.
- Existing entry, field-only change: assigning only the Grid value on an existing entry and calling `save()` is a
  silent no-op (fixture: rows unchanged). Likely mechanism (inferred from `ContentModel::save()`, not separately
  proven): `Grid_ft::save()` returns NULL for a non-searchable field, so the entry row has no changed column and the
  Model skips the update. Set `edit_date` (as the control panel does) or call `$entry->markAsDirty()`; both landed
  the write in the fixture. A relationship field does not have this problem (`relationship.md`).
- A Grid created after the channel's custom-field list was cached in the session is invisible to the entry: see
  Gotchas.

## Rollback

`down()` for a created Grid: `$field->delete()` (data table and `grid_columns` rows go), then delete
`grid_columns` rows by `field_id` and drop `channel_data_field_G` / `channel_grid_field_G` with plain SQL if the
field was created in the same request (`CpsRefFixture::removeAll()` does all of this, Fluid first). Entries delete
their rows (`Grid_ft::delete()` calls `Grid_lib::delete_rows()`; relationship cells' rows go with them).

Deleting a Grid field or column that holds real rows is `backup-only rollback`: the rows cannot be recreated from
the migration. Rolling back a column type change does not restore values the new type truncated.

## Verification

- Settings: `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'grid';` then
  `unserialize(base64_decode(field_settings))` has the five keys.
- Columns: `SELECT col_id, field_id, content_type, col_order, col_type, col_name, col_settings FROM exp_grid_columns
  WHERE field_id = <id> ORDER BY col_order;` and `col_settings` decodes with `json_decode`.
- Orphans (must be 0): `SELECT COUNT(*) FROM exp_grid_columns WHERE field_id IS NULL OR field_id = 0;`
- Data columns match the settings rows: `SHOW COLUMNS FROM exp_channel_grid_field_<G> LIKE 'col_id_<C>'` for every
  `col_id` above. Use `SHOW TABLES LIKE`/`SHOW COLUMNS`, not `table_exists()` (see Gotchas).
- Rows: `SELECT * FROM exp_channel_grid_field_<G> WHERE entry_id = <id> ORDER BY row_order;`
- Fluid: `SELECT id FROM exp_fluid_field_data WHERE fluid_field_id = <F> AND entry_id = <id>;` equals the Grid row's
  `fluid_field_data_id`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check` (SettingsContract and the smoke render); the fixture
  run is `run-fixtures.sh <site> grid`.
- Status of this reference: `run-fixtures.sh ../cfk grid file_grid relationship` printed `PASS grid` twice in a
  row on cfk (EE 7.5.27, 2026-10-05) with the final file, leaving the schema byte-identical.

## Gotchas

The production defects, each with the source reason and (where reproduced) the fixture's PROBE output:

1. **`save_col_settings()` with positional arguments or without `field_id`: orphan column rows.** The signature is
   `save_col_settings($column, $col_id = false, $content_type = 'channel')`; `field_id` and `content_type` are
   KEYS of `$column`. For a new column the method does `ee('db')->insert()` first (`grid_columns.field_id` is
   nullable, so a row with `field_id = NULL` is accepted), then reads `$column['field_id']`
   (`Undefined array key "field_id"`, `grid_model.php`), then runs `set_datatype()`, which `ALTER`s
   `exp_channel_grid_field_` (no id) and throws. Reproduced: `PROBE positional outcome: Exception: SQLSTATE[42S02]
   ... Table 'admin_cfk.exp_channel_grid_field_' doesn't exist`, `PROBE positional orphan rows with field_id NULL: 1`.
   The orphan row stays unless something deletes it (the fixture does).
2. **`grid_model` used before `fetch_installed_fieldtypes()`: a column row without its data column.** The registry
   (`api_channel_fields->field_types`) is empty until that call, so `setup_handler($column['col_type'])` returns
   false and `set_datatype()` passes NULL to `custom_field_data_hook()`. Reproduced: `PROBE no-registry registry_primed:
   no`, `outcome: TypeError: Api_channel_fields::custom_field_data_hook(): Argument #1 ($obj) must be of type
   EE_Fieldtype, null given`, `orphan_settings_rows: 1`, `col_id_N data columns: none`. Always bootstrap in the order
   shown under Create.
3. **Settings formats differ.** `col_settings` is JSON (`json_encode`); channel field settings are
   `base64_encode(serialize())`. Do not mix them. URL columns need `allowed_url_schemes` and
   `url_scheme_placeholder` in `col_settings` because `save_col_settings()` does not fill defaults (see Settings).
   I tried to reproduce the 2026-10-05 `TypeError` from inside a Grid (`$entry->validate()` on a url column whose
   settings lacked the key); the attempt returned 'invalid' rather than a `TypeError` and I could not diagnose it
   before cfk was left dirty, so that failure mode is explained from source only (`ft.url.php::validate()` calls
   `in_array('/', $this->get_setting('allowed_url_schemes'))` and `get_setting()` returns `false` when the key is
   absent; PHP 8 throws). The incident record is in `url.md`.
4. **A field deleted in the request that created it leaves its tables.** `grid_model::delete_field()` and
   `create_field()` guard with `ee()->db->table_exists()`, which caches the table list for the request. Reproduced:
   `PROBE doomed tables after delete in same request: {"channel_data_field_N":true,"channel_grid_field_N":true}`
   (the `grid_columns` rows did go: `1/0`). Use `SHOW TABLES LIKE` for any existence check and drop leftovers with
   `DROP TABLE IF EXISTS` (`CpsRefFixture::tableExists()` / `dropDataTableIfExists()`).
5. **A Grid created after an entry was saved in the same request is invisible to entries.**
   `Channel::getAllCustomFields()` caches the field list in `ee()->session` under `ChannelCustomFields/<channel_id>/`;
   `ChannelEntry` is built from it, so a later `field_id_N` assignment is stored as a plain property and silently
   dropped. Reproduced: `PROBE late field written, stale cached field list: 0 row(s)`; after
   `ee()->session->set_cache(\ExpressionEngine\Model\Channel\Channel::class, 'ChannelCustomFields/<id>/', false)`:
   `1 row(s)`. Create all fields first and drop the cache entry before the first entry write. Whether the cache is warm
   differs per environment, which is why this passed locally and failed on staging for relationships.
6. Existing-entry writes need `edit_date` or `markAsDirty()` (Content writes). Reproduced in the fixture.
7. Searchable data only appears after `validate()`; use `update_grid_search()` in migrations. Only `field_type =
   'grid'` is handled (not `file_grid`).
8. Grid and File Grid cannot be Grid columns; relationship columns are channel-only.
9. A Fluid write through the Model logs a harmless `E_WARNING: Undefined variable $field_group_id` from
   `ft.fluid_field.php`; the rows are written.
10. `eecli migrate` exits 0 even when `up()` throws. Judge success from `exp_migrations`, not the exit code.
11. A fixture or migration whose `up()` fails midway can leave rows and tables behind with no migration
    row to roll back. `run-fixtures.sh <site> --cleanup` removes `cpsref*` leftovers; it rolls back only when
    the newest `exp_migrations` row is its own cleanup migration, never on an exit code.
