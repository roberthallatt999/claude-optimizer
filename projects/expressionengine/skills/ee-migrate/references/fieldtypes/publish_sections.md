---
fieldtype: publish_sections
addon: publish_sections 1.2.0
origin: third-party
verified: 7.5.27
fixture: 2099_02_01_000027_cpsref_publish_sections
fixture_site: cps
grid: no
fluid: no
---
# publish_sections

Evidence: `system/user/addons/publish_sections/ft.publish_sections.php` (`accepts_content_type()`,
`display_settings()`, `save_settings()`, `save()`, `display_field()`, `replace_tag()`), `addon.setup.php`,
`libraries/icons.php` (the icon list), EE 7.5.27, the 17 existing cps fields, the two cps migrations that create
and place them (`2026_09_22_100000_group_event_fields_into_sections.php`,
`2026_09_22_100300_group_cccymh_fields_into_sections.php`), and the passing fixture
`fixtures/2099_02_01_000027_cpsref_publish_sections.php` (`run-fixtures.sh <site> publish_sections`; cps only).
The official EE docs do not cover third-party fieldtypes (`EE-DOCS-NOTES.md`).

A **layout-only heading**: a field whose only job is to draw a coloured section heading (and an optional paragraph)
on the publish screen. It stores no entry data.

**Version sensitivity.** Behaviour is that of publish_sections **1.2.0** (`PUBLISH_SECTIONS_VERSION`,
`exp_fieldtypes.version`) on EE 7.5.27. Re-run `run-fixtures.sh <site> publish_sections` after upgrading it.

## Settings contract

`save_settings()` ignores its argument and reads `ee('Request')->post(...)`, so a migration writes the array itself.
The exact stored shape (identical on all 17 cps fields and in both cps migrations):

| Key | PHP type | Allowed values | Notes |
|---|---|---|---|
| `show_heading` | `null` | always `null` | Read from the POST (the CP form has no such input) and never used by `display_field()`; keep it `null` to match |
| `display_style` | string | `'large'`, `'medium'`, `'small'` | `display_field()` adds it as a CSS class; default in the form `'medium'` |
| `display_icon` | string | a name in `libraries/icons.php` (Font Awesome light, e.g. `'info-circle'`, `'calendar'`, `'bookmark'`, `'link'`) | Rendered as `<i class="fal fa-<icon>">`; not validated on save. Default `'bookmark'` |
| `bg_color` | string | CSS hex like `'#228BE6'`, or `''` for none | Used as the heading's `background-color`; brightness over 150 switches the heading text to dark (`light` class). cps uses `#228BE6` (`SECTION_COLOUR`) |
| `collapse_state` | string | `'none'`, `'collapsible'`, `'collapsed'` | `'collapsible'` is open and foldable (cps convention); `'collapsed'` starts folded; any other value or `''` is not collapsible |
| `field_fmt` | string | `'none'` | Fixed by `save_settings()` |
| `field_show_fmt` | string | `'n'` | Fixed by `save_settings()` |

All seven keys are stored and read back in the fixture. The **heading text is the field label**
(`field_label`, leading dashes stripped: `preg_replace('/^[-]+/', '', ...)`) and the paragraph under it is the
**field instructions** (`field_instructions`, parsed as HTML; the field's own instruction box is hidden by an inline
`<style>`). Neither is a setting. `display_field()` also reads `initial_state`, which `save_settings()` never writes:
ignore it. A missing key is tolerated (each is guarded by `!empty()`), a missing `field_label` is not meaningful.

## Storage

- No entry data. `save()` returns `null` unconditionally, so whatever value is assigned to the field is discarded.
  Fixture proof: an entry saved with `'this value is discarded'` for the field left `field_id_N` `NULL`
  (checked for the grouped and the directly attached heading).
- The field still gets the default data table `exp_channel_data_field_N` (`field_id_N text`, `field_ft_N tinytext`,
  proven by `SHOW COLUMNS`, no `settings_modify_column()` override) with a row per entry, always `NULL`. Both CPS
  migrations assert this table exists after creating a heading (a safety check; not proven necessary).
- `replace_tag()` returns `$data` (empty), so `{section_name}` in a template prints nothing. `$disable_frontedit` is true.
- Settings: `field_settings` is `base64_encode(serialize($array))`. Existing cps headings also have the native
  `field_fmt` column `'xhtml'` (observed; the CP sets it); the migrations and the fixture use `'none'`, both work.

## Create / change / remove

`accepts_content_type($name)` returns `$name == 'channel'` only. **Not usable as a Grid column or a Fluid child**
(fixture proof: `accepts_content_type('grid')`, `('fluid_field')`, `('blocks/1')`, `('low_variables')` all `false`;
Grid_lib filters its column picker on `accepts_content_type('grid')`, and the generic `FieldFacade::acceptsContentType()` is the per-content-type check; the Fluid picker was not exercised).
The add-on declares `compatibility => 'text'` only.

