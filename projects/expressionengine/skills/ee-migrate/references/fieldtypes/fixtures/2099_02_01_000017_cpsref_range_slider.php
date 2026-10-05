<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: range_slider (Plan 2 Task 4). Proves the stored string format ("12|43", pipe via
 * encode_multi_field, sorted low to high), what save() accepts (array or string), that the default
 * field_content_type is 'all' (TEXT column) and that a numeric content type would create a column that cannot hold
 * the pair, plus Grid / Fluid use. down() removes everything cpsref*.
 */
class CpsrefRangeSlider extends Migration
{
    const FIELD = 'cpsref_range_slider';
    const FIELD_STRING = 'cpsref_range_slider_str';
    const FIELD_FLOAT = 'cpsref_range_slider_float';
    const GRID = 'cpsref_range_slider_grid';
    const FLUID = 'cpsref_range_slider_fluid';
    const COLUMN = 'cpsref_range_slider_col';
    const ENTRY = 'cpsref-range-slider';

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

    private function settings(string $contentType = 'all'): array
    {
        return [
            'field_min_value' => '0', 'field_max_value' => '100', 'field_step' => '1',
            'field_prefix' => '', 'field_suffix' => ' yrs', 'datalist_items' => '',
            'field_content_type' => $contentType,
        ];
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        CpsRefFixture::makeField($group, self::FIELD, 'range_slider', $this->settings(), 1);
        CpsRefFixture::makeField($group, self::FIELD_STRING, 'range_slider', $this->settings(), 2);
        // Trap: a numeric content type gives a FLOAT column, which cannot hold "12|43". Only the column type is read.
        CpsRefFixture::makeField($group, self::FIELD_FLOAT, 'range_slider', $this->settings('numeric'), 3);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'range_slider', 'label' => 'Range', 'settings' => $this->settings()],
        ], 4);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 5);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => [43, 12],                      // array, deliberately reversed: save() sorts it
            self::FIELD_STRING => '20|60',                // a string is stored as is
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => [30, 70]]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => [5, 15]]]],
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
        $check = function (bool $ok, string $message) use (&$problems) {
            CpsRefFixture::check($problems, $ok, $message);
        };

        $contract = [
            'field_min_value', 'field_max_value', 'field_step', 'field_prefix', 'field_suffix',
            'datalist_items', 'field_content_type',
        ];
        $field = CpsRefFixture::fieldSettings(self::FIELD);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach ($contract as $key) {
            $check(array_key_exists($key, $field), "field settings missing $key");
            $check(array_key_exists($key, $column), "grid column settings missing $key");
        }

        $id = CpsRefFixture::fieldId(self::FIELD);
        $check(CpsRefFixture::columnType('channel_data_field_' . $id, 'field_id_' . $id) === 'text', 'column is not text');
        $floatId = CpsRefFixture::fieldId(self::FIELD_FLOAT);
        $check(
            CpsRefFixture::columnType('channel_data_field_' . $floatId, 'field_id_' . $floatId) === 'float',
            'numeric content type did not create a float column'
        );

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $read = CpsRefFixture::fieldValue(self::FIELD, $entryId);
        $check($read === '12|43', 'array [43, 12] stored as ' . var_export($read, true) . ', expected 12|43');
        $readString = CpsRefFixture::fieldValue(self::FIELD_STRING, $entryId);
        $check($readString === '20|60', 'string 20|60 stored as ' . var_export($readString, true));

        $gridId = CpsRefFixture::fieldId(self::GRID);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        $check($gridType === 'text', "grid column type is $gridType, expected text");
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $check(count($rows) === 1, 'expected 1 grid row');
        $check(($rows[0]['col_id_' . $colId] ?? null) === '30|70', 'grid value stored as ' . var_export($rows[0]['col_id_' . $colId] ?? null, true));

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $check(count($fluid) === 1, 'expected 1 fluid row');
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $id . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $id)->row_array();
            $check(($stored['v'] ?? null) === '5|15', 'fluid value stored as ' . var_export($stored['v'] ?? null, true));
        }

        // Direct fieldtype calls
        ee()->load->library('session');
        ee()->api_channel_fields->include_handler('range_slider');
        $ft = new Range_slider_ft();
        $ft->settings = $this->settings();
        $check($ft->save([43, 12]) === '12|43', 'save(array) not sorted/pipe-joined');
        $check($ft->save(['9', '10']) === '10|9' || $ft->save(['9', '10']) === '9|10', 'save() output unexpected');
        $check($ft->save('12|43') === '12|43', 'save(string) should pass through');
        $check($ft->save('12 - 43') === '12 - 43', 'save() does not parse the display form "12 - 43"');
        $check($ft->save([7]) === '7', 'save([7]) should be 7');
        $check($ft->save([]) === '', 'save([]) should be empty string');
        $check($ft->save_settings([])['field_content_type'] === 'all', 'range_slider default content type is not all');

        return $problems;
    }
}
