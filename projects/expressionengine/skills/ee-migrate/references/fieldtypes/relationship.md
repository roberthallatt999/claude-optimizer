---
fieldtype: relationship
addon: relationship
origin: core
verified: 7.5.27
fixture: 2099_02_01_000023_cpsref_relationship
fixture_site: cfk
grid: yes
fluid: yes
---
# relationship

Evidence: `system/ee/ExpressionEngine/Addons/relationship/ft.relationship.php` (`save_settings()`, `_form()`,
`validate()`, `save()`, `post_save()`, `delete()`, `grid_delete()`, `display_field()`, `accepts_content_type()`,
`settings_modify_column()`, `_clear_defunct_relationships()`), `libraries/EntryList.php::query()`,
`libraries/Relationships_ft_cp.php` (`all_order_options()`, `Relationship_settings_form`),
`Model/Channel/ChannelEntry.php` (`Children`/`Parents` associations), `Model/Channel/Channel.php::getAllCustomFields()`,
`Addons/fluid_field/ft.fluid_field.php::removeField()`, `Addons/grid/libraries/Grid_lib.php::get_grid_fieldtypes()`, EE
7.5.27, and the fixture `fixtures/2099_02_01_000023_cpsref_relationship.php` (`run-fixtures.sh <site> relationship`).
Official docs: see `EE-DOCS-NOTES.md` (labels only; no keys, no storage, no write path).

## Settings contract

`ft.relationship.php::save_settings()` runs the posted data through `_form()` and keeps every key the form knows:
exactly **fifteen**. Booleans are converted with `get_bool_from_string()`; an array containing `'--'` ("any") becomes
`[]`. Always write all fifteen when creating the field from a migration: `validate()` and `display_field()` read
`allow_multiple`, `channels`, `categories`, `statuses`, `authors`, `limit`, `expired`, `future`, `order_field` and
`order_dir` straight from `$this->settings` with no `isset()` guard (project note: a first attempt that omitted the
last five keys broke the publish screen in production).

| Key | PHP type | Default (`_form()`) | Meaning / used by |
|---|---|---|---|
| `channels` | array of numeric **strings** | `[]` (any) | channels whose entries can be picked |
| `expired` | int `0`/`1` (CP stores `''` or `1`) | `0` | include expired entries |
| `future` | int `0`/`1` (CP stores `''` or `1`) | `0` | include entries dated in the future |
| `categories` | array of category ids (strings) | `[]` | limit by category |
| `authors` | array of strings `'g_<role_id>'` / `'m_<member_id>'` | `[]` | limit by author (role or member) |
| `statuses` | array of status names | `[]` (any) | limit by status (`'open'`, `'closed'`, custom) |
| `limit` | int or numeric string | `100` | picker list length only (display) |
| `order_field` | string: `'title'` or `'entry_date'` | `'title'` | orders the PICKER list only; must be a real field |
| `order_dir` | `'asc'` / `'desc'` | `'asc'` | picker order direction |
| `display_entry_id` | bool | `false` | show the entry id in the picker |
| `display_status` | bool | `false` | show the status in the picker |
| `deferred_loading` | bool | `false` | defer initialising the widget |
| `allow_multiple` | bool | `true` | `false` = single selection (`validate()` skips min/max when false) |
| `rel_min` | int | `0` | minimum selection; enforced by `validate()` when `allow_multiple` |
| `rel_max` | int/string | `''` | maximum selection (`''` = none); enforced by `validate()` |

Valid `order_field` values are the keys of `Relationships_ft_cp::all_order_options()`: `title` and `entry_date` (the
legacy value `date` is mapped to `entry_date`). `order_field` does not control the order a template outputs related
entries; that is `exp_relationships.order`, the order the editor arranged them in.

Fixture: the stored settings contained exactly these fifteen keys, `channels` was an array of strings, `order_field`
`entry_date` and the booleans round-tripped as booleans. Grid column: the same fifteen keys in `col_settings` JSON
plus `field_required` (`'n'`); a column lacking `field_required` made `cps:schema-check` log
`ft.relationship.php:62 Undefined array key "field_required"` (a warning).

The settings keys `channels`, `categories`, `authors`, `statuses` are references by id or name: resolve the target
channel by NAME (`SELECT channel_id FROM exp_channels WHERE channel_name = ?`) and cast with `(string)`.

## Storage

- The field's own column is a dummy: `settings_modify_column()` returns `field_id_N` as `VARCHAR(8)`; `save()` returns
  NULL, so it stays NULL (fixture asserted both). For a Grid column the dummy is `col_id_C` `varchar(8)`.
