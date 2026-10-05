# What the official ExpressionEngine docs say (read 2026-10-05, EE 7.x "latest")

Notes in our own words from docs.expressionengine.com, for cross-checking references against the
documentation. The docs describe settings by their **control-panel label**; they never give the stored
setting **keys**, the database layout, or how to create content structure from a migration. For those the
fieldtype's PHP source and a passing fixture are the evidence. Where a reference and these notes disagree,
re-read the source, then record the discrepancy in the reference's Gotchas.

## Migrations (`/latest/cli/built-in-commands/migrate.html`, `…/make-migration.html`)

- Commands: `migrate` (also `migrate:all`), `migrate:core`, `migrate:addon`, `migrate:rollback`,
  `migrate:reset`. Flags: `--steps=<n>`/`-s`, `--everything`/`-e` (alias `--all`), `--core`/`-c`,
  `--addon=<name>`/`-a`, `--addons`. Core migrations run before add-on migrations.
- Migrations are tracked in batches (groups). `migrate:rollback` reverses the most recent batch;
  `--steps` on rollback is documented as a number of batches. `migrate:reset` reverses everything.
  (Our runner runs one migration per batch so a rollback is always exactly one file.)
- `make:migration`: `--name`/`-n` (required), `--location`/`-l` (`ExpressionEngine` = core, or an add-on
  short name), `--table`/`-t`, `--create`/`-c`, `--update`/`-u`. It scaffolds `up()`/`down()` for
  **database tables only**.
- **Not documented anywhere:** creating channels, fields, field groups, Grid columns, layouts, categories
  or entries from a migration; failure modes; exit codes. (Observed on 7.5.27: `migrate` exits 0 when
  `up()` throws, and the migration is then not recorded.)

## Fieldtype development (`/latest/development/fieldtypes/fieldtypes.html`)

- `save_settings($data)` returns the array that is persisted and becomes `$this->settings`;
  `validate_settings`, `display_settings`, `post_save_settings` (runs after the field exists, field id
  available) surround it.
- `settings_modify_column($data)` (with `ee_action` = `add` | `delete` | `get_info`) returns the column
  definitions. By default a field gets `field_id_N` (text) and `field_ft_N` (tinytext); a fieldtype can
  override types or add columns (Date adds `field_dt_N`).
- `save($data)` returns the string to store; `post_save($data)` runs after the entry is saved (content id
  available); `validate($data)` returns TRUE or an error string; `delete($ids)` cleans up.
- `accepts_content_type($name)`: default is `channel` only. Returning TRUE for `grid` enables Grid columns,
  for `fluid_field` enables Fluid. Grid uses `grid_*` variants when present (`grid_save`, `grid_validate`,
  `grid_display_field`, …); `grid_settings_modify_column()` is required for Grid support. Grid adds
  `col_id`, `col_name`, `col_required`, `grid_field_id`, `grid_row_id`, `grid_row_name` to the settings;
  Fluid adds `fluid_field_data_id`.
- `'compatibility'` in `addon.setup.php` lets admins switch a field between compatible types.

## Per fieldtype (`/latest/fieldtypes/<page>.html`)

Shared field properties shown on every page: name, short name, instructions, required, include in search,
hide field, make conditional.

| Fieldtype (page) | Documented settings | Documented stored value / behaviour | Grid / Fluid |
|---|---|---|---|
| text (`text`) | maximum characters; text formatting (None, Auto line break, Markdown, XML Encode, XHTML); allow override; text direction; allowed content; field tools | single-line text; the limit applies when an entry is next edited | not documented |
| textarea (`textarea`) | row height; text formatting; allow override; text direction; field tools | text/HTML as entered; `{file:ID:url}` tags are tracked for file usage (compat mode shows `{filedir_N}name`) | not documented |
| number (`number`) | minimum, maximum, step, data-list items, allowed content (changes the DB column type) | numeric | not documented |
| email_address (`email-address`) | none listed | plain text; only valid emails save | not documented |
| colorpicker (`colorpicker`) | allowed colors (Any / Swatches), default color, swatches | CSS hex e.g. `#ff0000`; Swatches mode rejects other colours | not documented |
| notes (`notes`) | note content (required, Markdown) | display-only on the publish form; stores no entry data | not documented |
| url (`url`) | allowed URL schemes (`http://`, `https://`, `/`, `//`, `mailto:`, `ftp://`, `sftp://`, `ssh://`, `tel://`); URL scheme placeholder | entity-encoded URL; only well-formed URLs | not documented |
| toggle (`toggle`) | none listed | `1` on, `0` off | not documented |
| select (`select`) | text formatting; options (value/label pairs, manual textarea, or populated from a channel field) | the selected option's value | not documented |
| multi_select (`multiselect`) | text formatting; options (same three ways) | not documented (labels output comma-separated) | not documented |
| radio (`radio-buttons`) | text formatting; options | the selected value; single selection | not documented |
| checkboxes (`checkboxes`) | text formatting; options | not documented (comma-separated output) | not documented |
| selectable_buttons (`selectable-buttons`) | allow multiple selections (default single); text formatting; options | selected value(s) | not documented |
| date (`date`) | date localization (always localized / always fixed / ask each time); include time | not documented | localization options exist only as a field, **not as a Grid column** |
| duration (`duration`) | units (hours / minutes / seconds, required) | whole number in the chosen unit; accepts colon notation on input | not documented |
| slider (`value-slider`) | minimum, maximum, step, prefix, suffix, allowed content (changes DB column type) | one number | not documented |
| range_slider (`range-slider`) | minimum, maximum, step, prefix, suffix | two values as one string, e.g. `12 - 43` (`:from` / `:to`) | not documented |
| rte (`rte`) | editor configuration (a toolset created in the RTE add-on); defer initialization; column type TEXT (64 KB) or MEDIUMTEXT (16 MB) | not documented (HTML) | not documented |
| file (`file`) | allowed file types (images only / all safe); allowed directory (all or one); show existing files; existing files limit | not documented; an upload directory must exist first | not documented |
| file_grid (`file-grid`) | allowed file types; allowed directory; plus Grid's settings | a Grid with a mandatory File column, short name `file`, that cannot be removed | n/a |
| grid (`grid`) | minimum rows; maximum rows; allow reordering; show row numbers; layout (Auto / Vertical / Horizontal). Column: type, label, name, instructions, required, search, minimum width | not documented; 100 rows output by default | columns: all native types except Grid, File Grid and Fluid |
| fluid_field (`fluid`) | custom fields; custom field groups | not documented; conditional fields are not supported inside Fluid; not usable in Channel Form | children: all native types except another Fluid |
| relationship (`relationships`) | channels to relate (required); include expired / future; categories; authors; statuses; maximum entries (display only); order by (title or entry date); allow multiple; minimum / maximum selection; display entry IDs; display status; defer initialization | not documented; MSM: channels from any site | not documented |
| member (`member`) | roles to include (primary only); maximum members listed; order by; allow multiple; minimum / maximum selection; display member IDs; defer initialization | not documented | not documented |

Not in the docs at all: `hidden`, `structure`, `pro_variables` (they need add-ons that are not installed on
any CPS site), and the third-party types (wygwam, ansel, publish_sections, category_entry_picker, playa,
matrix, image_cropper).
