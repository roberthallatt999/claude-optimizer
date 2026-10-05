<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: text (Plan 2 Task 2). Creates a free-text field, an integer-only text field
 * (proves settings_modify_column changes the column type), a Grid column and a Fluid child, writes a value
 * through each path and verifies the settings contract, storage and read-back. down() removes everything cpsref*.
 */
class CpsrefText extends Migration
{
    const FIELD = 'cpsref_text';
    const FIELD_INT = 'cpsref_text_int';
    const GRID = 'cpsref_text_grid';
    const FLUID = 'cpsref_text_fluid';
    const COLUMN = 'cpsref_text_col';
    const ENTRY = 'cpsref-text';

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

        // Top-level: ft.text.php::save_settings() keeps exactly these four keys in field_settings. The three
        // native columns (field_maxl, field_text_direction, field_fmt) live on exp_channel_fields itself.
        $textSettings = [
            'field_maxl' => 100, 'field_content_type' => 'all',
            'field_show_smileys' => 'n', 'field_show_file_selector' => 'n',
        ];
        $native = ['field_maxl' => 100, 'field_text_direction' => 'ltr', 'field_fmt' => 'none'];
        CpsRefFixture::makeField($group, self::FIELD, 'text', $textSettings, 1, $native);

        $intSettings = array_merge($textSettings, ['field_content_type' => 'integer']);
        CpsRefFixture::makeField($group, self::FIELD_INT, 'text', $intSettings, 2, $native);

        // Grid column: grid_save_settings() returns the posted array unchanged, so the column carries the
        // native keys itself (there is no channel_fields row to hold them).
        $gridSettings = [
            'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr',
            'field_maxl' => 100, 'field_required' => 'n',
        ];
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'text', 'label' => 'Text column', 'settings' => $gridSettings],
        ], 3);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 4);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $textFieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => 'Hello <b>cps</b> & friends',
            self::FIELD_INT => '42',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => 'grid text']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $textFieldId => 'fluid text']]],
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

        $field = CpsRefFixture::fieldSettings(self::FIELD);
        foreach (['field_maxl', 'field_content_type', 'field_show_smileys', 'field_show_file_selector'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $field), "field settings missing $key");
        }
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::nativeColumn(self::FIELD, 'field_text_direction') === 'ltr',
            'native field_text_direction column is not ltr'
        );
        CpsRefFixture::check(
            $problems,
            (int) CpsRefFixture::nativeColumn(self::FIELD, 'field_maxl') === 100,
            'native field_maxl column is not 100'
        );

        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach (['field_fmt', 'field_content_type', 'field_text_direction', 'field_maxl'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $intId = CpsRefFixture::fieldId(self::FIELD_INT);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $type = CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId);
        CpsRefFixture::check($problems, $type === 'text', "free-text column type is $type, expected text");
        $intType = CpsRefFixture::columnType('channel_data_field_' . $intId, 'field_id_' . $intId);
        CpsRefFixture::check($problems, $intType === 'int(11)', "integer column type is $intType, expected int(11)");
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        CpsRefFixture::check($problems, $gridType === 'text', "grid column type is $gridType, expected text");

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        // text::save() stores the raw string (no entity encoding), unlike url.
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD, $entryId) === 'Hello <b>cps</b> & friends',
            'top-level value did not read back verbatim'
        );
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD_INT, $entryId) === '42',
            'integer value did not read back as 42'
        );

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check(
            $problems,
            ($rows[0]['col_id_' . $colId] ?? null) === 'grid text',
            'grid value did not read back'
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === 'fluid text', 'fluid value did not read back');
        }

        return $problems;
    }
}
