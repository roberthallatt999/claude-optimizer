---
fieldtype: file_grid
addon: grid
origin: core
verified: 7.5.27
fixture: 2099_02_01_000022_cpsref_file_grid
fixture_site: cfk
grid: no
fluid: yes
---
# file_grid

Evidence: `system/ee/ExpressionEngine/Addons/grid/ft.file_grid.php` (the class lives in the grid add-on; there is no
`Addons/file_grid/`), `Addons/grid/addon.setup.php`, `Addons/grid/ft.grid.php`, `Addons/grid/libraries/Grid_lib.php`,
`Addons/fluid_field/ft.fluid_field.php::removeField()`, `Service/File/Usage.php`, `legacy/models/grid_model.php`, EE
7.5.27, and the fixture `fixtures/2099_02_01_000022_cpsref_file_grid.php` (`run-fixtures.sh <site> file_grid`).
Everything not listed as different below is identical to `grid.md`; read that first. Official docs: see
`EE-DOCS-NOTES.md` (a Grid with a mandatory File column, short name `file`, that cannot be removed).

## Settings contract

`file_grid_ft extends Grid_ft` (`require_once PATH_ADDONS . 'grid/ft.grid.php'`), registered in
`grid/addon.setup.php` as a second fieldtype of the Grid add-on with `'compatibility' => 'file_grid'`.
`ft.file_grid.php::save_settings()` returns Grid's five keys (`parent::save_settings()`) plus two more, read straight
from the posted data with no default:

| Key | PHP type | Default | Notes |
|---|---|---|---|
| `grid_min_rows` | int | `0` | as Grid; `validate()` is overridden so the minimum is enforced for non-AJAX saves |
| `grid_max_rows` | string | `''` | as Grid |
| `allow_reorder` | `'y'`/`'n'` | `'y'` | as Grid |
| `vertical_layout` | string | `'n'` | as Grid (`'n'`, `'y'`, `'horizontal'`) |
| `row_counter` | `'y'`/`'n'` | `'n'` | as Grid |
| `field_content_type` | `'all'` or `'image'` | none (CP: `'image'`) | read directly from `$data`: always pass it |
| `allowed_directories` | `'all'` or ONE directory id string | none (CP: `'all'`) | read directly: always pass it |

Fixture: the seven keys stored; `allowed_directories` was the directory id as a string; `field_content_type`
`'image'`. Resolve the directory by NAME (`SELECT id FROM exp_upload_prefs WHERE name = ?`), as in `file.md`; the
fixture instead takes the first directory holding two unused files so it runs on every site.

### The mandatory `file` column

The control panel adds a hidden first column (`getColumnsForSettingsView()`: `col_type = 'file'`,
`col_label = 'File'`, `col_name = 'file'`, `col_search = 'y'`, `col_hidden = true`) and
`post_save_settings()` overwrites that column's `col_settings` from the POST with exactly the two file settings:

```
{"field_content_type": "image", "allowed_directories": "63"}
```

A migration has to create this column itself (nothing else will): `col_name` `file`, `col_type` `file`,
`col_order` 0, `col_search` `y`, `col_settings` repeating the field's two file settings (plus `field_required`).
Fixture asserted: first column named `file`, typed `file`, `col_search = 'y'`, `col_settings` equal to the field's
values. Further columns are ordinary Grid columns (the fixture adds a `text` column). When the field is `required`,
`Grid_lib::validate()` makes the `file` column required (`settings_form_field_name == 'file_grid' && col_name ==
'file'`).

Can it be a column of another Grid? No: it inherits `Grid_ft::accepts_content_type($name)` (`$name != 'grid'`), so
`accepts_content_type('grid')` is false (fixture asserts it for `grid` and `file_grid`), while `fluid_field` and
`channel` are true. Fluid's `removeField()` has an explicit `case 'file_grid':` next to `grid`.

## Storage

Same as Grid: `exp_channel_fields.field_type = 'file_grid'`, base64-serialized `field_settings` (seven keys), data
rows in `exp_channel_grid_field_N` (`row_id`, `entry_id`, `row_order`, `fluid_field_data_id`, `col_id_C`), settings
in `exp_grid_columns` (JSON `col_settings`). The `file` column's data column is `text` (fixture) and holds the file
reference as written: `{file:ID:url}` (the current format, see `file.md`). Fluid children get `fluid_field_data_id`
as for Grid (fixture asserted).

File usage: `Service/File/Usage.php` walks `grid` and `file_grid` columns when it rebuilds usage (run
`eecli sync:file-usage`). A Model/CLI save writes NO `exp_file_usage` rows for Grid cells (fixture asserted 0 rows
for the entry), the same limit as `file.md` records for plain Grid.

Search: `grid_model::update_grid_search()` filters `field_type = 'grid'`, so it does NOT process `file_grid`;
compound search data (`field_search = 'y'`) is written only by `validate()` then `save()` on the entry
(`Grid_ft::save()`, inherited). Not run here.

