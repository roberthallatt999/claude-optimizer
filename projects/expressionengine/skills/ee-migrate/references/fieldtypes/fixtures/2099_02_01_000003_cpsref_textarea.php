<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: textarea (Plan 2 Task 2). Creates a textarea field, a MEDIUMTEXT textarea field
 * (proves db_column_type drives the column type), a Grid column and a Fluid child, writes a value through each
 * path and verifies the settings contract, storage and read-back. down() removes everything cpsref*.
 */
class CpsrefTextarea extends Migration
{
    const FIELD = 'cpsref_textarea';
    const FIELD_MEDIUM = 'cpsref_textarea_medium';
    const GRID = 'cpsref_textarea_grid';
    const FLUID = 'cpsref_textarea_fluid';
    const COLUMN = 'cpsref_textarea_col';
    const ENTRY = 'cpsref-textarea';
    const TOP_VALUE = "Line one\nLine <b>two</b> & three";

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

        // ft.textarea.php::save_settings() keeps exactly these four keys in field_settings; the three native
        // columns (field_ta_rows, field_text_direction, field_fmt) live on exp_channel_fields itself.
        $settings = [
            'field_show_file_selector' => 'n', 'db_column_type' => 'text',
            'field_show_smileys' => 'n', 'field_show_formatting_btns' => 'n',
        ];
        $native = ['field_ta_rows' => 6, 'field_text_direction' => 'ltr', 'field_fmt' => 'none'];
        CpsRefFixture::makeField($group, self::FIELD, 'textarea', $settings, 1, $native);
        CpsRefFixture::makeField(
            $group,
            self::FIELD_MEDIUM,
            'textarea',
            array_merge($settings, ['db_column_type' => 'mediumtext']),
            2,
            $native
        );

        // Grid column: grid_save_settings() = array_merge(save_settings($data), $data), so the four keys plus
        // whatever the grid posted (the native keys) are stored in col_settings.
        $gridSettings = array_merge($settings, [
            'db_column_type' => 'mediumtext', 'field_fmt' => 'none', 'field_text_direction' => 'ltr',
            'field_ta_rows' => 6, 'field_required' => 'n',
        ]);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'textarea', 'label' => 'Textarea column', 'settings' => $gridSettings],
        ], 3);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 4);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => self::TOP_VALUE,
            self::FIELD_MEDIUM => 'medium text',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => 'grid area']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => 'fluid area']]],
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
        $contract = ['field_show_file_selector', 'db_column_type', 'field_show_smileys', 'field_show_formatting_btns'];

        $field = CpsRefFixture::fieldSettings(self::FIELD);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $field), "field settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }
        foreach (['field_fmt', 'field_text_direction', 'field_ta_rows'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }
        CpsRefFixture::check(
            $problems,
            (int) CpsRefFixture::nativeColumn(self::FIELD, 'field_ta_rows') === 6,
            'native field_ta_rows column is not 6'
        );

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $mediumId = CpsRefFixture::fieldId(self::FIELD_MEDIUM);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $type = CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId);
        CpsRefFixture::check($problems, $type === 'text', "text column type is $type, expected text");
        $mediumType = CpsRefFixture::columnType('channel_data_field_' . $mediumId, 'field_id_' . $mediumId);
        CpsRefFixture::check($problems, $mediumType === 'mediumtext', "medium column type is $mediumType");
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        CpsRefFixture::check($problems, $gridType === 'mediumtext', "grid column type is $gridType, expected mediumtext");

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        // textarea::save() is the EE_Fieldtype default (raw string).
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD, $entryId) === self::TOP_VALUE,
            'top-level value did not read back verbatim'
        );
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD_MEDIUM, $entryId) === 'medium text',
            'mediumtext value did not read back'
        );

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check(
            $problems,
            ($rows[0]['col_id_' . $colId] ?? null) === 'grid area',
            'grid value did not read back'
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === 'fluid area', 'fluid value did not read back');
        }

        return $problems;
    }
}
