---
fieldtype: url
addon: url
origin: core
verified: 7.5.27
fixture: 2099_02_01_000001_cpsref_url
fixture_site: cps
grid: yes
fluid: yes
---
# url

Evidence: `system/ee/ExpressionEngine/Addons/url/ft.url.php` and `addon.setup.php` (EE 7.5.27), the Fluid
source (`Addons/fluid_field/ft.fluid_field.php`, `Model/FluidField.php`), and the passing fixture
`fixtures/2099_02_01_000001_cpsref_url.php` (run with `run-fixtures.sh <site> url`). The official docs pages
could not be fetched in this session, so nothing here relies on them.

## Settings contract

`ft.url.php::save_settings()` merges the posted settings over these defaults and keeps ONLY these two keys
(`array_intersect_key`), so any other key passed through the control panel is dropped:

| Key | PHP type | Default | Needed by |
|---|---|---|---|
| `allowed_url_schemes` | array of strings from `http://`, `https://`, `/`, `//`, `ftp://`, `mailto:`, `sftp://`, `ssh://`, `tel://` | `['http://', 'https://']` | `validate()` (`in_array`), `display_settings()` |
| `url_scheme_placeholder` | string, one of the same scheme values | `''` (the form pre-selects the first scheme when unset) | `display_field()` (input placeholder) |

Both are effectively required: `validate()` calls `in_array(..., $this->get_setting('allowed_url_schemes'))`
for any value lacking a scheme or host, which is a `TypeError` when the key is absent (see Gotchas). When
writing settings directly (Model API or `grid_columns.col_settings`), the generic keys the other CPS fields
carry are also set: `field_fmt` (`'none'`), `field_required` (`'n'`).

Scheme semantics in `validate()`: `/` allows root-relative values, `//` allows protocol-relative values,
`mailto:` allows `mailto:` values (which have a path but no host); any other scheme must appear as
`<scheme>://` in the list. Empty string always validates.

## Storage

- Top-level field: one column `field_id_N` (`text`, nullable) plus `field_ft_N` (`tinytext`) on
  `exp_channel_data_field_N` (own table because `legacy_field_data = 'n'`). `url` has no
  `settings_modify_column` override, so it gets the default columns. Verified with `SHOW COLUMNS`.
- Settings: `exp_channel_fields.field_settings` is `base64_encode(serialize($array))`. Grid column settings
  are JSON in `exp_grid_columns.col_settings` (slashes escaped: `"https:\/\/"`).
- Grid value: `exp_channel_grid_field_G.col_id_C` (`text`), one row per grid row.
- Fluid value: the Fluid child's value lives in the CHILD field's own data table
  (`exp_channel_data_field_N`) on a row with `entry_id = 0`; `exp_fluid_field_data` links it
  (`fluid_field_id`, `entry_id`, `field_id`, `field_data_id`, `order`, `field_group_id`, `group`).
- Values are stored through `prepForStorage()`: `htmlspecialchars($url, ENT_QUOTES, 'UTF-8', false)`. An
  `&` is stored as `&amp;` (`https://example.com/top?a=1&b=2` is stored `...?a=1&amp;b=2`), but an existing
  entity is not double-encoded.

## Create / change / remove

`addon.setup.php` declares `'compatibility' => 'text'` and `accepts_content_type()` returns `true` for every
content type, so `url` works as a channel field, a Grid column and a Fluid child (Fluid filters children with
`getField()->acceptsContentType('fluid_field')`; Grid with `'grid'`; `url` accepts both).

Prerequisites (Grid only): `ee()->legacy_api->instantiate('channel_fields')` then
`ee()->api_channel_fields->fetch_installed_fieldtypes()` BEFORE `ee()->load->model('grid_model')`.

Top-level field (Model API, never raw SQL; `$group` is a saved `ChannelFieldGroup`, which needs `short_name`
only where `exp_field_groups` has that column):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'event_website';
$field->field_label = 'Website';
$field->field_type = 'url';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'field_fmt' => 'none', 'field_required' => 'n',
    'allowed_url_schemes' => ['http://', 'https://'], 'url_scheme_placeholder' => 'https://',
];
$field->ChannelFieldGroups = $group;   // or attach later; see the attach recipe in the migration author notes
$field->save();                        // creates exp_channel_data_field_N with field_id_N / field_ft_N
```

Grid column (`$gridField` is a saved `grid` ChannelField; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id,
    'content_type' => 'channel',
    'col_order' => 0,
    'col_type' => 'url',
    'col_label' => 'Link',
    'col_name' => 'link_url',
    'col_instructions' => '',
    'col_required' => 'n',
    'col_search' => 'n',
    'col_width' => 0,
    'col_settings' => json_encode([
        'field_fmt' => 'none', 'field_required' => 'n',
        'allowed_url_schemes' => ['http://', 'https://'], 'url_scheme_placeholder' => 'https://',
    ]),
], false, 'channel');
```

