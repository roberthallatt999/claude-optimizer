<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: url (Plan 2, exemplar). Creates a URL field, a Grid column of type url and a
 * Fluid field containing the URL field, writes a value through each path, and verifies the settings contract,
 * storage and read-back. down() removes everything cpsref*.
 */
class CpsrefUrl extends Migration
{
    const FIELD = 'cpsref_url';
    const GRID = 'cpsref_url_grid';
    const FLUID = 'cpsref_url_fluid';
    const COLUMN = 'cpsref_url_link';
    const ENTRY = 'cpsref-url';
    const TOP_VALUE = 'https://example.com/top?a=1&b=2';
    const GRID_VALUE = 'https://example.com/grid';
    const FLUID_VALUE = 'https://example.com/fluid';

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

        $urlSettings = [
            'field_fmt' => 'none', 'field_required' => 'n',
            'allowed_url_schemes' => ['http://', 'https://'], 'url_scheme_placeholder' => 'https://',
        ];

        CpsRefFixture::makeField($group, self::FIELD, 'url', $urlSettings, 1);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'url', 'label' => 'Link', 'settings' => $urlSettings],
        ], 2);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 3);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $urlFieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => self::TOP_VALUE,
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => self::GRID_VALUE]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $urlFieldId => self::FLUID_VALUE]]],
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
        $contract = ['allowed_url_schemes', 'url_scheme_placeholder'];

        $field = CpsRefFixture::fieldSettings(self::FIELD);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $field), "field settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data_field_' . $fieldId, 'field_id_' . $fieldId), 'url data column missing');

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        // The fieldtype stores htmlspecialchars(value, ENT_QUOTES, UTF-8, false): & becomes &amp;
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD, $entryId) === 'https://example.com/top?a=1&amp;b=2',
            'top-level value did not read back as the entity-encoded string'
        );

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        CpsRefFixture::check(
            $problems,
            ($rows[0]['col_id_' . $colId] ?? null) === self::GRID_VALUE,
            'grid value did not read back'
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === self::FLUID_VALUE, 'fluid value did not read back');
        }

        return $problems;
    }
}
