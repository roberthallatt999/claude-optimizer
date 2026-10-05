<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: duration (Plan 2 Task 4). Proves the single `units` setting (hours|minutes|seconds),
 * the default TEXT column, that the stored value is whatever was written (colon notation is NOT converted by
 * save(); it is validated and converted only when rendered), and Grid / Fluid use.
 * down() removes everything cpsref*.
 */
class CpsrefDuration extends Migration
{
    const MINUTES = 'cpsref_duration';
    const HOURS = 'cpsref_duration_hours';
    const SECONDS = 'cpsref_duration_seconds';
    const GRID = 'cpsref_duration_grid';
    const FLUID = 'cpsref_duration_fluid';
    const COLUMN = 'cpsref_duration_col';
    const ENTRY = 'cpsref-duration';

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

        // ft.duration.php::save_settings() keeps exactly one key: units. validate() and display_field() read
        // $this->settings['units'] by direct index, so it must be present.
        CpsRefFixture::makeField($group, self::MINUTES, 'duration', ['units' => 'minutes'], 1);
        CpsRefFixture::makeField($group, self::HOURS, 'duration', ['units' => 'hours'], 2);
        CpsRefFixture::makeField($group, self::SECONDS, 'duration', ['units' => 'seconds'], 3);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'duration', 'label' => 'Duration', 'settings' => ['units' => 'minutes']],
        ], 4);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::MINUTES], 5);

        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $fieldId = CpsRefFixture::fieldId(self::MINUTES);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::MINUTES => '90',
            self::HOURS => '1:30',
            self::SECONDS => '1:30:15',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $colId => '45']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => '1:30']]],
        ]);
        CpsRefFixture::makeEntry('cpsref-duration-empty', [self::MINUTES => '  ']);
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

        foreach ([self::MINUTES => 'minutes', self::HOURS => 'hours', self::SECONDS => 'seconds'] as $name => $units) {
            $settings = CpsRefFixture::fieldSettings($name);
            $check(($settings['units'] ?? null) === $units, "$name units not stored as $units");
            $check(array_keys($settings) === ['units'], "$name settings should hold only units");
        }
        $check(
            (CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN)['units'] ?? null) === 'minutes',
            'grid column units missing'
        );

        $minutesId = CpsRefFixture::fieldId(self::MINUTES);
        $table = 'channel_data_field_' . $minutesId;
        $type = CpsRefFixture::columnType($table, 'field_id_' . $minutesId);
        $check($type === 'text', "duration column type is $type, expected text");
        $check(CpsRefFixture::columnExists($table, 'field_ft_' . $minutesId), 'field_ft_N missing');
        $check(! CpsRefFixture::columnExists($table, 'field_dt_' . $minutesId), 'unexpected field_dt_N');

        $gridId = CpsRefFixture::fieldId(self::GRID);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        $check($gridType === 'text', "grid column type is $gridType, expected text");

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        // Stored exactly as written: no unit conversion, no colon conversion.
        $reads = [self::MINUTES => '90', self::HOURS => '1:30', self::SECONDS => '1:30:15'];
        foreach ($reads as $name => $value) {
            $actual = CpsRefFixture::fieldValue($name, $entryId);
            $check($actual === $value, "$name read back as " . var_export($actual, true));
        }
        $emptyActual = CpsRefFixture::fieldValue(self::MINUTES, CpsRefFixture::entryId('cpsref-duration-empty'));
        $check($emptyActual === null, 'blank did not store NULL: ' . var_export($emptyActual, true));

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $check(count($rows) === 1, 'expected 1 grid row');
        $check(($rows[0]['col_id_' . $colId] ?? null) === '45', 'grid value did not read back');

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $check(count($fluid) === 1, 'expected 1 fluid row');
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $minutesId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get($table)->row_array();
            $check(($stored['v'] ?? null) === '1:30', 'fluid value did not read back');
        }

        // Direct fieldtype calls
        ee()->load->library('session');
        ee()->api_channel_fields->include_handler('duration');
        $ft = new Duration_Ft();
        $ft->settings = ['units' => 'minutes'];
        $check($ft->save('1:30') === '1:30', 'save() must not convert colon notation');
        $check($ft->save('  ') === null && $ft->save('') === null, 'save() should return null for blank');
        $check($ft->validate('') === true && $ft->validate('1:30') === true && $ft->validate('90') === true, 'validate() should accept');
        $check(is_string($ft->validate('abc')), 'validate(abc) should return an error string');
        $check(is_string($ft->validate('1.5')), 'validate(1.5) should return an error string (digits and colons only)');
        $check(is_string($ft->validate('-5')), 'validate(-5) should return an error string');
        $check(
            $ft->save_settings(['units' => 'hours', 'junk' => 1]) === ['units' => 'hours'],
            'save_settings did not filter to units'
        );
        $check($ft->save_settings([]) === ['units' => 'minutes'], 'save_settings default is not minutes');

        return $problems;
    }
}