## Create / change / remove

Create exactly as `grid.md`, with the `file_grid` type, the seven settings and the `file` column first. Prerequisites
first (`fetch_installed_fieldtypes()` before `grid_model`; `field_id` and `content_type` INSIDE the column array):

```php
ee()->load->library('api');
ee()->legacy_api->instantiate('channel_fields');
ee()->api_channel_fields->fetch_installed_fieldtypes();
ee()->load->model('grid_model');

$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_file_grid';
$field->field_label = 'Example file grid';
$field->field_type = 'file_grid';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'grid_min_rows' => 0, 'grid_max_rows' => '4', 'allow_reorder' => 'y',
    'vertical_layout' => 'n', 'row_counter' => 'y',
    'field_content_type' => 'image', 'allowed_directories' => (string) $directoryId,
];
$field->ChannelFieldGroups = $group;
$field->save();
ee()->grid_model->create_field($field->field_id, 'channel');

ee()->grid_model->save_col_settings([
    'field_id' => $field->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'file', 'col_label' => 'File', 'col_name' => 'file',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'y', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_content_type' => 'image', 'allowed_directories' => (string) $directoryId,
        'field_required' => 'n',
    ]),
], false, 'channel');
```

Fluid child: create the field as above, then a `fluid_field` whose settings are
`['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []]`. Grid column: not possible.

Change and remove: as `grid.md` (`save_col_settings($array, $colId, 'channel')`, `delete_columns()`,
`$field->delete()`). Never delete the `file` column; the control panel hides it and the field's file settings are
applied to it. Never create or move files or upload directories from a field migration.

## Content writes

```php
$entry->{'field_id_' . $fieldId} = ['rows' => [
    'new_row_1' => ['col_id_' . $fileCol => '{file:' . $file['file_id'] . ':url}', 'col_id_' . $captionCol => 'first'],
]];
$entry->save();
```

Look the file up first (`SELECT file_id FROM exp_files WHERE upload_location_id = ? AND file_name = ?`) and throw when
it is missing; the Model save does not. Row keys, append, reorder and deletion follow `grid.md` (`new_row_N`,
`row_id_R`, omitted rows are deleted, omitted cells become NULL). Fluid:
`['fields' => ['new_field_1' => ['field_id_N' => ['rows' => [...]]]]]` (fixture wrote and read it back). The
existing-entry rule of `grid.md` applies (set `edit_date`); I did not probe it again for `file_grid`. In Channel
Form `display_field()` returns the plain Grid markup; the drag-and-drop widget is control-panel only.

## Rollback

`down()`: delete the entries (rows go via `Grid_ft::delete()`), the Fluid field, the `file_grid` field (its table and
`grid_columns` rows), the field group and channel (`CpsRefFixture::removeAll()` ranks `file_grid` with `grid`).
Deleting a `file_grid` field that holds real rows is `backup-only rollback`; the files stay, the references go. The
fixture reads existing `exp_files` rows and never changes them.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` for `field_type = 'file_grid'` has the seven keys.
- The file column: `SELECT col_order, col_name, col_type, col_search, col_settings FROM exp_grid_columns WHERE
  field_id = <id> ORDER BY col_order;` first row `0, file, file, y` and `col_settings` equal to the field's file
  settings.
- Orphans: `SELECT COUNT(*) FROM exp_grid_columns WHERE field_id IS NULL OR field_id = 0;` is 0.
- Rows: `SELECT col_id_<C> FROM exp_channel_grid_field_<G> WHERE entry_id = <id>;` every value is `{file:ID:url}`
  and each ID exists in `exp_files`.
- Usage after control-panel saves: `SELECT file_id FROM exp_file_usage WHERE entry_id = <id>;`; after migrated content
  run `eecli sync:file-usage`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> file_grid`.
- Status of this reference: `run-fixtures.sh ../cfk grid file_grid relationship` printed `PASS file_grid` twice in a
  row on cfk (EE 7.5.27, 2026-10-05) with the final file, leaving the schema byte-identical.

## Gotchas

- Different from Grid: type `file_grid`, seven settings (two read without defaults), a mandatory first `file` column
  whose settings repeat the field's, `compatibility => 'file_grid'`, and `update_grid_search()` ignores it.
- Not a Grid column and not nestable; usable in Fluid (source: `accepts_content_type()`; fixture asserted).
- The `file` column must exist. `Grid_lib::validate()` special-cases it by name; the CP assumes it is present and
  hidden. Do not rename it.
- `allowed_directories` is a single id string or `'all'`; there is no multi-directory value.
- No usage rows from a Model/CLI save; run `sync:file-usage` for migrated content.
- Everything in `grid.md` Gotchas applies: bootstrap order, `field_id`/`content_type` inside the array, JSON vs
  base64, same-request deletion leaves tables, stale cached field list, `eecli migrate` exit code.
