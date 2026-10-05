---
fieldtype: range_slider
addon: slider
origin: core
verified: 7.5.27
fixture: 2099_02_01_000017_cpsref_range_slider
fixture_site: cps
grid: yes
fluid: yes
---
# range_slider

Evidence: `Addons/slider/ft.range_slider.php` (`Range_slider_ft extends Slider_ft`: `save()`, `display_field()`,
`replace_tag()`), `Addons/slider/ft.slider.php`, `Addons/text/ft.text.php` (column types), `legacy/helpers/
custom_field_helper.php` (`encode_multi_field()` / `decode_multi_field()`), `addon.setup.php`, docs `range-slider`, and the
passing fixture `fixtures/2099_02_01_000017_cpsref_range_slider.php`. No range slider exists on cps.

## Settings contract

Same seven keys as `slider.md` (`save_settings()` is inherited; proved on a field and a Grid column):

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `field_min_value` | numeric string or number | `0` | Minimum | `display_field()`/`replace_tag()` read it through `isset()` with fallback 0; `replace_min()` by direct index |
| `field_max_value` | numeric string or number | `100` | Maximum | same, fallback 100; `replace_max()` direct index |
| `field_step` | numeric string or number | `1` | Step | No |
| `field_prefix` | string | `''` | Prefix | `replace_prefix()`, `replace_tag(prefix="yes")` direct index |
| `field_suffix` | string | `''` | Suffix | `replace_suffix()`, `replace_tag(suffix="yes")` direct index |
| `datalist_items` | string | `''` | (not shown) | No |
| `field_content_type` | `all` (default for range) / `numeric` / `integer` / `decimal` | `all` | (docs: not offered for Range Slider) | Drives the column type: only `all` (TEXT) can hold the pair |

Write all seven. The CP does not show the allowed-content radio for a range slider, but `save_settings()` still keeps
the key, so a migration can set it wrongly (see Gotchas). Documented settings missing from source: none; source keys the
docs omit: `datalist_items`, `field_content_type` (stored, hidden).

## Storage

Default content type `all` gives `field_id_N text` NULL; Grid `col_id_C text` NULL (proved). Setting `field_content_type`
to `numeric` creates a `float` column (proved) that cannot hold `12|43`.

Stored string: `from|to`, joined with a bare pipe (no spaces), low value first. `save()` accepts an array, sorts it
(`sort()`), then `encode_multi_field()` joins with `|` and escapes any pipe or backslash inside values. A string is returned
unchanged. Proved: `[43, 12]` stored `12|43`; `'20|60'` stored `20|60`; Grid `[30, 70]` stored `30|70`; Fluid `[5, 15]`
stored `5|15`. The docs' "12 - 43" is only the template output (`{field}` renders `from &mdash; to`; `{field:from}`,
`{field:to}`, or a tag pair with `{from}`/`{to}`), not the stored form. `save('12 - 43')` stores that string verbatim
(proved) and `decode_multi_field()` would then return one element, so `from` becomes the whole string. Direct calls
(proved): `save([7])` -> `'7'`, `save([])` -> `''`, `save(['9', '10'])` sorts numerically.
Min/max are not enforced server-side (inherited `Text_ft::validate()` only checks content type).

## Create / change / remove

`accepts_content_type()` inherited from `Text_ft` returns `true`: top-level, Grid column and Fluid child all proved.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'age_range';
$field->field_label = 'Age range';
$field->field_type = 'range_slider';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'field_min_value' => '0', 'field_max_value' => '18', 'field_step' => '1',
    'field_prefix' => '', 'field_suffix' => ' yrs', 'datalist_items' => '',
    'field_content_type' => 'all',
];
$field->ChannelFieldGroups = $group;
$field->save();     // field_id_N text
```

```php
// Grid column
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'range_slider', 'col_label' => 'Range', 'col_name' => 'range',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_min_value' => '0', 'field_max_value' => '100', 'field_step' => '1',
        'field_prefix' => '', 'field_suffix' => '', 'datalist_items' => '', 'field_content_type' => 'all',
    ]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $rangeField->field_id], 'field_channel_field_groups' => []];
```

Change: do not change `field_content_type` to a numeric type on an existing range slider (it would convert the column and
destroy the pairs). Remove: `$field->delete()`; Fluid before children.

## Content writes

```php
$entry->field_id_N = [12, 43];     // array: sorted, stored 12|43
$entry->field_id_N = '12|43';      // string: stored as is (preferred in migrations; no PHP array coercion questions)
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => [30, 70]]]];       // Grid (array proved)
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => [5, 15]]]];  // Fluid (array proved)
```

Tested path: `CpsRefFixture::makeEntry()`. Always write low then high, joined with `|`, or pass a two-element array.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting a range slider with content is backup-only rollback.

## Verification

- `SELECT field_id, field_settings FROM exp_channel_fields WHERE field_type = 'range_slider';` (decode; seven keys, `field_content_type` = `all`)
- `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` expect `text`.
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;` expect `12|43`.
- `SELECT SUBSTRING_INDEX(field_id_N, '|', 1) AS from_value, SUBSTRING_INDEX(field_id_N, '|', -1) AS to_value ...` to range-query.
- `cps:migrate-verify <migration>`; `run-fixtures.sh <site> range_slider` prints `PASS range_slider`.

## Gotchas

- Stored `12|43`, displayed `12 - 43` (docs) / `12 &mdash; 43` (source `replace_tag()`): do not write the display form.
- `field_content_type` other than `all` makes a numeric column; the hidden setting still persists, so set it to `all`.
- A string is not validated or sorted: `'43|12'` is stored as written and `{from}` would be the larger value.
- Switching a slider to a range slider (or back) keeps the stored text; the single slider reads the part before `|`.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
