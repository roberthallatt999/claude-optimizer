---
fieldtype: selectable_buttons
addon: selectable_buttons
origin: core
verified: 7.5.27
fixture: 2099_02_01_000012_cpsref_selectable_buttons
fixture_site: cfk
grid: yes
fluid: yes
---
# selectable_buttons

Evidence: `system/ee/ExpressionEngine/Addons/selectable_buttons/ft.selectable_buttons.php` and `addon.setup.php`, the shared base class
`system/ee/legacy/fieldtypes/OptionFieldtype.php` (settings form, `save_settings()`, `validate_settings()`)
and `EE_Fieldtype.php` (`_get_field_options()`, `_get_historic_field_options()`, `get_setting()`,
`settings_modify_column()`), the Fluid source (`Addons/fluid_field/ft.fluid_field.php`), EE 7.5.27, and the
passing fixture `fixtures/2099_02_01_000012_cpsref_selectable_buttons.php` (`run-fixtures.sh <site> selectable_buttons`; run on
cfk). Official docs: see `EE-DOCS-NOTES.md` (the docs list control-panel labels only).

## Settings contract

An option fieldtype stores its option list in ONE of three modes, and the three modes live in different
places. This is the part that is easy to get wrong.

| Mode (docs label) | Where it is stored (top-level field) | Where (Grid column `col_settings`) |
|---|---|---|
| Value/label pairs ("value/label pairs") | `field_settings['value_label_pairs']` (array `value => label`); column `field_pre_populate` stays `n` | `value_label_pairs` plus `field_pre_populate = 'v'`, `field_list_items = ''` |
| Manual textarea ("populate manually") | the `channel_fields.field_list_items` COLUMN (newline-separated, value == label); `field_settings` has no pairs | `field_list_items`, `field_pre_populate = 'n'`, `value_label_pairs = []` |
| Populated from a channel field ("populate from channel field") | columns `field_pre_populate = 'y'`, `field_pre_channel_id`, `field_pre_field_id` | same keys in `col_settings` (form offers it; not exercised by the Grid fixture) |

Keys, with what the code does when they are absent:

| Key | PHP type | Default | Docs label | Absence |
|---|---|---|---|---|
| `value_label_pairs` | array<string, string> (value => label) | `[]` | Options: value/label pairs | not an error: `_get_field_options()` takes pairs first when non-empty, otherwise falls through to manual/channel mode; with all modes empty the option list is empty and every non-empty value fails `validate()` with `invalid_selection` |
| `field_list_items` | string, one option per line | `''` (`ChannelField::onBeforeInsert()` turns NULL into `''`; the column is NOT NULL) | Options: manual | top-level: harmless. Grid manual column: `_get_field_options()` reads `$this->settings['field_list_items']` without `isset`, so a missing key is an undefined-array-key warning; always write it |
| `field_pre_populate` | top-level: `'y'`/`'n'` column (typed `boolString`; the form value `'v'` is stored as `'n'`; seen in cfk data, a pairs field has the column `n`). Grid: string `'v'`/`'n'`/`'y'` | `'n'` | which option mode is selected | absent reads false (`get_setting()` casts it), i.e. manual/pairs; safe |
| `field_pre_channel_id` | int | `0`/NULL | Options: populate from channel field, channel | only used when mode is `y` |
| `field_pre_field_id` | int | `0`/NULL | Options: populate from channel field, field | only used when mode is `y`; `validate_settings()` rejects `y` without it (CP path only) |
| `field_fmt` | string (`none`, `br`, `xhtml`, `markdown`, ...) | `'none'` | Text formatting | top-level it is the `channel_fields.field_fmt` column, not a `field_settings` key; Grid: key in `col_settings`; there is no separate `grid_save_settings()`: `save_settings()` branches on `content_type() == 'grid'` and reads `$data['field_fmt']` unconditionally |
| `allow_multiple` | bool | `false` (an absent key reads as falsy) | docs: "allow multiple selections" (default single) | `validate()` and `display_field()` read `$this->settings['allow_multiple']` with `isset`, so absence is safe and means single |

`ft.selectable_buttons.php::save_settings()` calls the parent and then adds `allow_multiple` as a real bool (`$data['allow_multiple'] == 'y'`). `OptionFieldtype::save_settings()` is what the control panel posts through: for the pairs mode it returns `['value_label_pairs' => $pairs]` at top level, `[]` for the other modes, and for Grid columns the full set (`field_fmt`, `field_pre_populate`, `field_pre_channel_id`/`field_pre_field_id` or `field_list_items`, `value_label_pairs`). Writing through the Model with property assignment (as the fixture does, like the `url` fixture) skips `save_settings()`, so you must set the columns and `field_settings` yourself.

Documented but not in `field_settings`: "text formatting" is a column at top level (see `field_fmt` above). Source keys the docs omit: `field_pre_channel_id`, `field_pre_field_id`, `field_pre_populate = 'v'` (a form-only value) and the manual-list column.

