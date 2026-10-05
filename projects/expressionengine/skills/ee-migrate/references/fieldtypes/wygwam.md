---
fieldtype: wygwam
addon: wygwam 6.0.2
origin: third-party
verified: 7.5.27
fixture: 2099_02_01_000025_cpsref_wygwam
fixture_site: cps
grid: yes
fluid: yes
---
# wygwam

Evidence: `system/user/addons/wygwam/ft.wygwam.php` (`save_settings()`, `grid_save_settings()`,
`settings_modify_column()`, `grid_settings_modify_column()`, `get_column_type()`, `display_field()`, `validate()`,
`save()`, `pre_process()`, `replace_tag()`, `accepts_content_type()`), `Helper.php` (`defaultSettings()`,
`insertConfigJsById()`, `replaceFileUrls()`, `replaceFileTags()`, `replacePageUrls()`), `Model/Config.php`,
`addon.json` / `addon.setup.php`, EE 7.5.27, the existing CPS fields (107 top-level, 40 Grid columns, 136 Fluid
rows), the creating migration `2026_09_11_100000_create_events_channel.php`, and the passing fixture
`fixtures/2099_02_01_000025_cpsref_wygwam.php` (`run-fixtures.sh <site> wygwam`; cps only). The official EE docs
do not cover third-party fieldtypes (`EE-DOCS-NOTES.md`); there is no vendor documentation in the repo, so the
source is the authority.

**Version sensitivity.** Everything below is behaviour of Wygwam **6.0.2** on EE 7.5.27 (`addon.json` `version`,
`exp_fieldtypes.version`). Third-party fieldtypes change between releases (the file-URL conversion in
`Helper::replaceFileUrls()` is already branched on `app_version`). After any Wygwam upgrade re-run
`run-fixtures.sh <site> wygwam` before trusting this file.

## Settings contract

`save_settings()` ignores its argument: it returns `ee('Request')->post('wygwam')` (the CP form) plus three fixed
keys, so a migration builds the whole array itself. `Helper::defaultSettings()` is `config_id => ''`, `defer => 'n'`.

| Key | PHP type | Default | Required? | Notes |
|---|---|---|---|---|
| `config_id` | string of digits (the CP posts a string; the events migration stores `(string) $id`) | `''` | No, but set it | Row in `exp_wygwam_configs`. **Resolve by NAME.** Empty/unknown id: display uses the built-in default config (see below) |
| `defer` | `'y'` / `'n'` | `'n'` | No (read as `n`) | `'y'` initialises the editor only when the field is clicked |
| `db_column_type` | `'text'` or `'mediumtext'` | `'text'` when absent | No | Decides the data column type, read at field-create time by `settings_modify_column()` |
| `field_wide` | bool `true` | none | No | Added by `save_settings()`; layout hint |
| `field_fmt` | `'none'` | none | No | Added by `save_settings()`; also a real `exp_channel_fields.field_fmt` column |
| `field_show_fmt` | `'n'` | none | No | Added by `save_settings()` |

A Grid column stores only the posted keys (`grid_save_settings()` returns `$settings['wygwam']`): `config_id`,
`defer`, `db_column_type`, in `grid_columns.col_settings` JSON (no `field_wide`/`field_fmt`; proven). Older CPS
columns also carry harmless extras (`convert`, `field_required`); `db_column_type` is absent on older fields, which
then get a `text` column (fixture field `cpsref_wygwam_bare` proves the default).

**Config by name, not id.** Configs live in `exp_wygwam_configs` (`config_id` int, `config_name` varchar(32),
`settings` text; ids and names differ per site; cps has dozens such as `Basic`, `Full`, `Clinical - Full`). Look the
id up by `config_name` and throw if missing, exactly as `2026_09_11_100000_create_events_channel.php` does:

```php
$row = ee()->db->select('config_id')->where('config_name', 'Clinical - Full')->get('wygwam_configs')->row_array();
if (empty($row)) {
    throw new \Exception("Wygwam config 'Clinical - Full' not found");
}
$configId = (string) (int) $row['config_id'];
```

**A `config_id` that does not exist is accepted silently and does NOT break anything.** Nothing validates it on
save (no `validate_settings()`), and `Helper::insertConfigJsById()` falls back to `$baseConfig` with handle
`default0` when the id is non-numeric or has no row. The fixture keeps a field with a nonexistent id
(`cpsref_wygwam_orphan`) through the whole run: `cps:schema-check`'s smoke test displayed it and passed, and an
entry value saved and read back. The failure is therefore silent: the editor opens with the generic default
toolbar instead of the intended one. That is a contrast with `rte`, where a missing toolset fatals at display.
Always resolve by name and throw.

