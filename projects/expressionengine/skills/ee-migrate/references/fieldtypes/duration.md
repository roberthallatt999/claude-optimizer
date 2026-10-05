---
fieldtype: duration
addon: duration
origin: core
verified: 7.5.27
fixture: 2099_02_01_000015_cpsref_duration
fixture_site: cps
grid: yes
fluid: yes
---
# duration

Evidence: `Addons/duration/ft.duration.php` (`Duration_Ft`: `validate()`, `save()`, `save_settings()`,
`display_settings()`, `replace_tag()`), `Addons/duration/Traits/DurationTrait.php`, `addon.setup.php`, the base class
`legacy/fieldtypes/EE_Fieldtype.php` (default columns), docs `fieldtypes/duration.html` (EE-DOCS-NOTES.md), and the passing
fixture `fixtures/2099_02_01_000015_cpsref_duration.php`. No duration field exists on cps.

## Settings contract

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `units` | string `hours` / `minutes` / `seconds` | `minutes` | Units (required) | YES: `validate()`, `display_field()` and `replace_tag()` read `$this->settings['units']` by direct index (undefined-key warning, and `lang('duration_ft_')` garbage); never create a duration field without it |

`save_settings()` keeps exactly one key (`array_intersect_key` against `['units' => 'minutes']`; proved: stored
settings are exactly `['units' => ...]`). Documented settings not in source: none. Source keys the docs omit: none.
Grid column: `grid_save_settings()` is not overridden; `col_settings` carries the same single `units` key (proved).

## Storage

No `settings_modify_column()` override: the field gets EE's defaults, `field_id_N` TEXT NULL plus `field_ft_N` tinytext
(proved), and no `field_dt_N`. Grid column: default `grid_settings_modify_column()`, `col_id_C` TEXT NULL (proved).
Fluid child: own data table, same TEXT column.

Stored value: EXACTLY the string written. Despite the docs ("whole number in the chosen unit"), `save()` only turns a blank
value into `NULL` (`trim($data) == ''`); it does NOT convert. Proved: `'90'` in a minutes field stays `'90'`, `'1:30'` in
an hours field stays `'1:30'`, `'1:30:15'` in a seconds field stays `'1:30:15'`, and `'  '` stores `NULL`. Colon
notation is converted only for display (`replace_tag()` -> `convertDurationToSeconds()` -> `Number->duration()`):
`hh:mm:ss` = h*3600+m*60+s; `mm:ss` = m*60+s, but when the field's units are `minutes` the pair is read as `hh:mm` (x60
again); a bare number is multiplied by the unit (hours x3600, minutes x60). `validate()` (CP only) accepts `''` and
`/^[0-9:]+$/` only: no decimals, no negatives, no letters (proved: `1.5`, `-5`, `abc` return an error string).
To get a clean integer-in-units column of data, write the integer yourself; do not rely on colon input being normalised.

## Create / change / remove

`accepts_content_type()` returns `true`: top-level, Grid column and Fluid child proved.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'session_length';
$field->field_label = 'Session length';
$field->field_type = 'duration';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = ['units' => 'minutes'];
$field->ChannelFieldGroups = $group;
$field->save();
```

```php
// Grid column
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'duration', 'col_label' => 'Length', 'col_name' => 'length',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode(['units' => 'minutes']),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $durationField->field_id], 'field_channel_field_groups' => []];
```

Change: changing `units` later does NOT convert stored values; `90` meant 90 minutes and now means 90 hours. Migrate the
data in the same migration. Remove: `$field->delete()`; Fluid before children.

## Content writes

```php
$entry->field_id_N = '90';                                                         // minutes field: 90 minutes
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '45']]];            // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '1:30']]];    // Fluid
```

Write the integer in the field's units. Colon strings are stored verbatim (proved). Tested path: `CpsRefFixture::makeEntry()`.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting a duration field with content is backup-only rollback.

## Verification

- `SELECT field_id, field_settings FROM exp_channel_fields WHERE field_type = 'duration';` (decode; expect only `units`)
- `SHOW COLUMNS FROM exp_channel_data_field_N;` expect `field_id_N text`, `field_ft_N`.
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`; Grid `col_settings` JSON has `units`.
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE field_id_N LIKE '%:%';` finds unnormalised colon values.
- `cps:migrate-verify <migration>`; `run-fixtures.sh <site> duration` prints `PASS duration`.

## Gotchas

- Docs say "whole number in the chosen unit; accepts colon notation": the stored value is whatever was submitted, so a field can
  hold a mix of `90` and `1:30`; queries must not assume numeric.
- TEXT column: no numeric comparison in SQL without a CAST.
- `units` is required by source, not just by the docs; always write it.
- `replace_tag()` needs `ee('Format')`, which dies under `eecli.php` (see memory note); template rendering was not exercised.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
