<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: number (Plan 2 Task 2). Creates a numeric (FLOAT) field, an integer (INT) field and
 * a decimal (DECIMAL(10,4)) field to prove field_content_type drives the column type, plus a Grid column and a
 * Fluid child. Writes a value through each path and verifies the settings contract, storage and read-back.
 * down() removes everything cpsref*.
 */
class CpsrefNumber extends Migration
{
    const FIELD = 'cpsref_number';
    const FIELD_INT = 'cpsref_number_int';
    const FIELD_DECIMAL = 'cpsref_number_decimal';
    const GRID = 'cpsref_number_grid';
    const FLUID = 'cpsref_number_fluid';
    const COLUMN = 'cpsref_number_col';
    const ENTRY = 'cpsref-number';

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

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        // ft.number.php::save_settings() keeps exactly these five keys. validate() and display_field() read the
        // min/max/step/datalist keys by direct index, so all five must be present (empty string = unset).
        $numeric = [
            'field_min_value' => '0', 'field_max_value' => '100', 'field_step' => '0.5',
            'datalist_items' => '', 'field_content_type' => 'numeric',
        ];
        CpsRefFixture::makeField($group, self::FIELD, 'number', $numeric, 1);
        CpsRefFixture::makeField(
            $group,
            self::FIELD_INT,
            'number',
            array_merge($numeric, ['field_content_type' => 'integer', 'field_step' => '1']),
            2
        );
        CpsRefFixture::makeField(
            $group,
            self::FIELD_DECIMAL,
            'number',
            array_merge($numeric, ['field_content_type' => 'decimal', 'field_step' => '']),
            3
        );

        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'number', 'label' => 'Number column', 'settings' => $numeric],
        ], 4);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 5);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => '12.5',
            self::FIELD_INT => '42',
            self::FIELD_DECIMAL => '3.1416',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => '7.25']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => '99']]],
        ]);
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        $contract = ['field_min_value', 'field_max_value', 'field_step', 'datalist_items', 'field_content_type'];

        $field = CpsRefFixture::fieldSettings(self::FIELD);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $field), "field settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $intId = CpsRefFixture::fieldId(self::FIELD_INT);
        $decimalId = CpsRefFixture::fieldId(self::FIELD_DECIMAL);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $expected = [
            [self::FIELD, $fieldId, 'float'],
            [self::FIELD_INT, $intId, 'int(11)'],
            [self::FIELD_DECIMAL, $decimalId, 'decimal(10,4)'],
        ];
        foreach ($expected as [$name, $id, $sqlType]) {
            $actual = CpsRefFixture::columnType('channel_data_field_' . $id, 'field_id_' . $id);
            CpsRefFixture::check($problems, $actual === $sqlType, "$name column type is $actual, expected $sqlType");
        }
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        CpsRefFixture::check($problems, $gridType === 'float', "grid column type is $gridType, expected float");

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        $reads = [
            [self::FIELD, '12.5'],
            [self::FIELD_INT, '42'],
            [self::FIELD_DECIMAL, '3.1416'],
        ];
        foreach ($reads as [$name, $value]) {
            $actual = CpsRefFixture::fieldValue($name, $entryId);
            CpsRefFixture::check($problems, $actual === $value, "$name read back as " . var_export($actual, true));
        }

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check(
            $problems,
            (float) ($rows[0]['col_id_' . $colId] ?? -1) === 7.25,
            'grid value did not read back as 7.25'
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, (float) ($stored['v'] ?? -1) === 99.0, 'fluid value did not read back');
        }

        return $problems;
    }
}
