---
fieldtype: textarea
addon: textarea
origin: core
verified: 7.5.27
fixture: 2099_02_01_000003_cpsref_textarea
fixture_site: cps
grid: yes
fluid: yes
---
# textarea

Evidence: `Addons/textarea/ft.textarea.php`, `addon.setup.php` (EE 7.5.27), `EE_Fieldtype.php`,
`Model/Channel/ChannelField.php`, existing cps fields, and the passing fixture
`fixtures/2099_02_01_000003_cpsref_textarea.php` (`run-fixtures.sh <site> textarea`).

## Settings contract

`ft.textarea.php::save_settings()` merges the posted settings over four defaults and keeps ONLY these keys in
`field_settings`:

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `field_show_file_selector` | `'y'`/`'n'` | `'n'` | Field tools: show file selector | No (guarded with `isset`) |
| `db_column_type` | `'text'` or `'mediumtext'` | `'text'` | none in the docs notes (CP label "Column type": TEXT / MEDIUMTEXT) | No: `get_column_type()` defaults to `text` |
| `field_show_smileys` | `'y'`/`'n'` | `'n'` | none (vestigial) | No |
| `field_show_formatting_btns` | `'y'`/`'n'` | `'n'` | Field tools: show formatting buttons | No (guarded with `isset`) |

Real `exp_channel_fields` COLUMNS (set as Model properties, not in `field_settings`):

| Native column | Default | Docs label | Absence breaks? |
|---|---|---|---|
| `field_ta_rows` | 8 | Row height | Front-end `display_field()` reads `$this->settings['field_ta_rows']` by index; column always present |
| `field_fmt` | `xhtml` | Text formatting | Rendering only |
| `field_show_fmt` | `y` | Allow override | No. The CP form reads `$data['field_show_fmt']` by index |
| `field_text_direction` | `ltr` | Text direction | Read by index in front-end `display_field()` |

Documented setting not found in source: none. Source keys the docs omit: `db_column_type`, `field_show_smileys`.
Real cps textarea fields also carry legacy keys (`field_show_glossary`, `field_show_spellcheck`,
`field_show_writemode`) that `save_settings()` no longer keeps; they are harmless and vanish on the next CP save.

**Grid column** (`grid_save_settings()` = `array_merge(save_settings($data), $data)`): the four contract keys plus
whatever the Grid posted. Store `field_fmt`, `field_text_direction`, `field_ta_rows` (and `field_required`) in
`col_settings` as well; real cps columns store
`{"field_fmt":"none","field_text_direction":"ltr","field_ta_rows":"6","field_required":"y"}`. A Grid column has no
channel_fields row, so the native values must be in the JSON. `grid_settings_modify_column()` reads
`db_column_type` from the column settings.

## Storage

- Channel field: `field_id_N` on `exp_channel_data_field_N`, type from `db_column_type`: `text` or `mediumtext`
  (both proved), NULL allowed. `settings_modify_column()` returns only `field_id_N` (no `field_ft_N` entry from the
  fieldtype; the format is the `field_fmt` column).
- Grid: `col_id_C` on `exp_channel_grid_field_G`; `mediumtext` proved from a column with
  `db_column_type = mediumtext`. JSON settings in `exp_grid_columns.col_settings`.
- Fluid: child value in the child field's data table (`entry_id = 0` row) linked from `exp_fluid_field_data`.
- The stored value is the raw string; `getTableColumnConfig()` returns `['encode' => false]`. Newlines and HTML are
  kept verbatim (`"Line one\nLine <b>two</b> & three"` read back unchanged). `{file:ID:url}` tokens are
  tracked by EE (docs), not rewritten by a migration.

## Create / change / remove

`'compatibility' => 'text'`; `accepts_content_type()` is `true` for all content types, so top-level, Grid column and
Fluid child all work. Grid prerequisite: `instantiate('channel_fields')` + `fetch_installed_fieldtypes()` before
`load->model('grid_model')`.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'event_summary';
$field->field_label = 'Summary';
$field->field_type = 'textarea';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_ta_rows = 6;                // native columns
$field->field_text_direction = 'ltr';
$field->field_fmt = 'none';
$field->field_settings = [
    'field_show_file_selector' => 'n', 'db_column_type' => 'text',
    'field_show_smileys' => 'n', 'field_show_formatting_btns' => 'n',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Use `'db_column_type' => 'mediumtext'` for long content (16 MB instead of 64 KB).

```php
// Grid column (field_id and content_type go INSIDE the array)
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'textarea', 'col_label' => 'Notes', 'col_name' => 'notes_text',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_show_file_selector' => 'n', 'db_column_type' => 'text', 'field_show_smileys' => 'n',
        'field_show_formatting_btns' => 'n', 'field_fmt' => 'none', 'field_text_direction' => 'ltr',
        'field_ta_rows' => 6, 'field_required' => 'n',
    ]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $textareaField->field_id], 'field_channel_field_groups' => []];
```

Change: merge over current settings. Switching `db_column_type` from `mediumtext` back to `text` can truncate data.
Remove: `$field->delete()`; delete Fluid before children; Grid columns via `grid_columns`.

## Content writes

```php
$entry->field_id_N = "Line one\nLine two";                                            // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => 'text']]];             // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => 'text']]];       // Fluid
```

`validate()` always returns true; there is nothing to reject. Tested path: `CpsRefFixture::makeEntry()`.

## Rollback

`down()` = `CpsRefFixture::removeAll()` (entry, Fluid, Grid + columns, textarea fields with their data tables, group,
channel). Deleting a field with real content is backup-only rollback.

## Verification

- `SELECT field_id, field_name, field_ta_rows, field_fmt, field_settings FROM exp_channel_fields WHERE field_type = 'textarea';`
- `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'textarea';`
- `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` (expect `text` or `mediumtext`)
- Values: `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;` and the Grid/Fluid queries in text.md.
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> textarea` prints `PASS textarea`.

## Gotchas

- `field_ta_rows`, `field_fmt`, `field_show_fmt`, `field_text_direction` are `exp_channel_fields` columns, not
  `field_settings` keys; the column default `field_fmt = xhtml` auto-formats output, so set `field_fmt` explicitly.
- `db_column_type` decides the SQL type; the docs notes do not list it. Choose `mediumtext` at creation for
  anything that may pass 64 KB.
- Grid columns must carry the native keys (`field_fmt`, `field_text_direction`, `field_ta_rows`) in `col_settings`;
  `display_field()` reads `field_ta_rows` and `field_text_direction` by index outside the control panel.
- `save_settings()` drops unknown keys, including the legacy `field_show_glossary` etc. still present on old cps fields.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1) are in url.md Gotchas.
