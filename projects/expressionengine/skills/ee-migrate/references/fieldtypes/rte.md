---
fieldtype: rte
addon: rte
origin: core
verified: 7.5.27
fixture: 2099_02_01_000018_cpsref_rte
fixture_site: cfk
grid: yes
fluid: yes
---
# rte

Evidence: `system/ee/ExpressionEngine/Addons/rte/ft.rte.php`, `RteHelper.php`, `Model/Toolset.php`,
`addon.setup.php`, `upd.rte.php`, `Model/Channel/ChannelEntry.php` (`updateFilesUsage()`),
`Library/CP/FileManager/Traits/FileUsageTrait.php`, `Model/Content/FieldModel.php`, EE 7.5.27, and the passing
fixture `fixtures/2099_02_01_000018_cpsref_rte.php` (`run-fixtures.sh <site> rte`; passes on cfk and cps; cfk has no
`rte` fields of its own, only wygwam). The fixture is portable: it prefers toolsets named Basic and Full and otherwise
takes the lowest toolset ids, and takes its file from the first upload directory that holds an unused file, so it
runs on every site; in a real migration resolve the toolset by name. Official docs: see `EE-DOCS-NOTES.md`.

## Settings contract

`ft.rte.php::save_settings()` ignores its argument: it returns `ee('Request')->post('rte')` (the CP form) plus
three fixed keys. A migration therefore has to build the array itself.

| Key | PHP type | Default | Docs label | Absence |
|---|---|---|---|---|
| `toolset_id` | int (the CP form posts it as a string) | `ee()->config->item('rte_default_toolset')` (`'1'` on cfk) | Editor configuration | `display_field()` falls back to `rte_default_toolset`, then to the first toolset row; with no toolset at all it fatals |
| `defer` | string `'y'`/`'n'` | `'n'` | Defer initialization | read as `n` |
| `db_column_type` | string `'text'` or `'mediumtext'` | `'text'` | Column type (TEXT / MEDIUMTEXT) | `settings_modify_column()` uses `'text'` |
| `field_wide` | bool | `true` | none (CP form only) | none; layout hint |
| `field_fmt` | string | `'none'` | none | none; also a real `exp_channel_fields.field_fmt` column |
| `field_show_fmt` | string | `'n'` | none | none |

`field_wide`, `field_fmt` and `field_show_fmt` are added by `save_settings()` and are not in the docs; the docs
list only the toolset, defer and the column type. A Grid column stores only the first three
(`grid_save_settings()` returns `$settings['rte']` unchanged), in `grid_columns.col_settings` JSON.

Toolsets live in `exp_rte_toolsets` (`toolset_id`, `toolset_type` `ckeditor`/`redactor`/`redactorX`,
`toolset_name` unique, `settings`). Ids differ per site (cfk: 1 Basic, 2 Full, 3 Redactor Basic, ...), so
**resolve the id by NAME** at migration time:

```php
$toolset = ee('Model')->get('rte:Toolset')->filter('toolset_name', 'Basic')->first();
if (! $toolset) { throw new \RuntimeException("RTE toolset 'Basic' not found"); }
$toolsetId = (int) $toolset->toolset_id;
```

**A `toolset_id` that does not exist is accepted silently.** Nothing validates it (`rte` has no
`validate_settings()`); the fixture saved a field with a nonexistent id without error. The break comes at
display time: `display_field()` loads `$toolset = null`, builds the service name from `$toolset->toolset_type`
and `ee('rte:' . 'Service')` throws `Unregistered service "rte:Service"` (found: `cps:schema-check` smoke test,
`display_field() threw RuntimeException: Dependency Injection: Unregistered service "rte:Service"`), so the
publish screen for that channel breaks. The fixture creates such a field only to prove this and deletes it again.

## Storage

- Top-level: `field_id_N` and `field_ft_N` on `exp_channel_data_field_N` (`legacy_field_data = 'n'`).
  `settings_modify_column()` returns `type => $settings['db_column_type'] ?? 'text'`, nullable. Fixture proof,
  `SHOW COLUMNS`: `db_column_type = 'text'` gives `text`, `'mediumtext'` gives `mediumtext`. The value is read
  from `field_settings` at create time, so set it before the first `save()`.
- Grid: `grid_settings_modify_column()` reads the same key from the column settings;
  `exp_channel_grid_field_G.col_id_C` was `mediumtext` for a column created with `db_column_type = 'mediumtext'`.
- Settings: `exp_channel_fields.field_settings` is `base64_encode(serialize($array))`; Grid `col_settings` is JSON.
- Value: an HTML string. Fixture proof of what `save()` does to it before it reaches the column:
  - leading and trailing empty tags / whitespace are trimmed (`<p>&nbsp;</p>` at the start is removed);
  - `?cachebuster:123` query strings are removed;
  - braces inside `<code>...</code>` become `&#123;` / `&#125;`;
  - a URL that starts with a configured upload-directory URL, and a `{filedir_N}name` tag, both become
    `{file:ID:url}` when the file exists in `exp_files` and `file_manager_compatibility_mode` is off (cfk:
    off). With compatibility mode on, `getFileUsageReplacements()` returns nothing, so only the URL to
    `{filedir_N}` step (`replaceFileUrls()`) applies.