## Storage

- Top-level (fields created by migration, `legacy_field_data = 'n'`): `field_id_N` and `field_ft_N` on
  `exp_channel_data_field_N`. `get_column_type()` returns `type => $settings['db_column_type'] ?? 'text'`,
  `null => true`. Fixture proof (`SHOW COLUMNS`): `'text'` gives `text`, `'mediumtext'` gives `mediumtext`, a
  setting without `db_column_type` gives `text`. Set it before the first `save()`.
- **cps legacy fields:** 94 of the 107 existing cps wygwam fields have `legacy_field_data = 'y'`; their HTML is in
  `exp_channel_data.field_id_N` (e.g. field 155, `mediumtext`), not in a per-field table. Only new fields use
  the per-field table. Use `legacy_field_data = 'n'`; verification SQL must check which one applies.
- Grid: `grid_settings_modify_column()` reads the same key from the column settings;
  `exp_channel_grid_field_G.col_id_C` was `mediumtext` for `db_column_type = 'mediumtext'`.
- Settings: `field_settings` is `base64_encode(serialize($array))`; Grid `col_settings` is JSON.
- Value: an HTML string. `save()` (via `Wygwam_ft::save()`) transforms it; fixture-proven on cps (non-compat mode):
  - leading/trailing empty tags and whitespace trimmed (`<p>&nbsp;</p>` at the start is removed);
  - `?cachebuster:123` removed; `&quot;` decoded to `"`;
  - braces inside `<code>...</code>` become `&#123;` / `&#125;`;
  - a URL starting with an upload-directory URL becomes `{filedir_N}name`, and a `{filedir_N}name` that is
    **followed by a closing double quote** (an `href="..."` or `src="..."` value) becomes `{file:ID:url}`, when the
    file exists in `exp_files`. The fixture stored `<img src="{file:5056:url}">` and `<a href="{file:10063:url}">`.
    A `{filedir_N}name` in running text (not before a `"`, e.g. `<p>{filedir_18}x.png</p>`) is **left as written**
    and is not tracked as usage (found); write `{file:ID:url}` yourself if you need it;
  - page URLs become `{page_N}` tags only when the Pages/Structure site pages exist (neither is installed on cps;
    not exercised; the CPS convention is hand-authored internal links);
  - `<!--read_more-->` is preserved. Extension hooks `wygwam_before_save` etc. run if present (none registered on cps).
  - `wygwam_prevent_url_conversion` (config) turns the URL conversion off (not checked on cps; the fixture proves conversion is active there).
- Output: `pre_process()`/`replace_tag()` turn `{file:ID:url}` / `{filedir_N}` back into URLs at render time, so the
  stored form is portable across upload-directory URL changes.
- **File usage:** the same entry-save mechanism as `rte`: `ChannelEntry::updateFilesUsage()` writes one
  `exp_file_usage` row per distinct file the entry's top-level values reference and recounts
  `exp_files.total_records`. Fixture proof: the `{file:A:url}` and quoted-`{filedir}` files each got one row and
  `total_records = 1`; a file used only inside a Grid cell got no row (`total_records` stayed 0); the raw
  running-text `{filedir_N}` file got none. This is written by the entry save, not by Wygwam. With
  `file_manager_compatibility_mode` on, usage is not tracked and `replaceFileUrls()` stops at `{filedir_N}`;
  cps has it off and the fixture fails if it is on.
- Difference from core `rte`: Wygwam is the CKEditor add-on configured by rows in `exp_wygwam_configs` (an `rte`
  field points at `exp_rte_toolsets`); the stored HTML and `{file:ID:url}` handling are close to identical, but
  Wygwam has the `config_id` silent fallback (above), `db_column_type` is optional, and Wygwam additionally
  supports `{assets_N}` (Assets add-on, not installed), page tags and `wygwam_*` hooks.

## Create / change / remove

`accepts_content_type()` returns `true` for `channel`, `grid`, `low_variables`, `fluid_field`, `blocks/1`; the
add-on declares `compatibility => 'text'`. All three of top level, Grid column and Fluid child were created and
read back in the fixture (and cps already has 40 Grid columns and 136 Fluid rows of wygwam).