`validate()` first returns `ft_multiselect_not_allowed` when `allow_multiple` is falsy and `$data` is an array with more than one element, then defers to `Multi_select_ft::validate()` (unknown values give `invalid_selection`). `display_field()` renders `_shared/form/fields/buttons` (a button group of hidden checkboxes; `multi` follows `allow_multiple`). Single mode is enforced in the browser by unchecking the other buttons.

How options are resolved (`EE_Fieldtype::_get_field_options()`): non-empty `value_label_pairs` win; otherwise, when `field_pre_populate` is false, `field_list_items` is split on `\n`, each line trimmed and used as both key and label (a blank line becomes an empty-string option); otherwise, with a channel id, every entry of that channel (any status) is read, ordered by the source field ascending, blank values skipped, key = trimmed value, label = first 110 characters.

## Storage

- Top-level: `field_id_N` (`text`, nullable) and `field_ft_N` (`tinytext`) on `exp_channel_data_field_N`
  (`legacy_field_data = 'n'`). `selectable_buttons` does not override `settings_modify_column()`, so these are the defaults;
  verified by `SHOW COLUMNS` in the fixture.
- Settings: `exp_channel_fields.field_settings` is `base64_encode(serialize($array))` (here
  `value_label_pairs`, `allow_multiple`); the manual list and channel-mode ids are separate columns of
  `exp_channel_fields` (`field_list_items` text, `field_pre_populate` char(1), `field_pre_channel_id`,
  `field_pre_field_id`). Grid column settings are JSON in `exp_grid_columns.col_settings`.
- Value (pipe-delimited values): A pipe-delimited string: `encode_multi_field()` joins the selected values with `|` and escapes a literal `\` as `\\` and a literal `|` as `\|`. `decode_multi_field()` splits on unescaped pipes and reverses the escapes. Fixture proof: selecting `beta` and `delta|pipe` stored exactly `beta|delta\|pipe`; an empty selection is the empty string. `save()` encodes only when it receives an array (a string is stored as given).
- Grid: `exp_channel_grid_field_G.col_id_C` (`text`), same value format. Fluid: the child's value is in the
  child field's own data table on a row with `entry_id = 0`, linked by `exp_fluid_field_data.field_data_id`;
  same value format (fixture proof below).

## Create / change / remove

`accepts_content_type()` returns `true` for every content type, so `selectable_buttons` works as a channel field, a Grid
column and a Fluid child (Fluid filters children with `acceptsContentType('fluid_field')`). The fixture
created all three.

Top-level field, value/label pairs (`$group` is a saved `ChannelFieldGroup`):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_selectable_buttons';
$field->field_label = 'Example';
$field->field_type = 'selectable_buttons';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = ['value_label_pairs' => ['alpha' => 'Alpha label', 'beta' => 'Beta label', 'gamma' => 'Gamma label', 'delta|pipe' => 'Delta label'], 'allow_multiple' => true];
$field->field_pre_populate = 'n';
$field->field_list_items = '';
$field->ChannelFieldGroups = $group;
$field->save();
```

Manual textarea (value == label, one per line, in the COLUMN):

```php
$field->field_settings = ['allow_multiple' => false];
$field->field_pre_populate = 'n';
$field->field_list_items = "One\nTwo\nThree";
$field->save();
```

Populated from another channel field (the fixture used a `text` field `$source` in the same channel):

```php
$field->field_settings = ['allow_multiple' => false];
$field->field_pre_populate = 'y';
$field->field_list_items = '';
$field->field_pre_channel_id = (int) $channel->channel_id;
$field->field_pre_field_id = (int) $source->field_id;
$field->save();
```