- Side tables: **`exp_file_usage`** gets one row `(file_id, entry_id)` per distinct file the entry's values
  reference, and `exp_files.total_records` is recounted. This is written by the entry save
  (`ChannelEntry::updateFilesUsage()`), not by the fieldtype. It scans `$_POST`, or `getValues()` when `$_POST`
  is empty (CLI, Model save): top-level values are seen; a Grid cell or Fluid child written through the Model was
  not (see the `file` reference). Deleting the entry removes the usage rows and recounts.

## Create / change / remove

`accepts_content_type()` returns `true`, and the add-on declares `compatibility => 'text'`: usable as a channel
field, a Grid column and a Fluid child (all three created in the fixture and read back).

Top-level field (`$group` is a saved `ChannelFieldGroup`; the helper `CpsRefFixture::makeField()` does this):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_rte';
$field->field_label = 'Example';
$field->field_type = 'rte';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_fmt = 'none';
$field->field_settings = [
    'toolset_id' => $toolsetId,          // resolved by name, see above
    'defer' => 'n',
    'db_column_type' => 'text',          // or 'mediumtext'; decides the data column type
    'field_wide' => true,
    'field_fmt' => 'none',
    'field_show_fmt' => 'n',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column (prerequisites: `ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes();` BEFORE `ee()->load->model('grid_model')`; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'rte', 'col_label' => 'Body', 'col_name' => 'body',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode(['toolset_id' => $toolsetId, 'defer' => 'n', 'db_column_type' => 'mediumtext']),
], false, 'channel');
```

Fluid child: create the field as above, then a `fluid_field` whose settings list it:
`['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []]`.

Change: merge into the existing `field_settings` and `save()`. Changing `toolset_id` or `defer` is settings only.
Changing `db_column_type` on a field that already has data was not tested; treat shrinking MEDIUMTEXT to TEXT as
a truncation risk and take a backup. Remove: `$field->delete()` (drops the data table); Grid: also delete the
`grid_columns` rows; Fluid before its children.

## Content writes

Through the Model (`CpsRefFixture::makeEntry()` is the tested path):

```php
$entry->field_id_N = '<p>Hello</p>';                                                  // top level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '<p>Cell</p>']]];      // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '<p>Child</p>']]]; // Fluid
$entry->save();
```

`save()` runs `Rte_ft::save()` (the transformations under Storage), so write the HTML you want stored; image URLs
that match an upload directory become `{file:ID:url}` by themselves. `save()` does not call `validate()`; the
fieldtype's `validate()` only enforces `field_required`. Under `eecli` the session library is not loaded and
`file_upload_preferences_model::get_paths()` (used by `save()` and by the entry's file-usage tracking) fails
with `No such property: 'session'` if you call it directly: `ee()->load->library('session')` first.

## Rollback

`down()` removes the entry (which removes its `exp_file_usage` rows and recounts `files.total_records`), the
Fluid field, the Grid field and its `grid_columns` rows, the RTE fields (Model `delete()` drops the data tables)
and the channel and field group (`CpsRefFixture::removeAll()`). A settings-only change (toolset, defer) is
reversible from the previous `field_settings`. Deleting an `rte` field that holds real content, or shrinking
its column type, is `backup-only rollback`.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has `toolset_id`, `defer`, `db_column_type`,
  `field_wide`, `field_fmt`, `field_show_fmt`; Grid: `json_decode(col_settings, true)` has the first three.
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'rte';`
- Toolset exists: `SELECT toolset_id, toolset_name, toolset_type FROM exp_rte_toolsets;` and every
  `toolset_id` in use appears in it.
- Column type: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'` (`text` / `mediumtext`);
  Grid: `SHOW COLUMNS FROM exp_channel_grid_field_G LIKE 'col_id_C'`.
- Value: `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>`.
- Usage: `SELECT file_id FROM exp_file_usage WHERE entry_id = <id>`; `SELECT total_records FROM exp_files WHERE file_id = <id>`.
- `$entry->validate()->isValid()`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check` (its smoke test runs `display_field()` and is what
  catches a missing toolset); `run-fixtures.sh <site> rte` prints `PASS rte`.

## Gotchas

- Always resolve the toolset by name. A hard-coded id works until the site's toolsets differ, then silently
  breaks the publish screen (see Settings contract).
- `save_settings()` reads the HTTP POST, not its argument: the Model path must supply the whole settings array.
- `db_column_type` is read when the data table is created; the Grid column type follows its own `col_settings`.
- Pasting full URLs into the HTML is fine: `save()` rewrites those that match an upload directory to
  `{file:ID:url}` (non-compat mode); other URLs are stored as given.
- File usage for the RTE HTML is tracked at the top level; do not expect usage rows for a Grid cell or Fluid
  child written through the Model.
- Model `delete()` of a field created in the same request can leave its data table behind
  (smartforge's `table_exists()` is cached per request); the fixture drops the throwaway table explicitly.
- Writing a Fluid value through the Model may log a harmless `E_WARNING: Undefined variable $field_group_id`
  from `ft.fluid_field.php`; the row is still written (seen again here).
- `eecli migrate` exits 0 even when `up()` throws; judge success from `exp_migrations` (`run-fixtures.sh` does).
- Member id 1 does not exist on every site; `makeEntry()` resolves a real `author_id`.
