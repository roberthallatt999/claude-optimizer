<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: colorpicker (Plan 2 Task 2). Creates a swatch-restricted colour field, a Grid
 * column and a Fluid child, writes a value through each path and verifies the settings contract, storage and
 * read-back. down() removes everything cpsref*.
 */
class CpsrefColorpicker extends Migration
{
    const FIELD = 'cpsref_colorpicker';
    const GRID = 'cpsref_colorpicker_grid';
    const FLUID = 'cpsref_colorpicker_fluid';
    const COLUMN = 'cpsref_colorpicker_col';
    const ENTRY = 'cpsref-colorpicker';

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

        // ft.colorpicker.php::save_settings() keeps exactly these five keys. value_swatches is a flat list of
        // "#hex" or "#hex|Name" strings (the control panel posts rows and save_settings flattens them).
        $settings = [
            'allowed_colors' => 'swatches',
            'colorpicker_default_color' => '',
            'value_swatches' => ['#FF0000|Red', '#00FF00|Green'],
            'manual_swatches' => '',
            'populate_swatches' => 'v',
        ];
        CpsRefFixture::makeField($group, self::FIELD, 'colorpicker', $settings, 1);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'colorpicker', 'label' => 'Colour column', 'settings' => $settings],
        ], 2);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 3);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => '#FF0000',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => '#00FF00']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => '#FF0000']]],
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
        $contract = ['allowed_colors', 'colorpicker_default_color', 'value_swatches', 'manual_swatches', 'populate_swatches'];

        $field = CpsRefFixture::fieldSettings(self::FIELD);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $field), "field settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }
        CpsRefFixture::check(
            $problems,
            is_array($field['value_swatches'] ?? null) && count($field['value_swatches']) === 2,
            'value_swatches should be a 2-item array'
        );

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $type = CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId);
        CpsRefFixture::check($problems, $type === 'text', "colour column type is $type, expected text");
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        CpsRefFixture::check($problems, $gridType === 'text', "grid column type is $gridType, expected text");

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD, $entryId) === '#FF0000',
            'top-level value did not read back verbatim'
        );

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check(
            $problems,
            ($rows[0]['col_id_' . $colId] ?? null) === '#00FF00',
            'grid value did not read back'
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === '#FF0000', 'fluid value did not read back');
        }

        return $problems;
    }
}
