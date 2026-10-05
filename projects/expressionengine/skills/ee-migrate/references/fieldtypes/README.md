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

| Type | Origin | Verified | Fixture site |
|---|---|---|---|
| [checkboxes](checkboxes.md) | core | 7.5.27 | cfk |
| [colorpicker](colorpicker.md) | core | 7.5.27 | cps |
| [date](date.md) | core | 7.5.27 | cps |
| [duration](duration.md) | core | 7.5.27 | cps |
| [email_address](email_address.md) | core | 7.5.27 | cps |
| [file](file.md) | core | 7.5.27 | cfk |
| [file_grid](file_grid.md) | core | 7.5.27 | cfk |
| [fluid_field](fluid_field.md) | core | 7.5.27 | cps |
| [grid](grid.md) | core | 7.5.27 | cfk |
| [hidden](hidden.md) | core | no — not installed on any CPS site; source only | none |
| [member](member.md) | core | 7.5.27 | cfk |
| [multi_select](multi_select.md) | core | 7.5.27 | cfk |
| [notes](notes.md) | core | 7.5.27 | cps |
| [number](number.md) | core | 7.5.27 | cps |
| [pro_variables](pro_variables.md) | core | no — not installed on any CPS site; source only | none |
| [radio](radio.md) | core | 7.5.27 | cfk |
| [range_slider](range_slider.md) | core | 7.5.27 | cps |
| [relationship](relationship.md) | core | 7.5.27 | cfk |
| [rte](rte.md) | core | 7.5.27 | cfk |
| [select](select.md) | core | 7.5.27 | cfk |
| [selectable_buttons](selectable_buttons.md) | core | 7.5.27 | cfk |
| [slider](slider.md) | core | 7.5.27 | cps |
| [structure](structure.md) | core (module not installed) | no — Structure not installed on any CPS site; source only | none |
| [text](text.md) | core | 7.5.27 | cps |
| [textarea](textarea.md) | core | 7.5.27 | cps |
| [toggle](toggle.md) | core | 7.5.27 | cfk |
| [url](url.md) | core | 7.5.27 | cps |
| [wygwam](wygwam.md) | third-party | 7.5.27 | cps |
| [ansel](ansel.md) | third-party | 7.5.27 | cps |
| [publish_sections](publish_sections.md) | third-party | 7.5.27 | cps |
| [category_entry_picker](category_entry_picker.md) | third-party | no — not installed in any live CPS database; source-documented | cyntc |
| [playa](playa.md) | legacy (cpsp) | 7.5.27 (read-only: existing fields) | cpsp |
| [matrix](matrix.md) | legacy (cpsp) | 7.5.27 (read-only: existing fields) | cpsp |
| [image_cropper](image_cropper.md) | legacy (cpsp) | 7.5.27 (read-only: existing fields) | cpsp |
