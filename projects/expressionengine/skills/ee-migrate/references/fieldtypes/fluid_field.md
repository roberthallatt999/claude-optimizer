---
fieldtype: fluid_field
addon: fluid_field
origin: core
verified: 7.5.27
fixture: 2099_02_01_000024_cpsref_fluid_field
fixture_site: cps
grid: no
fluid: no
---
# fluid_field

Evidence: `system/ee/ExpressionEngine/Addons/fluid_field/` (`ft.fluid_field.php`, `Model/FluidField.php`,
`addon.setup.php`), `Model/Channel/ChannelField.php`, `Model/Content/FieldModel.php` (EE 7.5.27), the docs notes in
`EE-DOCS-NOTES.md`, and the fixture `fixtures/2099_02_01_000024_cpsref_fluid_field.php`.

Labels used below: **ASSERTED** = a deviation makes the fixture's `up()` throw or `verify()` fail. **PROBE** = observed
and printed as a `PROBE` line in the migrate log, not asserted. **SOURCE** = read from the PHP, not exercised.

## Settings contract

`ft.fluid_field.php::save_settings()` returns `array_intersect_key($all, $defaults)`, so only two keys persist:

| Key | PHP type | Default | Needed by |
|---|---|---|---|
| `field_channel_fields` | child `field_id` list (ints work; the CP posts strings) | `[]` | `validate()`, `display_field()` |
| `field_channel_field_groups` | list of field group ids | `[]` | `validate()`, `display_field()` |

Both keys exist in the stored settings ASSERTED (`verify()`); the fixture creates the field with ints and
`field_channel_field_groups => []`. Settings are stored as `base64_encode(serialize())` in
`exp_channel_fields.field_settings`.

Which fieldtypes may be children (SOURCE, `ft.fluid_field.php::display_settings()`): the control panel lists fields
with `field_type != 'fluid_field'` whose `getField()->acceptsContentType('fluid_field')` is true. The fieldtype's own
`accepts_content_type()` returns false for `grid` and `fluid_field`, so Fluid is neither a Grid column nor a Fluid
child (front matter `grid: no`, `fluid: no`). The docs notes list all native types except Fluid as children. The
fixture proved text, url, toggle, Grid (with a text column) and relationship as children (ASSERTED).

That list is only enforced by the control panel. `validate()` and `save()` accept a field not in the list
(`validate()` comment "the field might be present, but not in the settings currently"). A text field outside
`field_channel_fields` was written and stored (ASSERTED in `up()`, also a PROBE line).

## Storage

- Fluid field column: `exp_channel_data_field_F.field_id_F`, `mediumtext` (`settings_modify_column()`); holds the
  compiled search text, not the rows. Type ASSERTED. (PROBE: the column read back as an empty string for an entry.)
- `exp_fluid_field_data` (model `Model/FluidField.php`), column types ASSERTED: `id` int(11) unsigned, `fluid_field_id`,
  `entry_id`, `field_id`, `field_data_id` int(11) unsigned, `order` int(5) unsigned, `field_group_id` and `group`
  int(10) unsigned (nullable). One row per child value.
- Row meaning ASSERTED on a 6-row entry: `fluid_field_id` = the Fluid field, `entry_id` = the entry, `field_id` = the
  child field, `field_data_id` = the `id` of the child's own data row, `order` 1..n and `group` 1..n in write order,
  `field_group_id` NULL when no Fluid field group is used. (SOURCE: `post_save()` increments `group` per row when
  there is no field group.)
- Child value: stored in the CHILD's own `exp_channel_data_field_N` table, one row whose `entry_id` is 0
  (`addField()` merges `'entry_id' => 0`); `exp_fluid_field_data.field_data_id` points at its `id`. ASSERTED for text,
  url and toggle values and `entry_id = 0`. Each child table has its own `id` sequence, so `field_data_id` values
  repeat across different children.
- Grid child: rows in `exp_channel_grid_field_G` carry `fluid_field_data_id` = the `exp_fluid_field_data.id`
  (ASSERTED, `ft.grid.php` reads `settings['fluid_field_data_id']`).
