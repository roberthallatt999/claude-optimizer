---
fieldtype: number
addon: number
origin: core
verified: 7.5.27
fixture: 2099_02_01_000004_cpsref_number
fixture_site: cps
grid: yes
fluid: yes
---
# number

Evidence: `Addons/number/ft.number.php` (extends `Text_ft` from `Addons/text/ft.text.php`), `addon.setup.php`
(EE 7.5.27), and the passing fixture `fixtures/2099_02_01_000004_cpsref_number.php`
(`run-fixtures.sh <site> number`). No number field exists on cps; nothing here is inferred from live data.

## Settings contract

`ft.number.php::save_settings()` merges over five defaults and keeps ONLY these keys:

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `field_min_value` | numeric string or `''` | `''` | Minimum | `validate()` and `display_field()` read it by direct index: absent = PHP 8 undefined-array-key warning (not a TypeError; not exercised) |
| `field_max_value` | numeric string or `''` | `''` | Maximum | same |
| `field_step` | numeric string or `''` | `''` | Step | same (`display_field()`); `decimal` falls back to step 0.01 when empty |
| `datalist_items` | string, one item per line | `''` | Data list items | same (`display_field()` reads `$this->settings['datalist_items']`) |
| `field_content_type` | `numeric`, `integer`, `decimal` | `numeric` | Allowed content | No crash, but drives the COLUMN TYPE (see Storage) |

Always write all five keys (empty string = not set). Documented settings not found in source: none. Source keys the
docs omit: none. `validate_settings()` (CP only) requires min < max when both are set and `numeric` values;
`integer` content also requires integer min/max/step.

**Grid column:** `grid_save_settings()` is inherited from `Text_ft` (returns the posted array unchanged), so the
column's `col_settings` carries the same five keys (proved). `Text_ft` shows no `field_maxl`/`field_fmt` controls
in `Number_ft::display_settings()`.

## Storage

`settings_modify_column()` and `grid_settings_modify_column()` come from `Text_ft::_get_column_settings()` and
depend on `field_content_type` (the "allowed content" docs setting):

| `field_content_type` | `field_id_N` / `col_id_C` type | Proved |
|---|---|---|
| `numeric` | `float` | yes |
| `integer` | `int(11)` | yes |
| `decimal` | `decimal(10,4)` | yes |
| absent / anything else (including `number`, the class's `default_field_content_type`) | `text`, NULL allowed | source only |

Numeric types are NOT NULL with default 0 per the column definition (source); `save()` returns NULL for `''` on
numeric content types. Values read back as the SQL type renders them: `12.5`, `42`, `3.1416` (decimal keeps four
places, so `3.1` reads `3.1000`). Settings: `field_settings` base64-serialized; Grid JSON in `col_settings`. Fluid
child value: the child's own data table, `entry_id = 0` row, linked from `exp_fluid_field_data`.
`settings_modify_column()` returns NO columns when `field_settings` is empty.

## Create / change / remove

`'compatibility' => 'text'`; `accepts_content_type()` inherited from `Text_ft` returns `true`: top-level, Grid
column and Fluid child all proved. Grid prerequisite: `instantiate('channel_fields')` +
`fetch_installed_fieldtypes()` before `load->model('grid_model')`.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'event_capacity';
$field->field_label = 'Capacity';
$field->field_type = 'number';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'field_min_value' => '0', 'field_max_value' => '100', 'field_step' => '1',
    'datalist_items' => '', 'field_content_type' => 'integer',
];
$field->ChannelFieldGroups = $group;
$field->save();     // creates field_id_N as int(11) for integer, float for numeric, decimal(10,4) for decimal
```

```php
// Grid column (field_id and content_type go INSIDE the array)
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'number', 'col_label' => 'Qty', 'col_name' => 'qty',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_min_value' => '', 'field_max_value' => '', 'field_step' => '',
        'datalist_items' => '', 'field_content_type' => 'numeric',
    ]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $numberField->field_id], 'field_channel_field_groups' => []];
```

Change: changing `field_content_type` later alters the column type (and can lose precision, e.g. decimal to
integer); back up first. Remove: `$field->delete()`; Fluid before children.

## Content writes

```php
$entry->field_id_N = '12.5';                                                          // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '7.25']]];             // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '99']]];         // Fluid
```

`validate()` enforces min/max and, for `integer`, whole numbers; the Model `save()` skips it. Tested path:
`CpsRefFixture::makeEntry()`.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Fields drop with their data tables. Deleting a number field with content
is backup-only rollback.

## Verification

- `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'number';`
- `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'number';`
- `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` (expect `float`, `int(11)` or `decimal(10,4)`)
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`; Grid/Fluid queries as in text.md.
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> number` prints `PASS number`.

## Gotchas

- The docs call it "allowed content (changes the DB column type)"; the stored key is `field_content_type` and the
  default `numeric` is a FLOAT column, which stores `0.1 + 0.2` style binary fractions: use `decimal` for money.
- `Number_ft::$default_field_content_type` is `number`, which `_get_column_settings()` does not recognise, so any
  field whose `field_content_type` is missing or `number` gets a TEXT column. Always set the key.
- Never create a number field with empty `field_settings` (no data column is created).
- Not a text field: a number field's allowed content list has no `all`; use `text` with `numeric` content for loose input.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
