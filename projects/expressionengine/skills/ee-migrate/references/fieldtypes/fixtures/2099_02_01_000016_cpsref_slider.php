<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: slider ("Value Slider", Plan 2 Task 4). Proves the seven settings keys, that
 * field_content_type drives the column type (numeric FLOAT, integer INT, decimal DECIMAL(10,4), all TEXT), that
 * min/max are NOT enforced on the server (validate() and the Model path accept out-of-range values), and Grid /
 * Fluid use. down() removes everything cpsref*.
 */
class CpsrefSlider extends Migration
{
    const FIELD = 'cpsref_slider';
    const FIELD_INT = 'cpsref_slider_int';
    const FIELD_DECIMAL = 'cpsref_slider_decimal';
    const FIELD_ALL = 'cpsref_slider_all';
    const GRID = 'cpsref_slider_grid';
    const FLUID = 'cpsref_slider_fluid';
    const COLUMN = 'cpsref_slider_col';
    const ENTRY = 'cpsref-slider';

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

    private function settings(string $contentType): array
    {
        // ft.slider.php::save_settings() keeps exactly these seven keys; display_field() reads
        // field_min_value directly and the others through isset(), replace_prefix/suffix by direct index.
        return [
            'field_min_value' => '0', 'field_max_value' => '100', 'field_step' => '5',
            'field_prefix' => '$', 'field_suffix' => ' pts', 'datalist_items' => '',
            'field_content_type' => $contentType,
        ];
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        CpsRefFixture::makeField($group, self::FIELD, 'slider', $this->settings('numeric'), 1);
        CpsRefFixture::makeField($group, self::FIELD_INT, 'slider', $this->settings('integer'), 2);
        CpsRefFixture::makeField($group, self::FIELD_DECIMAL, 'slider', $this->settings('decimal'), 3);
        CpsRefFixture::makeField($group, self::FIELD_ALL, 'slider', $this->settings('all'), 4);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'slider', 'label' => 'Slider', 'settings' => $this->settings('integer')],
        ], 5);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 6);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => '35.5',
            self::FIELD_INT => '40',
            self::FIELD_DECIMAL => '12.3456',
            self::FIELD_ALL => '250',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => '65']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => '80']]],
        ]);
        // 250 is above field_max_value (100) in FIELD_ALL: nothing server-side stops it.
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
        $check(($field['field_prefix'] ?? null) === '$' && ($field['field_suffix'] ?? null) === ' pts', 'prefix/suffix not stored');

        $expected = [
            [self::FIELD, 'float'], [self::FIELD_INT, 'int(11)'],
            [self::FIELD_DECIMAL, 'decimal(10,4)'], [self::FIELD_ALL, 'text'],
        ];
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $values = [self::FIELD => '35.5', self::FIELD_INT => '40', self::FIELD_DECIMAL => '12.3456', self::FIELD_ALL => '250'];
        foreach ($expected as [$name, $sqlType]) {
            $id = CpsRefFixture::fieldId($name);
            $actual = CpsRefFixture::columnType('channel_data_field_' . $id, 'field_id_' . $id);
            $check($actual === $sqlType, "$name column type is $actual, expected $sqlType");
            $read = CpsRefFixture::fieldValue($name, $entryId);
            $check($read === $values[$name], "$name read back as " . var_export($read, true));
        }

        $gridId = CpsRefFixture::fieldId(self::GRID);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        $check($gridType === 'int(11)', "grid column type is $gridType, expected int(11)");
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $check(count($rows) === 1, 'expected 1 grid row');
        $check((string) ($rows[0]['col_id_' . $colId] ?? '') === '65', 'grid value did not read back');

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $check(count($fluid) === 1, 'expected 1 fluid row');
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            $check((float) ($stored['v'] ?? -1) === 80.0, 'fluid value did not read back');
        }

        // Direct fieldtype calls
        ee()->load->library('session');
        ee()->api_channel_fields->include_handler('slider');
        $ft = new Slider_ft();
        $ft->settings = $this->settings('numeric');
        $check($ft->validate('500') === true, 'validate() must not enforce max (docs/UI clamp only)');
        $check($ft->validate('-40') === true, 'validate() must not enforce min');
        $check($ft->save('') === null, "save('') should be null for numeric content");
        $ft->settings = $this->settings('all');
        $check($ft->save('') === '', "save('') should stay '' for content type all");
        $check($ft->save_settings(['junk' => 1])['field_content_type'] === 'numeric', 'slider default content type is not numeric');
        $check(count($ft->save_settings([])) === 7, 'save_settings should keep exactly seven keys');
        $ft->settings = $this->settings('integer');
        $check(is_string($ft->validate('1.5')), 'validate(1.5) should fail for integer content');

        return $problems;
    }
}
