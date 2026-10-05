<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: email_address (Plan 2 Task 2). The fieldtype has no settings of its own, so the
 * contract is "an empty array is valid". Creates a top-level field, a Grid column and a Fluid child, writes a
 * value through each path and verifies storage and read-back. down() removes everything cpsref*.
 */
class CpsrefEmailAddress extends Migration
{
    const FIELD = 'cpsref_email_address';
    const GRID = 'cpsref_email_address_grid';
    const FLUID = 'cpsref_email_address_fluid';
    const COLUMN = 'cpsref_email_address_col';
    const ENTRY = 'cpsref-email-address';

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

        // ft.email_address.php has no save_settings() override: the base class returns the posted array, and
        // the form posts none, so real fields store a:0:{}. field_required is the only generic key worth setting.
        CpsRefFixture::makeField($group, self::FIELD, 'email_address', [], 1);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'email_address', 'label' => 'Email column', 'settings' => ['field_required' => 'n']],
        ], 2);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 3);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => 'top.level+tag@example.com',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => 'grid@example.com']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => 'fluid@example.com']]],
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

        // No settings contract: nothing to assert except that the stored settings decode to an array.
        $field = CpsRefFixture::fieldSettings(self::FIELD);
        CpsRefFixture::check($problems, $field === [], 'email_address field settings are expected to be empty');

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $type = CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId);
        CpsRefFixture::check($problems, $type === 'text', "email column type is $type, expected text");
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        CpsRefFixture::check($problems, $gridType === 'text', "grid column type is $gridType, expected text");

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD, $entryId) === 'top.level+tag@example.com',
            'top-level value did not read back verbatim'
        );

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check(
            $problems,
            ($rows[0]['col_id_' . $colId] ?? null) === 'grid@example.com',
            'grid value did not read back'
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === 'fluid@example.com', 'fluid value did not read back');
        }

        return $problems;
    }
}