- Relationship child: rows in `exp_relationships` carry `fluid_field_data_id` = the `exp_fluid_field_data.id`,
  `grid_field_id` 0, `parent_id` = the entry, `child_id` = the related entry (ASSERTED; source
  `ft.relationship.php`).
- Children are normally NOT attached to a field group; the fixture creates them with no group (ASSERTED to work).

## Create / change / remove

Create the children first (ids are needed), then the Fluid field. `CpsRefFixture::makeFluidField()` is the tested
path (`fixtures/CpsRefFixture.php`):

```php
$fluid = ee('Model')->make('ChannelField');
$fluid->site_id = (int) ee()->config->item('site_id');
$fluid->field_name = 'content_blocks';
$fluid->field_label = 'Content blocks';
$fluid->field_type = 'fluid_field';
$fluid->field_instructions = '';
$fluid->field_required = 'n';
$fluid->field_search = 'n';
$fluid->field_is_hidden = 'n';
$fluid->field_order = 10;
$fluid->legacy_field_data = 'n';
$fluid->field_settings = [
    'field_channel_fields' => [(int) $textField->field_id, (int) $urlField->field_id, (int) $gridField->field_id],
    'field_channel_field_groups' => [],
];
$fluid->ChannelFieldGroups = $group;
$fluid->save();   // creates exp_channel_data_field_F with field_id_F mediumtext
```

Grid children need `fetch_installed_fieldtypes()` before `grid_model` (see `grid.md`), and a relationship child needs
all 15 relationship keys with `channels` as strings (see `relationship.md`). Never use `table_exists()` to check a
table created in the same run; use `SHOW TABLES LIKE` (`CpsRefFixture::tableExists()`).

**Add a child** (ASSERTED): create the child field, then write the merged id list with a direct property write:

```php
$fluid = ee('Model')->get('ChannelField')->filter('field_name', 'content_blocks')->first();
$settings = $fluid->field_settings;
$settings['field_channel_fields'][] = (int) $newChild->field_id;
$fluid->field_settings = $settings;
$fluid->save();
```

**Remove a child from the list.** Two paths, with different results:

1. Direct property write (the migration style above) with the id removed: the Fluid rows and child data rows of that
   child are LEFT in place, orphaned (ASSERTED). Nothing cleans them; `save_settings()` is not called
   (`ChannelField::set()` is the only caller, `Model/Channel/ChannelField.php`).
2. `$fluid->set(['field_channel_fields' => $ids, 'field_channel_field_groups' => []]); $fluid->save();` runs
   `save_settings()` as the control panel does. It deleted the removed child's `exp_fluid_field_data` rows and its
   child data row (ASSERTED, run under eecli). Side effects: it logs an action and sets `search_reindex_needed` in
   `exp_config` (the fixture saves and restores that row, so a migration using this path should expect a reindex
   prompt in the control panel). Grid and relationship rows of a removed Grid/relationship child are NOT cleaned by
   this path (SOURCE: `save_settings()` only deletes `FluidField` models; `removeField()` is the only code that
   cleans Grid and relationship rows).

**Delete a child field:** `$childField->delete()` deletes every `exp_fluid_field_data` row for it, and with it the
child's data rows (ASSERTED; `ChannelField::onBeforeDelete()` -> `removeFromFluidFields()`). That method is meant to
strip the id from each Fluid field's `field_channel_fields`, but on 7.5.27 the id was still listed afterwards (PROBE:
it persisted a hand-written copy of the same logic fine, cause not found). After deleting a child, write the list
again without the id. The fixture does exactly that and asserts the final list.

**Remove the Fluid field:** `$fluid->delete()` (`settings_modify_column()` with `ee_action = delete` deletes its
`exp_fluid_field_data` rows; `FluidField::onAfterDelete()` deletes the simple child data rows). With data present
this leaves behind (PROBE, then cleaned by the fixture): the Grid child rows and the relationship child rows of the
deleted rows (1 each). A later delete of the entry removed the relationship rows but NOT the Grid rows (PROBE).
Prefer deleting the entries' Fluid content first, or delete the entries (see Rollback).

