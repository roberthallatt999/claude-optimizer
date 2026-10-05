<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: date (Plan 2 Task 4). Proves the top-level settings (localization, show_time), the
 * two columns a date field gets (field_id_N BIGINT, field_dt_N VARCHAR(50)), the different Grid settings
 * (localize, show_time) and Grid storage (VARCHAR(60), no companion column, "timestamp|timezone" when not
 * localized), and what save()/grid_save() return for '', 0, a timestamp, a human date and garbage.
 * down() removes everything cpsref*.
 */
class CpsrefDate extends Migration
{
    const LOCALIZED = 'cpsref_date';
    const FIXED = 'cpsref_date_fixed';
    const GRID = 'cpsref_date_grid';
    const FLUID = 'cpsref_date_fluid';
    const COL_LOCALIZED = 'cpsref_date_col';
    const COL_FIXED = 'cpsref_date_col_fixed';
    const ENTRY = 'cpsref-date';
    const ENTRY_EMPTY = 'cpsref-date-empty';
    const ENTRY_GARBAGE = 'cpsref-date-garbage';
    const TIMESTAMP = 1700000000;
    const HUMAN = '2024-03-05 10:30 AM';

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

        // ft.date.php::save_settings() keeps exactly localization (localized|fixed|ask) and show_time (bool).
        CpsRefFixture::makeField($group, self::LOCALIZED, 'date', ['localization' => 'localized', 'show_time' => true], 1);
        CpsRefFixture::makeField($group, self::FIXED, 'date', ['localization' => 'fixed', 'show_time' => false], 2);

