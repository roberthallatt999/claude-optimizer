---
fieldtype: hidden
addon: hidden
origin: core
verified: no — fieldtype not installed on any CPS site; documented from 7.5.27 source only
fixture: none
fixture_site: none
grid: no — default accepts_content_type() returns channel only (see Create)
fluid: no — same reason
---
# hidden

**Do not use in a migration on CPS sites without first** installing the fieldtype on the target site and
proving it with a fixture. `hidden` has no row in `exp_fieldtypes` on any CPS site, so a `ChannelField` with
`field_type = 'hidden'` would point at a fieldtype EE cannot load. It also has no fixture, so `run-fixtures.sh`
has nothing to run for it (and a fixture added later would print `SKIP hidden (fieldtype not installed on this
site)` on every CPS site). Nothing below has been executed; it is read from source, and "inferred" marks
anything not read.

Evidence: `system/ee/ExpressionEngine/Addons/hidden/ft.hidden.php` and `addon.setup.php`,
`system/ee/legacy/fieldtypes/EE_Fieldtype.php`, `Service/Addon/Addon.php`, `legacy/libraries/Addons.php`,
`legacy/libraries/addons/Addons_installer.php`. The official docs do not cover it (`EE-DOCS-NOTES.md`).

## Why it is not available

- It is a real fieldtype file: `ft.hidden.php` defines `Hidden_ft extends EE_Fieldtype`, name "Hidden Field",
  version 1.0.0. `Addon::hasFieldtype()` is true because it only tests for an `ft.*.php` file.
- `addon.setup.php` declares `'built_in' => true` and NO `fieldtypes` key (so no `compatibility`). With
  `built_in`, `Controller/Addons/Addons.php::getAllAddons()` skips it (`continue`), so it is not listed in the
  Add-on Manager and cannot be installed from that screen (inferred from the skip; not tried).
- Installation is the row in `exp_fieldtypes` written by `Addons_installer::install_fieldtype()`;
  `Addon::isInstalled()` and `Addons::get_installed('fieldtypes')` both read that table. The EE installer that
  seeds the other built-in fieldtypes is not in this tree, so whether a fresh EE install ever seeds `hidden` is
  inferred (CPS sites do not have it).
- Nothing in `system/ee` consumes it: `grep` for `Hidden_ft` / `field_type … 'hidden'` found no use, and
  `publish.hidden_fields` (set by `display_field()`) has no reader in `system/ee` sources I searched (the
  `hidden_fields` hits are unrelated Channel Form / form helpers). `field_is_hidden` and
  `exp_channel_entry_hidden_fields` are conditional-field collapsing, not this fieldtype.

## Settings contract

None. `ft.hidden.php` defines no `display_settings()` / `save_settings()`; the inherited
`EE_Fieldtype::save_settings()` returns `array()` and `display_settings()` returns `''`. `settings_exist` is
`false`. `install()` (inherited) returns `array()`. Generic keys other CPS fields carry (`field_fmt`,
`field_required`) would be set by the Model path, not by this fieldtype (inferred).

## Storage

Inherited `settings_modify_column()`: `field_id_N` (`text`, nullable) and `field_ft_N` (`tinytext`) on
`exp_channel_data_field_N` when `legacy_field_data = 'n'`. `save()` is the inherited pass-through, so the value
is stored as posted (no escaping, no validation: `validate()` is the inherited default, inferred to return the
data unchanged). `display_field()` renders `form_hidden($this->field_name, $data)`.

## Create / change / remove

Prerequisite: `eecli addons:install -a hidden` (or equivalent) on the target site, reviewed and approved
separately; that inserts the `exp_fieldtypes` row (`Addons_installer::install_fieldtype`). Then the generic
Model recipe in `url.md` applies with `field_type = 'hidden'` and `field_settings = ['field_fmt' => 'none',
'field_required' => 'n']` (inferred; unproven).

Grid and Fluid are not offered: `accepts_content_type()` is not overridden, so the inherited version returns
`$name == 'channel'` only. Grid (`Grid_lib.php`) drops fieldtypes whose `accepts_content_type('grid')` is false and
Fluid (`ft.fluid_field.php`) filters on `acceptsContentType('fluid_field')`. Do not create it as a Grid column or
Fluid child.

## Content writes

Inferred from `save()`: `$entry->field_id_N = 'value'` through the Model, as in `url.md`. The value is returned
to the template unchanged by the inherited `replace_tag()`.

## Rollback

Not proven. By analogy with `url.md`: delete the field through the Model (drops its data table) and, if the
migration installed the fieldtype, `addons:uninstall -a hidden`. Deleting a field with content is backup-only.

## Verification

- `SELECT name, version FROM exp_fieldtypes WHERE name = 'hidden';` must return a row before use.
- `SELECT field_id, field_name FROM exp_channel_fields WHERE field_type = 'hidden';`
- `cps:schema-check` has no SettingsContract rule for it (none needed: no settings).

## Gotchas

- Creating a field of an uninstalled type is the failure to avoid; check `exp_fieldtypes` first.
- It is hidden from the Add-on Manager listing by `built_in`; do not expect to find it there.
- To carry an invisible value, a plain `text` field with `field_is_hidden = 'y'` is the proven alternative, but
  that only collapses the field on the publish form (inferred from `ChannelField.php`); it is not equivalent.