Source quirk, not exercised: `save_settings()` computes `$removed_groups` from
`$this->settings['field_channel_fields']` (the field list) instead of `field_channel_field_groups`, then deletes
`FluidField` rows whose `field_group_id` is in it. Rows without a field group are unaffected; a Fluid field group id
equal to a removed child's field id would lose rows. Fluid field groups (`field_channel_field_groups`) are
otherwise not covered by the fixture (SOURCE only; `validate()` and `display_field()` read them).

## Content writes

Write through the Model so the fieldtype's `save()` / `post_save()` run. Shape ASSERTED (new entry and existing
entry):

```php
$entry->field_id_F = ['fields' => [
    'new_field_1' => ['field_id_T' => 'alpha'],                                            // text
    'new_field_2' => ['field_id_G' => ['rows' => ['new_row_1' => ['col_id_C' => 'g1']]]],  // Grid child
    'new_field_3' => ['field_id_R' => ['data' => [$relatedEntryId]]],                      // relationship child
    'new_field_4' => ['field_id_U' => 'https://example.com'],                              // url
    'new_field_5' => ['field_id_B' => 1],                                                  // toggle
]];
```

Each element is ONE child value, keyed `field_id_<child field id>`; a child value takes whatever that child's own
`save()` expects (Grid `rows`, relationship `data`). Repeating a child (two text rows) is fine.

Update, reorder, append, delete (ASSERTED on an existing entry):

- Update an existing row with the key `field_<exp_fluid_field_data.id>`; the row id and its child data row are kept.
  A Grid child updates its rows with `row_id_<n>` and appends with `new_row_N`; the Grid rows keep their
  `fluid_field_data_id`.
- Append with `new_field_N`.
- Row order is the PHP array order: `order` is reassigned 1..n on every write (rows moved first came back first).
- Any existing row NOT present in the array is deleted: its `exp_fluid_field_data` row, its child data row, and for
  Grid and relationship children their `exp_channel_grid_field_G` / `exp_relationships` rows
  (`ft.fluid_field.php::removeField()`). Writing an empty `fields` array deletes every row.
- Set `$entry->edit_date = ee()->localize->now` before `save()` when only custom fields changed; otherwise the Model
  skips the save and nothing is written (same defect as Grid).
- PROBE: updated rows come back with `field_group_id` 0 where new rows have NULL (`save()` assigns the undefined
  `$field_group_id`). `ft.fluid_field.php` also raises `E_WARNING: Undefined variable $field_group_id` on every
  write; the rows are still correct.
- A Fluid field group row uses the first key `field_group_id_<n>` inside the element (SOURCE: `save()`,
  `post_save()`); not exercised.

Pitfalls, each with a fix:

- **Second write to the same entry in the same request fails.** `ft.fluid_field.php::getFieldData()` caches the
  entry's rows in the session under class `FluidField`, key `FluidField/<fluid id>/<entry id>`, and the first save
  of a new entry caches it empty. Writing `field_<id>` again then dies with
  `Error: Call to a member function getFieldData() on null` (PROBE; the update that clears the cache is ASSERTED):

  ```php
  ee()->session->set_cache('FluidField', 'FluidField/' . $fluidFieldId . '/' . $entryId, false);
  ```

- **A Fluid field created after an entry was saved in the same request is silently dropped** (PROBE: 0 rows
  written; ASSERTED: 1 row once the cache is cleared). `Channel::getAllCustomFields()` caches the channel's field
  list in the session:

  ```php
  ee()->session->set_cache(
      \ExpressionEngine\Model\Channel\Channel::class,
      'ChannelCustomFields/' . $channelId . '/',
      false
  );
  ```

  Fluid children are not affected (Fluid reads them through `ChannelField` directly). Whether the cache is warm
  differs per environment, so always clear it and read the rows back.
- Writes do not validate. Call `$entry->validate()` first for untrusted values.

## Rollback

`down()` is `CpsRefFixture::removeAll()`: entries first (this removes the Fluid rows, child data rows and the
relationship rows), then channel, then fields with Fluid first and Grid second, then Grid columns, then the field
group; the helper also drops data tables a same-request delete leaves behind. After it, the fixture reports 0
`cpsref%` rows and the schema byte-identical (`run-fixtures.sh`).

