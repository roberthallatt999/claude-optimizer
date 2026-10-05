---
fieldtype: email_address
addon: email_address
origin: core
verified: 7.5.27
fixture: 2099_02_01_000005_cpsref_email_address
fixture_site: cps
grid: yes
fluid: yes
---
# email_address

Evidence: `Addons/email_address/ft.email_address.php`, `addon.setup.php` (EE 7.5.27), existing cps field
`committee_member_email`, and the passing fixture `fixtures/2099_02_01_000005_cpsref_email_address.php`
(`run-fixtures.sh <site> email_address`).

## Settings contract

None. The class defines no `save_settings()`, `display_settings()` or `validate_settings()`, so the base
`EE_Fieldtype::save_settings()` returns the posted array and the form posts nothing: real fields store
`a:0:{}` (checked on cps). The docs notes also list no settings. An empty `field_settings` is valid and nothing in
`validate()` or `display_field()` reads a setting (only the generic `get_setting('field_disabled')`, which defaults
to false). Documented settings not found in source: none; source keys the docs omit: none.

Grid column: `col_settings` may be `{}`; the fixture stores `{"field_required":"n"}` (the generic key the other
fixtures use).

## Storage

- `field_id_N` (`text`, NULL allowed) and `field_ft_N` (`tinytext`) on `exp_channel_data_field_N`; there is no
  `settings_modify_column()` override (proved: `text`).
- Grid: `col_id_C` `text` on `exp_channel_grid_field_G` (proved).
- Fluid: the child's own data table, `entry_id = 0` row, linked from `exp_fluid_field_data`.
- Value stored verbatim (`top.level+tag@example.com` read back unchanged); `save()` is the base default.

## Create / change / remove

`'compatibility' => 'text'`; `accepts_content_type()` returns `true` for every content type: top-level, Grid column
and Fluid child all proved. Grid prerequisite: `instantiate('channel_fields')` + `fetch_installed_fieldtypes()`
before `load->model('grid_model')`.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'contact_email';
$field->field_label = 'Contact email';
$field->field_type = 'email_address';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [];
$field->ChannelFieldGroups = $group;
$field->save();
```

```php
// Grid column (field_id and content_type go INSIDE the array)
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'email_address', 'col_label' => 'Email', 'col_name' => 'email',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode(['field_required' => 'n']),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $emailField->field_id], 'field_channel_field_groups' => []];
```

Change: only generic properties (label, instructions, required) can change. Remove: `$field->delete()`; Fluid
before children.

## Content writes

```php
$entry->field_id_N = 'person@example.com';                                            // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => 'person@example.com']]];       // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => 'person@example.com']]];  // Fluid
```

`validate()` (empty allowed) uses EE's `email` validation rule; the Model `save()` skips it, so call
`$entry->validate()` before saving untrusted values. Tested path: `CpsRefFixture::makeEntry()`.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting an email field with content is backup-only rollback.

## Verification

- `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'email_address';`
  (expect `YTowOnt9` = `a:0:{}` for real fields)
- `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'email_address';`
- `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N';` (expect `text`)
- `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;`; Grid/Fluid queries as in text.md.
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> email_address` prints `PASS email_address`.

## Gotchas

- No settings: unlike url there is nothing to forget. `field_settings = []` is correct.
- Nothing enforces valid emails except `validate()`; a Model/migration write stores any string.
- The template tag `{field:mailto}` is obfuscated by default (`encode="no"` disables); `{field}` returns the plain string.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
