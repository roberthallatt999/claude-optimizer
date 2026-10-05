---
fieldtype: date
addon: date
origin: core
verified: 7.5.27
fixture: 2099_02_01_000014_cpsref_date
fixture_site: cps
grid: yes
fluid: yes
---
# date

Evidence: `Addons/date/ft.date.php` (`Date_ft`, `save_settings()`, `grid_save_settings()`, `settings_modify_column()`,
`grid_settings_modify_column()`, `save()`, `grid_save()`, `validate()`), `Addons/date/addon.setup.php`, `Model/Content/
ContentModel.php` (`field_dt_` mapping), `Addons/fluid_field/ft.fluid_field.php` (copies `field_dt_`), docs
`fieldtypes/date.html` (EE-DOCS-NOTES.md), and the passing fixture `fixtures/2099_02_01_000014_cpsref_date.php`
(`run-fixtures.sh <site> date`).

## Settings contract

Top-level field: `save_settings()` merges over two defaults and keeps ONLY these keys:

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `localization` | string `localized` / `fixed` / `ask` | `ask` | Date localization (always localized / always fixed / ask each time) | No: `display_field()` reads it through `isset()` and falls back to `ask` |
| `show_time` | bool (`true`/`false`; `get_bool_from_string()` also takes `y`/`n`) | `true` | Include time | No: read through `isset()`; missing = time shown |

Grid column: DIFFERENT keys. `grid_display_settings()` offers `localize` (yes/no, default true) and `show_time`; the
three-way `localization` choice does not exist for a Grid column (matches the docs: localization options are field-only,
the column gets only a localized yes/no). `grid_save_settings()` returns
`['localize' => get_bool_from_string($data['localize']), 'show_time' => get_bool_from_string($data['show_time'])]`
by direct index, so BOTH keys must be posted or you get an undefined-array-key warning; proved: `'y'`/`'n'` become
`true`/`false`. `grid_save()` and `grid_replace_tag()` also read `$this->settings['localize']` by direct index: a
column whose `col_settings` lacks `localize` breaks writes. Write `{"localize":true,"show_time":true}` (JSON booleans).

Documented settings missing from source: none. Source keys the docs omit: Grid `localize`. The task shorthand
"`localize` and `show_time`" therefore names the GRID keys; the field-level key is `localization`.

Live cps date fields (e.g. `cf_aboutpages_updated_override`) carry NEITHER key (legacy settings with only
`field_show_*` flags): they still work because the top-level reads are `isset()`-guarded. Do not copy those.

## Storage

`settings_modify_column()` (top-level) creates, in `exp_channel_data_field_N`:

| Column | Type | Holds | Proved |
|---|---|---|---|
| `field_id_N` | `bigint(10)` NULL, default 0 | Unix timestamp (UTC seconds) | yes |
| `field_dt_N` | `varchar(50)` NULL | localization / timezone, see below | yes |
| `field_ft_N` | `tinytext` NULL | EE's standard format column, unused by date | yes |

(Legacy fields with `legacy_field_data = y` keep the same three columns in `exp_channel_data`.)

