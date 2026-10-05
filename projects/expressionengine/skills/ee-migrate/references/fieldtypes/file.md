---
fieldtype: file
addon: file
origin: core
verified: 7.5.27
fixture: 2099_02_01_000019_cpsref_file
fixture_site: cfk
grid: yes
fluid: yes
---
# file

Evidence: `system/ee/ExpressionEngine/Addons/file/ft.file.php` and `addon.setup.php`,
`legacy/libraries/File_field.php` (`getFileModelForFieldData()`, `parse_string()`),
`Model/Channel/ChannelEntry.php` (`updateFilesUsage()`, the `EntryFiles` association on the `file_usage` pivot),
`Library/CP/FileManager/Traits/FileUsageTrait.php`, `Service/File/Usage.php`, `Model/Content/ContentModel.php`
(`updateFilesTotalRecords()`), EE 7.5.27, and the passing fixture `fixtures/2099_02_01_000019_cpsref_file.php`
(`run-fixtures.sh <site> file`; passes on cfk and cps). The fixture is portable: it takes the
first upload directory (lowest id) holding five unused files and fails with "prerequisite missing" if the site has
none. In a real migration resolve the directory by name, as below. Official docs: see `EE-DOCS-NOTES.md`.

## Settings contract

`save_settings()` merges the posted data over the defaults and keeps only the five default keys
(`array_intersect_key`):

| Key | PHP type | Default | Docs label | Absence |
|---|---|---|---|---|
| `field_content_type` | string `'all'` or `'image'` | `'all'` | Allowed file types (images only / all safe) | `display_field()` treats absent as `'all'` |
| `allowed_directories` | string: `'all'` or ONE upload-directory id as a string (`'8'`) | `''` | Allowed directory | `display_field()` treats absent as `'all'`; the CP form requires it (`validate_settings()`), the Model path does not |
| `show_existing` | string `'y'`/`'n'` | `''` (the CP form pre-selects `y`) | Show existing files (Channel Form setting) | absent reads as `'n'` |
| `num_existing` | string/int, `0` means all (CP default 50) | `0` | Existing files limit (Channel Form setting) | absent reads as `0` |
| `field_fmt` | string | `'none'` | none | none |

Existing cfk data stores the CP shape: all values as strings (`s:2:"63"`, `s:1:"y"`, `s:2:"50"`). Docs and source
agree on the four documented settings; `field_fmt` is source only. `show_existing`/`num_existing` only matter
for Channel Form (front-end) rendering; the control panel uses the drag-and-drop widget regardless.

The directory must exist already (docs: "an upload directory must exist first"). **Resolve it by NAME**, never
by a copied id (the fixture instead picks the first directory with files so it runs on every site):

```php
$dir = ee()->db->select('id')->where('name', 'Handout images')->get('upload_prefs')->row_array();
if (! $dir) { throw new \RuntimeException('upload directory not found'); }
$allowed = (string) $dir['id'];
```

(cfk directories at the time of writing: Handout images 8, CFK images 9, Handout featured images 63, Wellbeings 64,
Featured images 68, Heroes 95, Sidenav images 96, plus legacy member-image directories 78 to 82.) The upload
directory model is `UploadDestination` (`exp_upload_prefs`); do not create or alter directories from a field migration.

Grid column: the same five keys in `grid_columns.col_settings` JSON (`grid_display_settings()` reuses
`display_settings()`); the fixture's column stored all five.

## Storage

- Top-level: `field_id_N` (`text`) and `field_ft_N` on `exp_channel_data_field_N` (default column, no
  `settings_modify_column()` override; fixture: `text`). Older fields may have `legacy_field_data = 'y'` and
  keep the value in `exp_channel_data` (cfk field 1341 does); this reference and the fixture use `'n'`.
- Settings: `exp_channel_fields.field_settings` is `base64_encode(serialize($array))`.
- Value formats (fixture proof, read back from the data column): `save()` returns `$data` unchanged, so the
  string you write is the string stored.
  - `{file:ID:url}` is the current format (docs; all existing cfk data is in it). Stored as written.
  - `{filedir_N}name.ext` is the legacy format. Stored as written, NOT converted to a tag by `save()`.
  - A bare file id (`'100'`) is accepted by `validate()` (`getFileModelForFieldData()` handles numeric,
    `{file:ID:url}` and `{filedir_N}name`) and stored as written. Do not use it: no usage row is created.
- Side tables written by the entry save, not by the fieldtype (`ChannelEntry::updateFilesUsage()`):
  `exp_file_usage (file_usage_id, file_id, entry_id, cat_id)` gets one row per distinct file referenced, and
  `exp_files.total_records` is recounted. Fixture proof on a Model save: a `{file:ID:url}` value and a
  `{filedir_N}name` value each produced one usage row (`total_records` 0 to 1); a bare id produced none; entry
  delete removed the rows and returned `total_records` to 0.
- **Grid and Fluid files are not tracked by a Model/CLI save.** `updateFilesUsage()` walks `$_POST`, or
  `$this->getValues()` when `$_POST` is empty; the Grid cell and the Fluid child written through the Model
  (both `{file:ID:url}`) produced no usage rows (found, fixture). A control-panel save posts them, so by source they are
  tracked there. For migrated content run `eecli sync:file-usage` (`Cli/Commands/CommandSyncFileUsage.php`, not run here;
  it rebuilds usage from stored data using `Service/File/Usage.php` and reads the Grid tables too) or accept the gap.
