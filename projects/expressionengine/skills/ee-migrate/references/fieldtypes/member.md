---
fieldtype: member
addon: member
origin: core
verified: 7.5.27
fixture: 2099_02_01_000020_cpsref_member
fixture_site: cfk
grid: yes
fluid: yes
---
# member

Evidence: `system/ee/ExpressionEngine/Addons/member/ft.member.php` and `addon.setup.php`, its parent
`Addons/relationship/ft.relationship.php` (`save()`, `post_save()`, `delete()`, `validate()`,
`accepts_content_type()`, `settings_modify_column()`), `legacy/fieldtypes/EE_Fieldtype.php`, EE 7.5.27, and the
passing fixture `fixtures/2099_02_01_000020_cpsref_member.php` (`run-fixtures.sh <site> member`; run on cfk,
which has no `member` fields of its own). Official docs: see `EE-DOCS-NOTES.md`.

`Member_ft extends Relationship_ft` with `$_table = 'member_relationships'`. Almost everything below is the
relationship fieldtype pointed at members instead of entries.

## Settings contract

`save_settings()` converts the three yes/no keys to booleans, collapses any array containing `'--'` ("any role")
to `[]`, merges over `$default_settings` and keeps ONLY those nine keys (`array_intersect_key`):

| Key | PHP type | Default | Docs label | Absence |
|---|---|---|---|---|
| `roles` | array of role ids (strings from the CP form); `[]` = any role | `'--'` in `$default_settings`, stored as `[]` | Roles to include (primary role only) | `display_field()` runs `count($this->settings['roles'])`, so a missing key is a warning; always write it. Filter is on the member's PRIMARY role (`PrimaryRole.role_id IN`) |
| `limit` | int | `100` | Maximum members listed | `0`/empty means no limit on the picker list |
| `order_field` | string `'screen_name'` or `'join_date'` | `'screen_name'` | Order by | picker order only; not the stored order |
| `order_dir` | string `'asc'`/`'desc'` | `'asc'` | (docs name no direction) | treated as `desc` unless exactly `'asc'` |
| `allow_multiple` | bool | `true` | Allow multiple selections | falsy = single dropdown, `rel_min`/`rel_max` ignored |
| `rel_min` | int | `0` | Minimum selection | `validate()` only checks it when `allow_multiple` is truthy |
| `rel_max` | int or `''` | `''` | Maximum selection | `''` means no maximum |
| `display_member_id` | bool | `false` | Display member IDs | none; display only |
| `deferred_loading` | bool | `false` | Defer initialization | none; display only |

`validate_settings()` (CP only) requires `rel_min` natural and `rel_max` natural non-zero; the Model path does not
run it. All nine keys round-trip through `field_settings` (fixture checked each, including the Grid column's
`col_settings`). The docs list every key except `order_dir`.

Resolve roles by NAME, never by id:

```php
$role = ee()->db->select('role_id')->where('name', 'Members')->get('roles')->row_array();
$settings['roles'] = [(string) $role['role_id']];
```

(The fixture picks the primary role of the lowest member and looks it up by name; role names vary per site.)

## Storage

- **The selection is not in the field's column.** `settings_modify_column()` (inherited) creates a dummy
  `field_id_N varchar(8)` that stays NULL (fixture: column type `varchar(8)`, value `NULL`), plus
  `field_ft_N tinytext`, on `exp_channel_data_field_N`.
- **`exp_member_relationships`** is the storage (same shape as `exp_relationships`; the table already exists
  on every site, `install()` returns true):

  | Column | Meaning |
  |---|---|
  | `parent_id` | the channel entry id |
  | `child_id` | the member id |
  | `field_id` | the member field id; for a Grid column it is the COLUMN id |
  | `order` | 1-based position in the submitted array |
  | `grid_field_id`, `grid_col_id`, `grid_row_id` | 0 at top level; Grid field id, column id and `channel_grid_field_G.row_id` for a Grid cell |
  | `fluid_field_data_id` | 0 unless the field is a Fluid child; then the `exp_fluid_field_data.id` of its row |

  Fixture proof: `['data' => [$second, $first]]` wrote two rows with `child_id` `[74, 43]` and `order` `[1, 2]`;
  the Grid cell row had `field_id = grid_col_id = <column id>`, `grid_field_id = <Grid field>`,
  `grid_row_id = <row_id>`; the Fluid child row had `fluid_field_data_id = <fluid_field_data.id>`.