`field_dt_N`: written through the Model property `field_dt_N` (ContentModel maps it to the field's timezone); any string up
to 50 characters is stored raw: proved `Pacific/Auckland`. Never set = `NULL` (some rows hold `''`). `replace_tag()`
uses it as `$localize`: empty means `true` (convert to the viewer's timezone), a non-empty value is passed to
`process_date()` as the timezone. The publish form posts `y`/`n` through this column per `display_field()`
(source, not exercised). Fluid children get the same columns in their own data table (fixture: row exists, `field_dt_N`
`NULL`, `field_ft_N` `xhtml`).

Grid column (`grid_settings_modify_column()`): ONE column, `col_id_C varchar(60)` NULL default NULL. There is NO
companion `col_dt_C` column (proved from `SHOW COLUMNS` on the Grid table). Localized column (`localize` true) stores the bare timestamp,
`'1700000000'`; a non-localized column stores `'<timestamp>|<timezone>'`, e.g. `'1709652600|America/Toronto'`, the timezone
being the session's `timezone` userdata or `default_site_timezone` at write time (proved).

What empty is stored as (Model path, proved): top-level `''`, `0` and unparseable text such as `not a date` all store `0`
(the column default). Grid `''` stores `NULL`; Fluid `''` stored `NULL` in the probe run. `save('')` returns PHP `null`.
A stored `0` renders as the Unix epoch, and `''`/NULL in templates is the CPS "renders as now" bug class
(`format="%U"` on an empty-string date, see the memory note): not reproduced by this fixture (no template parse), so do not
rely on it either way; guard with `{if field != ""}` AND a `0` check.

## Create / change / remove

`accepts_content_type()` returns `true` for every content type: top-level, Grid column and Fluid child all proved.
Grid prerequisite: `instantiate('channel_fields')` + `fetch_installed_fieldtypes()` before `load->model('grid_model')`.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'event_deadline';
$field->field_label = 'Deadline';
$field->field_type = 'date';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = ['localization' => 'localized', 'show_time' => true];
$field->ChannelFieldGroups = $group;
$field->save();     // creates field_id_N BIGINT, field_dt_N VARCHAR(50), field_ft_N
```

```php
// Grid column (note the different keys; field_id and content_type go INSIDE the array)
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'date', 'col_label' => 'When', 'col_name' => 'when',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode(['localize' => true, 'show_time' => true]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $dateField->field_id], 'field_channel_field_groups' => []];
```

Change: switching `localization` or `show_time` later changes no column and no stored value; only how the CP shows and
renders it. Remove: `$field->delete()` drops the data table; Fluid before children.

## Content writes

```php
$entry->field_id_N = '1700000000';           // timestamp (numeric string or int): stored unchanged
$entry->field_id_N = '2024-03-05 10:30 AM';  // human string: parsed in the site timezone (1709652600 on cps)
$entry->field_dt_N = 'America/Toronto';      // optional timezone / localization marker (top-level only)
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => '1700000000']]];   // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => '1700000000']]];  // Fluid
```

`save()` results (proved): `''` -> `null`, `null` -> `null`, `0` -> `0` (int), `'0'` -> `'0'`, a timestamp (int or numeric
string) -> returned unchanged with its type, a human date string -> the timestamp as a numeric string (first tried with the
configured CP date format, then the fuzzy `string_to_timestamp()`; `show_time` false still accepts a time), unparseable text
-> `null`. `grid_save()`: same, and for `localize` false it returns `[timestamp, timezone]` (encoded to `ts|tz` on save);
`''` -> `null`. A pre-joined `'1700000000|Pacific/Auckland'` posted to a Grid column was NOT accepted (stored NULL) in the
development probe: write a bare timestamp and let `grid_save()` add the timezone. `validate()` (CP only; the Model path skips it)
returns `['value' => ...]`, or the `invalid_date` error for unparseable text; empty passes.

CLI warning (proved): `save()`/`grid_save()` on any non-numeric input call `Localize::get_date_format()`, which needs
`ee()->session`. Under `eecli` that property does not exist until something loads it (the Model path does it lazily): a
direct fieldtype call throws `No such property: 'session'`. Call `ee()->load->library('session')` first, or write
timestamps, not strings.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting a date field with content is backup-only rollback.

## Verification

- `SELECT field_id, field_settings FROM exp_channel_fields WHERE field_type = 'date';` (base64-serialized; decode and check keys)
- `SHOW COLUMNS FROM exp_channel_data_field_N;` expect `field_id_N bigint(10)`, `field_dt_N varchar(50)`, `field_ft_N`.
- `SELECT field_id_N, field_dt_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`
- Grid: `SELECT col_id, col_settings FROM exp_grid_columns WHERE col_type = 'date';` (JSON with `localize`, `show_time`);
  `SELECT col_id_C FROM exp_channel_grid_field_G WHERE entry_id = <id>;`.
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> date` prints `PASS date`.

## Gotchas

- Field key is `localization`, Grid key is `localize`; mixing them silently does nothing (field) or breaks `grid_save()` (Grid).
- No `col_dt_C`: a non-localized Grid date carries its timezone INSIDE the value (`ts|tz`) in a `varchar(60)`, so `SUM`/range
  SQL on the column needs `SUBSTRING_INDEX(col_id_C, '|', 1)`.
- Timestamp is timezone-dependent for human strings: `'2024-03-05 10:30 AM'` is 1709652600 on cps (America/Toronto), a
  different integer on another site timezone. Migrations should write integer timestamps.
- Empty top-level dates are `0`, not NULL, via the Model path; Grid and Fluid empties are NULL. Filter both.
- Unparseable input is silently stored as `0` through the Model path (it never calls `validate()`).
- Shared fixture caveats (Fluid `E_WARNING` undefined `$field_group_id`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
