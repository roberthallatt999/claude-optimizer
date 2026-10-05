---
fieldtype: slider
addon: slider
origin: core
verified: 7.5.27
fixture: 2099_02_01_000016_cpsref_slider
fixture_site: cps
grid: yes
fluid: yes
---
# slider

The "Value Slider" (docs page `value-slider`). Evidence: `Addons/slider/ft.slider.php` (`Slider_ft extends Text_ft`),
`Addons/text/ft.text.php` (`validate()`, `save()`, `_get_column_settings()`, `settings_modify_column()`,
`grid_settings_modify_column()`, `grid_save_settings()`), `addon.setup.php` (addon name "Value & Range Sliders", both
types, `'compatibility' => 'text'`), docs (EE-DOCS-NOTES.md), and the passing fixture
`fixtures/2099_02_01_000016_cpsref_slider.php`. No slider field exists on cps.

## Settings contract

`save_settings()` merges over seven defaults and keeps ONLY these keys (proved: all seven stored for a field and a Grid
column):

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `field_min_value` | numeric string or number | `0` | Minimum | `display_field()` reads it by direct index when the stored value is not numeric (undefined-key warning), `replace_min()` by direct index |
| `field_max_value` | numeric string or number | `100` | Maximum | `replace_max()` by direct index (display falls back to 100 through `isset()`) |
| `field_step` | numeric string or number | `1` | Step | No (`isset()` guarded, falls back to 1) |
| `field_prefix` | string | `''` | Prefix | `replace_prefix()` and `replace_tag(prefix="yes")` by direct index |
| `field_suffix` | string | `''` | Suffix | `replace_suffix()` and `replace_tag(suffix="yes")` by direct index |
| `datalist_items` | string | `''` | (not shown in the slider settings form) | No; unused by the slider display; kept for Text_ft compatibility |
| `field_content_type` | `numeric` / `integer` / `decimal` / `all` | `numeric` | Allowed content (changes DB column type) | Drives the column type (see Storage); the setting is `isset()`-guarded in `replace_tag()` |

Always write all seven keys. Documented settings not found in source: none. Source keys the docs omit: `datalist_items`.
The CP radio for allowed content is shown only for the Value Slider (`settings_form_field_name == 'slider'`), and not for
category/member contexts, which matches the docs ("only for Value Slider"). `validate_settings()` (CP only): min and max
numeric, min < max when both set, and integers for `integer` content.

Grid column: `grid_save_settings()` is inherited from `Text_ft` and returns the posted array unchanged; `col_settings`
holds the same seven keys (proved).

## Storage

`settings_modify_column()` and `grid_settings_modify_column()` are inherited from `Text_ft` and follow
`field_content_type`:

| `field_content_type` | `field_id_N` / `col_id_C` | Proved |
|---|---|---|
| `numeric` (default) | `float` | yes |
| `integer` | `int(11)` | yes (field and Grid column) |
| `decimal` | `decimal(10,4)` | yes |
| `all` (or missing/unknown) | `text` NULL | yes (`all`) |

Values read back as the SQL type renders them: `35.5`, `40`, `12.3456`, `250` (text). A numeric-content slider stores
`NULL` for `''` (`save('')` returns `null`; proved) while `all` keeps `''`. Min and max are NOT enforced on the server:
`validate('500')` and `validate('-40')` return `true` on a 0..100 slider and the Model path stored `250` in a 0..100
field (proved); only `display_field()` clamps the displayed handle. Fluid child: the child's own data table, FLOAT column
(proved, value `80`). `settings_modify_column()` returns no columns when `field_settings` is empty: never create a slider
without settings.

## Create / change / remove

`accepts_content_type()` is inherited from `Text_ft` (returns `true`): top-level, Grid column and Fluid child all proved.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'pain_score';
$field->field_label = 'Pain score';
$field->field_type = 'slider';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'field_min_value' => '0', 'field_max_value' => '10', 'field_step' => '1',
    'field_prefix' => '', 'field_suffix' => '', 'datalist_items' => '',
    'field_content_type' => 'integer',
];
$field->ChannelFieldGroups = $group;
$field->save();     // field_id_N int(11)
```

```php
// Grid column
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'slider', 'col_label' => 'Score', 'col_name' => 'score',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_min_value' => '0', 'field_max_value' => '10', 'field_step' => '1',
        'field_prefix' => '', 'field_suffix' => '', 'datalist_items' => '', 'field_content_type' => 'integer',
    ]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $sliderField->field_id], 'field_channel_field_groups' => []];
```

Change: changing `field_content_type` later alters the column type (decimal to integer loses precision); back up first.
Remove: `$field->delete()`; Fluid before children.

## Content writes

```php
$entry->field_id_N = '35.5';                                                       // one number
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '65']]];            // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '80']]];      // Fluid
```

Write a single number. If the value contains `|` (a former range slider) `display_field()`/`replace_tag()` use the first part.
Range limits are your job: validate min/max in the migration.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting a slider field with content is backup-only rollback.

## Verification

- `SELECT field_id, field_settings FROM exp_channel_fields WHERE field_type = 'slider';` (decode; seven keys)
- `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` (`float` / `int(11)` / `decimal(10,4)` / `text`)
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`; Grid `col_settings` JSON has the seven keys.
- `cps:migrate-verify <migration>`; `run-fixtures.sh <site> slider` prints `PASS slider`.

## Gotchas

- Slider is NOT a range slider: one number. The two types share `Slider_ft`; `range_slider.md` covers the pair.
- No server-side range check; a stored value can exceed max (`250` in a 0..100 slider).
- `field_content_type` has four values here (`all` is allowed, unlike `number`); the default `numeric` is a FLOAT, so use
  `integer` or `decimal` for exact values.
- Prefix/suffix are display-only (`{field prefix="yes" suffix="yes"}` in templates); they are not stored in the value.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
