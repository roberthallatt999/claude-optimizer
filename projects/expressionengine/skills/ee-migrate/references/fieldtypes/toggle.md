---
fieldtype: toggle
addon: toggle
origin: core
verified: 7.5.27
fixture: 2099_02_01_000013_cpsref_toggle
fixture_site: cfk
grid: yes
fluid: yes
---
# toggle

Evidence: `system/ee/ExpressionEngine/Addons/toggle/ft.toggle.php` and `addon.setup.php`, `EE_Fieldtype.php`,
`Model/Content/FieldModel.php` (`getColumns()`, `ensureDefaultColumns()`, `set()`), `legacy/core/Config.php`
(`update_site_prefs()`, `_update_config()`), the Fluid source, EE 7.5.27, and the passing fixture
`fixtures/2099_02_01_000013_cpsref_toggle.php` (`run-fixtures.sh <site> toggle`; run on cfk). Official docs:
see `EE-DOCS-NOTES.md` (docs list no settings and `1` on / `0` off).

## Settings contract

`ft.toggle.php::save_settings()` merges the posted data over `$settings_vars` and keeps ONLY the keys of
`$settings_vars` (`array_intersect_key`), which is a single key:

| Key | PHP type | Default | Docs label | Absence |
|---|---|---|---|---|
| `field_default_value` | `'0'` or `'1'` (string or int; the CP form posts `0`/`1`) | `'0'` | none listed in the docs (the CP shows "Default value"); the docs omit this setting | `display_field()` merges `$settings_vars`, so display copes. BUT `settings_modify_column()` reads `$data['field_settings']['field_default_value']` unguarded when the field is created (undefined-array-key warning, and a NULL/empty `DEFAULT` for the column). Always write it, for fields and for Grid column `col_settings` |

Other behaviour:

- `validate()` accepts `false`, `''`, `'1'` and `'0'`; anything else returns `invalid_selection` (fixture: `7`
  fails). `save()` casts to int.
- `yes_no` is read through `get_setting('yes_no', false)` by `validate()`, `save()` and `display_field()`
  (then `y`/`n` replace `1`/`0`), but `save_settings()` drops it, so it is not a channel-field setting: do not
  use it with a TINYINT column.

### What `save_settings()` writes besides the field's own settings

Source (`ft.toggle.php::save_settings()`), exactly:

```php
if (is_null($this->field_id)) {
    ee('CP/Alert')->makeInline('search-reindex')->asImportant()->...->defer();   // deferred CP alert
    ee()->config->update_site_prefs(['search_reindex_needed' => ee()->localize->now], 0);
}
```

- The condition is `field_id` being NULL, i.e. `save_settings()` runs for a field that has no id yet. It is
  NOT keyed on `field_id` being `0` (a `0` id is not null and would skip the block). That is the case for a
  new field posted through the control panel or built with `$model->set([...])`/`ee('Model')->make('ChannelField', $data)`,
  because `FieldModel::set()` calls `saveSettingsForm()` and so `save_settings()` before the row exists.
- It does not run when you assign properties one by one (`$field->field_settings = [...]`) and `save()`,
  nor when editing an existing field (the id is set). The fixture asserts this: it compares
  `exp_config.search_reindex_needed` before and after creating all four toggle fields (top-level, Grid, Fluid
  child) and throws if it changed.
