<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: toggle (Plan 2 Task 3). Proves field_default_value at top level, in a Grid
 * column and in a Fluid child, the TINYINT NOT NULL column it creates (default taken from the setting), the
 * stored 1/0 values, and that the Model path used here does NOT trigger save_settings()'s site-preference
 * write. down() removes everything cpsref*.
 */
class CpsrefToggle extends Migration
{
    const ON_BY_DEFAULT = 'cpsref_toggle';
    const OFF_BY_DEFAULT = 'cpsref_toggle_off';
    const GRID = 'cpsref_toggle_grid';
    const FLUID = 'cpsref_toggle_fluid';
    const COLUMN = 'cpsref_toggle_flag';
    const ENTRY = 'cpsref-toggle';

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

    /** exp_config value of search_reindex_needed (the preference toggle's save_settings() writes), or null. */
    private static function reindexFlag(): ?string
    {
        $row = ee()->db->select('value')->where('key', 'search_reindex_needed')->get('config')->row_array();

        return $row['value'] ?? null;
    }

    private function build(): void
    {
        $before = self::reindexFlag();

        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        // field_default_value is the only key save_settings() keeps (array_intersect_key against settings_vars)
        CpsRefFixture::makeField($group, self::ON_BY_DEFAULT, 'toggle', ['field_default_value' => '1'], 1);
        CpsRefFixture::makeField($group, self::OFF_BY_DEFAULT, 'toggle', ['field_default_value' => '0'], 2);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'toggle', 'label' => 'Flag', 'settings' => ['field_default_value' => '1']],
        ], 3);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::ON_BY_DEFAULT], 4);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::ON_BY_DEFAULT);

        // OFF_BY_DEFAULT is left out of the entry so the stored value is the column default
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::ON_BY_DEFAULT => 1,
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => 0]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => 1]]],
        ]);

        if (self::reindexFlag() !== $before) {
            throw new \RuntimeException('the Model path changed search_reindex_needed; save_settings() ran with a null field_id');
        }
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    /** SHOW COLUMNS row for a data column. */
    private static function dataColumn(string $table, string $column): array
    {
        $name = ee()->db->dbprefix . $table;

        return ee()->db->query('SHOW COLUMNS FROM `' . $name . '` LIKE ' . ee()->db->escape($column))->row_array() ?: [];
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];

        $on = CpsRefFixture::fieldSettings(self::ON_BY_DEFAULT);
        $off = CpsRefFixture::fieldSettings(self::OFF_BY_DEFAULT);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        CpsRefFixture::check($problems, array_key_exists('field_default_value', $on), 'field settings missing field_default_value');
        CpsRefFixture::check($problems, array_key_exists('field_default_value', $column), 'grid column settings missing field_default_value');
        CpsRefFixture::check($problems, (string) ($on['field_default_value'] ?? '') === '1', 'on-by-default setting should be 1');
        CpsRefFixture::check($problems, (string) ($off['field_default_value'] ?? '') === '0', 'off-by-default setting should be 0');

        // Storage: TINYINT NOT NULL whose DEFAULT is the setting (settings_modify_column())
        $onId = CpsRefFixture::fieldId(self::ON_BY_DEFAULT);
        $offId = CpsRefFixture::fieldId(self::OFF_BY_DEFAULT);
        $onColumn = self::dataColumn('channel_data_field_' . $onId, 'field_id_' . $onId);
        $offColumn = self::dataColumn('channel_data_field_' . $offId, 'field_id_' . $offId);
        CpsRefFixture::check($problems, stripos($onColumn['Type'] ?? '', 'tinyint') === 0, 'toggle column should be tinyint');
        CpsRefFixture::check($problems, ($onColumn['Null'] ?? '') === 'NO', 'toggle column should be NOT NULL');
        CpsRefFixture::check($problems, (string) ($onColumn['Default'] ?? '') === '1', 'column default should follow field_default_value = 1');
        CpsRefFixture::check($problems, (string) ($offColumn['Default'] ?? '') === '0', 'column default should follow field_default_value = 0');

        CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data_field_' . $onId, 'field_ft_' . $onId), 'ensureDefaultColumns() should still add field_ft_N');
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $gridColId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridColumn = self::dataColumn('channel_grid_field_' . $gridId, 'col_id_' . $gridColId);
        CpsRefFixture::check($problems, stripos($gridColumn['Type'] ?? '', 'tinyint') === 0, 'grid toggle column should be tinyint');
        CpsRefFixture::check($problems, ($gridColumn['Null'] ?? '') === 'NO' && (string) ($gridColumn['Default'] ?? '') === '1', 'grid toggle column should be NOT NULL DEFAULT 1');

        // Values
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::ON_BY_DEFAULT, $entryId) === '1', 'written 1 did not read back as 1');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::OFF_BY_DEFAULT, $entryId) === '0', 'unwritten field should hold its column default 0');

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check($problems, (string) ($rows[0]['col_id_' . $colId] ?? '') === '0', 'grid 0 did not read back');

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $onId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $onId)->row_array();
            CpsRefFixture::check($problems, (string) ($stored['v'] ?? '') === '1', 'fluid value did not read back');
        }

        // validate(): 1/0 pass, anything else is rejected
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));
        $entry->{'field_id_' . $onId} = '7';
        CpsRefFixture::check($problems, ! $entry->validate()->isValid(), 'toggle value 7 should fail validate()');

        return $problems;
    }
}
