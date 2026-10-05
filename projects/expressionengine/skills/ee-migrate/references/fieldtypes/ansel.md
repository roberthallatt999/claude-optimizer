---
fieldtype: ansel
addon: ansel 3.0.8
origin: third-party
verified: 7.5.27
fixture: 2099_02_01_000026_cpsref_ansel
fixture_site: cps
grid: yes
fluid: yes
---
# ansel

Evidence: `system/user/addons/ansel/ft.ansel.php` (`accepts_content_type()`, `save_settings()`, `validate_settings()`,
`save()`, `post_save()`, `grid_post_save()`, `delete()`, `grid_delete()`), `Controller/Field/FieldSettings.php`
(`get()`, `validate()`, `save()`), `Controller/Field/FieldSave.php`, `Service/AnselImages/SaveRow.php` and
`DeleteRow.php`, `Model/FieldSettings.php`, `Record/Image.php`, `Extensions/AfterChannelFieldDelete.php`,
`AfterChannelEntrySave.php`, `AfterFileDelete.php`, EE 7.5.27, the one existing cps field (`committee_photo`,
field 2006, 13 image rows read-only), and the passing fixture `fixtures/2099_02_01_000026_cpsref_ansel.php`
(`run-fixtures.sh <site> ansel`; cps only). The official EE docs do not cover third-party fieldtypes
(`EE-DOCS-NOTES.md`).

**Version sensitivity.** Everything here is Ansel **3.0.8** (`ANSEL_VERSION`, `exp_fieldtypes.version`) on EE 7.5.27;
Ansel is a commercial BoldMinded add-on whose settings keys and tables have changed between majors (`updates/up_3_00_*`).
Re-run the fixture after any Ansel upgrade.

## Content writes: not supported from a migration

**Do not write image values from a migration.** `ft.ansel.php::post_save()` hands the posted rows to
`SaveRow::save()`, which crops and resizes the source image with the image-manipulation service, writes a
high-quality copy, a thumbnail and the standard image to disk in the save directory (`copy()`, temp files
`unlink()`ed), and creates `exp_files` rows (`addFile()`). Writing a value therefore needs the original image
on disk and creates files, which is outside what a migration may do. The reverse is dangerous too: deleting an
entry (or a row) runs `DeleteRow::delete()`, which **deletes the processed files from disk and their `exp_files`
rows**. Never insert `exp_ansel_images` rows that point at real `file_id`s: removing the entry would delete real
files. Create the field, set its settings, and leave image content to editors in the control panel. The fixture
creates the fields and an entry with no image value, and proves everything else.

## Settings contract

`ft.ansel.php::save_settings()` builds `Model/FieldSettings` from the posted values (the `ansel_` prefix is
stripped, `FieldSettings` controller constructor) and returns `$fieldSettings->toArray()` plus `field_wide => true`
(booleans are converted to `'y'`/`'n'`; `field_id`, `field_name`, `type`, `ratio_width`, `ratio_height` are excluded).
If the field is required it forces `ansel_min_qty` to at least 1. `validate_settings()` (CP only) enforces the rules
below; **the Model path does not run it**, so a migration must satisfy them itself.