- **Compatibility mode:** when `file_manager_compatibility_mode` is on, `updateFilesUsage()` returns at once and
  `getFileUsageReplacements()` returns `[]`: no usage rows, no `{filedir_N}` to `{file:ID:url}` conversion
  anywhere. cfk has it off (read via `bool_config_item()` in a probe).
- Grid: `exp_channel_grid_field_G.col_id_C` (`text`). Fluid: the child's value is in the child field's own data
  table, row `entry_id = 0`, linked by `exp_fluid_field_data.field_data_id`.

## Create / change / remove

`accepts_content_type()` returns `true`; the add-on declares `compatibility => 'file'`. All three shapes were created and read back.

Top-level field (`CpsRefFixture::makeField()`):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_file';
$field->field_label = 'Example';
$field->field_type = 'file';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'field_content_type' => 'image',        // or 'all'
    'allowed_directories' => (string) $dir['id'],   // or 'all'
    'show_existing' => 'y',
    'num_existing' => '20',
    'field_fmt' => 'none',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column (prerequisites: `ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes();` BEFORE `ee()->load->model('grid_model')`; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'file', 'col_label' => 'Image', 'col_name' => 'image',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_content_type' => 'image', 'allowed_directories' => (string) $dir['id'],
        'show_existing' => 'y', 'num_existing' => '20', 'field_fmt' => 'none',
    ]),
], false, 'channel');
```

Fluid child: create the field as above, then a `fluid_field` whose settings are
`['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []]`.

Change: merge into `field_settings` and `save()` (settings only; existing values are not re-validated). Remove:
`$field->delete()` (drops the data table; Grid: delete `grid_columns` rows too; Fluid before its children). Never
create, move or delete files or upload directories from a field migration; this fixture only reads `exp_files`.

## Content writes

```php
$entry->field_id_N = '{file:' . $fileId . ':url}';                                       // top level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '{file:' . $fileId . ':url}']]];   // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '{file:' . $fileId . ':url}']]]; // Fluid
$entry->save();
```

Look the file up first (`SELECT file_id FROM exp_files WHERE upload_location_id = ? AND file_name = ?`) and throw
when it is missing; the Model save does not. `save()` does not run `validate()`; call `$entry->validate()` for
untrusted values: it passed for the stored entry and failed (`invalid_selection`) for `{file:999999999:url}`.
`validate()` also checks directory permission with `ee()->session->getMember()` whenever the value CHANGED
(`$check_permissions`); under `eecli` there is no member, so changing a file value through `validate()` there
returns `directory_no_access`: validate unchanged values only, or skip it in CLI. Under `eecli` the session
library is not loaded and `file_upload_preferences_model::get_paths()` (used by the entry save's usage
tracking) fails with `No such property: 'session'` if called directly: `ee()->load->library('session')` first.

## Rollback

`down()` removes the entry (usage rows removed, `total_records` recounted: fixture proof, back to 0), the Fluid
field, the Grid field and its `grid_columns` rows, the file fields (data tables dropped), the field group and the
channel (`CpsRefFixture::removeAll()`). The fixture reads existing `exp_files` rows and changes only their
`total_records`, which the entry delete restores; it never touches files on disk. Deleting a `file` field that
holds real references is `backup-only rollback` (the files stay, the references and usage rows go).

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has the five keys; Grid `col_settings` the same five.
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'file';`
- Directory exists: `SELECT id, name FROM exp_upload_prefs;`
- Data column: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'`; value:
  `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>`.
- Every stored reference resolves: for `{file:ID:url}`, `SELECT file_id FROM exp_files WHERE file_id = ID`.
- Usage: `SELECT file_id FROM exp_file_usage WHERE entry_id = <id>`; consistency check
  `SELECT COUNT(*) FROM exp_files f WHERE total_records <> (SELECT COUNT(*) FROM exp_file_usage u WHERE u.file_id = f.file_id);` (0 on cfk).
- `$entry->validate()->isValid()` for unchanged values.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> file` prints `PASS file`.

## Gotchas

- Write `{file:ID:url}`. `{filedir_N}name` is stored verbatim; it still creates a usage row, but is the legacy
  format. A bare id creates no usage row.
- `allowed_directories` is a single id (string) or `'all'`; there is no multi-directory value.
- Model/CLI saves do not record usage for files in Grid cells or Fluid children (see Storage).
- Usage rows are written by the entry save, never by the field: raw SQL changes to the field data bypass them.
- With `file_manager_compatibility_mode` on, no usage rows are written and nothing is converted to `{file:ID:url}`.
- `legacy_field_data = 'y'` fields keep their data in `exp_channel_data`, not in `exp_channel_data_field_N`.
- Docs list no storage format; source and the fixture are the authority.
- Writing a Fluid value through the Model may log a harmless `E_WARNING: Undefined variable $field_group_id`
  from `ft.fluid_field.php`; the row is still written.
- `eecli migrate` exits 0 even when `up()` throws; judge success from `exp_migrations` (`run-fixtures.sh` does).
- Member id 1 does not exist on every site; `makeEntry()` resolves a real `author_id`.