Fluid child: create the `url` field as above, then a `fluid_field` whose settings list it:

```php
$fluid->field_settings = ['field_channel_fields' => [(int) $urlField->field_id], 'field_channel_field_groups' => []];
```

Change settings: update `field_settings` through the Model (`$field->field_settings = array_merge(...)`; `save()`),
or `col_settings` JSON for a Grid column; always merge over the current settings, never replace.
Remove: `$field->delete()` (drops `exp_channel_data_field_N`); for a Grid field also delete its
`grid_columns` rows and let the Model drop `exp_channel_grid_field_G`; delete a Fluid field before its children.

## Content writes

Write through the Model so the fieldtype's `save()` runs; the fixture's `CpsRefFixture::makeEntry()` is the
tested path:

```php
$entry = ee('Model')->make('ChannelEntry');
$entry->Channel = $channel;
$entry->site_id = $siteId;
$entry->author_id = $memberId;            // must be a real member: Author is read in onAfterInsert()
$entry->title = 'x'; $entry->url_title = 'x'; $entry->status = 'open';
$entry->entry_date = ee()->localize->now;
$entry->field_id_N = 'https://example.com';                                   // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => 'https://example.com']]];   // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => 'https://example.com']]]; // Fluid
$entry->save();
```

`save()` does NOT validate: a bad scheme (`javascript:alert(1)`) was stored verbatim in the fixture probe.
Call `$entry->validate()` first when the value is not trusted; it returned
`Your URL must begin with a valid scheme: http://, https://` for that value.

## Rollback

Fully reversible without data loss of anything but the field's own data: `down()` removes the entry, then the
Fluid field, Grid field and its `grid_columns` rows, the URL field (Model `delete()` drops its data table),
then the field group and channel. The fixture's `down()` is `CpsRefFixture::removeAll()`. Rolling back
`allowed_url_schemes` edits is a settings-only change: restore the previous array from the backup/baseline.
Deleting a url field that holds real content is `backup-only rollback`.

## Verification

- Settings stored contain both keys (PHP-side check in `verify()`):
  `unserialize(base64_decode($row['field_settings']))` has `allowed_url_schemes` and `url_scheme_placeholder`;
  Grid: `json_decode(col_settings, true)` has both.
- SQL for the stored settings of every url field and Grid column:
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'url';`
  `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'url';`
- Data: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'`; read the value back with
  `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>` (expect `&amp;` for `&`).
- Grid row: `SELECT col_id_C FROM exp_channel_grid_field_G WHERE entry_id = <id>`.
- Fluid row: `SELECT * FROM exp_fluid_field_data WHERE fluid_field_id = <F> AND entry_id = <id>`, then
  `field_id_N` on `exp_channel_data_field_N` where `id = field_data_id`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check` (SettingsContract rule for `url` must report no
  failures); `run-fixtures.sh <site> url` prints `PASS url`.

## Gotchas

- **2026-10-05 incident (cps Events).** `2026_09_11_100000` created `event_website` and the `event_links`
  Grid column `link_url` without `allowed_url_schemes` / `url_scheme_placeholder`. A value without a scheme or
  host (`www.example.ca`, `/en/cccymh`) made `validate()` run `in_array(..., null)`: a `TypeError`, a 500 on
  the publish screen and on the relationship field's edit modal. Fixed by
  `2026_10_05_090000_fix_event_url_field_settings`. Always set both keys, for fields AND Grid columns.
- `save_settings()` drops any key other than those two; do not expect extra settings to persist.
- Model `save()` skips `validate()`; unsafe schemes can be written by a migration. Validate untrusted values.
- Stored values are HTML-escaped (`&` becomes `&amp;`); compare against the escaped form, and do not
  pre-escape values you pass in.
- Writing a Fluid value through the Model logs a harmless `E_WARNING: Undefined variable $field_group_id`
  from `ft.fluid_field.php::save()` (no field-group key in the data); the row is still written correctly.
- `eecli migrate` exits 0 even when `up()` dies with an uncaught fatal; judge success from `exp_migrations`
  or `cps:migrate-status`, not the exit code. A failed `up()` has no migration row, so `migrate:rollback
  --steps=1` would roll back the PREVIOUS migration; clean up with a cleanup migration instead.
- Active-record chains: do not call a query helper inside a pending `ee()->db->select()->where(...)` chain
  (it consumed the chain and produced `Unknown column 'col_id'`); resolve ids first.
- Member id 1 does not exist on every site (absent on local cps); resolve an existing member before setting
  `author_id`, or `ChannelEntry::onAfterInsert()` fails on `$this->Author->updateAuthorStats()`.
- Entry inserts and deletes touch `exp_members` author stats (net zero after the fixture's delete).
