---
fieldtype: colorpicker
addon: colorpicker
origin: core
verified: 7.5.27
fixture: 2099_02_01_000006_cpsref_colorpicker
fixture_site: cps
grid: yes
fluid: yes
---
# colorpicker

Evidence: `Addons/colorpicker/ft.colorpicker.php`, `addon.setup.php` (EE 7.5.27) and the passing fixture
`fixtures/2099_02_01_000006_cpsref_colorpicker.php` (`run-fixtures.sh <site> colorpicker`). No colorpicker field
exists on cps.

## Settings contract

`ft.colorpicker.php::save_settings()` merges over `$default_settings` and keeps ONLY these five keys:

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `allowed_colors` | `'any'` or `'swatches'` | `'any'` | Allowed colors | No: `get_setting()` returns false, which is not `'swatches'` |
| `colorpicker_default_color` | string `#RRGGBB` or `''` | `''` | Default color | No (compared in `validate()` swatches mode only) |
| `value_swatches` | array of strings `'#RRGGBB'` or `'#RRGGBB|Name'` | `null` in defaults, saved as `[]` | Swatches (populate with values) | YES: `getSwatches()` and `replace_name()` do `foreach` over `get_setting('value_swatches')`, which is `false` when the key is absent (a PHP warning at publish-form render and in `validate()` swatch mode) |
| `manual_swatches` | string, one colour per line | `''` | Swatches (populate manually) | No |
| `populate_swatches` | `'v'` (values) or `'m'` (manual) | `'v'` | Swatches: populate method | No (`'v'` path is the else branch) |

The control panel posts `value_swatches` as `['rows' => [...]]`; `save_settings()` flattens it. When writing settings
directly, store the already-flattened list (`['#FF0000|Red', '#00FF00|Green']`). Always write all five keys.
Documented settings not found in source: none. Source keys the docs omit: `populate_swatches`.

**Grid column:** the class has `grid_display_settings()` but no `grid_save_settings()`, so the posted/array
settings are stored as given. The fixture stores the same five keys in `col_settings` (proved).

## Storage

- `field_id_N` (`text`, NULL allowed) and `field_ft_N` (`tinytext`) on `exp_channel_data_field_N`; no
  `settings_modify_column()` override (proved: `text`).
- Grid: `col_id_C` `text` (proved). Fluid: child's own data table, `entry_id = 0` row, linked from
  `exp_fluid_field_data`.
- Value stored verbatim, case preserved (`#FF0000`). `validate()` accepts a 6-digit hex (`/#([a-f0-9]{6})\b/i`,
  unanchored) and in `swatches` mode a value that is a swatch (case-insensitive) or the default colour.

## Create / change / remove

`'compatibility' => 'text'`; `accepts_content_type()` is `true` for all content types: top-level, Grid column and
Fluid child proved. Grid prerequisite: `instantiate('channel_fields')` + `fetch_installed_fieldtypes()` before
`load->model('grid_model')`.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'brand_colour';
$field->field_label = 'Brand colour';
$field->field_type = 'colorpicker';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'allowed_colors' => 'swatches',
    'colorpicker_default_color' => '',
    'value_swatches' => ['#FF0000|Red', '#00FF00|Green'],
    'manual_swatches' => '',
    'populate_swatches' => 'v',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

For any colour use `'allowed_colors' => 'any'` and `'value_swatches' => []`.

```php
// Grid column (field_id and content_type go INSIDE the array)
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'colorpicker', 'col_label' => 'Colour', 'col_name' => 'colour',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'allowed_colors' => 'any', 'colorpicker_default_color' => '', 'value_swatches' => [],
        'manual_swatches' => '', 'populate_swatches' => 'v',
    ]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $colourField->field_id], 'field_channel_field_groups' => []];
```

Change: merge over current settings; changing swatches does not touch stored values, so existing entries can hold
colours that are no longer allowed. Remove: `$field->delete()`; Fluid before children.

## Content writes

```php
$entry->field_id_N = '#FF0000';                                                       // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '#00FF00']]];          // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '#FF0000']]];    // Fluid
```

`save()` does not validate; `$entry->validate()` enforces hex format and, in swatches mode, the swatch list.
Tested path: `CpsRefFixture::makeEntry()`.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting a colorpicker field with content is backup-only rollback.

## Verification

- `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'colorpicker';`
  (fixture decodes and asserts the five keys and a 2-item `value_swatches`)
- `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'colorpicker';`
- `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` (expect `text`)
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`; Grid/Fluid queries as in text.md.
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> colorpicker` prints `PASS colorpicker`.

## Gotchas

- `value_swatches` is a FLAT list of `'#hex'` / `'#hex|Name'` strings, not the `['rows' => ...]` shape the CP posts.
  Omitting it makes `getSwatches()` iterate `false`.
- Swatches mode with the other populate method: `populate_swatches = 'm'` reads `manual_swatches` (newline list)
  and ignores `value_swatches`.
- `validate()` only checks for a 6-digit hex somewhere in the string (the regex is unanchored): `xx#abcdef` passes.
- The `:name` modifier maps a stored hex to the swatch name; `:contrast_color` returns black or white.
- The fieldtype sets `disable_frontedit`; it is not editable with front-end editing.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
