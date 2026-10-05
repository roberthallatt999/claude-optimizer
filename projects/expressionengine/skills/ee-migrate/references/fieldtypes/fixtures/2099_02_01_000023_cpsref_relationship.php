<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: relationship (Plan 2 Task 6). Relationship stores nothing in its own column: the data
 * lives in exp_relationships, written by the fieldtype's post_save(). This fixture proves:
 *
 *  - the fifteen settings keys save_settings() produces (channels as numeric STRINGS, order_field a real column);
 *  - the reliable write path (Model: field_id_N = ['data' => [ids]]) read back from exp_relationships, as a top-level
 *    field, as a Grid column (grid_field_id/grid_col_id/grid_row_id) and as a Fluid child (fluid_field_data_id);
 *  - rewriting an existing entry (reorder, clear), validate() min/max;
 *  - three write-path traps, each reproduced and printed as a PROBE line in the migrate log:
 *    (1) a relationship field created after the channel's field list was cached in the session: the assignment is
 *        silently dropped and no rows are written,
 *    (2) $entry->getAssociation('Children')->add() writes a pivot row with field_id 0, unattached to the field,
 *    (3) a bogus order_field makes the entry-list query (EntryList::query(), used by display_field) throw;
 *  - the direct-insert fallback and how to prove it landed.
 * down() removes every cpsref* row, table and column, plus any exp_relationships row that touched a fixture entry.
 */
class CpsrefRelationship extends Migration
{
    const REL = 'cpsref_rel';
    const CHILD = 'cpsref_rel_child';
    const GRID = 'cpsref_rel_grid';
    const COL = 'cpsref_rel_col';
    const FLUID = 'cpsref_rel_fluid';
    const LATE = 'cpsref_rel_late';
    const ENTRY = 'cpsref-rel';
    const TARGET_A = 'cpsref-rel-target-a';
    const TARGET_B = 'cpsref-rel-target-b';
    const TARGET_C = 'cpsref-rel-target-c';
    const DIRECT = 'cpsref-rel-direct';
    const ASSOC = 'cpsref-rel-assoc';
    const LATE_ENTRY = 'cpsref-rel-late-entry';
    const LATE_ENTRY_FIXED = 'cpsref-rel-late-entry-fixed';
    const EXISTING = 'cpsref-rel-existing';

    /** @var string[] failed assertions collected by up() */
    private $problems = [];

