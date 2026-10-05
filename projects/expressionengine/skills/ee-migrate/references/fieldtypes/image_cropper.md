---
fieldtype: image_cropper
addon: image_cropper 1.0.1 (written by the Canadian Paediatric Society, namespace CPS\ImageCropper, cpsp only; requires EE >= 7.0, PHP >= 8.2)
origin: third-party        # CPS-custom add-on (CPS\ImageCropper); kept read-only here because content writes need image files
verified: 7.5.27 (read-only: existing fields only)
fixture: 2099_02_01_000031_cpsref_image_cropper
fixture_site: cpsp
grid: n/a
fluid: n/a
---
# image_cropper

**Legacy — do not create. Read existing data and migrate away.**

Not an EE2-era add-on: `image_cropper` is an in-house CPS add-on (author "Canadian Paediatric Society", declares EE >= 7.0), found only on cpsp, and it
is classed `legacy` here because it is a one-site fieldtype with no maintained recipe, not because of its age. A migration must never create an
`image_cropper` field or write to `exp_image_crops`. The fixture is read-only (`up()`/`down()` are empty; `verify()` reads the existing field), so
`run-fixtures.sh <site> image_cropper` only runs on cpsp. Evidence: `system/user/addons/image_cropper/` on cpsp (`ft.image_cropper.php`,
`Models/ImageCropModel.php`, `upd.image_cropper.php`, `addon.setup.php`, `addon.json`), the cpsp database (read-only SELECTs), `cps:schema-check` on cpsp, and the passing fixture.

State on cpsp: one field, `banner_image` (id 1644), upload directory 56 ("Home Page Banner", `public/uploads/banner`), output 1384 x 320; two crop
rows (entries 4599 and 4600, variant `default`). `cps:schema-check` on cpsp: `settings_contract` PASS ("settings match contract", the only one of the three
legacy types with a CPS contract) and `smoke` PASS. Nothing indicates it is broken on EE 7.5.27 / PHP 8; it is built for them.

## Settings contract

`save_settings()` returns exactly three keys (`field_settings`, base64-serialized):

| Key | Type | Meaning |
|---|---|---|
| `upload_location_id` | int | `exp_upload_prefs.id` the picker uses; also where `_cropped/` is created |
| `output_width` | int or null | target width of the cropped file; null = unset |
| `output_height` | int or null | target height; null = unset |

The code also reads `enable_variants` (`'y'`) and `variants` (text, one `name:width:height` per line), but nothing writes them: the settings form does not offer them,
so existing fields have only the three keys. `save_settings()` has a side effect: it creates `<upload dir>/_cropped/`.

## Storage

- **The field value** is the original image reference as text. Field 1644 has its own data table (`legacy_field_data = 'n'`):
  `exp_channel_data_field_1644` (`id, entry_id, field_id_1644 text, field_ft_1644 tinytext`). Values on cpsp are absolute URLs with a trailing space
  (`https://cpsp.cps.ca/uploads/banner/banner2.jpg `: `save()` appends a space to force the dirty flag); new saves store a relative path (`/uploads/banner/x.jpg`).
  `settings_modify_column()` declares `field_id_N TEXT NULL`.
- **`exp_image_crops`** holds the crops, one row per entry + field + variant: `crop_id, entry_id, field_id, original_file, cropped_file, variant_name` (default `'default'`),
  `crop_x, crop_y, crop_width, crop_height, output_width, output_height, aspect_ratio`, `canvas_data` and `cropbox_data` (JSON text: Cropper.js screen
  coordinates), `created_at, updated_at` (cpsp rows hold `0000-00-00 00:00:00`). Created by `upd.image_cropper.php::install()`.
- **Cropped files** are written to `<upload dir>/_cropped/<cropped_file>` on disk (not registered in `exp_files`). The original may or may not be an `exp_files` row.
- Settings: base64-serialized `field_settings`.

## Create / change / remove

**Migrating away.** Do not create image_cropper fields. Replace each with a native `file` field (see `file.md`) or an Ansel field (Ansel is installed on CPS sites and
stores crops itself); `file.md` has the create recipe and write path.

1. Back up the database and `public/uploads/<dir>/_cropped/`.
2. Create the replacement field (`file`, `allowed_directories` = the field's `upload_location_id`, content type `image`). Pick the crop strategy first:
   - **Keep the crops**: the cropped files already exist on disk under `_cropped/`. A `file` field can only point at an `exp_files` row, so each cropped file must be
     registered (Filemanager API, `file.md`) and the new field set to that file; the original and the crop are then two different files.
   - **Keep the original**: write the original as the `file` value and let templates size it (jcogs_img / `file` manipulations). This is the simplest and loses the crop box.
3. Value: for each row in `exp_channel_data_field_<id>` resolve the original to an `exp_files` row by upload directory and file name (`basename` of the URL/path, trimmed);
   write `{filedir_<upload_location_id>}<file_name>` through the Model path in `file.md`; read it back.
4. Templates: `{banner_image}` returns the default crop URL, `{banner_image:original}` the original, `{banner_image variant="x"}` a variant, and the tag pair exposes
   `original_url, cropped_url, variant_name, crop_width, crop_height`. Replace each with the `file` field tags or an Ansel/jcogs_img tag.
5. Delete the old field only in a later migration (`delete()` removes that entry's crop rows AND their files under `_cropped/`: `backup-only rollback`). Then uninstall the add-on
   (`uninstall()` drops `exp_image_crops`).

## Content writes

Not done. Do not write to `exp_image_crops` or the field's data table directly. To read:

```sql
SELECT d.entry_id, TRIM(d.field_id_1644) AS original, c.variant_name, c.cropped_file, c.crop_x, c.crop_y, c.crop_width, c.crop_height
FROM exp_channel_data_field_1644 d LEFT JOIN exp_image_crops c ON c.entry_id = d.entry_id AND c.field_id = 1644;
```

## Rollback

The fixture changes nothing. A migrate-away migration's `down()` deletes the new field and leaves the old field, its data table, `exp_image_crops` and the `_cropped/` files untouched.
Deleting the old field also deletes the cropped files from disk: `backup-only rollback` (database dump plus a copy of `_cropped/`).

## Verification

- Read-only fixture: `run-fixtures.sh <cpsp repo> image_cropper` prints `PASS image_cropper` (three settings keys; `upload_location_id` names an upload directory; the field's data column exists;
  `exp_image_crops` has the 15 documented columns and at least one row; crop sizes are positive; `canvas_data`/`cropbox_data` are JSON).
- `SELECT field_id, field_name, legacy_field_data FROM exp_channel_fields WHERE field_type = 'image_cropper';`
- `SELECT field_id, COUNT(*) FROM exp_image_crops GROUP BY 1;`
- Disk: every `cropped_file` exists in `<upload dir>/_cropped/`.
- `cps:schema-check`: `settings_contract` and `smoke` both pass.

## Gotchas

- Stored values can carry a trailing space and an absolute `https://cpsp.cps.ca/...` URL (staging/production hosts differ); trim and compare by file name.
- Crops are keyed by `entry_id` + `field_id`, not by `exp_files`; duplicating an entry does not duplicate its crops.
- `created_at`/`updated_at` are `datetime` columns but the model types them `int` and cpsp holds zero dates; do not sort or filter on them.
- `compatibility => 'file'` in `addon.setup.php` lets EE treat it as a file-type field for file usage, but the field does not register its files in `exp_file_usage`.
- Only `upload_location_id`, `output_width`, `output_height` are real settings; `variants` support exists in code but is unreachable from the UI.