| Key | PHP type | Default (CP) | Rule (`validate()`) |
|---|---|---|---|
| `upload_directory` | string `'ee:<upload_prefs.id>'` | none | required, must be an existing directory, **must differ from `save_directory`/`preview_directory`** |
| `save_directory` | string `'ee:<id>'` | none | required, existing, unique |
| `preview_directory` | string `'ee:<id>'` or `0`/absent | none | optional (Live Preview), existing, unique |
| `tile_view` | `'y'`/`'n'` | `'y'` | tile layout in the CP |
| `min_qty`, `max_qty` | int (`0` = none) | none / global default | non-negative, min <= max |
| `prevent_upload_over_max` | `'y'`/`'n'` | `'n'` | |
| `quality` | int 1 to 100 | 90 | required |
| `force_jpg`, `force_webp`, `retina_mode` | `'y'`/`'n'` | `'n'` | `enum[y, n]` |
| `min_width`, `min_height`, `max_width`, `max_height` | int (`0` = none) | none | natural number; min <= max |
| `ratio` | string `'W:H'`, two integers, e.g. `'1:1'`, `'16:9'` (empty = free crop, as in the source's blank handling) | empty | `validateCropRatio` splits on `:` and needs exactly two parts |
| `show_title`, `require_title`, `show_description`, `require_description`, `show_cover`, `require_cover` | `'y'`/`'n'` | global defaults | `enum[y, n]` |
| `title_label`, `description_label`, `cover_label` | string | empty | custom labels |
| `prepend_to_table` | `'y'`/`'n'` | `'n'` | new images go first |
| `field_wide` | bool `true` | none | added by `save_settings()` |

The directories are strings in the form `ee:<id>` (`UploadLocation::getUploadLocationByIdentifier()`), where the id
is `exp_upload_prefs.id`: the existing field has `ee:104` (upload, "NRP/AcORN Committee") and `ee:105` (save, "NRP/AcORN
Committee Ansel"). **Resolve by upload directory NAME** in a real migration (ids differ per site). The existing
cps field stores a subset (no `preview_directory`, `tile_view`, `force_webp`, `prepend_to_table`); the fixture creates
both that shape and the full shape and reads both back. An absent key reads as empty/false; a missing directory
makes `SaveRow` fail at upload time (`getUploadDirectory()` returns null), not at field-create time.

A Grid column: there is **no `grid_save_settings()`**, so the column keeps whatever the settings form posts. The
`FieldSettings` controller strips an `ansel_` prefix when reading, so both prefixed and unprefixed keys display,
but `post_save()` passes the raw settings to `FieldSave`, which reads unprefixed names. The fixture stores unprefixed
keys in `col_settings` and they round-trip; whether a CP-created column stores prefixed keys is **unverified**
(cps has no Ansel Grid column). Prefer creating Grid image columns in the control panel and copying the resulting
`col_settings`.

## Storage

- The field's own column is the default `text` column (`exp_channel_data_field_N.field_id_N`, plus `field_ft_N`);
  there is no `settings_modify_column()` override. Fixture proof: `text`; an entry saved without an Ansel value leaves
  it `NULL`. After a real CP save the column holds `save()`'s output, `json_encode($posted)`, e.g.
  `{"placeholder":"placeholder","ansel_row_id_6392...":{"ansel_image_id":"12","ansel_image_delete":"","source_file_id":"10326",
  "original_location_type":"ee","upload_location_id":"105","upload_location_type":"ee","filename":"...","extension":"jpg",
  "file_location":"","x":"227","y":"67","width":"2219","height":"2219","order":"1"}}` (read from the existing cps field).
  The authoritative data is NOT this JSON but the image table below.
- **`exp_ansel_images`** (Record `ansel:Image`): one row per image: `id`, `site_id`, `source_id` (channel id; 181 on
  cps), `content_id` (entry id), `field_id`, `content_type` (`channel`, `grid`, `blocks`, `lowVar` per the source filters), `row_id` and
  `col_id` (Grid), `file_id` (the processed image's `exp_files` row, in the save directory), `original_file_id` (the
  source image's `exp_files` row, in the upload directory), `upload_location_type`/`upload_location_id` (the save
  directory id), `directory_id`, `filename`, `extension`, `filesize`, `original_filesize`, `width`, `height` (output size),
  `x`/`y` (crop origin in the source), `title`, `description`, `member_id`, `position`, `cover`, `upload_date`,
  `modify_date`, `disabled`, plus `publisher_lang_id`/`publisher_status` (present in the schema; not used by the fixture). Verified on the 13
  cps rows: every `file_id` resolves in `exp_files` (e.g. image row 5: `file_id` 10393 in directory 105 and
  `original_file_id` 10364 in directory 104).
- Other tables: `exp_ansel_settings` (global add-on settings; not queried here, because add-on settings tables are where licence keys live), `exp_ansel_upload_keys`.
- File usage: Ansel does not use the entry-save file-usage mechanism directly; `SaveRow::updateFileUsage()` queues
  usage in the session cache and `Extensions/AfterChannelEntrySave` + `CoreBoot` write it on the next page load.
  On cps the files of the 13 existing images have `total_records = 0`.
- Settings: `field_settings` is `base64_encode(serialize($array))`; Grid `col_settings` is JSON.

## Create / change / remove

`accepts_content_type()` returns `true` for `blocks/1`, `channel`, `grid`, `low_variables`, `fluid_field`, so
Ansel is allowed as a channel field, a Grid column and a Fluid child (the fixture created all three; no image content
was written to any). Hooks `after_channel_field_delete`, `after_file_save`, `after_file_delete`, `after_channel_entry_save`
and `core_boot` are registered by Ansel and run during migrations: **call `CpsRefFixture::ensureSession()`** first
(`AfterChannelEntrySave` reads `ee()->session->cache`, absent under `eecli`).

Top-level field (settings from the fixture; directories resolved by name in a real migration):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_photo';
$field->field_label = 'Photo';
$field->field_type = 'ansel';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'upload_directory' => 'ee:' . $uploadId,   // upload_prefs.id, resolved by name
    'save_directory' => 'ee:' . $saveId,       // must differ from upload_directory
    'min_qty' => 0, 'max_qty' => 1, 'prevent_upload_over_max' => 'n',
    'quality' => 90, 'force_jpg' => 'n', 'retina_mode' => 'n',
    'min_width' => 500, 'min_height' => 500, 'max_width' => 500, 'max_height' => 500, 'ratio' => '1:1',
    'show_title' => 'n', 'require_title' => 'n', 'title_label' => '',
    'show_description' => 'n', 'require_description' => 'n', 'description_label' => '',
    'show_cover' => 'n', 'require_cover' => 'n', 'cover_label' => '',
    'field_wide' => true,
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column: same `col_settings` JSON via `grid_model->save_col_settings()` with `'col_type' => 'ansel'` (see the `wygwam`
reference for the exact call and prerequisites; unprefixed keys, see the caveat above). Fluid child: a `fluid_field`
whose `field_channel_fields` lists the Ansel field id.

Change: merge into `field_settings` and `save()`; settings-only. **Remove:** `$field->delete()` fires
`Extensions/AfterChannelFieldDelete`, which **deletes every `exp_ansel_images` row of that field id** (fixture proof:
a probe row for a deleted probe field was gone) but **does not delete the image files or their `exp_files` rows**:
the processed and original files stay on disk and in the File Manager as orphans. Entry delete is different: it
runs `Ansel_ft::delete()` and removes files from disk and `exp_files`, see above. Drop the orphan data table after
a same-request create/delete with `CpsRefFixture::dropDataTableIfExists($fieldId)`.

## Rollback

Settings changes are reversible from the old `field_settings`. A field with images: deleting the field loses the
`exp_ansel_images` rows (and so the link between entries and images) while leaving the files; there is no undo
other than a database backup (`backup-only rollback`). The fixture's `down()` removes everything `cpsref*`
(`CpsRefFixture::removeAll()`); it had no image rows to lose.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` contains `upload_directory`, `save_directory` (both `ee:<id>`),
  `quality`, `field_wide`; Grid `json_decode(col_settings, true)`.
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'ansel';`
- Directories exist and differ: `SELECT id, name FROM exp_upload_prefs WHERE id IN (<ids from the settings>);`
- Column: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'` (`text`).
- Image rows: `SELECT id, content_id, file_id, original_file_id FROM exp_ansel_images WHERE field_id = <N>;` and orphan check
  `SELECT COUNT(*) FROM exp_ansel_images a LEFT JOIN exp_files f ON f.file_id = a.file_id WHERE f.file_id IS NULL;` (0 on cps).
- After deleting a field: `SELECT COUNT(*) FROM exp_ansel_images WHERE field_id = <N>;` is 0.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check` (smoke validates/displays the field);
  `run-fixtures.sh <site> ansel` prints `PASS ansel`.

## Gotchas

- Never write image content or `exp_ansel_images` rows from a migration; entry deletion deletes real files.
- Upload and save directories must be different directories, and `ee:<id>` is a string.
- Deleting the field leaves the image files and `exp_files` rows behind.
- The Model path skips `validate_settings()`; a missing/invalid directory fails later, when an editor uploads.
- Ansel's hooks need a session: call `CpsRefFixture::ensureSession()` before saving entries or deleting fields under `eecli`.
- Never select from `exp_ansel_settings` (global add-on settings, where a licence key would live).
