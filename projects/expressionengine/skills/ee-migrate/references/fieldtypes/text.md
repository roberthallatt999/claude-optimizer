---
fieldtype: text
addon: text
origin: core
verified: 7.5.27
fixture: 2099_02_01_000002_cpsref_text
fixture_site: cps
grid: yes
fluid: yes
---
# text

Evidence: `system/ee/ExpressionEngine/Addons/text/ft.text.php` and `addon.setup.php` (EE 7.5.27),
`legacy/fieldtypes/EE_Fieldtype.php`, `Model/Channel/ChannelField.php`, the Fluid source, existing cps fields,
and the passing fixture `fixtures/2099_02_01_000002_cpsref_text.php` (`run-fixtures.sh <site> text`). The docs
(`EE-DOCS-NOTES.md`) list control-panel labels only; the mapping to stored keys is in the table.

## Settings contract

`ft.text.php::save_settings()` merges the posted settings over four defaults and keeps ONLY these keys
(`array_intersect_key`) in `exp_channel_fields.field_settings`:

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `field_maxl` | int or numeric string | `256` | Maximum characters | No: `display_field()` treats a falsy value as "no maxlength" |
| `field_content_type` | string: `all`, `numeric`, `integer`, `decimal` (`''` also means free text) | `''` | Allowed content | No: `validate()` and `save()` fall back to free text; `settings_modify_column()` falls back to `all` (text column) |
| `field_show_smileys` | `'y'`/`'n'` | `'n'` | none (vestigial, no control in 7.5.27) | No |
| `field_show_file_selector` | `'y'`/`'n'` | `'n'` | Field tools: show file selector | No (`get_setting()` returns false) |

Keys the docs list that are NOT in `field_settings` because they are real columns of `exp_channel_fields`
(set them as Model properties on the `ChannelField`, not inside `field_settings`):

| Native column | Default | Docs label | Absence breaks? |
|---|---|---|---|
| `field_maxl` | NULL | Maximum characters (mirrors the key above) | No (NULL is falsy) |
| `field_fmt` | `xhtml` | Text formatting (Auto line break / Markdown / XML Encode / XHTML / None) | Wrong value changes rendering only |
| `field_show_fmt` | `y` | Allow override | No |
| `field_text_direction` | `ltr` | Text direction | `display_field()` reads `$this->settings['field_text_direction']` directly; the column is NOT NULL so it is always present for channel fields |
| `field_content_type` | `any` | (legacy column; the fieldtype reads the `field_settings` key instead) | No |

Documented setting not found in source: none. Source keys the docs omit: `field_show_smileys`.

**Grid column** (`grid_save_settings()` returns the posted array unchanged; there is no channel_fields row, so the
column carries the native keys itself). Real cps columns store:
`{"field_fmt":"none","field_content_type":"all","field_text_direction":"ltr","field_maxl":"256","field_required":"n"}`.
Include all four of `field_fmt`, `field_content_type`, `field_text_direction`, `field_maxl`: in a Grid cell
`display_field()` reads `field_text_direction` and `field_maxl` by direct index (an absent key is a PHP 8
undefined-array-key warning, not a TypeError; not exercised here). `field_show_fmt` and the file selector are not
offered for Grid columns (`content_type() != 'grid'` guards).

## Storage

- Channel field: `field_id_N` on `exp_channel_data_field_N`, plus `field_ft_N` (`tinytext`). The `field_id_N`
  type depends on `field_content_type` (`settings_modify_column()` -> `_get_column_settings()`):

  | `field_content_type` | `field_id_N` type (proved) |
  |---|---|
  | `all`, `''`, anything else | `text`, NULL allowed |
  | `integer` | `int(11)` (type proved), default 0 (source) |
  | `numeric` | `FLOAT`, default 0 (source) |
  | `decimal` | `DECIMAL(10,4)`, default 0 (source) |

  `settings_modify_column()` returns an EMPTY array when `field_settings` is empty, so a text field must be created
  with non-empty `field_settings` or it may get no data column (source reading; the fixture always passes the four
  keys).
- Grid: `col_id_C` on `exp_channel_grid_field_G`, same type mapping via `grid_settings_modify_column()`
  (`text` proved). Settings are JSON in `exp_grid_columns.col_settings`.
- Fluid: the child value lives in the child field's own data table (`entry_id = 0` row) linked from
  `exp_fluid_field_data.field_data_id`.
