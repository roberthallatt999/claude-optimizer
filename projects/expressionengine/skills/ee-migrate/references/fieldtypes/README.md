# Fieldtype references

One file per fieldtype, `<type>.md`, loaded only when a migration touches that type. Plan 2 writes them.
Evidence is the 7.5.27 PHP source, the official docs and vendor docs, never memory. A file is marked
`verified: <EE version>` only after its fixture migration passes (create top-level, as Grid column and in
Fluid where allowed, attach, write a value, pass schema-check and `verify()`, roll back to a byte-identical
schema).

## Template (seven headings, in this order)

1. **Settings contract** — every key `save_settings()` (and `grid_save_settings()` where different) writes,
   with PHP type and default; which keys the publish form and `validate()` need.
2. **Storage** — columns added to `channel_data_field_N` (`settings_modify_column`), side tables, and how
   settings are encoded (base64-serialized for channel fields, JSON for Grid columns).
3. **Create / change / remove** — the supported call path as a top-level field, as a Grid column and inside
   Fluid; attaching to field groups and channels; model API, legacy library or "never raw SQL";
   prerequisites (e.g. `fetch_installed_fieldtypes()` before `grid_model`).
4. **Content writes** — how to set a value on an entry so it persists, including relationships
   (`getAssociation()->add()`), Grid/Fluid rows and files.
5. **Rollback** — what `down()` must reverse; what cannot be reversed without data loss (declare
   `backup-only rollback`).
6. **Verification** — exact queries and schema-check rules proving the change.
7. **Gotchas** — including the known pitfalls listed in `SKILL.md`.

## Status

Notes: playa, matrix and image_cropper are EE2-era (cpsp only): read and migrate-away only, no create
recipe. structure is shipped with EE but the Structure module is not installed on any CPS site.

| Type | Origin | Status |
|---|---|---|
| checkboxes | core | not yet written |
| colorpicker | core | not yet written |
| date | core | not yet written |
| duration | core | not yet written |
| email_address | core | not yet written |
| file | core | not yet written |
| file_grid | core | not yet written |
| fluid_field | core | not yet written |
| grid | core | not yet written |
| hidden | core | not yet written |
| member | core | not yet written |
| multi_select | core | not yet written |
| notes | core | not yet written |
| number | core | not yet written |
| pro_variables | core | not yet written |
| radio | core | not yet written |
| range_slider | core | not yet written |
| relationship | core | not yet written |
| rte | core | not yet written |
| select | core | not yet written |
| selectable_buttons | core | not yet written |
| slider | core | not yet written |
| structure | core (module not installed) | not yet written |
| text | core | not yet written |
| textarea | core | not yet written |
| toggle | core | not yet written |
| url | core | not yet written |
| wygwam | third-party | not yet written |
| ansel | third-party | not yet written |
| publish_sections | third-party | not yet written |
| category_entry_picker | third-party | not yet written |
| playa | legacy (cpsp) | not yet written |
| matrix | legacy (cpsp) | not yet written |
| image_cropper | legacy (cpsp) | not yet written |
