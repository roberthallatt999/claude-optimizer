<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: member (Plan 2 Task 5). Member extends Relationship_ft, so the selection is not in
 * the field's own column but in exp_member_relationships (parent_id = entry, child_id = member, order from 1).
 * Proves the settings contract (roles resolved by NAME), the Model write path (field_id_N = ['data' => [ids]])
 * at top level, as a Grid column and as a Fluid child, the direct-insert fallback, and that the fieldtype reads
 * the rows back. down() removes every cpsref* row; entry delete and field delete clear the relationship rows.
 */
class CpsrefMember extends Migration
{
    const FIELD = 'cpsref_member';
    const LIMITED = 'cpsref_member_limited';
    const GRID = 'cpsref_member_grid';
    const COL = 'cpsref_member_col';
    const FLUID = 'cpsref_member_fluid';
    const ENTRY = 'cpsref-member';
    const DIRECT = 'cpsref-member-direct';

    public function up()
    {
        try {
            $this->build();
        } catch (\Throwable $e) {
            try {
                CpsRefFixture::removeAll();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    /** The two lowest existing member ids (member 1 may not exist; on cfk the lowest is 43). Private helper. */
    private static function memberIds(): array
    {
        $rows = ee()->db->select('member_id')->order_by('member_id')->limit(2)->get('members')->result_array();
        if (count($rows) < 2) {
            throw new \RuntimeException('need two existing members');
        }

        return array_map('intval', array_column($rows, 'member_id'));
    }

    /** Role id by NAME, taken from the primary role of the lowest member so a real role is used. */
    private static function roleIdOfMember(int $memberId): int
    {
        $member = ee()->db->select('role_id')->where('member_id', $memberId)->get('members')->row_array();

        return (int) ($member['role_id'] ?? 0);
    }

    /** The full settings shape (the nine keys save_settings() returns; booleans, not 'y'/'n'). */
    private static function settings(array $override = []): array
    {
        return array_merge([
            'roles' => [], 'limit' => 100, 'order_field' => 'screen_name', 'order_dir' => 'asc',
            'allow_multiple' => true, 'rel_min' => 0, 'rel_max' => '', 'display_member_id' => false,
            'deferred_loading' => false,
        ], $override);
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        [$first, $second] = self::memberIds();
        $roleId = self::roleIdOfMember($first);
        $roleName = ee()->db->select('name')->where('role_id', $roleId)->get('roles')->row_array()['name'] ?? '';
        if ($roleName === '') {
            throw new \RuntimeException('primary role of the lowest member not found');
        }
        // Resolve the role by NAME at migration time (ids differ per site)
        $roleByName = ee()->db->select('role_id')->where('name', $roleName)->get('roles')->row_array();

        CpsRefFixture::makeField($group, self::FIELD, 'member', self::settings(), 1);
        CpsRefFixture::makeField($group, self::LIMITED, 'member', self::settings([
            'roles' => [(string) $roleByName['role_id']], 'limit' => 50, 'order_field' => 'join_date',
            'order_dir' => 'desc', 'rel_min' => 1, 'rel_max' => '1', 'display_member_id' => true,
            'deferred_loading' => true,
        ]), 2);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL, 'type' => 'member', 'label' => 'Member', 'settings' => self::settings()],
        ], 3);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 4);

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $col = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        // Model path: field_id_N = ['data' => [member ids]]; order is the position in the array, starting at 1
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => ['data' => [$second, $first]],
            self::LIMITED => ['data' => [$first]],
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $col => ['data' => [$first]]]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => ['data' => [$second]]]]],
        ]);

        // Fallback path: a second entry written with direct inserts (what a failed post_save would have written)
        $directId = CpsRefFixture::makeEntry(self::DIRECT, []);
        foreach ([$first, $second] as $index => $memberId) {
            ee()->db->insert('member_relationships', [
                'parent_id' => $directId, 'child_id' => $memberId, 'field_id' => $fieldId, 'order' => $index + 1,
                'grid_field_id' => 0, 'grid_col_id' => 0, 'grid_row_id' => 0, 'fluid_field_data_id' => 0,
            ]);
        }
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    /** Relationship rows for an entry and field (top level unless $extra says otherwise), in order. */
    private static function rows(int $entryId, int $fieldId, array $extra = []): array
    {
        $where = array_merge(['parent_id' => $entryId, 'field_id' => $fieldId], $extra);

        return ee()->db->where($where)->order_by('order')->get('member_relationships')->result_array();
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        [$first, $second] = self::memberIds();
        $contract = ['roles', 'limit', 'order_field', 'order_dir', 'allow_multiple', 'rel_min', 'rel_max', 'display_member_id', 'deferred_loading'];

        // Settings contract: exactly the nine keys, booleans as booleans, roles as an array of role ids
        $plain = CpsRefFixture::fieldSettings(self::FIELD);
        $limited = CpsRefFixture::fieldSettings(self::LIMITED);
        $grid = CpsRefFixture::gridColumnSettings(self::GRID, self::COL);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $plain), "top-level settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $limited), "limited settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $grid), "grid column settings missing $key");
        }
        CpsRefFixture::check($problems, ($plain['roles'] ?? null) === [], 'any-role should be an empty roles array');
        CpsRefFixture::check($problems, ($plain['allow_multiple'] ?? null) === true, 'allow_multiple should be boolean true');
        CpsRefFixture::check($problems, count($limited['roles'] ?? []) === 1, 'limited roles should hold one role id');

        // Storage: the field's own column is a dummy (varchar(8), always NULL); the selection is in member_relationships
        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $table = 'channel_data_field_' . $fieldId;
        CpsRefFixture::check($problems, CpsRefFixture::columnType($table, 'field_id_' . $fieldId) === 'varchar(8)', 'data column type is ' . CpsRefFixture::columnType($table, 'field_id_' . $fieldId));
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::FIELD, $entryId) === null, 'the field column should stay NULL');
        CpsRefFixture::check($problems, CpsRefFixture::tableExists('member_relationships'), 'member_relationships table missing');

        // Model write path: rows, child ids and order (1-based, array position)
        $rows = self::rows($entryId, $fieldId, ['grid_field_id' => 0, 'fluid_field_data_id' => 0]);
        CpsRefFixture::check($problems, array_map('intval', array_column($rows, 'child_id')) === [$second, $first], 'top-level children/order wrong: ' . json_encode($rows));
        CpsRefFixture::check($problems, array_map('intval', array_column($rows, 'order')) === [1, 2], 'order should be 1, 2');

        // Grid: field_id and grid_col_id carry the COLUMN id, grid_field_id the Grid field, grid_row_id the row id
        $gridFieldId = CpsRefFixture::fieldId(self::GRID);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $gridRows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($gridRows) === 1, 'expected 1 grid row, found ' . count($gridRows));
        $gridRelations = ee()->db->where(['parent_id' => $entryId, 'grid_field_id' => $gridFieldId, 'grid_col_id' => $colId])->get('member_relationships')->result_array();
        CpsRefFixture::check($problems, count($gridRelations) === 1 && (int) $gridRelations[0]['child_id'] === $first, 'grid relationship row missing: ' . json_encode($gridRelations));
        CpsRefFixture::check($problems, count($gridRelations) === 1 && (int) $gridRelations[0]['grid_row_id'] === (int) ($gridRows[0]['row_id'] ?? -1), 'grid_row_id should equal the Grid row_id');
        CpsRefFixture::check($problems, count($gridRelations) === 1 && (int) $gridRelations[0]['field_id'] === $colId, 'grid relationship field_id should be the column id');

        // Fluid: fluid_field_data_id carries the fluid_field_data row id
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $fluidRelations = self::rows($entryId, $fieldId, ['fluid_field_data_id' => (int) $fluid[0]['id']]);
            CpsRefFixture::check($problems, count($fluidRelations) === 1 && (int) $fluidRelations[0]['child_id'] === $second, 'fluid relationship row missing: ' . json_encode($fluidRelations));
        }

        // Fallback path: direct inserts produce rows the fieldtype reads as the Model path's rows
        $directId = CpsRefFixture::entryId(self::DIRECT);
        CpsRefFixture::check($problems, $directId > 0, 'direct entry not found');
        $directRows = self::rows($directId, $fieldId, ['grid_field_id' => 0, 'fluid_field_data_id' => 0]);
        CpsRefFixture::check($problems, array_map('intval', array_column($directRows, 'child_id')) === [$first, $second], 'direct-insert rows missing');
        foreach ([[$entryId, [$second => 1, $first => 2]], [$directId, [$first => 1, $second => 2]]] as [$id, $want]) {
            $entry = ee('Model')->get('ChannelEntry', $id)->first();
            $facade = $entry->getCustomField('field_id_' . $fieldId);
            $fieldtype = $facade->getNativeField();
            $fieldtype->field_id = $fieldId;
            $fieldtype->row = ['entry_id' => $id];
            $got = $fieldtype->pre_process(null);
            CpsRefFixture::check($problems, $got === $want, 'pre_process() read ' . json_encode($got) . ' for entry ' . $id . ', expected ' . json_encode($want));
        }

        // validate(): rel_max / rel_min come from the settings (CP and entry validation, not Model save)
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $limitedId = CpsRefFixture::fieldId(self::LIMITED);
        $entry->{'field_id_' . $limitedId} = ['data' => [$first, $second]];
        CpsRefFixture::check($problems, ! $entry->validate()->isValid(), 'two members should fail rel_max = 1');
        $entry->{'field_id_' . $limitedId} = ['data' => [$first]];
        $valid = $entry->validate();
        CpsRefFixture::check($problems, $valid->isValid(), 'one member should pass: ' . json_encode($valid->getAllErrors()));

        return $problems;
    }
}