    public function up()
    {
        try {
            $this->build();
            if ($this->problems !== []) {
                throw new \RuntimeException('relationship fixture up() assertions failed: '
                    . implode('; ', $this->problems));
            }
        } catch (\Throwable $e) {
            try {
                $this->cleanup();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    public function down()
    {
        $this->cleanup();
    }

    /** Remove relationship rows that touch a fixture entry (a getAssociation() row has field_id 0), then the rest. */
    private function cleanup(): void
    {
        $ids = [];
        $channel = ee()->db->select('channel_id')->where('channel_name', CpsRefFixture::CHANNEL)
            ->get('channels')->row_array();
        if ($channel) {
            $rows = ee()->db->select('entry_id')->where('channel_id', (int) $channel['channel_id'])
                ->get('channel_titles')->result_array();
            $ids = array_map('intval', array_column($rows, 'entry_id'));
        }
        CpsRefFixture::removeAll();
        if ($ids !== []) {
            ee()->db->where_in('parent_id', $ids)->delete('relationships');
            ee()->db->where_in('child_id', $ids)->delete('relationships');
        }
    }

    // ------------------------------------------------------------------------------------------------ helpers

    private function expect(bool $condition, string $message): void
    {
        if (! $condition) {
            $this->problems[] = $message;
        }
    }

    private static function probe(string $label, string $value): void
    {
        echo 'PROBE ' . $label . ': ' . $value . PHP_EOL;
    }

    /**
     * All fifteen keys save_settings() returns. channels and categories/authors/statuses hold strings; every key is
     * set so display_field()/EntryList::query() never read an undefined index.
     */
    private static function settings(int $channelId, array $override = []): array
    {
        return $override + [
            'channels' => [(string) $channelId], 'expired' => 1, 'future' => 1, 'categories' => [], 'authors' => [],
            'statuses' => ['open'], 'limit' => 50, 'order_field' => 'entry_date', 'order_dir' => 'desc',
            'display_entry_id' => true, 'display_status' => true, 'deferred_loading' => true,
            'allow_multiple' => true, 'rel_min' => 1, 'rel_max' => '3',
        ];
    }

    /** Drop the session-cached custom-field list of the fixture channel (Channel::getAllCustomFields()). */
    private static function refreshFieldList(): void
    {
        if (! isset(ee()->session)) {
            return;
        }
        $channel = ee()->db->select('channel_id')->where('channel_name', CpsRefFixture::CHANNEL)
            ->get('channels')->row_array();
        if (! $channel) {
            return;
        }
        ee()->session->set_cache(
            \ExpressionEngine\Model\Channel\Channel::class,
            'ChannelCustomFields/' . $channel['channel_id'] . '/',
            false
        );
    }

    /** exp_relationships rows for a parent entry and field (top level: grid and fluid columns zero), by order. */
    private static function rows(int $parentId, int $fieldId): array
    {
        return ee()->db->where(['parent_id' => $parentId, 'field_id' => $fieldId])
            ->order_by('order')->get('relationships')->result_array();
    }

    private static function childIds(array $rows): array
    {
        return array_map('intval', array_column($rows, 'child_id'));
    }

    /** Assign a relationship value to an existing entry; $touch also sets edit_date, as the control panel does. */
    private static function rewrite(int $entryId, string $fieldName, array $ids, bool $touch = true): void
    {
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $entry->{'field_id_' . CpsRefFixture::fieldId($fieldName)} = ['data' => $ids];
        if ($touch) {
            $entry->edit_date = ee()->localize->now;
        }
        $entry->save();
    }

    // ------------------------------------------------------------------------------------------------ build

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $channelId = (int) $container['channel']->channel_id;

        // 1. Fields: top level, Fluid child, Grid column, and one with the shape that breaks the publish screen
        CpsRefFixture::makeField($group, self::REL, 'relationship', self::settings($channelId), 1);
        CpsRefFixture::makeField($group, self::CHILD, 'relationship', self::settings($channelId, [
            'allow_multiple' => false, 'rel_min' => 0, 'rel_max' => '',
        ]), 2);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::CHILD], 3);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL, 'type' => 'relationship', 'label' => 'Related',
                'settings' => self::settings($channelId, ['rel_min' => 0]) + ['field_required' => 'n']],
        ], 4);
        self::refreshFieldList();

        // 2. Targets, then one entry that writes all three shapes
        $a = CpsRefFixture::makeEntry(self::TARGET_A, []);
        $b = CpsRefFixture::makeEntry(self::TARGET_B, []);
        $c = CpsRefFixture::makeEntry(self::TARGET_C, []);
        $childId = CpsRefFixture::fieldId(self::CHILD);
        $col = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $entryId = CpsRefFixture::makeEntry(self::ENTRY, [
            self::REL => ['data' => [$a, $b]],
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $col => ['data' => [$c]]]]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $childId => ['data' => [$b]]]]],
        ]);
        $relId = CpsRefFixture::fieldId(self::REL);
        $this->expect(
            self::childIds(self::rows($entryId, $relId)) === [$a, $b],
            'top-level write: expected children [a, b], got '
                . json_encode(self::childIds(self::rows($entryId, $relId)))
        );

        $this->rewriteContract($a, $b, $c);
        $this->validateContract($a, $b, $c);
        $this->settingsProbes($channelId);
        $this->writePathProbes($group, $channelId, $a, $b);
    }

    /** Existing entry: reorder, clear, restore (with and without edit_date). */
    private function rewriteContract(int $a, int $b, int $c): void
    {
        $entryId = CpsRefFixture::makeEntry(self::EXISTING, [self::REL => ['data' => [$a, $b]]]);
        $relId = CpsRefFixture::fieldId(self::REL);

        // Unlike Grid, a field-only save on an existing entry DOES write: ft.relationship.php::save() sets the
        // model property to null, which dirties the entry. Found by this probe; edit_date is still harmless.
        self::rewrite($entryId, self::REL, [$b, $a, $c], false);
        $plain = self::childIds(self::rows($entryId, $relId));
        self::probe('existing entry: assign relationship + save() (no edit_date) leaves children', json_encode($plain));
        $this->expect($plain === [$b, $a, $c], 'existing entry: a field-only save should write relationship rows');

        self::rewrite($entryId, self::REL, [$c, $b, $a]);
        $reordered = self::rows($entryId, $relId);
        self::probe(
            'existing entry: assign + edit_date + save() leaves children',
            json_encode(self::childIds($reordered))
        );
        $this->expect(
            self::childIds($reordered) === [$c, $b, $a],
            'existing entry: reorder with edit_date should land'
        );
        $this->expect(
            array_map('intval', array_column($reordered, 'order')) === [1, 2, 3],
            'order column should start at 1 and follow the array position'
        );

        self::rewrite($entryId, self::REL, []);
        $this->expect(self::rows($entryId, $relId) === [], 'clearing: an empty data array should delete every row');

        self::rewrite($entryId, self::REL, [$a]);
        $this->expect(self::childIds(self::rows($entryId, $relId)) === [$a], 'restore after clear failed');
    }

    /** validate() enforces rel_min and rel_max when allow_multiple is on (ft.relationship.php::validate()). */
    private function validateContract(int $a, int $b, int $c): void
    {
        $extra = CpsRefFixture::makeEntry('cpsref-rel-target-d', []);
        $entryId = CpsRefFixture::entryId(self::EXISTING);
        $key = 'field_id_' . CpsRefFixture::fieldId(self::REL);
        $outcomes = [];
        foreach (['empty' => [], 'two' => [$a, $b], 'four' => [$a, $b, $c, $extra]] as $label => $ids) {
            $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
            $entry->$key = ['data' => $ids];
            $entry->edit_date = ee()->localize->now;
            $outcomes[$label] = $entry->validate()->isValid();
        }
        self::probe('validate() with rel_min 1, rel_max 3 (empty/two/four)', json_encode($outcomes));
        $this->expect($outcomes === ['empty' => false, 'two' => true, 'four' => false], 'validate() min/max: '
            . json_encode($outcomes));
    }

    /** What the entry-list query does with the stored settings: the source of the publish-screen 500. */
    private function settingsProbes(int $channelId): void
    {
        ee()->load->add_package_path(PATH_ADDONS . 'relationship');
        ee()->load->library('EntryList');
        $run = function (array $settings) {
            $settings += ['entry_id' => 0, 'field_id' => 0];
            try {
                return 'ok, ' . count(ee()->entrylist->query($settings)) . ' entries';
            } catch (\Throwable $e) {
                return get_class($e) . ': ' . substr($e->getMessage(), 0, 100);
            }
        };

        $good = $run(self::settings($channelId));
        self::probe('EntryList::query with the stored settings', $good);
        $this->expect(strpos($good, 'ok,') === 0, 'EntryList::query should work with the contract settings: ' . $good);

        $bogus = $run(self::settings($channelId, ['order_field' => 'cpsref_not_a_column']));
        self::probe('EntryList::query with order_field = a non-column', $bogus);
        $this->expect(strpos($bogus, 'ok,') !== 0, 'a non-column order_field was expected to fail the query');

        $empty = $run(self::settings($channelId, ['order_field' => '']));
        self::probe('EntryList::query with order_field = empty string', $empty);

        // Source note: channels are compared loosely (in_array, filter IN), so ints may work in the query itself;
        // production stores strings and the reference tells you to do the same.
        $ints = $run(self::settings($channelId, ['channels' => [$channelId]]));
        self::probe('EntryList::query with channels as ints', $ints);
    }

    /** Write-path traps and the fallback. */
    private function writePathProbes($group, int $channelId, int $a, int $b): void
    {
        // (1) A relationship field created after the channel's field list was cached in the session (an entry has
        // been saved already in this request). The assignment is stored as a plain property and post_save never runs.
        CpsRefFixture::makeField($group, self::LATE, 'relationship', self::settings($channelId), 20);
        $late = CpsRefFixture::makeEntry(self::LATE_ENTRY, [self::LATE => ['data' => [$a]]]);
        $lateId = CpsRefFixture::fieldId(self::LATE);
        $stale = count(self::rows($late, $lateId));
        self::probe('relationship created after a cached field list, written without refresh', $stale . ' row(s)');
        $this->expect($stale === 0, 'late field: the stale-cache write was expected to write no rows');

        self::refreshFieldList();
        $fixed = CpsRefFixture::makeEntry(self::LATE_ENTRY_FIXED, [self::LATE => ['data' => [$a, $b]]]);
        $after = count(self::rows($fixed, $lateId));
        self::probe('same field after dropping the cached field list', $after . ' row(s)');
        $this->expect($after === 2, 'late field: after refreshing the list the write should land 2 rows');

        // (2) The fallback: plain inserts into exp_relationships, the fieldtype's storage. Read back by the Model.
        $direct = CpsRefFixture::makeEntry(self::DIRECT, []);
        foreach ([$a, $b] as $index => $childId) {
            ee()->db->insert('relationships', [
                'parent_id' => $direct, 'child_id' => $childId, 'field_id' => CpsRefFixture::fieldId(self::REL),
                'order' => $index + 1, 'grid_field_id' => 0, 'grid_col_id' => 0, 'grid_row_id' => 0,
                'fluid_field_data_id' => 0,
            ]);
        }
        $directRows = self::rows($direct, CpsRefFixture::fieldId(self::REL));
        $this->expect(self::childIds($directRows) === [$a, $b], 'direct insert: rows did not read back');
        $viaModel = ee('Model')->get('ChannelEntry', $direct)->first()->Children->pluck('entry_id');
        self::probe('direct insert read through the Children association', json_encode(array_map('intval', $viaModel)));

        // (3) getAssociation('Children')->add(): a pivot row with field_id 0, not attached to any field
        $assoc = CpsRefFixture::makeEntry(self::ASSOC, []);
        $parent = ee('Model')->get('ChannelEntry', $assoc)->first();
        $child = ee('Model')->get('ChannelEntry', $a)->first();
        $parent->getAssociation('Children')->add($child);
        $parent->save();
        $pivot = ee()->db->where('parent_id', $assoc)->get('relationships')->result_array();
        self::probe(
            'getAssociation(Children)->add() pivot rows (count, field_id)',
            count($pivot) . ', ' . json_encode(array_map('intval', array_column($pivot, 'field_id')))
        );
        $this->expect(
            count($pivot) === 1 && (int) $pivot[0]['field_id'] === 0,
            'association add: expected one pivot row with field_id 0, got ' . json_encode($pivot)
        );
    }

    // ------------------------------------------------------------------------------------------------ verify

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        $check = function (bool $condition, string $message) use (&$problems) {
            CpsRefFixture::check($problems, $condition, $message);
        };

        // Settings contract: fifteen keys, channels as strings
        $settings = CpsRefFixture::fieldSettings(self::REL);
        $keys = ['channels', 'expired', 'future', 'categories', 'authors', 'statuses', 'limit', 'order_field',
            'order_dir', 'display_entry_id', 'display_status', 'deferred_loading', 'allow_multiple', 'rel_min',
            'rel_max'];
        foreach ($keys as $key) {
            $check(array_key_exists($key, $settings), "relationship settings missing $key");
        }
        $check(count($settings) === 15, 'expected exactly 15 settings keys, found ' . count($settings));
        $channels = $settings['channels'] ?? [];
        $check($channels !== [] && $channels === array_map('strval', $channels), 'channels must be numeric strings');
        $check(
            in_array($settings['order_field'] ?? '', ['title', 'entry_date'], true),
            'order_field must be title or entry_date'
        );
        $check(
            ($settings['allow_multiple'] ?? null) === true && ($settings['display_entry_id'] ?? null) === true,
            'booleans did not round-trip'
        );

        // Storage: the field's own column is a dummy varchar(8); the data is in exp_relationships
        $relId = CpsRefFixture::fieldId(self::REL);
        $dummyType = CpsRefFixture::columnType('channel_data_field_' . $relId, 'field_id_' . $relId);
        $check($dummyType === 'varchar(8)', 'dummy column type is ' . $dummyType);

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $a = CpsRefFixture::entryId(self::TARGET_A);
        $b = CpsRefFixture::entryId(self::TARGET_B);
        $c = CpsRefFixture::entryId(self::TARGET_C);
        $top = self::rows($entryId, $relId);
        $check(self::childIds($top) === [$a, $b], 'top-level children wrong: ' . json_encode(self::childIds($top)));
        $check(array_map('intval', array_column($top, 'order')) === [1, 2], 'top-level order should be 1,2');
        foreach ($top as $row) {
            $zero = (int) $row['grid_field_id'] + (int) $row['grid_col_id'] + (int) $row['grid_row_id']
                + (int) $row['fluid_field_data_id'];
            $check($zero === 0, 'top-level row should have grid/fluid columns 0');
        }
        $check(CpsRefFixture::fieldValue(self::REL, $entryId) === null, 'the field data column must stay NULL');

        // Grid column: grid_field_id / grid_col_id / grid_row_id
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $col = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $gridRows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $cell = ee()->db->where(['parent_id' => $entryId, 'grid_field_id' => $gridId, 'grid_col_id' => $col])
            ->get('relationships')->result_array();
        $check(count($cell) === 1 && (int) $cell[0]['child_id'] === $c, 'grid cell relationship rows wrong');
        $check(
            count($cell) === 1 && count($gridRows) === 1
                && (int) $cell[0]['grid_row_id'] === (int) $gridRows[0]['row_id'],
            'grid_row_id does not match the Grid row'
        );
        $check(
            CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $col) === 'varchar(8)',
            'grid column data type is ' . CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $col)
        );
        $colSettings = CpsRefFixture::gridColumnSettings(self::GRID, self::COL);
        $check(
            array_key_exists('rel_max', $colSettings) && array_key_exists('channels', $colSettings),
            'column settings lack keys'
        );

        // Fluid child: fluid_field_data_id
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $childRows = self::rows($entryId, CpsRefFixture::fieldId(self::CHILD));
        $check(
            count($fluid) === 1 && count($childRows) === 1,
            'fluid: expected one Fluid row and one relationship row'
        );
        $check(
            count($fluid) === 1 && count($childRows) === 1
                && (int) $childRows[0]['fluid_field_data_id'] === (int) $fluid[0]['id']
                && (int) $childRows[0]['child_id'] === $b,
            'fluid: fluid_field_data_id/child_id wrong'
        );

        // Probes' final state
        $existing = self::childIds(self::rows(CpsRefFixture::entryId(self::EXISTING), $relId));
        $check($existing === [$a], 'existing-entry final state wrong: ' . json_encode($existing));
        $check(
            self::rows(CpsRefFixture::entryId(self::LATE_ENTRY), CpsRefFixture::fieldId(self::LATE)) === [],
            'stale-cache entry has rows'
        );
        $check(
            count(self::rows(CpsRefFixture::entryId(self::LATE_ENTRY_FIXED), CpsRefFixture::fieldId(self::LATE))) === 2,
            'refreshed late entry should have 2 rows'
        );
        $check(
            count(self::rows(CpsRefFixture::entryId(self::DIRECT), $relId)) === 2,
            'direct-insert entry should have 2 rows'
        );
        $assoc = ee()->db->where('parent_id', CpsRefFixture::entryId(self::ASSOC))
            ->get('relationships')->result_array();
        $check(count($assoc) === 1 && (int) $assoc[0]['field_id'] === 0, 'association row should carry field_id 0');

        return $problems;
    }
}