- The data is in `exp_relationships`: `relationship_id`, `parent_id`, `child_id`, `order`, `field_id`,
  `grid_field_id`, `grid_col_id`, `grid_row_id`, `fluid_field_data_id`. `order` starts at **1** and follows array
  position.
  - Top level: `field_id = N`, the three grid columns and `fluid_field_data_id` all 0 (fixture asserted).
  - Grid column: `grid_field_id` = the Grid field id, `grid_col_id` = the column id and `grid_row_id` = the Grid row
    id (fixture asserted all three: `grid_row_id` equalled the Grid row's `row_id`). `field_id` is whatever the
    fieldtype was initialised with (`Grid_parser::instantiate_fieldtype()` passes the `col_id`); the fixture does not
    assert it, so filter Grid cells by `grid_field_id` and `grid_col_id`.
  - Fluid child: `fluid_field_data_id` = `exp_fluid_field_data.id` (fixture asserted `child_id` and the link).
- `post_save()` first deletes every row with the same `parent_id`, `field_id`, `grid_*` and `fluid_field_data_id`,
  then inserts the submitted set. Rewriting a field therefore replaces its whole set.
- Settings: `exp_channel_fields.field_settings` = `base64_encode(serialize($array))`.

## Create / change / remove

`accepts_content_type($name)` returns true for `channel`, `grid` and `fluid_field` (`Grid_lib` additionally excludes
it for non-`channel` Grid content types). Top-level field, minimal and complete (the fixture's shape):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_related';
$field->field_label = 'Related entries';
$field->field_type = 'relationship';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'channels' => [(string) $targetChannelId], 'expired' => 0, 'future' => 0,
    'categories' => [], 'authors' => [], 'statuses' => ['open'],
    'limit' => 100, 'order_field' => 'title', 'order_dir' => 'asc',
    'display_entry_id' => false, 'display_status' => false, 'deferred_loading' => false,
    'allow_multiple' => true, 'rel_min' => 0, 'rel_max' => '',
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column (prerequisites and the full call in `grid.md`; `field_id` and `content_type` INSIDE the array):

```php
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'relationship', 'col_label' => 'Related', 'col_name' => 'related',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode($sameFifteenKeys + ['field_required' => 'n']),
], false, 'channel');
```

Fluid child: create the relationship field as above, then a `fluid_field` whose settings are
`['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []]`.

Change: merge into `field_settings` and `save()`. Remove: `$field->delete()`; `settings_modify_column()` with
`ee_action = delete` calls `_clear_defunct_relationships()`, which deletes the field's `exp_relationships` rows (for a
Grid column by `grid_col_id`). Delete Fluid parents first. Never `table_exists()` for checks (see Gotchas).

## Content writes

The reliable path is the Model with the fieldtype's own shape, then reading `exp_relationships` back:

```php
$key = 'field_id_' . $field->field_id;
$entry->$key = ['data' => [$childId1, $childId2]];            // order = array position, from 1
$entry->save();
// Grid cell:  ['rows' => ['new_row_1' => ['col_id_' . $colId => ['data' => [$childId]]]]]
// Fluid:      ['fields' => ['new_field_1' => ['field_id_' . $childFieldId => ['data' => [$childId]]]]]
```

`save()` (`ft.relationship.php::save()`) only caches the ids (and sets the model property to NULL); the rows are
written in `post_save()`. Always count the rows back and throw when they are missing; the Model reports success
even when nothing was written.

Fixture-proved facts:

- **Top level, Grid column and Fluid child** each wrote the expected `exp_relationships` rows (read back in
  `verify()`).
- **Existing entry, field-only change**: reordering, clearing (`['data' => []]` deletes every row) and re-writing all
  landed WITHOUT touching `edit_date` (`PROBE existing entry: assign relationship + save() (no edit_date) leaves
  children: [b,a,c]`). Unlike Grid, nothing special is needed.
- **`validate()`** enforces `rel_min`/`rel_max` when `allow_multiple` is on: with min 1 and max 3 the fixture got
  `{"empty":false,"two":true,"four":false}`. `save()` itself never validates.
- **Trap 1, stale field list (the silent no-op).** A relationship field created after an entry was saved earlier in
  the same request is invisible to `ChannelEntry`: `Channel::getAllCustomFields()` caches the channel's field list in
  `ee()->session` (`ChannelCustomFields/<channel_id>/`) the first time it is built. The assignment becomes a plain
  property and `post_save()` never runs: no rows, no error. Reproduced: `PROBE relationship created after a cached
  field list, written without refresh: 0 row(s)`. After
  `ee()->session->set_cache(\ExpressionEngine\Model\Channel\Channel::class, 'ChannelCustomFields/<id>/', false)`
  the same write gave `2 row(s)`. Whether the cache is already warm differs per environment (it wrote rows locally and
  none on staging in the 2026-09-11 incident). Fix: create all fields first, drop the cache entry, then write; or
  write in a later migration; and always read the rows back.
- **Trap 2, `getAssociation('Children')->add()`.** `ChannelEntry::$_relationships['Children']` is a
  `hasAndBelongsToMany` through `exp_relationships` (`parent_id`/`child_id`). Adding through it writes a pivot row
  with `field_id = 0`, attached to no field, so no relationship field shows it. Reproduced: `PROBE
  getAssociation(Children)->add() pivot rows (count, field_id): 1, [0]`. Use it only for deliberate association
  bookkeeping, never as a way to fill a relationship field. (Project note, not re-tested here: `Collection::add()` on
  an already-loaded to-many property can silently write nothing, because the collection has no Association
  backreference; `getAssociation(...)->add()` is the spelling that does write.)
- **Fallback: direct insert.** `exp_relationships` IS the storage, so inserting the rows yourself is equivalent to a
  successful `post_save()`:

```php
ee()->db->insert('relationships', [
    'parent_id' => $parentId, 'child_id' => $childId, 'field_id' => $fieldId, 'order' => $position, // from 1
    'grid_field_id' => 0, 'grid_col_id' => 0, 'grid_row_id' => 0, 'fluid_field_data_id' => 0,
]);
```

  Fixture: two inserted rows read back correctly and the Model's `Children` association returned the same ids
  (`PROBE direct insert read through the Children association: [a,b]`). Use it only as the fallback after counting
  the Model path's rows and finding none.

## Rollback

`down()`: delete the entries (`ft.relationship.php::delete($ids)` removes rows where the entry is parent OR child),
then the fields (`_clear_defunct_relationships()` removes each field's rows), the Fluid parent first. Rows written by
`getAssociation()` have `field_id = 0`; the fixture deletes `exp_relationships` rows by `parent_id`/`child_id` of its
entries to be sure none remain (`CpsrefRelationship::cleanup()`).

Deleting a TARGET entry deletes every relationship pointing at it (`child_id`), on every site: that is data loss, so
removing real relationship fields or entries is `backup-only rollback`.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has the fifteen keys; `channels` is an array of strings;
  `order_field` is `title` or `entry_date`:
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'relationship';`
- Rows (the proof a write landed):

```sql
SELECT child_id, `order`, grid_field_id, grid_col_id, grid_row_id, fluid_field_data_id
FROM exp_relationships
WHERE parent_id = <entry> AND field_id = <field>
ORDER BY `order`;
```

  For a Grid cell filter on `grid_field_id = <G> AND grid_col_id = <C>` instead of `field_id`; for a Fluid child add
  `AND fluid_field_data_id = <fluid row id>`.
- No stray rows with `field_id = 0`: `SELECT COUNT(*) FROM exp_relationships WHERE field_id = 0;` (on a clean site 0).
- The dummy column: `SHOW COLUMNS FROM exp_channel_data_field_<N> LIKE 'field_id_<N>'` is `varchar(8)` and NULL.
- The picker query works: `cps:schema-check` smoke renders `display_field()`; it reported
  `display_field() threw Exception: Unknown field ChannelEntry. (Select.php:713)` for a field whose `order_field` was
  empty. In the CLI it stops before the control-panel half (`No such property: 'cp'`), which is reported as "not
  exercised".
- `$entry->validate()->isValid()` for the written ids.
- CLI: `cps:migrate-verify <migration>`; `run-fixtures.sh <site> relationship`.
- Status of this reference: `run-fixtures.sh ../cfk grid file_grid relationship` printed `PASS relationship` twice in a
  row on cfk (EE 7.5.27, 2026-10-05) with the final file, leaving the schema byte-identical.

## Gotchas

- **`order_field` must be a real column.** `EntryList::query()` does `->order($order_field, $order_dir)` on the
  `ChannelEntry` model, so `''` or a made-up name throws `Unknown field ChannelEntry.<name>`. Reproduced:
  `PROBE EntryList::query with order_field = a non-column: Exception: Unknown field ChannelEntry.cpsref_not_a_column`
  and `... = empty string: Exception: Unknown field ChannelEntry.`. `display_field()` calls the same query on every
  publish-screen render, which is the HTTP 500 (the page renders unstyled, which looks like a CSS or JS asset
  failure; the browser console shows the 500). `cps:schema-check` flags it.
- **`channels` must be strings.** Every working field on the CPS sites stores `s:3:"180"` and the control panel
  writes strings. I could NOT reproduce a failure with integer ids: `EntryList::query()` with
  `channels => [(int) $id]` returned the entries (`PROBE EntryList::query with channels as ints: ok, 6 entries`),
  and `in_array($channel->getId(), $limit_channels)` in `display_field()` is a loose comparison. The 2026-09-11
  breakage that was blamed on integer ids is unproven: the empty `order_field` (reproduced above) or the five missing
  trailing keys are the demonstrated causes. Cast to string anyway; it matches what the control panel writes.
- Write all fifteen keys; a grid column also needs `field_required`.
- The Model write can silently write nothing (trap 1). Count the rows back.
- `getAssociation('Children')->add()` writes `field_id = 0` rows (trap 2). `Collection::add()` can no-op.
- Never `table_exists()`; use `SHOW TABLES LIKE` (`CpsRefFixture::tableExists()`). It caches per request
  (`grid.md` Gotchas 4).
- `limit` and `order_field` only affect the picker list, not what templates output.
- Relationship columns are channel-only inside Grid; a relationship child inside Fluid is deleted by
  `Fluid::removeField()` by `fluid_field_data_id`.
- The relationship field's `order` column starts at 1, not 0.
- Fixture note: a relationship field whose `order_field` is empty was created and removed during development;
  leaving one behind fails `cps:schema-check` (new failure), so a migration that tests a broken shape must delete it
  in the same run.
