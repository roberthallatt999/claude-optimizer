---
fieldtype: notes
addon: notes
origin: core
verified: 7.5.27
fixture: 2099_02_01_000007_cpsref_notes
fixture_site: cps
grid: yes
fluid: yes
---
# notes

Evidence: `Addons/notes/ft.notes.php`, `addon.setup.php` (EE 7.5.27), existing cps field `title_notes`, and the
passing fixture `fixtures/2099_02_01_000007_cpsref_notes.php` (`run-fixtures.sh <site> notes`). Notes is a
display-only field: the text shown on the publish form lives in the field settings and entries store no data.

## Settings contract

`ft.notes.php::save_settings()` merges over `$default_settings` and keeps ONLY these keys:

| Key | PHP type | Default | Docs label | Absence breaks? |
|---|---|---|---|---|
| `note_content` | string (Markdown) | `''` | Note content (required) | YES: `getParsedNote()` reads `$this->settings['note_content']` by index for both `display_field()` and `replace_tag()` (undefined-array-key warning; not exercised) |
| `field_hide_title` | bool | `true` | none (source key the docs omit) | No: hides the field label on the publish form |
| `field_hide_publish_layout_collapse` | bool | `true` | none (source key the docs omit) | No: hides the collapse control in publish layouts |

Real cps field `title_notes` stores exactly these three (`field_hide_*` as `b:1`). Documented settings not found in
source: none. Note content is rendered with `typography->markdown()`.

## Storage

- No entry value is ever written. The field still gets the default data column on creation (there is no
  `settings_modify_column()` override): `field_id_N` (`text`) and `field_ft_N` (`tinytext`) on
  `exp_channel_data_field_N`; after saving an entry the column is NULL (or the row is absent). The fixture proves this.
- The note text is in `exp_channel_fields.field_settings` (`base64(serialize())`) or, for a Grid column, in the
  JSON `col_settings`.
- `replace_tag()` returns the parsed note, so `{notes_field}` outputs the settings text on the front end.

## Create / change / remove

`addon.setup.php` declares no `fieldtypes` section (no `compatibility`), but `accepts_content_type()` returns `true`
for every content type, so the field can be created at top level, as a Grid column and as a Fluid child (creation
proved by the fixture). A Grid or Fluid notes field is only a static caption; use it sparingly.

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'title_notes';
$field->field_label = 'Notes';
$field->field_type = 'notes';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'note_content' => "# Heading\n\nGuidance for editors, in Markdown.",
    'field_hide_title' => true,
    'field_hide_publish_layout_collapse' => true,
];
$field->ChannelFieldGroups = $group;
$field->save();
```

```php
// Grid column (field_id and content_type go INSIDE the array)
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'notes', 'col_label' => 'Notes', 'col_name' => 'help_notes',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode([
        'note_content' => 'Guidance', 'field_hide_title' => true, 'field_hide_publish_layout_collapse' => true,
    ]),
], false, 'channel');

// Fluid child
$fluid->field_settings = ['field_channel_fields' => [(int) $notesField->field_id], 'field_channel_field_groups' => []];
```

Change the text by merging a new `note_content` into `field_settings`; no data migration is needed. Remove:
`$field->delete()`; Fluid before children.

## Content writes

None. There is nothing to write: do not pass a value for a notes field. The tested entry carries no notes value and
the column stays NULL. `validate()` always returns true and `save()` passes the data through.

## Rollback

`down()` = `CpsRefFixture::removeAll()`. Deleting a notes field loses only its settings text (no entry data), so a
rollback is restoring `field_settings` from the baseline dump.

## Verification

- `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'notes';`
  (fixture decodes it and asserts the three keys)
- `SELECT col_id, col_name, col_settings FROM exp_grid_columns WHERE col_type = 'notes';`
- No data: `SELECT field_id_N FROM exp_channel_data_field_N WHERE entry_id = <id>;` returns NULL or no row.
- `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> notes` prints `PASS notes`.

## Gotchas

- Notes stores no entry data; any migration that copies "values" into it is a bug.
- `note_content` is mandatory in the CP form; a migration that omits it leaves an empty or broken note.
- The note is Markdown rendered at display time; it is not HTML-escaped by the fieldtype.
- Adding a notes field to a field group adds it to publish layouts automatically (`ChannelField::onAfterInsert()`
  calls `addToLayouts()`); check layouts when you remove or move it.
- Shared fixture caveats (Fluid `E_WARNING`, `eecli migrate` exit code, member id 1): see url.md Gotchas.
