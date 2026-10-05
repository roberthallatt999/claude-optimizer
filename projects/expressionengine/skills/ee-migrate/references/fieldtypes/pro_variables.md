---
fieldtype: pro_variables
addon: pro_variables
origin: core
verified: no — add-on and fieldtype not installed on any CPS site; documented from 7.5.27 source only
fixture: none
fixture_site: none
grid: no — accepts_content_type() not overridden, so channel only (see Create)
fluid: no — same reason
---
# pro_variables

**Do not use in a migration on CPS sites without first** installing the Pro Variables add-on (module +
extension + fieldtype) on the target site, and proving it with a fixture. It is not installed on any CPS site, so
there is no `pro_variables` row in `exp_fieldtypes`, no `exp_pro_variables` table and no variable groups to point
at. It has no fixture, so `run-fixtures.sh` has nothing to run for it (a fixture added later would `SKIP` on every
CPS site). Nothing below was executed; "inferred" marks anything not read from source.

Evidence: `Addons/pro_variables/ft.pro_variables.php`, `addon.setup.php`, `addon.json`, `upd.pro_variables.php`,
`models/*.php`, `libraries/Pro_variables_types.php`, `types/type.pro_variables.php`, `types/*/vt.*.php`,
`Service/Addon/Addon.php`, `Controller/Addons/Addons.php`, `Cli/Commands/CommandAddonsInstall.php`.

## What it is, and is not

- Two separate things share the add-on. (1) A **channel fieldtype** `Pro_variables_ft` (name "Pro Variables")
  that lets an editor pick one (or several) **Pro Variables variables** by name. (2) **Variable types**
  (`types/<name>/vt.<name>.php`, classes extending `Pro_variables_type`, e.g. `pro_text_input`, `pro_grid`,
  `pro_select`), which are field widgets for the global-variables manager and are NOT channel fieldtypes: they are
  never listed in `exp_fieldtypes` and are stored as `exp_pro_variables.variable_type`. This reference covers
  (1) only; (2) cannot be created as channel fields.
- The fieldtype is real and installable: `hasFieldtype()` is true (file `ft.pro_variables.php`), and
  `getFieldtypeNames()` falls back to `getName()` ("Pro Variables") because `addon.setup.php` has no `fieldtypes`
  key. The Add-on Manager install path (`Controller/Addons/Addons.php`, module then `installFieldtype()`) and
  `CommandAddonsInstall` (module `install()`, then `install_fieldtype()` per `ft.*.php`) both install it with the add-on.
- Not installed on CPS: the add-on is absent (CLAUDE.md add-on list; `exp_fieldtypes` has no row). The `pro`
  add-on (built-in, `pro/`) is a different add-on.
- `upd.pro_variables.php::install()` migrates from Low Variables if `low_variables` is installed (inferred
  irrelevant on CPS), otherwise creates its tables via the models, inserts the module row, actions
  (`Pro_variables::sync`), hooks (`sessions_end`, `template_fetch_template`) and registers a `pro_variables`
  content type.

## Settings contract

`ft.pro_variables.php::$default_settings` and `save_settings()` (note: reads `ee('Request')->post()`, ignoring its
`$data` argument):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `lv_ft_multiple` | `'y'`/`'n'` (form yes_no; default `false`) | `false` | multi-select (checkboxes) vs single select |
| `lv_ft_groups` | array of group ids (ints as strings; `'0'` = ungrouped) | `[]` | variable groups the picker offers |

With no `lv_ft_groups`, `display_field()` returns the string `no_variable_group_selected` instead of a control.
Because `save_settings()` reads the POST, a Model/migration write of `field_settings` must set both keys itself
(inferred: it will not go through `save_settings()`).

## Storage

Default columns (`settings_modify_column` not overridden): `field_id_N` `text` + `field_ft_N` `tinytext` on
`exp_channel_data_field_N`. Value = the chosen variable NAME (`variable_name`); multiple choices are
joined with `"\n"` by `save()` and split again in `replace_tag()`. Tables the add-on adds (models): `exp_pro_variables`
(`variable_id`, `group_id`, `variable_label`, `variable_notes`, `variable_type`, `variable_settings`,
`variable_order`, `early_parsing`, `is_hidden`, `save_as_file`, `edit_date`) and `exp_pro_variable_groups`
(`group_id`, `site_id`, `group_label`, `group_notes`, `group_order`); it also reads `exp_global_variables`.
Variables with `early_parsing = 'y'` or `is_hidden = 'y'` are never offered (`get_ft()`).

## Create / change / remove

Prerequisites: add-on installed on the target (reviewed separately), and at least one variable group containing
non-hidden, non-early-parsed variables. Then the Model recipe from `url.md` with
`field_type = 'pro_variables'` and `field_settings = ['lv_ft_multiple' => 'n', 'lv_ft_groups' => ['3']]`
(inferred; unproven). `accepts_content_type()` is inherited (channel only), so it is not offered as a Grid column
or Fluid child (`Grid_lib.php` and `ft.fluid_field.php` both filter on it). Remove with the Model `delete()`.

## Content writes

Inferred: `$entry->field_id_N = 'my_variable'` (or `"a\nb"` for multiple). Nothing validates that the name exists.

## Rollback

Not proven. Deleting the field is backup-only if it holds content. Uninstalling the add-on drops its tables
(`upd.pro_variables.php::uninstall()`, inferred from its model-driven install) and must not be done to roll
back a field.

## Verification

- `SELECT name, version FROM exp_fieldtypes WHERE name = 'pro_variables';`
- `SELECT field_id, field_settings FROM exp_channel_fields WHERE field_type = 'pro_variables';` (decode with
  `unserialize(base64_decode(...))`, expect both keys).
- `cps:schema-check` has no SettingsContract rule for it (inferred; check before relying).

## Gotchas

- Do not confuse the channel fieldtype with the `vt.*` variable types, or with the built-in `pro` add-on.
- The picker stores a variable NAME, not an id: renaming a variable orphans stored values.
- `lv_ft_groups` empty means an unusable field.