- Settings: `field_settings` is `base64_encode(serialize($array))`; Grid `col_settings` is JSON (all nine keys).
- Reading back: `Member_ft::pre_process()` returns `[member_id => order]`, ordered by `order`. Fixture proof via
  the entry's `getCustomField()->getNativeField()`, setting `field_id` and `row['entry_id']`:
  `[74 => 1, 43 => 2]` for the Model-written entry and `[43 => 1, 74 => 2]` for the direct-insert entry.
- Member ids belong to `exp_members` (cfk: lowest id 43; member 1 does not exist everywhere).

## Create / change / remove

`accepts_content_type()` is inherited from `Relationship_ft` and returns true for `channel`, `grid` and
`fluid_field`; all three shapes were created and written in the fixture.

Top-level field (`CpsRefFixture::makeField()`):

```php
$field = ee('Model')->make('ChannelField');
$field->site_id = (int) ee()->config->item('site_id');
$field->field_name = 'example_member';
$field->field_label = 'Example';
$field->field_type = 'member';
$field->field_instructions = '';
$field->field_required = 'n';
$field->field_search = 'n';
$field->field_is_hidden = 'n';
$field->field_order = 1;
$field->legacy_field_data = 'n';
$field->field_settings = [
    'roles' => [], 'limit' => 100, 'order_field' => 'screen_name', 'order_dir' => 'asc',
    'allow_multiple' => true, 'rel_min' => 0, 'rel_max' => '',
    'display_member_id' => false, 'deferred_loading' => false,
];
$field->ChannelFieldGroups = $group;
$field->save();
```

Grid column (prerequisites: `ee()->legacy_api->instantiate('channel_fields'); ee()->api_channel_fields->fetch_installed_fieldtypes();` BEFORE `ee()->load->model('grid_model')`; `field_id` and `content_type` go INSIDE the array):

```php
ee()->grid_model->create_field($gridField->field_id, 'channel');   // once per Grid field
ee()->grid_model->save_col_settings([
    'field_id' => $gridField->field_id, 'content_type' => 'channel',
    'col_order' => 0, 'col_type' => 'member', 'col_label' => 'Member', 'col_name' => 'member',
    'col_instructions' => '', 'col_required' => 'n', 'col_search' => 'n', 'col_width' => 0,
    'col_settings' => json_encode($settings),   // the same nine keys
], false, 'channel');
```

Fluid child: create the field as above, then a `fluid_field` whose settings are
`['field_channel_fields' => [(int) $field->field_id], 'field_channel_field_groups' => []]`.

Change: merge into `field_settings` and `save()` (settings only). Remove: `$field->delete()`; the inherited
`settings_modify_column()` with `ee_action = 'delete'` clears that field's rows from `exp_member_relationships`
(source: `_clear_defunct_relationships()`; the fixture proved the table is empty after teardown, through entry
delete plus field delete together).

## Content writes

The tested path is the Model, exactly like `relationship`:

```php
$key = 'field_id_' . $fieldId;
$entry->$key = ['data' => [$memberId1, $memberId2]];     // order = array position, starting at 1
$entry->save();
// Grid cell: ['rows' => ['new_row_1' => ['col_id_C' => ['data' => [$memberId]]]]]
// Fluid child: ['fields' => ['new_field_1' => ['field_id_N' => ['data' => [$memberId]]]]]
```

`Relationship_ft::save()` caches the ids and returns NULL (so the column stays NULL); `post_save()` deletes the
entry's old rows for that field and `insert_batch()`es the new ones, filtering non-numeric ids. Result on cfk:
all three shapes wrote their rows, **including fields created earlier in the same migration run**.

The known `relationship` pitfalls apply and were NOT reproduced here, so keep the guard: (1) `Collection::add()`
writes nothing unless the collection carries its association, which is why this path assigns `field_id_N`
instead; (2) a `post_save` can no-op for a field created earlier in the same request (seen on staging for
`relationship`, environment dependent). Always count the rows back and fall back to the direct insert, which the
fixture proves produces rows the fieldtype reads identically:

