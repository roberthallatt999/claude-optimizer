---
fieldtype: category_entry_picker
addon: category_entry_picker 1.0.1 (CPS-custom, author Robert Hallatt)
origin: third-party
verified: no — add-on not installed in any CPS site's live database (code present in the cyntc repo; installed only in a stale local database)
fixture: 2099_02_01_000028_cpsref_category_entry_picker
fixture_site: cyntc
grid: no
fluid: no
---
# category_entry_picker

**Not installed — do not use in a migration until the add-on is installed on the target site.** Install the
add-on (module and fieldtype) first, then run `run-fixtures.sh <site> category_entry_picker` to verify. Until
then the runner SKIPs the fixture. Nothing below was proven by a passing fixture. Evidence is the source in
`cyntc/system/user/addons/category_entry_picker/` (`addon.setup.php`, `ft.category_entry_picker.php`,
`upd.category_entry_picker.php`, `ext.category_entry_picker.php`) and a read-only look at the one existing field
in `admin_immun`, a STALE local database (not the database cyntc's EE uses). That field is `test_url` (#1816).

## Settings contract

What it does: pick a category from one category group, then pick an entry in that category.

`save_settings()` returns exactly these keys (all strings):

| Key | Type | Default | Needed by validate()/display? |
|---|---|---|---|
| `channel_id` | string (channel id) | `''` | No. Fallback source channel when the URL gives none |
| `cat_group_id` | string (category group id) | `''` | No (`??`), but with `''` the category list is empty |
| `allow_nested` | `'y'`/`'n'` | `'y'` | No (`?? 'y'`) |
| `field_required` | `'y'`/`'n'` | `'n'` | **Yes**: `validate()` indexes `$this->settings['field_required']` directly. Always write it |

Existing field in `admin_immun`: `a:3:{channel_id "165"; cat_group_id "42"; allow_nested "y"}`.

## Storage

- Default `exp_channel_data_field_N`: `field_id_N` (`text`, nullable) and `field_ft_N` (`tinytext`),
  `legacy_field_data = 'n'`. No add-on table.
- Value: a JSON string `{"entry_id":N,"category_id":N}` (integers) produced by `save()`. `save()` returns `''`
  unless `entry_id` is non-empty. `parse_data()` also accepts a bare entry id (legacy). The one stored row in
  `admin_immun` matched the JSON shape.

## Create / change / remove

Top-level channel field only. `accepts_content_type()` is not overridden, so the base default
(`EE_Fieldtype.php`: `$name == 'channel'`) applies: not a Grid column, not a Fluid child.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_picker';
$field->field_label = 'Example';
$field->field_type = 'category_entry_picker';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'channel_id' => (string) $channelId,
    'cat_group_id' => (string) $categoryGroupId,
    'allow_nested' => 'y',
    'field_required' => 'n',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Change: merge into the current `field_settings` and `save()`. Remove: `$field->delete()`.

## Content writes

Through the Model, pass an array (the fieldtype's `save()` encodes it):

```php
$entry->field_id_N = ['entry_id' => $targetEntryId, 'category_id' => $categoryId];
$entry->save();
```

Not proven (fixture never run to PASS). Stored value is the JSON string above.

## Rollback

`$field->delete()` drops the data table; nothing else to undo (no add-on table). Module and action rows belong to
the add-on install, not the field.

## Verification

```sql
SELECT CAST(FROM_BASE64(field_settings) AS CHAR) FROM exp_channel_fields WHERE field_name = 'example_picker';
SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;  -- {"entry_id":N,"category_id":N}
```

Or `run-fixtures.sh <site> category_entry_picker` once installed.

## Gotchas

- Version mismatch: `addon.setup.php` and `upd` say 1.0.1, `ft.category_entry_picker.php` says 1.0.0; the
  stale database holds 1.0.0. Treat any version-dependent claim as unverified (version sensitivity).
- `validate()` crash path: reads `$this->settings['field_required']` directly; always write `field_required`.
- The module registers action `get_entries` with `csrf_exempt = 1` (`upd::install()`); the field's AJAX uses it.
  Anyone installing the add-on gets an unauthenticated-capable endpoint by design; review before enabling.
- Channel-only: no Grid column, no Fluid child.
- The picker lists entries only for the channel in the URL or `channel_id` setting, excluding status `closed`.
- Not installed on cyntc staging or production (no `exp_fieldtypes` row), nor in cyntc's local live database.
