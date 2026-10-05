---
fieldtype: structure
addon: structure
origin: core
verified: no — Structure add-on not installed on any CPS site; documented from 7.5.27 source only
fixture: none
fixture_site: none
grid: yes — accepts_content_type() lists 'grid' (ft.structure.php); unproven without a fixture
fluid: no — 'fluid_field' is not in accepts_content_type()
---
# structure

**Do not use in a migration on CPS sites without first** installing the Structure add-on on the target site,
and proving it with a fixture. **CPS navigation is hand-authored HTML (`stash/partials/main-menu-*.html`);
there is no Structure add-on on any CPS site, and a migration must never create a `structure` field.**
Installing Structure is a site-wide change (six tables, `exp_sites.site_pages`, publish tabs) that CPS does not
want. There is no fixture, so `run-fixtures.sh` has nothing to run for it (a fixture added later would `SKIP` on
every CPS site). Nothing below was executed; "inferred" marks anything not read from source.

Evidence: `Addons/structure/ft.structure.php`, `addon.setup.php`, `addon.json` (version 6.0.0),
`upd.structure.php`, `sql.structure.php`, `tab.structure.php`, `Service/Addon/Addon.php`,
`Controller/Addons/Addons.php`, `Cli/Commands/CommandAddonsInstall.php`.

## What it is, and why it is unavailable

- Real, installable: `addon.setup.php` declares `'fieldtypes' => ['structure' => ['name' => 'Structure']]` and
  `ft.structure.php` defines `Structure_ft extends EE_Fieldtype`. The Add-on Manager and `addons:install` install
  the module (`upd.structure.php::install()`) and then the fieldtype (`install_fieldtype()` inserts the
  `exp_fieldtypes` row).
- It is a **page picker dropdown** (`build_dropdown()`): it lists Structure pages (or one listing channel) and stores
  the chosen `entry_id`. It needs the Structure module: `__construct()` returns early when
  `Sql_structure::module_is_installed()` (row in `exp_modules` named `Structure`) is false, leaving `site_pages`
  unset, which `replace_tag()` then reads (inferred to fail or return false).
- Install refuses if the `Pages` module is installed (`install()` shows an error).
- On CPS: no Structure add-on, no `exp_fieldtypes` row. CLAUDE.md forbids `{exp:structure:*}` for the same reason.

## Settings contract

One key, set by `save_settings()` from POST (`structure_list_type`), by `install()` (default) and by
`grid_save_settings()` for Grid columns:

| Key | Value | Meaning |
|---|---|---|
| `structure_list_type` | `'pages'` or a numeric channel id | `'pages'` = whole pages tree; id = a Structure "listing" channel |

`display_field()` treats it as a channel id only when `is_numeric`. A Grid column's settings come from
`grid_save_settings($data)` = `current(array_values($data))` (first posted value), a quirk to keep in mind
when writing `col_settings` directly (inferred).

## Storage

Value: default `field_id_N` (`text`) + `field_ft_N` (`tinytext`); contents are an entry id. Tables and data the
module adds (`upd.structure.php`): `exp_structure` (nested-set tree: `site_id, entry_id, parent_id, channel_id,
listing_cid, lft, rgt, dead, hidden, structure_url_title, template_id, updated`), `exp_structure_settings`
(`site_id, var, var_value`; seeded with `module_id`, `action_ajax_move`, `show_picker`, `show_view_page`,
`show_global_add_page`, `hide_hidden_templates`, `redirect_on_login`, `redirect_on_publish`,
`add_trailing_slash`), `exp_structure_members` (`nav_state`), `exp_structure_channels` (`type` enum
`page|listing|asset|unmanaged`, `split_assets`, `show_in_page_selector`), `exp_structure_nav_history`, and
`exp_structure_listings`; it also adds `exp_sites.site_pages` (longtext, via `dbforge->add_column`), a module action
(`ajax_move_set_data`), and publish-layout tabs `parent_id`, `uri`, `template_id`, `hidden`, `listing_channel`
(`upd.structure.php::tabs()`; `has_publish_fields = 'y'`).

## Create / change / remove

Not to be done on CPS. For reference: after the add-on is installed, the Model recipe in `url.md` with
`field_type = 'structure'` and `field_settings = ['structure_list_type' => 'pages']` (inferred). Grid is accepted
(`accepts_content_type`: `channel`, `grid`, `blocks/1`); Fluid is not. `uninstall()` drops all six tables and the
layout tabs, so removing the add-on is destructive (backup-only).

## Content writes, Rollback, Verification

Not proven. Inferred: write an existing page `entry_id` as the field value. Rollback of the add-on =
`uninstall()` plus a database restore. Prerequisite checks before any use:
`SELECT name FROM exp_fieldtypes WHERE name = 'structure';` and
`SELECT module_id FROM exp_modules WHERE module_name = 'Structure';`.

## Gotchas

- The `structure` fieldtype is separate from Structure's own publish-tab fields; creating the former does not make
  pages.
- `replace_tag()` returns a page URL from `exp_sites.site_pages`, not the entry id.
- Structure would also take over page URIs (`site_pages`), conflicting with CPS Resource Router routing.