        // Grid columns use DIFFERENT keys: localize (bool) and show_time (bool); there is no 'localization'.
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL_LOCALIZED, 'type' => 'date', 'label' => 'Localized',
                'settings' => ['localize' => true, 'show_time' => true]],
            ['name' => self::COL_FIXED, 'type' => 'date', 'label' => 'Fixed',
                'settings' => ['localize' => false, 'show_time' => false]],
        ], 3);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::LOCALIZED], 4);

        $localizedCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_LOCALIZED);
        $fixedCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_FIXED);
        $fieldId = CpsRefFixture::fieldId(self::LOCALIZED);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::LOCALIZED => (string) self::TIMESTAMP,
            self::FIXED => self::HUMAN,
            self::GRID => ['rows' => ['new_row_1' => [
                'col_id_' . $localizedCol => (string) self::TIMESTAMP,
                'col_id_' . $fixedCol => self::HUMAN,
            ]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => (string) self::TIMESTAMP]]],
        ]);
        CpsRefFixture::makeEntry(self::ENTRY_EMPTY, [self::LOCALIZED => '', self::FIXED => 0]);
        CpsRefFixture::makeEntry(self::ENTRY_GARBAGE, [self::LOCALIZED => 'not a date']);

        // field_dt_N is written through the same Model property (ContentModel maps it to the field's timezone).
        $entry = ee('Model')->get('ChannelEntry', CpsRefFixture::entryId(self::ENTRY))->first();
        $property = 'field_dt_' . $fieldId;
        $entry->$property = 'Pacific/Auckland';
        $entry->save();
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    private static function raw(int $fieldId, int $entryId): array
    {
        $table = ee()->db->dbprefix . 'channel_data_field_' . $fieldId;

        return ee()->db->query(
            'SELECT field_id_' . $fieldId . ' AS v, field_dt_' . $fieldId . ' AS dt FROM `' . $table
            . '` WHERE entry_id = ' . (int) $entryId
        )->row_array() ?: [];
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        // Date_ft::save() calls Localize::get_date_format(), which needs ee()->session; the CLI does not load it
        // (the Model path loads it lazily, a bare fieldtype call does not).
        ee()->load->library('session');

        $problems = [];
        $check = function (bool $ok, string $message) use (&$problems) {
            CpsRefFixture::check($problems, $ok, $message);
        };

        $localized = CpsRefFixture::fieldSettings(self::LOCALIZED);
        $fixed = CpsRefFixture::fieldSettings(self::FIXED);
        $check(($localized['localization'] ?? null) === 'localized', 'localization setting not stored');
        $check(($localized['show_time'] ?? null) === true, 'show_time (true) not stored as bool');
        $check(($fixed['localization'] ?? null) === 'fixed' && ($fixed['show_time'] ?? null) === false, 'fixed settings wrong');
        foreach ([self::COL_LOCALIZED => [true, true], self::COL_FIXED => [false, false]] as $name => [$localize, $time]) {
            $column = CpsRefFixture::gridColumnSettings(self::GRID, $name);
            $check(($column['localize'] ?? null) === $localize, "grid column $name localize wrong");
            $check(($column['show_time'] ?? null) === $time, "grid column $name show_time wrong");
        }

        $fieldId = CpsRefFixture::fieldId(self::LOCALIZED);
        $table = 'channel_data_field_' . $fieldId;
        $check(CpsRefFixture::columnType($table, 'field_id_' . $fieldId) === 'bigint(10)', 'field_id_N is not bigint(10)');
        $check(CpsRefFixture::columnType($table, 'field_dt_' . $fieldId) === 'varchar(50)', 'field_dt_N is not varchar(50)');
        $check(CpsRefFixture::columnExists($table, 'field_ft_' . $fieldId), 'field_ft_N missing');

        $gridId = CpsRefFixture::fieldId(self::GRID);
        $localizedCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_LOCALIZED);
        $fixedCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_FIXED);
        $gridTable = 'channel_grid_field_' . $gridId;
        $check(CpsRefFixture::columnType($gridTable, 'col_id_' . $localizedCol) === 'varchar(60)', 'grid column is not varchar(60)');
        $check(
            ! CpsRefFixture::columnExists($gridTable, 'col_dt_' . $localizedCol),
            'unexpected Grid companion timezone column'
        );

        // Stored values (Model path)
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $row = self::raw($fieldId, $entryId);
        $check((string) ($row['v'] ?? '') === (string) self::TIMESTAMP, 'timestamp did not read back: ' . json_encode($row));
        $check(($row['dt'] ?? null) === 'Pacific/Auckland', 'field_dt_N did not read back: ' . json_encode($row));
        $fixedRow = self::raw(CpsRefFixture::fieldId(self::FIXED), $entryId);
        $humanStamp = (int) ($fixedRow['v'] ?? 0);
        $check($humanStamp > 1700000000 && $humanStamp < 1800000000, 'human date was not parsed: ' . json_encode($fixedRow));
        $check(
            in_array($fixedRow['dt'], [null, ''], true),
            'field_dt_N should be NULL or empty when never set: ' . json_encode($fixedRow)
        );
        $emptyId = CpsRefFixture::entryId(self::ENTRY_EMPTY);
        $check((string) (self::raw($fieldId, $emptyId)['v'] ?? 'missing') === '0', "'' did not store 0");
        $check((string) (self::raw(CpsRefFixture::fieldId(self::FIXED), $emptyId)['v'] ?? 'missing') === '0', '0 did not store 0');
        $garbageId = CpsRefFixture::entryId(self::ENTRY_GARBAGE);
        $garbage = self::raw($fieldId, $garbageId);
        $check((string) ($garbage['v'] ?? 'missing') === '0', 'garbage did not store 0: ' . json_encode($garbage));

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $check(count($rows) === 1, 'expected 1 grid row');
        $check(($rows[0]['col_id_' . $localizedCol] ?? null) === (string) self::TIMESTAMP, 'localized grid value wrong');
        $fixedGrid = (string) ($rows[0]['col_id_' . $fixedCol] ?? '');
        $check(
            preg_match('/^\d{10}\|[A-Za-z_\/+-]+$/', $fixedGrid) === 1,
            "non-localized grid value is not 'timestamp|timezone': $fixedGrid"
        );

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $check(count($fluid) === 1, 'expected 1 fluid row');
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get($table)->row_array();
            $check((string) ($stored['v'] ?? '') === (string) self::TIMESTAMP, 'fluid value did not read back');
        }

        // Direct fieldtype calls: what save()/grid_save()/validate() return.
        ee()->api_channel_fields->include_handler('date');
        $ft = new Date_ft();
        $ft->settings = ['localization' => 'localized', 'show_time' => true];
        $expected = [
            ['', null], [null, null], [0, 0], ['0', '0'], [self::TIMESTAMP, self::TIMESTAMP],
            [(string) self::TIMESTAMP, (string) self::TIMESTAMP], ['garbage', null],
        ];
        foreach ($expected as [$input, $output]) {
            $check($ft->save($input) === $output, 'save(' . var_export($input, true) . ') returned ' . var_export($ft->save($input), true));
        }
        $parsed = $ft->save(self::HUMAN);
        $check(is_numeric($parsed) && (int) $parsed === $humanStamp, 'save(human) differs from the Model path');
        $check($ft->validate('') === ['value' => ''], 'validate(empty) should accept');
        $check(is_string($ft->validate('garbage')), 'validate(garbage) should return an error string');
        $ft->settings = ['localize' => true, 'show_time' => true];
        $check($ft->grid_save((string) self::TIMESTAMP) === (string) self::TIMESTAMP, 'grid_save(localize) wrong');
        $ft->settings = ['localize' => false, 'show_time' => true];
        $pair = $ft->grid_save(self::TIMESTAMP);
        $check(is_array($pair) && $pair[0] === self::TIMESTAMP && is_string($pair[1]) && $pair[1] !== '', 'grid_save(fixed) not [ts, tz]');
        $check($ft->grid_save('') === null, 'grid_save(empty) should be null');
        $check(
            $ft->grid_save_settings(['localize' => 'y', 'show_time' => 'n']) === ['localize' => true, 'show_time' => false],
            'grid_save_settings did not coerce y/n to bool'
        );
        $check(
            $ft->save_settings(['localization' => 'fixed', 'junk' => 1]) === ['localization' => 'fixed', 'show_time' => true],
            'save_settings did not filter to localization/show_time'
        );

        return $problems;
    }
}