Top-level heading (`$group` = a saved `ChannelFieldGroup`; from the migrations and the fixture):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'event_section_links';
$field->field_label = 'Links';                       // the heading text
$field->field_type = 'publish_sections';
$field->field_instructions = '';                     // optional paragraph under the heading (HTML allowed)
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 0;                             // the publish layout places it; see below
$field->legacy_field_data = 'n';
$field->field_settings = [
    'show_heading' => null,
    'display_style' => 'medium',
    'display_icon' => 'link',
    'bg_color' => '#228BE6',
    'collapse_state' => 'collapsible',
    'field_fmt' => 'none',
    'field_show_fmt' => 'n',
];
$field->ChannelFieldGroups = $fieldGroup;            // convention 1, see below
$field->save();
```

**Two attachment conventions, both used on cps and both proven by the fixture:**

1. **Through a field group** (events channel: `2026_09_22_100000`): `$field->ChannelFieldGroups = $fieldGroup;`.
   The heading is in `exp_channel_field_groups_fields` and is a custom field of every channel using that group.
   `field_order` was also set to mirror the grouping (the field group is shared, so ordering is global).
2. **Directly to the channel** (CCCYMH: `2026_09_22_100300`, the channel has no field group): create the field without a
   group, then
   ```php
   $channel->getAssociation('CustomFields')->add($field);
   $channel->save();
   ```
   which writes `exp_channels_channel_fields (channel_id, field_id)`. `Collection::add()` on the magic getter
   silently writes nothing, so use `getAssociation()`, then check the pivot row with a count and insert the row
   directly if it is missing (the CCCYMH migration's `attachToChannel()` does exactly that). In the fixture the
   Model call took and the pivot row was present; the fallback insert is the belt-and-braces.
   `field_order` is NOT used here, because the other fields are shared with other channels.

After creating a heading, assert its data table with `SHOW TABLES LIKE`, not `table_exists()` (cached per request).

**Placing headings in a publish layout** (what actually draws the grouped screen). Layouts are
`exp_layout_publish` rows (Model `ChannelLayout`, `layout_name`, `field_layout`); the fixture saved and read one back:

```php
$layout = ee('Model')->make('ChannelLayout');
$layout->site_id = $channel->site_id;
$layout->channel_id = $channel->channel_id;
$layout->layout_name = 'Sections';
$layout->field_layout = [[
    'id' => 'publish', 'name' => 'publish', 'visible' => true, 'fields' => [
        ['field' => 'title', 'visible' => true, 'collapsed' => false],
        ['field' => 'field_id_' . $headingId, 'visible' => true, 'collapsed' => false],   // heading
        ['field' => 'field_id_' . $bodyId, 'visible' => true, 'collapsed' => false],
    ],
]];
$layout->save();
```

A layout only applies to roles listed in `exp_layout_publish_member_roles (layout_id, role_id)`, and **a role can hold
only one layout per channel**; the CPS migrations rebuild the existing layout in place, save its previous name, field
layout and roles first, assign Super Admins plus every role with access to the channel, and never create a second
layout for a role that already has one (see `assignRoles()` in `2026_09_22_100300`). The fixture creates no role
assignments. Without a layout, roles fall back to `field_order`, which is why convention 1 also set it.

Change: merge into `field_settings` and `save()` (colour, icon, collapse state are cosmetic). Remove:
`$field->delete()` (drops the data table; also remove it from layouts, otherwise the layout keeps a dangling
`field_id_N`); `ChannelLayout` rows are deleted by name as the fixture's `down()` does.

## Content writes

None. There is nothing to write: `save()` returns `null` and a value passed through the Model is discarded
(proven). Do not include headings in `$entry->field_id_N = ...` assignments.

## Rollback

Fully reversible without data loss, since no entry data exists: delete the heading fields (and take them out of any
layouts and the layout's field list), or restore the previous `field_settings`. The CPS migrations log the previous
layout before rebuilding it and restore it in `down()`. No `backup-only` caveat for the fields themselves; a layout
rebuild is the part that needs the saved snapshot.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has all seven keys, `show_heading` is `null`.
  `SELECT field_id, field_name, field_label, field_settings FROM exp_channel_fields WHERE field_type = 'publish_sections';`
- Icon is valid: the value appears in `libraries/icons.php` (`$icons` array).
- Data table: `SHOW TABLES LIKE 'exp_channel_data_field_N'`; `SELECT COUNT(*) FROM exp_channel_data_field_N WHERE field_id_N IS NOT NULL;` is 0.
- Attachment: grouped `SELECT COUNT(*) FROM exp_channel_field_groups_fields WHERE field_id = N;` or direct
  `SELECT COUNT(*) FROM exp_channels_channel_fields WHERE field_id = N AND channel_id = C;` is 1 (cps today: 14 headings
  in field groups, 3 CCCYMH headings direct).
- Layout: `SELECT layout_id, layout_name FROM exp_layout_publish WHERE channel_id = C;` and the roles in `exp_layout_publish_member_roles`.
- Not Grid/Fluid: `accepts_content_type('grid')` is `false`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check` (smoke runs `display_field()`); `run-fixtures.sh <site> publish_sections` prints `PASS publish_sections`.

## Gotchas

- Do not look for stored data: there is none. `save()` is a hard `return null`.
- Not available in Grid or Fluid (`accepts_content_type()` is channel only; the CP pickers hide it). The Model would not stop you, so do not try.
- The heading is the field **label**, not a setting; the paragraph is the **instructions**.
- Attach through a field group or through `getAssociation('CustomFields')`, never `$channel->CustomFields->add()`.
- A role sees a layout's grouping only if it is assigned to that layout; otherwise `field_order` decides, and EE always
  puts Title and URL title first on the default screen.
- Check the data table with `SHOW TABLES`, not `table_exists()`.