Points that matter for real migrations:

- Deleting an entry removes its `exp_fluid_field_data` rows, the child data rows and the relationship rows, but NOT
  the `exp_channel_grid_field_G` rows of a Grid that is a Fluid child (PROBE: 2 rows left; source: Grid's `delete()`
  is only called for the entry's own fields and `FluidField::onAfterDelete()` only deletes the child data row). Delete
  them with SQL by `entry_id` (the fixture does).
- Removing a child or the Fluid field with data is not reversible without a backup; keep a database backup.
- Settings changes are reversible by restoring the previous `field_channel_fields` array.
- Orphan check (also run by `verify()`): child data rows with `entry_id = 0` must equal the `exp_fluid_field_data`
  rows for that child.

## Verification

`run-fixtures.sh ../cps fluid_field` printed `PASS fluid_field` twice in a row on cps (EE 7.5.27, 2026-10-05),
leaving the schema byte-identical.

`verify()` asserts: both settings keys, the five base children listed and the deleted ones absent; the `mediumtext`
column and `fluid_field_data` column types; a 6-row entry (field ids, `order`, `group`, NULL `field_group_id`, text,
url and toggle values, `entry_id = 0` on child rows, Grid rows tagged with the Fluid row id, the relationship row with
`grid_field_id` 0); a mutated entry (3 rows, new order, no Grid or relationship rows); no orphan child, Grid or
relationship rows.

SQL:

```sql
SELECT * FROM exp_fluid_field_data WHERE fluid_field_id = <F> AND entry_id = <E> ORDER BY `order`;
SELECT * FROM exp_channel_data_field_<N> WHERE id = <field_data_id>;            -- entry_id = 0
SELECT * FROM exp_channel_grid_field_<G> WHERE fluid_field_data_id = <fluid_row_id>;
SELECT * FROM exp_relationships WHERE parent_id = <E> AND fluid_field_data_id = <fluid_row_id>;
SELECT field_settings FROM exp_channel_fields WHERE field_type = 'fluid_field';  -- base64 serialized
```

CLI: `cps:migrate-verify <migration>`; `cps:schema-check`.

## Gotchas

- Never run `migrate` or `migrate:rollback` by hand to test a fixture: `eecli migrate` exits 0 even when `up()`
  throws, and a blind rollback undoes the previous real migration (it happened once while building this fixture).
- A direct settings write is not `save_settings()`: removing a child that way orphans its rows; the `set()` path
  cleans simple rows but sets `search_reindex_needed`.
- Deleting a child field does not reliably strip it from `field_channel_fields` (observed on 7.5.27); rewrite the list.
- The list of children is not enforced on write; only the control panel limits it.
- The FluidField session cache breaks a second write to the same entry in one request; the channel field-list
  cache silently drops writes to a Fluid field created later in the request (same family as the relationship
  no-op: `field_id_N = ['data' => ...]` written nothing when the field was created earlier in the run). Read rows
  back after every write.
- `ee()->db->table_exists()` answers from a table list cached per request (`legacy/database/DB_driver.php::
  table_exists()`/`list_tables()`), so code such as `FluidField::onAfterDelete()` (which guards on it) can skip
  deleting a child data row whose table was created earlier in the same request (SOURCE; in this fixture the probe
  printed `true`, and the fixture resets `ee()->db->data_cache['table_names']` anyway). Use `SHOW TABLES LIKE` in
  your own checks and never `table_exists()`.
- Grid children: call `ee()->api_channel_fields->fetch_installed_fieldtypes()` before any `grid_model` use or the
  columns silently fail to save.
- Relationship children: `channels` must be strings; an empty `order_field` or integer channels return a 500 on the
  publish screen (see `relationship.md`).
- Deleting an entry leaves the Grid rows of a Fluid-child Grid; deleting the Fluid field leaves Grid and
  relationship rows of its rows. Clean them by SQL on `entry_id` / `fluid_field_data_id`.
- `save_settings()` has a field-groups bug (reads the field list instead of the group list); avoid Fluid field
  groups unless you test them.
- Fluid is not supported in Channel Form and has no conditional fields (docs notes).