Top-level field (`$group` is a saved `ChannelFieldGroup`; `CpsRefFixture::makeField()` does this):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_body';
$field->field_label = 'Body';
$field->field_type = 'wygwam';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_fmt = 'none';
$field->field_settings = [
    'config_id' => $configId,           // string, resolved by name (see above)
    'defer' => 'n',
    'db_column_type' => 'mediumtext',   // or 'text'
    'field_wide' => true,
    'field_fmt' => 'none',
    'field_show_fmt' => 'n',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column (prerequisites: `ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes();`
BEFORE `ee()->load->model('grid_model')`; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'wygwam', 'col_label' => 'Body', 'col_name' => 'body',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode(['config_id' => $configId, 'defer' => 'n', 'db_column_type' => 'mediumtext']),
], false, 'channel');
```

Fluid child: create the field as above, then a `fluid_field` whose settings list it:
`['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []]`.

Change: merge into the existing `field_settings` and `save()`; changing `config_id` or `defer` is settings only.
Changing `db_column_type` on a field with data was not tested (shrinking MEDIUMTEXT to TEXT can truncate;
back up first). Remove: `$field->delete()` (drops the data table); for Grid also delete the `grid_columns` rows;
Fluid before its children. **Pitfall:** a field created and deleted in the same request leaves
`channel_data_field_N` behind (cached `table_exists()`); use `CpsRefFixture::dropDataTableIfExists($fieldId)`
or a `DROP TABLE IF EXISTS` after the delete.

## Content writes

Through the Model (`CpsRefFixture::makeEntry()` is the tested path):

```php
$entry->field_id_N = '<p>Hello</p>';                                                  // top level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '<p>Cell</p>']]];      // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '<p>Child</p>']]]; // Fluid
$entry->save();
```

`Wygwam_ft::save()` runs (the transformations under Storage). Write the HTML you want stored; if it must be a tracked
file reference write `{file:ID:url}` explicitly. `save()` also writes `$_POST[$this->field_name] = $data` (a no-op under
`eecli`). `validate()` enforces only `field_required` (`$this->settings['field_required'] == 'y' && ! $data`).
Under `eecli` the session library is missing and `file_upload_preferences_model::get_paths()` (used by `save()`
and by file-usage tracking) fails: call `CpsRefFixture::ensureSession()` (or `ee()->load->library('session');
ee()->load->model('file_upload_preferences_model');`) first.

## Rollback

`down()` removes the entry (which removes its `exp_file_usage` rows and recounts `files.total_records`), the Fluid
field, the Grid field and its `grid_columns` rows, the wygwam fields and the channel and field group
(`CpsRefFixture::removeAll()`, which now also drops orphan data tables). A settings-only change (config, defer)
is reversible from the previous `field_settings`. Deleting a wygwam field that holds content, or shrinking its
column type, is `backup-only rollback`.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has `config_id` (string), `defer`, and for new fields
  `db_column_type`, `field_wide`, `field_fmt`, `field_show_fmt`; Grid: `json_decode(col_settings, true)` has
  `config_id`, `defer`, `db_column_type`.
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'wygwam';`
- Config exists: `SELECT config_id, config_name FROM exp_wygwam_configs;` and every `config_id` in use appears in it
  (a missing one is silent, so check it explicitly).
- Column type: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'` (`text` / `mediumtext`); Grid:
  `SHOW COLUMNS FROM exp_channel_grid_field_G LIKE 'col_id_C'`; legacy fields: `SHOW COLUMNS FROM exp_channel_data LIKE 'field_id_N'`.
- Value: `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>`.
- Usage: `SELECT file_id FROM exp_file_usage WHERE entry_id = <id>`; `SELECT total_records FROM exp_files WHERE file_id = <id>`.
- `$entry->validate()->isValid()`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> wygwam` prints `PASS wygwam`.

## Gotchas

- Resolve `config_id` by NAME and throw if missing: a wrong id never errors, it just gives editors the default toolbar.
- `config_id` is stored as a string; `(string)` it.
- `{filedir_N}name` is converted/tracked only before a closing `"` (inside an attribute); in running text it is kept
  as written. Prefer `{file:ID:url}` in migrated HTML.
- Files only referenced from a Grid cell or Fluid child written through the Model get no `exp_file_usage` row.
- Most existing cps wygwam fields are `legacy_field_data = 'y'` (data in `exp_channel_data`); new ones are not.
- Install requires a config row; `_fieldSettings()` shows a "create config" link instead of a picker when
  `exp_wygwam_configs` is empty.