```php
$count = ee()->db->where(['parent_id' => $entryId, 'field_id' => $fieldId, 'grid_col_id' => 0,
    'grid_field_id' => 0, 'grid_row_id' => 0, 'fluid_field_data_id' => 0])->count_all_results('member_relationships');
if ($count !== count($memberIds)) {
    ee()->db->where(['parent_id' => $entryId, 'field_id' => $fieldId, 'grid_col_id' => 0,
        'grid_field_id' => 0, 'grid_row_id' => 0, 'fluid_field_data_id' => 0])->delete('member_relationships');
    foreach (array_values($memberIds) as $index => $memberId) {
        ee()->db->insert('member_relationships', [
            'parent_id' => $entryId, 'child_id' => $memberId, 'field_id' => $fieldId, 'order' => $index + 1,
            'grid_field_id' => 0, 'grid_col_id' => 0, 'grid_row_id' => 0, 'fluid_field_data_id' => 0,
        ]);
    }
}
```

`save()` does not call `validate()`. `validate()` is the place `rel_min`/`rel_max`/`field_required` are enforced
(fixture: two members fail `rel_max = 1`, one passes; it does not check that ids exist or match `roles`).
Use an existing member id (`SELECT MIN(member_id) FROM exp_members`).

## Rollback

`down()` removes the entries (the inherited `delete()` clears their `exp_member_relationships` rows), the Fluid
field, the Grid field and its `grid_columns` rows, the member fields, the field group and the channel
(`CpsRefFixture::removeAll()`); the table held 0 rows afterwards. Deleting a `member` field that holds real
selections drops those rows: `backup-only rollback`. Settings-only changes are reversible from the previous
`field_settings`.

## Verification

- Settings: `unserialize(base64_decode(field_settings))` has the nine keys; Grid `col_settings` the same.
  `SELECT field_id, field_name, field_settings FROM exp_channel_fields WHERE field_type = 'member';`
- Roles resolve: `SELECT role_id, name FROM exp_roles;` for every id in `roles`.
- Rows: `SELECT parent_id, child_id, field_id, `order`, grid_field_id, grid_col_id, grid_row_id,
  fluid_field_data_id FROM exp_member_relationships WHERE parent_id = <entry> ORDER BY field_id, `order`;`
  and every `child_id` exists in `exp_members`.
- Column: `SHOW COLUMNS FROM exp_channel_data_field_N LIKE 'field_id_N'` is `varchar(8)` and the value is NULL.
- `$entry->validate()->isValid()`.
- CLI: `cps:migrate-verify <migration>`; `cps:schema-check`; `run-fixtures.sh <site> member` prints `PASS member`.

## Gotchas

- The selection lives in `exp_member_relationships`, not in the field column; a migration that only writes the
  column writes nothing.
- Read the rows back after every write (see Content writes); the direct insert is the proven fallback.
- Booleans, not `'y'`/`'n'`: `allow_multiple`, `display_member_id` and `deferred_loading` are PHP booleans after
  `save_settings()`; `$default_settings` still shows `'y'`/`'n'` and `roles => '--'`, which a form post turns into
  booleans and `[]`.
- A Grid cell's relationship rows are keyed by the COLUMN id (`field_id` and `grid_col_id` both hold it) and the
  Grid `row_id`; deleting and re-creating Grid rows orphans them unless the Grid save runs.
- Source finding, not exercised by the fixture: `Member_ft` inherits `Relationship_ft::delete($ids)`, which runs
  `WHERE parent_id IN (ids) OR child_id IN (ids)` on `member_relationships` with ENTRY ids; deleting an entry whose id
  equals some member id also deletes that member's selections in other entries. Entry ids and member ids rarely
  collide, but a bulk entry delete can hit it.
- `roles` filters on the member's primary role only (docs say the same).
- The CP posts `roles` as strings; the fixture writes strings.
- Writing a Fluid value through the Model may log a harmless `E_WARNING: Undefined variable $field_group_id`
  from `ft.fluid_field.php`; the row is still written.
- `eecli migrate` exits 0 even when `up()` throws; judge success from `exp_migrations` (`run-fixtures.sh` does).
- Member id 1 does not exist on every site; `makeEntry()` resolves a real `author_id`.
