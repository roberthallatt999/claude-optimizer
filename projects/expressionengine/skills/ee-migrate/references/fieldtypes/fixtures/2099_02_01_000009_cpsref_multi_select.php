<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: multi_select (Plan 2 Task 3). Proves the three ways an option fieldtype gets its
 * options (value/label pairs, manual textarea, populated from another channel field) at top level, the two
 * Grid column shapes, and a Fluid child. down() removes everything cpsref*.
 */
class CpsrefMultiSelect extends Migration
{
    const FIELD = 'cpsref_multi_select';
    const MANUAL = 'cpsref_multi_select_manual';
    const SOURCE = 'cpsref_multi_select_src';
    const FROM_CHANNEL = 'cpsref_multi_select_chan';
    const GRID = 'cpsref_multi_select_grid';
    const FLUID = 'cpsref_multi_select_fluid';
    const COL_PAIRS = 'cpsref_multi_select_pick';
    const COL_MANUAL = 'cpsref_multi_select_note';
    const ENTRY = 'cpsref-multi-select';

    private static $pairs = ['alpha' => 'Alpha label', 'beta' => 'Beta label', 'gamma' => 'Gamma label',
        'delta|pipe' => 'Delta label'];

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

    /**
     * Create an option field. $settings is field_settings (value_label_pairs lives here); $columns are the
     * channel_fields columns the option fieldtypes read directly (field_pre_populate, field_list_items,
     * field_pre_channel_id, field_pre_field_id). Private helper: candidate for promotion to CpsRefFixture.
     */
    private static function makeOptionField($group, string $name, string $type, array $settings, array $columns, int $order)
    {
        $field = CpsRefFixture::makeField($group, $name, $type, $settings, $order);
        foreach ($columns as $column => $value) {
            $field->$column = $value;
        }
        $field->save();

        return $field;
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $channelId = (int) $container['channel']->channel_id;

        // 1. value/label pairs: what the control panel mini-grid stores (settings['value_label_pairs'])
        self::makeOptionField($group, self::FIELD, 'multi_select', ['value_label_pairs' => self::$pairs], [
            'field_pre_populate' => 'n', 'field_list_items' => '',
        ], 1);
        // 2. manual textarea: one option per line, in the field_list_items COLUMN; value == label
        self::makeOptionField($group, self::MANUAL, 'multi_select', [], [
            'field_pre_populate' => 'n', 'field_list_items' => "One\nTwo\nThree",
        ], 2);
        // 3. populated from another channel field: field_pre_populate = y plus channel and field ids
        CpsRefFixture::makeField($group, self::SOURCE, 'text', ['field_maxl' => 256], 3);
        $sourceId = CpsRefFixture::fieldId(self::SOURCE);
        self::makeOptionField($group, self::FROM_CHANNEL, 'multi_select', [], [
            'field_pre_populate' => 'y', 'field_list_items' => '',
            'field_pre_channel_id' => $channelId, 'field_pre_field_id' => $sourceId,
        ], 4);

        // Grid column shapes: 'v' (pairs) as grid_save_settings() returns it; 'n' (manual) likewise
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL_PAIRS, 'type' => 'multi_select', 'label' => 'Pick', 'settings' => [
                'field_fmt' => 'none', 'field_pre_populate' => 'v', 'field_list_items' => '',
                'value_label_pairs' => self::$pairs,
            ]],
            ['name' => self::COL_MANUAL, 'type' => 'multi_select', 'label' => 'Note', 'settings' => [
                'field_fmt' => 'none', 'field_pre_populate' => 'n', 'field_pre_channel_id' => '0',
                'field_pre_field_id' => '0', 'field_list_items' => "One\nTwo\nThree", 'value_label_pairs' => [],
            ]],
        ], 5);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 6);

        $pairsCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_PAIRS);
        $manualCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_MANUAL);
        $fieldId = CpsRefFixture::fieldId(self::FIELD);

        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => ['beta', 'delta|pipe'],
            self::MANUAL => ['One', 'Two'],
            self::SOURCE => 'Fresh',
            self::FROM_CHANNEL => ['Fresh'],
            self::GRID => ['rows' => ['new_row_1' => [
                'col_id_' . $pairsCol => ['alpha', 'gamma'], 'col_id_' . $manualCol => ['Two', 'Three'],
            ]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => ['alpha', 'beta']]]],
        ]);
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    /** channel_fields columns the option fieldtypes read (they are columns, not field_settings keys). */
    private static function fieldColumns(string $name): array
    {
        return ee()->db->select('field_pre_populate, field_list_items, field_pre_channel_id, field_pre_field_id')
            ->where('field_name', $name)->get('channel_fields')->row_array() ?: [];
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];

        // Settings contract: pairs mode
        $field = CpsRefFixture::fieldSettings(self::FIELD);
        CpsRefFixture::check($problems, ($field['value_label_pairs'] ?? null) === self::$pairs, 'value_label_pairs not stored as value => label');
        $pairsColumns = self::fieldColumns(self::FIELD);
        CpsRefFixture::check($problems, ($pairsColumns['field_pre_populate'] ?? '') === 'n', 'pairs field: field_pre_populate column should be n');

        // Manual mode: the options live in the column, not in field_settings
        $manualColumns = self::fieldColumns(self::MANUAL);
        CpsRefFixture::check($problems, ($manualColumns['field_list_items'] ?? '') === "One\nTwo\nThree", 'manual list not stored in field_list_items');
        CpsRefFixture::check($problems, empty(CpsRefFixture::fieldSettings(self::MANUAL)['value_label_pairs'] ?? null), 'manual field should have no value_label_pairs');

        // Channel-field mode
        $chan = self::fieldColumns(self::FROM_CHANNEL);
        CpsRefFixture::check($problems, ($chan['field_pre_populate'] ?? '') === 'y', 'channel mode: field_pre_populate should be y');
        CpsRefFixture::check($problems, (int) ($chan['field_pre_field_id'] ?? 0) === CpsRefFixture::fieldId(self::SOURCE), 'channel mode: field_pre_field_id wrong');
        CpsRefFixture::check($problems, (int) ($chan['field_pre_channel_id'] ?? 0) > 0, 'channel mode: field_pre_channel_id missing');

        // Grid column contracts
        $contractPairs = ['field_fmt', 'field_pre_populate', 'field_list_items', 'value_label_pairs'];
        $contractManual = ['field_fmt', 'field_pre_populate', 'field_pre_channel_id', 'field_pre_field_id', 'field_list_items', 'value_label_pairs'];
        $gridPairs = CpsRefFixture::gridColumnSettings(self::GRID, self::COL_PAIRS);
        $gridManual = CpsRefFixture::gridColumnSettings(self::GRID, self::COL_MANUAL);
        foreach ($contractPairs as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $gridPairs), "grid pairs column missing $key");
        }
        foreach ($contractManual as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $gridManual), "grid manual column missing $key");
        }
        CpsRefFixture::check($problems, ($gridPairs['value_label_pairs'] ?? null) === self::$pairs, 'grid pairs not stored as value => label');

        // Storage
        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data_field_' . $fieldId, 'field_id_' . $fieldId), 'data column missing');

        // Values
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::FIELD, $entryId) === 'beta|delta\\|pipe', 'pairs value did not read back as pipe-delimited values (pipe in a value escaped as \\|)');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::MANUAL, $entryId) === 'One|Two', 'manual value did not read back');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::FROM_CHANNEL, $entryId) === 'Fresh', 'channel-populated value did not read back');

        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1, 'expected 1 grid row, found ' . count($rows));
        $pairsCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_PAIRS);
        $manualCol = CpsRefFixture::gridColumnId(self::GRID, self::COL_MANUAL);
        CpsRefFixture::check($problems, ($rows[0]['col_id_' . $pairsCol] ?? null) === 'alpha|gamma', 'grid pairs value did not read back');
        CpsRefFixture::check($problems, ($rows[0]['col_id_' . $manualCol] ?? null) === 'Two|Three', 'grid manual value did not read back');

        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get('channel_data_field_' . $fieldId)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === 'alpha|beta', 'fluid value did not read back');
        }

        // validate(): the fieldtype reads options in the stored shape (all three modes accept their own values)
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));
        $entry->{'field_id_' . $fieldId} = 'not-an-option';
        CpsRefFixture::check($problems, ! $entry->validate()->isValid(), 'a value outside the options should fail validate()');

        return $problems;
    }
}