- The stored value is the raw string (`save()` returns the input unchanged for free text; for numeric content types
  `''` is saved as NULL). No entity encoding (unlike `url`): `Hello <b>cps</b> & friends` reads back verbatim.

## Create / change / remove

`addon.setup.php`: `'compatibility' => 'text'`; `accepts_content_type()` returns `true` for every content type, so
text works as a channel field, a Grid column and a Fluid child. Grid prerequisite: `instantiate('channel_fields')`
and `fetch_installed_fieldtypes()` BEFORE `load->model('grid_model')`.

```php
// Top-level field. $group is a saved ChannelFieldGroup.
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'event_venue';
$field->field_label = 'Venue';
$field->field_type = 'text';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_maxl = 100;                 // native columns
$field->field_text_direction = 'ltr';
$field->field_fmt = 'none';
$field->field_settings = [
    'field_maxl' => 100, 'field_content_type' => 'all',
    'field_show_smileys' => 'n', 'field_show_file_selector' => 'n',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Integer-only variant: same snippet with `'field_content_type' => 'integer'` (column becomes `int(11)`).

```php
// Grid column ($gridField is a saved grid ChannelField; field_id and content_type go INSIDE the array).
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'text', 'col_label' => 'Label', 'col_name' => 'label_text',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr',
        'field_maxl' => 100, 'field_required' => 'n',
    ]),
], false, 'channel');

// Fluid child: create the text field above, then list it in the fluid field's settings.
$fluid->field_settings = ['field_channel_fields' => [(int) $textField->field_id], 'field_channel_field_groups' => []];
```

Change: merge over the current `field_settings` (or `col_settings` JSON) and save. Changing `field_content_type` on an
existing field alters the column type through `settings_modify_column()` and can truncate or fail on existing data;
back up first. Remove: `$field->delete()`; Grid column rows via `grid_columns`; delete a Fluid field before its children.

## Content writes

```php
$entry->field_id_N = 'Venue name';                                                    // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => 'Venue name']]];       // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => 'Venue name']]]; // Fluid
```

`CpsRefFixture::makeEntry()` is the tested path (real member as author). `save()` does not validate; call
`$entry->validate()` for untrusted data. With `field_content_type` `integer`, `validate()` rejects non-integers and
values outside the 32-bit range (`number_exceeds_limit`); `decimal` rejects values >= 999999.9999.

## Rollback

`down()` = `CpsRefFixture::removeAll()`: entry, Fluid field, Grid field and its columns, text fields (their data
tables drop with the Model `delete()`), field group, channel. Deleting a text field that holds real content is
backup-only rollback. Restoring settings is a settings-only change from the baseline dump (but see the column-type
note above).

## Verification

- Settings: `SELECT field_id, field_name, field_maxl, field_text_direction, field_fmt, field_settings FROM exp_channel_fields WHERE field_type = 'text';`
  (`field_settings` is `base64(serialize())`; the fixture decodes it and asserts the four keys.)
- Grid: `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'text';`
- Column types: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` (expect `text`, or `int(11)` for integer).
- Values: `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`
  `SELECT col_id_C FROM exp_channel_grid_field_G WHERE entry_id = <id>;`
  `SELECT * FROM exp_fluid_field_data WHERE fluid_field_id = <F> AND entry_id = <id>;`
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> text` prints `PASS text`.

## Gotchas

- `field_maxl`, `field_fmt`, `field_show_fmt`, `field_text_direction` are `exp_channel_fields` COLUMNS for channel
  fields, not `field_settings` keys (only `field_maxl` is in both). Setting only `field_settings` leaves the column
  defaults (`field_fmt` defaults to `xhtml`, which formats output with auto line breaks): always set `field_fmt` explicitly.
- For Grid columns the same four keys must be in `col_settings`; the Grid has no native columns to fall back on.
- `save_settings()` drops unknown keys; real cps text fields carry exactly the four contract keys.
- `field_content_type` changes the SQL column type (`integer` -> `int(11)`); the value `all` means free text.
- `settings_modify_column()` returns no columns when `field_settings` is empty: never create a text field with `[]`.
- Writing through the Model skips `validate()`; the `maxlength` limit is a browser attribute only and is not enforced
  on save.
- Fluid writes log a harmless `E_WARNING: Undefined variable $field_group_id` (see url.md); `eecli migrate` exits 0
  when `up()` throws (see url.md); Active-record chain and member-id-1 notes in url.md apply to every fixture.