Grid column (prerequisites: `ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes();` BEFORE `ee()->load->model('grid_model')`; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'selectable_buttons', 'col_label' => 'Pick', 'col_name' => 'pick',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'field_fmt' => 'none', 'field_pre_populate' => 'v', 'field_list_items' => '',
        'value_label_pairs' => ['alpha' => 'Alpha label', 'beta' => 'Beta label', 'gamma' => 'Gamma label', 'delta|pipe' => 'Delta label'], 'allow_multiple' => true,
    ]),
], false, 'channel');
```

Manual Grid column: `'field_pre_populate' => 'n', 'field_pre_channel_id' => '0', 'field_pre_field_id' => '0', 'field_list_items' => "One\nTwo\nThree", 'value_label_pairs' => [], 'allow_multiple' => false`.

Fluid child: create the field as above, then a `fluid_field` whose settings list it:

```php
$fluid->field_settings = ['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []];
```

Change: merge into the current `field_settings` and `save()` (never replace); for Grid edit the `col_settings` JSON.
Remove: `$field->delete()` (drops the data table); for Grid delete the `grid_columns` rows too; Fluid before its children.

## Content writes

Through the Model (`CpsRefFixture::makeEntry()` is the tested path); values by shape:

```php
$entry->field_id_N = ['beta', 'delta|pipe'];                                                    // top-level
$entry->field_id_G = ['rows' => ['new_row_1' => ['col_id_C' => ['alpha', 'gamma']]]];      // Grid
$entry->field_id_F = ['fields' => ['new_field_1' => ['field_id_N' => ['alpha', 'beta']]]];  // Fluid
$entry->save();
```

Pass an ARRAY of selected values for a multi-value field: `save()` encodes it. A pre-joined string is stored as given, so then you must escape pipes yourself. `save()` does not validate; call `$entry->validate()` first when the value is not trusted (the fixture calls it for a valid entry and for a value outside the options).

## Rollback

Fully reversible except for the field's own data: `down()` removes the entry, then the Fluid field, the Grid
field and its `grid_columns` rows, the option fields (Model `delete()` drops their data tables), the field
group and the channel (`CpsRefFixture::removeAll()`). Changing an option list is a settings-only change:
restore the previous `value_label_pairs` / `field_list_items` from the backup or baseline. Entries keep
stored values whose option was removed; the publish form still shows them (`_get_historic_field_options()`).
Deleting a `selectable_buttons` field that holds real content is `backup-only rollback`.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has `value_label_pairs`, `allow_multiple` (pairs mode);
  Grid: `json_decode(col_settings, true)` has `field_fmt`, `field_pre_populate`, `field_list_items`,
  `value_label_pairs`, `allow_multiple` (pairs) or additionally `field_pre_channel_id`, `field_pre_field_id` (manual).
  `SELECT field_id, field_name, field_pre_populate, field_list_items, field_pre_channel_id, field_pre_field_id, field_settings FROM exp_channel_fields WHERE field_type = 'selectable_buttons';`
  `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'selectable_buttons';`
- Data: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'`;
  `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>` (fixture: `beta|delta\|pipe`).
- Grid row: `SELECT col_id_C FROM exp_channel_grid_field_G WHERE entry_id = <id>`.
- Fluid row: `SELECT * FROM exp_fluid_field_data WHERE fluid_field_id = <F> AND entry_id = <id>`, then
  `field_id_N` on `exp_channel_data_field_N` where `id = field_data_id`.
- Options actually read in the stored shape: `$entry->validate()->isValid()` is true for the stored entry and
  false for a value outside the options (all three option modes are validated by the fixture on the pairs
  field, the manual field and the channel-populated field).
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> selectable_buttons` prints `PASS selectable_buttons`.

## Gotchas

- The manual list is a COLUMN (`field_list_items`), not a `field_settings` key, at top level; the pairs are
  a `field_settings` key. Setting `field_settings['field_list_items']` on a top-level field does nothing:
  `_get_field_options()` reads `$this->settings['field_list_items']`, which for a top-level field is built
  from the column.
- Existing fields mix both (seen in the cfk database: most use the column, some use pairs); check both before
  editing an existing field.
- Grid manual column must carry `field_list_items` (and `field_fmt`) in `col_settings`; omitting them is an
  undefined-array-key warning, not a clean empty list.
- `field_pre_populate` is not a free-form string at top level: the model types it as bool (`y`/`n`), so the
  form's `v` becomes `n`; whether pairs apply is decided by `value_label_pairs` being non-empty, not by the column.
- Value/label pairs: the stored value is the key. Numeric-string keys (`'2024'`) become integer keys in the PHP
  array; comparisons are loose so this is harmless, but do not rely on string identity.
- The control panel rejects duplicate values in the pairs list (`validate_settings()`); the Model path does not.
- Manual mode: a blank line in `field_list_items` becomes an empty-string option; trim the list.
- Changing a field between the list fieldtypes (`'compatibility' => 'list'`: select, multi_select, radio,
  checkboxes, selectable_buttons) keeps the stored string. Going multi to single leaves `a|b` in the column,
  which then fails `validate()` for the single type.
- Model `save()` skips `validate()` (finding from the `url` fixture; not re-tested here). Validate untrusted values.
- Single mode (`allow_multiple` false) is a publish-form behaviour plus a `validate()` check on ARRAY input only. The stored string of a single-mode field written from the stored string is not re-checked, so a migration that writes `a|b` into a single-mode field stores it silently; keep one value.
- The class extends `Multi_select_ft` (which `require_once`s `Select_ft`), so storage, `save()` and `replace_tag()` are the multi-select ones even in single mode: the value is still `encode_multi_field()` output.
- Writing a Fluid value through the Model may log a harmless `E_WARNING: Undefined variable $field_group_id`
  from `ft.fluid_field.php::save()`; the row is still written (seen with the `url` fixture; this fixture
  passed with it).
- `eecli migrate` exits 0 even when `up()` throws; judge success from `exp_migrations` or
  `cps:migrate-status` (`run-fixtures.sh` does).
- Member id 1 does not exist on every site; resolve a real `author_id` before saving entries.