- What it writes when it does run: `update_site_prefs()` with `site_ids = 0` (treated as the current site by
  `empty($site_ids)`); because `search_reindex_needed` is in the install-default list, it goes to
  `exp_config` as a row with `site_id = 0`, key `search_reindex_needed`, value = the current timestamp. The
  call then goes through `_remaining_config_values()` -> `_update_config()`, which requires `config.php`
  to be writable (a 503 `unwritable_config_file` otherwise) and re-reads it; the key is not appended to the
  file because it is a known install-default key. The fixture does NOT execute this path (it would touch the
  site's config), so the exact config-file effect is source-derived, not proven.
- Effect: the control panel then shows the "search reindex needed" notice
  (`Utilities/Reindex.php` reads that preference). It does not alter content or schema. To undo it after a
  migration that ran this path, reindex from the CP or reset the `exp_config` row; to avoid it, create the
  field by property assignment as in the snippets below.
- Seen on cps on 2026-10-05: a migration that created a toggle through the `set()` path left a
  `search_reindex_needed` preference behind.

## Storage

- Top-level: `field_id_N` as `TINYINT NOT NULL DEFAULT <field_default_value>` on `exp_channel_data_field_N`
  (`settings_modify_column()` -> `get_column_type()` overrides the default text column), plus the default
  `field_ft_N` (`tinytext`) added by `ensureDefaultColumns()`. Fixture proof: `SHOW COLUMNS` gave
  `tinyint`, `Null = NO`, `Default = 1` for a field created with `field_default_value = 1` and `Default = 0`
  for one created with `0`; `field_ft_N` exists.
- Grid: `col_id_C` on `exp_channel_grid_field_G` is the same `TINYINT NOT NULL` with the column's default
  (`grid_settings_modify_column()` reads `$data['field_default_value']`). Fixture proof: `tinyint`, NOT NULL,
  default `1`.
- Settings: `field_settings` is `base64_encode(serialize(['field_default_value' => ...]))`; Grid: JSON in
  `exp_grid_columns.col_settings`.
- Value: `1` on, `0` off, read back as the strings `'1'` / `'0'`. A field never written to an entry holds the
  column default (the fixture left one field out of the entry and read back `0`).
- Fluid: the child's value is in its own data table on a row with `entry_id = 0`, linked by
  `exp_fluid_field_data.field_data_id`; value `1` read back.

## Create / change / remove

`addon.setup.php` declares `'compatibility' => 'toggle'` (switchable only with other toggle-compatible
types) and `accepts_content_type()` returns `true` for all content types, so toggle works as a channel field,
a Grid column and a Fluid child; the fixture created all three.

Top-level field (property assignment: does NOT trigger the `search_reindex_needed` write):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'is_featured';
$field->field_label = 'Featured';
$field->field_type = 'toggle';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = ['field_default_value' => '0'];   // required for the column DEFAULT
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column (prerequisites: `ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes();` BEFORE `ee()->load->model('grid_model')`; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'toggle', 'col_label' => 'Flag', 'col_name' => 'flag',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode(['field_default_value' => '1']),
], false, 'channel');
```

Fluid child: create the toggle as above, then
`$fluid->field_settings = ['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []];`.

Change the default: update `field_settings['field_default_value']` and `save()`; `onAfterUpdate()` re-syncs the
column (`diffColumns`), which changes the column `DEFAULT` for new rows only. Existing rows keep their values.
Remove: `$field->delete()` (drops the data table); Grid: delete the `grid_columns` rows too; Fluid before its children.

## Content writes

```php
$entry->field_id_N = 1;                                                                  // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => 0]]];                      // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => 1]]];               // Fluid
$entry->save();
```

`save()` casts to int. `save()` on the Model does not validate; call `$entry->validate()` for untrusted
input (the fixture shows `7` is rejected).

## Rollback

`down()` removes the entry, the Fluid field, the Grid field and its `grid_columns` rows, the toggle fields
and the field group and channel (`CpsRefFixture::removeAll()`); the schema and settings dump are
byte-identical afterwards. If a migration used the `set()` path, `down()` does not undo the
`search_reindex_needed` preference (an `exp_config` row, see above). Deleting a toggle that holds real
content is `backup-only rollback`.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has `field_default_value`; Grid:
  `json_decode(col_settings, true)` has it.
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'toggle';`
  `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'toggle';`
- Column: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'` (expect `tinyint`, `NO`, the default);
  Grid: `SHOW COLUMNS FROM exp_channel_grid_field_G LIKE 'col_id_C'`.
- Data: `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>`; Grid row:
  `SELECT col_id_C FROM exp_channel_grid_field_G WHERE entry_id = <id>`; Fluid:
  `SELECT * FROM exp_fluid_field_data WHERE fluid_field_id = <F> AND entry_id = <id>` then the child table row.
- Side effect check: `SELECT site_id, value FROM exp_config WHERE `key` = 'search_reindex_needed';` before
  and after the migration.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> toggle` prints `PASS toggle`.

## Gotchas

- Always set `field_default_value` in `field_settings` / `col_settings`: the column `DEFAULT` is built from it
  at creation time (unguarded array access in `get_column_type()`).
- The `search_reindex_needed` preference write only happens through the `set()`/`make($data)` path for a new
  field; prefer property assignment in migrations (as above) and say so in the migration notes if you must
  use `set()`.
- The default is a column default, so changing `field_default_value` later does not rewrite existing rows.
- `NOT NULL`: an entry created without a value gets the default, never NULL. A toggle cannot be "unset".
- Values are `1`/`0` (ints cast to string on read). Conditionals/templates compare against `1`/`0`
  (`{if my_toggle == 1}`), not `y`/`n`; the `yes_no` display mode is not a settable channel-field option.
- Model `save()` skips `validate()` (finding from the `url` fixture). Validate untrusted values.
- Writing a Fluid value through the Model may log a harmless `E_WARNING: Undefined variable $field_group_id`
  from `ft.fluid_field.php::save()`; the row is still written.
- `eecli migrate` exits 0 even when `up()` throws; judge success from `exp_migrations` or
  `cps:migrate-status` (`run-fixtures.sh` does).
- Member id 1 does not exist on every site; resolve a real `author_id` before saving entries.
