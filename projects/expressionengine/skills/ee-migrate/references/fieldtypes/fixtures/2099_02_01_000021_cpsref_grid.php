<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: grid (Plan 2 Task 6). Grid is the type behind most real production defects, so this
 * fixture proves the whole life cycle, not just a create:
 *
 *  - the five field settings and the column array save_col_settings() needs (field_id and content_type INSIDE it),
 *    and that every column gets its col_id_N data column with the SQL type its fieldtype returns;
 *  - adding, renaming, retyping and deleting a column on a Grid that already has rows (mutations run in up() and
 *    are asserted there; a deviation fails the run);
 *  - the row write contract: new_row_N / row_id_N keys, row_order, what an omitted row and an omitted cell do,
 *    how to append without destroying, and searchable columns;
 *  - Grid inside a Fluid field;
 *  - three defects seen in production, each reproduced and printed as a PROBE line in the migrate log:
 *    (1) grid_model used before fetch_installed_fieldtypes() (TypeError, orphan settings row, no data column),
 *    (2) positional/missing field_id (orphan row with field_id NULL),
 *    (3) a field created in the same request that deleted it (leftover tables), and a field created after the
 *        channel's field list was cached in the session (entry writes silently dropped).
 * down() removes every cpsref* row, table and column; run-fixtures.sh then proves the schema is byte-identical.
 */
class CpsrefGrid extends Migration
{
    const GRID = 'cpsref_grid';
    const TEXT = 'cpsref_grid_text';
    const NUM = 'cpsref_grid_num';
    const DATE = 'cpsref_grid_date';
    const FLAG = 'cpsref_grid_flag';
    const REL = 'cpsref_grid_rel';
    const ENTRY = 'cpsref-grid';
    const TARGET = 'cpsref-grid-target';

    const MUT = 'cpsref_grid_mut';
    const MUT_A = 'cpsref_mut_a';
    const MUT_REL = 'cpsref_mut_rel';
    const MUT_ADDED = 'cpsref_mut_added';
    const MUT_ENTRY = 'cpsref-grid-mut';

    const ROWS = 'cpsref_grid_rows';
    const ROWS_T = 'cpsref_rows_t';
    const ROWS_N = 'cpsref_rows_n';
    const ROWS_ENTRY = 'cpsref-grid-rows';

    const SEARCH = 'cpsref_grid_search';
    const SEARCH_COL = 'cpsref_search_col';
    const SEARCH_ONE = 'cpsref-grid-s1';
    const SEARCH_TWO = 'cpsref-grid-s2';

    const CHILD = 'cpsref_grid_child';
    const CHILD_COL = 'cpsref_child_col';
    const FLUID = 'cpsref_grid_fluid';

    /** @var string[] failed assertions collected by up() */
    private $problems = [];

    public function up()
    {
        try {
            // Must run before anything calls CpsRefFixture::bootstrap(): it needs the unprimed registry.
            self::probeWithoutRegistry();
            $this->build();
            if ($this->problems !== []) {
                throw new \RuntimeException('grid fixture up() assertions failed: ' . implode('; ', $this->problems));
            }
        } catch (\Throwable $e) {
            try {
                CpsRefFixture::removeAll();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    public function down()
    {
        CpsRefFixture::removeAll();
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
     * Private helper (promote to CpsRefFixture::makeGridField): the shared helper hard-codes the five Grid
     * settings, this one takes them, plus native channel_fields columns (field_search).
     */
    private static function gridField(
        $group,
        string $name,
        array $settings,
        array $columns,
        int $order,
        array $native = [],
        bool $refresh = true
    ) {
        $grid = CpsRefFixture::makeField($group, $name, 'grid', $settings, $order, $native);
        ee()->grid_model->create_field($grid->field_id, 'channel');
        foreach (array_values($columns) as $index => $column) {
            self::addColumn(
                (int) $grid->field_id,
                $index,
                $column['name'],
                $column['type'],
                $column['settings'] ?? [],
                $column['label'] ?? null,
                $column['search'] ?? 'n'
            );
        }
        if ($refresh) {
            self::refreshFieldList();
        }

        return $grid;
    }

    /**
     * Drop the session's cached custom-field list for the fixture channel. Channel::getAllCustomFields() caches it
     * in ee()->session once any entry in the channel has been saved in this request; a field created afterwards
     * is then invisible to ChannelEntry, and assigning field_id_N on an entry is silently dropped. Private helper
     * (promote to CpsRefFixture and call from makeField()/makeGridField()/makeFluidField()).
     */
    private static function refreshFieldList(): void
    {
        if (! isset(ee()->session)) {
            return;
        }
        $channel = ee()->db->select('channel_id')->where('channel_name', CpsRefFixture::CHANNEL)->get('channels')->row_array();
        if (! $channel) {
            return;
        }
        ee()->session->set_cache(
            \ExpressionEngine\Model\Channel\Channel::class,
            'ChannelCustomFields/' . $channel['channel_id'] . '/',
            false
        );
    }

    private static function defaultGridSettings(): array
    {
        return [
            'grid_min_rows' => 0, 'grid_max_rows' => '', 'allow_reorder' => 'y',
            'vertical_layout' => 'n', 'row_counter' => 'n',
        ];
    }

    /** The complete column array save_col_settings() takes: field_id and content_type INSIDE it. */
    private static function columnArray(
        int $fieldId,
        int $order,
        string $name,
        string $type,
        array $settings,
        ?string $label = null,
        string $search = 'n'
    ): array {
        $settings['field_required'] = $settings['field_required'] ?? 'n';

        return [
            'field_id' => $fieldId,
            'content_type' => 'channel',
            'col_order' => $order,
            'col_type' => $type,
            'col_label' => $label ?? $name,
            'col_name' => $name,
            'col_instructions' => '',
            'col_required' => 'n',
            'col_search' => $search,
            'col_width' => 0,
            'col_settings' => json_encode($settings),
        ];
    }

    private static function addColumn(
        int $fieldId,
        int $order,
        string $name,
        string $type,
        array $settings,
        ?string $label = null,
        string $search = 'n'
    ): int {
        return (int) ee()->grid_model->save_col_settings(
            self::columnArray($fieldId, $order, $name, $type, $settings, $label, $search),
            false,
            'channel'
        );
    }

    private static function textSettings(): array
    {
        return [
            'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr', 'field_maxl' => 256,
        ];
    }

    /** All 15 relationship keys; channels is an array of STRINGS. */
    private static function relationshipSettings(int $channelId): array
    {
        return [
            'channels' => [(string) $channelId], 'expired' => 0, 'future' => 0, 'categories' => [], 'authors' => [],
            'statuses' => ['open'], 'limit' => 100, 'order_field' => 'title', 'order_dir' => 'asc',
            'display_entry_id' => false, 'display_status' => false, 'deferred_loading' => false,
            'allow_multiple' => true, 'rel_min' => 0, 'rel_max' => '',
        ];
    }

    private static function gridTable(string $fieldName): string
    {
        return 'channel_grid_field_' . CpsRefFixture::fieldId($fieldName);
    }

    /** grid_columns rows of a Grid field, keyed by col_name, in col_order. */
    private static function columns(string $fieldName): array
    {
        $fieldId = CpsRefFixture::fieldId($fieldName);
        $rows = ee()->db->where('field_id', $fieldId)->order_by('col_order')->get('grid_columns')->result_array();
        $byName = [];
        foreach ($rows as $row) {
            $byName[$row['col_name']] = $row;
        }

        return $byName;
    }

    private static function colId(string $fieldName, string $colName): int
    {
        return CpsRefFixture::gridColumnId($fieldName, $colName);
    }

    /** Write rows to an existing entry through the Model (the supported path). */
    private static function writeRows(string $entryUrlTitle, string $fieldName, array $rows): void
    {
        $entry = ee('Model')->get('ChannelEntry', CpsRefFixture::entryId($entryUrlTitle))->first();
        $entry->{'field_id_' . CpsRefFixture::fieldId($fieldName)} = ['rows' => $rows];
        // A field-only change leaves the entry row clean, and the Model then skips the save: set edit_date.
        $entry->edit_date = ee()->localize->now;
        $entry->save();
    }

    private static function relationshipRows(int $entryId, int $gridFieldId): array
    {
        return ee()->db->where(['parent_id' => $entryId, 'grid_field_id' => $gridFieldId])
            ->order_by('grid_row_id')->get('relationships')->result_array();
    }

    private static function showTables(array $names): array
    {
        $found = [];
        foreach ($names as $name) {
            $found[$name] = CpsRefFixture::tableExists($name);
        }

        return $found;
    }

    // ------------------------------------------------------------------------------------------------ probes

    /**
     * Defect 1: grid_model::save_col_settings() before api_channel_fields->fetch_installed_fieldtypes().
     * Uses a made-up field id (no channel_fields row) so nothing real is touched, and cleans up in finally.
     */
    private static function probeWithoutRegistry(): void
    {
        ee()->load->model('grid_model');
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        $registry = isset(ee()->api_channel_fields->field_types['text']) ? 'yes' : 'no';
        $max = ee()->db->select_max('field_id', 'm')->get('channel_fields')->row_array();
        $fake = (int) ($max['m'] ?? 0) + 90000;
        $outcome = 'saved without error';
        try {
            ee()->grid_model->create_field($fake, 'channel');
            ee()->grid_model->save_col_settings(
                self::columnArray($fake, 0, 'cpsref_probe_registry', 'text', self::textSettings()),
                false,
                'channel'
            );
        } catch (\Throwable $e) {
            $outcome = get_class($e) . ': ' . substr($e->getMessage(), 0, 160);
        } finally {
            $orphans = ee()->db->where('field_id', $fake)->count_all_results('grid_columns');
            $dataColumns = CpsRefFixture::columnExists('channel_grid_field_' . $fake, 'col_id_1') ? 'maybe' : 'none';
            ee()->db->where('field_id', $fake)->delete('grid_columns');
            ee()->db->query('DROP TABLE IF EXISTS `' . ee()->db->dbprefix . 'channel_grid_field_' . $fake . '`');
        }
        self::probe('no-registry registry_primed', $registry);
        self::probe('no-registry outcome', $outcome);
        self::probe('no-registry orphan_settings_rows', (string) $orphans);
        self::probe('no-registry col_id_N data columns', $dataColumns);
    }

    /** Defect 2: field_id missing from the column array (what passing it positionally amounts to). */
    private static function probePositional(int $realFieldId): void
    {
        $column = self::columnArray($realFieldId, 0, 'cpsref_probe_positional', 'text', self::textSettings());
        unset($column['field_id'], $column['content_type']);
        $previous = ee()->db->db_debug;
        ee()->db->db_debug = false;
        $outcome = 'no exception';
        try {
            ee()->grid_model->save_col_settings($column, false, 'channel');
        } catch (\Throwable $e) {
            $outcome = get_class($e) . ': ' . substr($e->getMessage(), 0, 120);
        } finally {
            ee()->db->db_debug = $previous;
            $orphans = ee()->db->query(
                "SELECT COUNT(*) AS n FROM exp_grid_columns WHERE col_name = 'cpsref_probe_positional' AND field_id IS NULL"
            )->row_array();
            ee()->db->where('col_name', 'cpsref_probe_positional')->delete('grid_columns');
        }
        self::probe('positional outcome', $outcome);
        self::probe('positional orphan rows with field_id NULL', (string) ($orphans['n'] ?? '?'));
    }

    // ------------------------------------------------------------------------------------------------ build

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $channelId = (int) $container['channel']->channel_id;

        self::probePositional(0);

        // A target entry the relationship column can point at.
        $targetId = CpsRefFixture::makeEntry(self::TARGET, []);

        // 1. The main Grid: every setting off its default, one column per interesting SQL type.
        $settings = [
            'grid_min_rows' => 1, 'grid_max_rows' => '3', 'allow_reorder' => 'n',
            'vertical_layout' => 'horizontal', 'row_counter' => 'y',
        ];
        self::gridField($group, self::GRID, $settings, [
            ['name' => self::TEXT, 'type' => 'text', 'label' => 'Text', 'settings' => self::textSettings(), 'search' => 'y'],
            ['name' => self::NUM, 'type' => 'number', 'label' => 'Number', 'settings' => [
                'field_min_value' => '', 'field_max_value' => '', 'field_step' => '', 'datalist_items' => '',
                'field_content_type' => 'numeric',
            ]],
            ['name' => self::DATE, 'type' => 'date', 'label' => 'Date', 'settings' => ['localize' => true, 'show_time' => true]],
            ['name' => self::FLAG, 'type' => 'toggle', 'label' => 'Flag', 'settings' => ['field_default_value' => '1']],
            ['name' => self::REL, 'type' => 'relationship', 'label' => 'Related', 'settings' => self::relationshipSettings($channelId)],
        ], 1);

        $gridId = CpsRefFixture::fieldId(self::GRID);
        $cols = [
            'text' => self::colId(self::GRID, self::TEXT), 'num' => self::colId(self::GRID, self::NUM),
            'date' => self::colId(self::GRID, self::DATE), 'flag' => self::colId(self::GRID, self::FLAG),
            'rel' => self::colId(self::GRID, self::REL),
        ];
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::GRID => ['rows' => [
                'new_row_1' => [
                    'col_id_' . $cols['text'] => 'first', 'col_id_' . $cols['num'] => '1.5',
                    'col_id_' . $cols['date'] => '1700000000', 'col_id_' . $cols['flag'] => 0,
                    'col_id_' . $cols['rel'] => ['data' => [$targetId]],
                ],
                'new_row_2' => [
                    'col_id_' . $cols['text'] => 'second', 'col_id_' . $cols['num'] => '2',
                    'col_id_' . $cols['date'] => '1700003600', 'col_id_' . $cols['flag'] => 1,
                    'col_id_' . $cols['rel'] => ['data' => []],
                ],
            ]],
        ]);

        // 2. Mutations on a Grid that already holds rows
        $this->mutateColumns($group, $channelId, $targetId);

        // 3. Row write contract
        $this->rowContract($group);

        // 4. Searchable columns
        $this->searchContract($group);

        // 5. Grid as a Fluid child
        self::gridField($group, self::CHILD, self::defaultGridSettings(), [
            ['name' => self::CHILD_COL, 'type' => 'text', 'settings' => self::textSettings()],
        ], 10);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::CHILD], 11);
        self::refreshFieldList();
        $childId = CpsRefFixture::fieldId(self::CHILD);
        $childCol = self::colId(self::CHILD, self::CHILD_COL);
        CpsRefFixture::makeEntry('cpsref-grid-fluid', [
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $childId => ['rows' => [
                'new_row_1' => ['col_id_' . $childCol => 'in fluid'],
            ]]]]],
        ]);

        $this->existingEntryWrite($group);

        // 6. Deleting a field in the request that created it
        $this->sameRequestDelete($group);

        // 7. A field created after the channel's field list was cached
        $this->lateFieldProbe($group, $channelId);
    }


    /**
     * Defect: updating ONLY a custom field on an existing entry is a silent no-op. fieldtype save() runs, but the
     * Model skips the update (and so every post_save, which is where Grid and relationship rows are written)
     * unless the entry row itself is dirty. Setting edit_date, as the control panel always does, fixes it.
     */
    private function existingEntryWrite($group): void
    {
        $field = 'cpsref_grid_exp';
        self::gridField($group, $field, self::defaultGridSettings(), [
            ['name' => 'cpsref_exp_t', 'type' => 'text', 'settings' => self::textSettings()],
        ], 30);
        $t = 'col_id_' . self::colId($field, 'cpsref_exp_t');
        $id = CpsRefFixture::makeEntry('cpsref-grid-exp', [$field => ['rows' => ['new_row_1' => [$t => 'a']]]]);
        $key = 'field_id_' . CpsRefFixture::fieldId($field);
        $read = function () use ($field, $id, $t) {
            return array_column(CpsRefFixture::gridRows($field, $id), $t);
        };

        $entry = ee('Model')->get('ChannelEntry', $id)->first();
        $entry->$key = ['rows' => ['new_row_1' => [$t => 'plain']]];
        $entry->save();
        self::probe('existing entry: assign field + save() leaves rows', json_encode($read()));
        $this->expect($read() === ['a'], 'existing entry: a field-only save was expected to be a no-op');

        $entry = ee('Model')->get('ChannelEntry', $id)->first();
        $entry->$key = ['rows' => ['new_row_1' => [$t => 'with-edit-date']]];
        $entry->edit_date = ee()->localize->now;
        $entry->save();
        self::probe('existing entry: assign field + edit_date + save() leaves rows', json_encode($read()));
        $this->expect($read() === ['with-edit-date'], 'existing entry: edit_date should make the write land');

        $entry = ee('Model')->get('ChannelEntry', $id)->first();
        $entry->$key = ['rows' => ['new_row_1' => [$t => 'marked']]];
        $entry->markAsDirty();
        $entry->save();
        self::probe('existing entry: assign field + markAsDirty() + save() leaves rows', json_encode($read()));
        $this->expect($read() === ['marked'], 'existing entry: markAsDirty() should make the write land');
    }

    /** Add, rename, retype and delete a column on a Grid that already has rows. */
    private function mutateColumns($group, int $channelId, int $targetId): void
    {
        self::gridField($group, self::MUT, self::defaultGridSettings(), [
            ['name' => self::MUT_A, 'type' => 'text', 'label' => 'A', 'settings' => self::textSettings()],
            ['name' => self::MUT_REL, 'type' => 'relationship', 'label' => 'Rel', 'settings' => self::relationshipSettings($channelId)],
        ], 2);
        $fieldId = CpsRefFixture::fieldId(self::MUT);
        $table = 'channel_grid_field_' . $fieldId;
        $a = self::colId(self::MUT, self::MUT_A);
        $rel = self::colId(self::MUT, self::MUT_REL);
        CpsRefFixture::makeEntry(self::MUT_ENTRY, [
            self::MUT => ['rows' => [
                'new_row_1' => ['col_id_' . $a => 'keep me', 'col_id_' . $rel => ['data' => [$targetId]]],
                'new_row_2' => ['col_id_' . $a => 'and me', 'col_id_' . $rel => ['data' => [$targetId]]],
            ]],
        ]);
        $entryId = CpsRefFixture::entryId(self::MUT_ENTRY);
        $this->expect(count(self::relationshipRows($entryId, $fieldId)) === 2, 'mut: expected 2 relationship rows before changes');

        // (a) ADD a column: data column appears, existing rows get '' (set_datatype() UPDATEs every row)
        $added = self::addColumn($fieldId, 2, self::MUT_ADDED, 'text', self::textSettings(), 'Added');
        $this->expect(CpsRefFixture::columnExists($table, 'col_id_' . $added), 'mut add: data column missing');
        $values = array_column(CpsRefFixture::gridRows(self::MUT, $entryId), 'col_id_' . $added);
        self::probe('add column existing rows get', json_encode($values));
        $this->expect($values === ['', ''], 'mut add: existing rows should hold empty strings, got ' . json_encode($values));
        $this->expect(
            array_column(CpsRefFixture::gridRows(self::MUT, $entryId), 'col_id_' . $a) === ['keep me', 'and me'],
            'mut add: existing data changed'
        );

        // (b) RENAME: same column id, new col_name/label. The data column is named by id, so nothing moves.
        $renamed = self::columnArray($fieldId, 0, 'cpsref_mut_renamed', 'text', self::textSettings(), 'Renamed');
        ee()->grid_model->save_col_settings($renamed, $a, 'channel');
        $this->expect(self::colId(self::MUT, 'cpsref_mut_renamed') === $a, 'mut rename: column id changed');
        $this->expect(self::colId(self::MUT, self::MUT_A) === 0, 'mut rename: old name still resolves');
        $this->expect(
            array_column(CpsRefFixture::gridRows(self::MUT, $entryId), 'col_id_' . $a) === ['keep me', 'and me'],
            'mut rename: data lost'
        );

        // (c) CHANGE TYPE text -> textarea: edit_datatype() runs the old type's delete hook, then modifies the
        // single data column in place.
        $before = CpsRefFixture::columnType($table, 'col_id_' . $a);
        $retyped = self::columnArray($fieldId, 0, 'cpsref_mut_renamed', 'textarea', [
            'field_fmt' => 'none', 'field_text_direction' => 'ltr', 'field_ta_rows' => 6, 'db_column_type' => 'mediumtext',
        ], 'Renamed');
        ee()->grid_model->save_col_settings($retyped, $a, 'channel');
        $after = CpsRefFixture::columnType($table, 'col_id_' . $a);
        self::probe('retype text->textarea column type', (string) $before . ' -> ' . (string) $after);
        $this->expect(
            array_column(CpsRefFixture::gridRows(self::MUT, $entryId), 'col_id_' . $a) === ['keep me', 'and me'],
            'mut retype: data lost'
        );
        $this->expect(
            ee()->db->select('col_type')->where('col_id', $a)->get('grid_columns')->row_array()['col_type'] === 'textarea',
            'mut retype: col_type not updated'
        );

        // (d) DELETE a relationship column: grid_model::delete_columns() removes the settings row and the data
        // column, and the fieldtype's delete hook removes that column's exp_relationships rows.
        ee()->grid_model->delete_columns([$rel], [$rel => 'relationship'], $fieldId, 'channel');
        $this->expect(! CpsRefFixture::columnExists($table, 'col_id_' . $rel), 'mut delete: data column still there');
        $this->expect(self::colId(self::MUT, self::MUT_REL) === 0, 'mut delete: settings row still there');
        $left = self::relationshipRows($entryId, $fieldId);
        self::probe('delete relationship column leaves exp_relationships rows', (string) count($left));
        $this->expect($left === [], 'mut delete: relationship rows survived the column');
        $this->expect(count(CpsRefFixture::gridRows(self::MUT, $entryId)) === 2, 'mut delete: rows were removed with the column');
        $this->expect(
            array_column(CpsRefFixture::gridRows(self::MUT, $entryId), 'col_id_' . $a) === ['keep me', 'and me'],
            'mut delete: sibling data lost'
        );
    }

    /** new_row_N / row_id_N, row_order, omitted rows, omitted cells, append. */
    private function rowContract($group): void
    {
        self::gridField($group, self::ROWS, self::defaultGridSettings(), [
            ['name' => self::ROWS_T, 'type' => 'text', 'settings' => self::textSettings()],
            ['name' => self::ROWS_N, 'type' => 'number', 'settings' => [
                'field_min_value' => '', 'field_max_value' => '', 'field_step' => '', 'datalist_items' => '',
                'field_content_type' => 'numeric',
            ]],
        ], 3);
        $t = 'col_id_' . self::colId(self::ROWS, self::ROWS_T);
        $n = 'col_id_' . self::colId(self::ROWS, self::ROWS_N);
        $fieldId = CpsRefFixture::fieldId(self::ROWS);

        CpsRefFixture::makeEntry(self::ROWS_ENTRY, [
            self::ROWS => ['rows' => [
                'new_row_1' => [$t => 'one', $n => '1'],
                'new_row_2' => [$t => 'two', $n => '2'],
                'new_row_3' => [$t => 'three', $n => '3'],
            ]],
        ]);
        $entryId = CpsRefFixture::entryId(self::ROWS_ENTRY);
        $rows = CpsRefFixture::gridRows(self::ROWS, $entryId);
        $ids = array_map('intval', array_column($rows, 'row_id'));
        $this->expect(count($ids) === 3, 'rows: expected 3 rows');
        $this->expect(array_map('intval', array_column($rows, 'row_order')) === [0, 1, 2], 'rows: row_order should be 0,1,2');
        [$one, $two, $three] = $ids;

        // Append: resubmit every existing row WITH its values, plus one new row. Existing row ids are kept.
        $existing = [];
        foreach ($rows as $row) {
            $existing['row_id_' . $row['row_id']] = [$t => $row[$t], $n => $row[$n]];
        }
        self::writeRows(self::ROWS_ENTRY, self::ROWS, $existing + ['new_row_1' => [$t => 'four', $n => '4']]);
        $rows = CpsRefFixture::gridRows(self::ROWS, $entryId);
        $this->expect(array_slice(array_map('intval', array_column($rows, 'row_id')), 0, 3) === $ids, 'rows append: existing row ids changed');
        $this->expect(array_column($rows, $t) === ['one', 'two', 'three', 'four'], 'rows append: wrong values ' . json_encode(array_column($rows, $t)));
        $four = (int) $rows[3]['row_id'];

        // An existing row submitted with an EMPTY cell blanks that cell (every column is saved, missing = null)
        self::writeRows(self::ROWS_ENTRY, self::ROWS, [
            'row_id_' . $one => [$t => 'one-edited'],
            'row_id_' . $two => [$t => 'two', $n => '2'],
            'row_id_' . $three => [$t => 'three', $n => '3'],
            'row_id_' . $four => [$t => 'four', $n => '4'],
        ]);
        $rows = CpsRefFixture::gridRows(self::ROWS, $entryId);
        self::probe('omitted cell on an existing row becomes', var_export($rows[0][$n], true));
        $this->expect($rows[0][$t] === 'one-edited' && $rows[0][$n] === null, 'rows partial: omitted cell should be NULL, got ' . var_export($rows[0][$n], true));

        // Reorder: row_order follows the array position; ids are unchanged
        $submit = [];
        foreach ([$three, $one, $two, $four] as $id) {
            $row = ee()->db->where('row_id', $id)->get('channel_grid_field_' . $fieldId)->row_array();
            $submit['row_id_' . $id] = [$t => $row[$t], $n => $row[$n] ?? '1'];
        }
        self::writeRows(self::ROWS_ENTRY, self::ROWS, $submit);
        $rows = CpsRefFixture::gridRows(self::ROWS, $entryId);
        $this->expect(array_map('intval', array_column($rows, 'row_id')) === [$three, $one, $two, $four], 'rows reorder: wrong order');
        $this->expect(array_map('intval', array_column($rows, 'row_order')) === [0, 1, 2, 3], 'rows reorder: row_order wrong');

        // A row left out of the submitted array is DELETED
        $submit = [];
        foreach ([$three, $one, $two] as $id) {
            $row = ee()->db->where('row_id', $id)->get('channel_grid_field_' . $fieldId)->row_array();
            $submit['row_id_' . $id] = [$t => $row[$t], $n => $row[$n] ?? '1'];
        }
        self::writeRows(self::ROWS_ENTRY, self::ROWS, $submit);
        $this->expect(count(CpsRefFixture::gridRows(self::ROWS, $entryId)) === 3, 'rows omit: omitted row should be deleted');
        $this->expect(
            ee()->db->where('row_id', $four)->count_all_results('channel_grid_field_' . $fieldId) === 0,
            'rows omit: row four still exists'
        );

        // An empty rows array deletes every row
        self::writeRows(self::ROWS_ENTRY, self::ROWS, []);
        $this->expect(CpsRefFixture::gridRows(self::ROWS, $entryId) === [], 'rows clear: rows should be gone');

        // Leave a known final state for verify()
        self::writeRows(self::ROWS_ENTRY, self::ROWS, [
            'new_row_1' => [$t => 'final-a', $n => '10'],
            'new_row_2' => [$t => 'final-b', $n => '20'],
        ]);
    }

    /** col_search + field_search: what is written to the field's own data column, and when. */
    private function searchContract($group): void
    {
        self::gridField($group, self::SEARCH, self::defaultGridSettings(), [
            ['name' => self::SEARCH_COL, 'type' => 'text', 'settings' => self::textSettings(), 'search' => 'y'],
        ], 4, ['field_search' => 'y']);
        $col = 'col_id_' . self::colId(self::SEARCH, self::SEARCH_COL);
        $fieldId = CpsRefFixture::fieldId(self::SEARCH);

        // Model save without validate(): the searchable data is gathered during validate(), so nothing is written
        CpsRefFixture::makeEntry(self::SEARCH_ONE, [
            self::SEARCH => ['rows' => ['new_row_1' => [$col => 'alpha'], 'new_row_2' => [$col => 'beta']]],
        ]);
        $one = CpsRefFixture::entryId(self::SEARCH_ONE);
        self::probe('search data after save() without validate()', var_export(CpsRefFixture::fieldValue(self::SEARCH, $one), true));
        $this->expect(CpsRefFixture::fieldValue(self::SEARCH, $one) === null, 'search: unexpected search data without validate()');

        // validate() first, then save(): the compound value is written
        $two = CpsRefFixture::makeEntry(self::SEARCH_TWO, []);
        $entry = ee('Model')->get('ChannelEntry', $two)->first();
        $entry->{'field_id_' . $fieldId} = ['rows' => ['new_row_1' => [$col => 'gamma'], 'new_row_2' => [$col => 'delta']]];
        $entry->edit_date = ee()->localize->now;
        $result = $entry->validate();
        $this->expect($result->isValid(), 'search: validate() failed ' . json_encode($result->getAllErrors()));
        $entry->save();
        self::probe('search data after validate() + save()', var_export(CpsRefFixture::fieldValue(self::SEARCH, $two), true));
        $this->expect(CpsRefFixture::fieldValue(self::SEARCH, $two) === 'gamma|delta', 'search: validate()+save() should write gamma|delta');

        // grid_model::update_grid_search() rebuilds the value for every entry from the row tables (migration-safe)
        ee()->grid_model->update_grid_search([$fieldId]);
        $this->expect(CpsRefFixture::fieldValue(self::SEARCH, $one) === 'alpha|beta', 'search: update_grid_search() did not fill entry one');
        $this->expect(CpsRefFixture::fieldValue(self::SEARCH, $two) === 'gamma|delta', 'search: update_grid_search() changed entry two');

        // col_search on a Grid whose field_search is 'n' (the main Grid's text column): nothing is stored
        ee()->grid_model->update_grid_search([CpsRefFixture::fieldId(self::GRID)]);
        $main = CpsRefFixture::entryId(self::ENTRY);
        $this->expect(CpsRefFixture::fieldValue(self::GRID, $main) === null, 'search: col_search without field_search must store nothing');
    }

    /** Defect 3a: delete a Grid field in the same request that created it. */
    private function sameRequestDelete($group): void
    {
        $field = self::gridField($group, 'cpsref_grid_doomed', self::defaultGridSettings(), [
            ['name' => 'cpsref_doomed_col', 'type' => 'text', 'settings' => self::textSettings()],
        ], 12);
        $id = (int) $field->field_id;
        $tables = ['channel_data_field_' . $id, 'channel_grid_field_' . $id];
        self::probe('doomed tables after create', json_encode(self::showTables($tables)));
        $columnsBefore = ee()->db->where('field_id', $id)->count_all_results('grid_columns');
        $field->delete();
        $after = self::showTables($tables);
        self::probe('doomed tables after delete in same request', json_encode($after));
        self::probe(
            'doomed grid_columns rows before/after delete',
            $columnsBefore . '/' . ee()->db->where('field_id', $id)->count_all_results('grid_columns')
        );
        // Safe pattern: plain SQL, never table_exists()/list_fields() (both cached per request)
        CpsRefFixture::dropDataTableIfExists($id);
        $this->expect(self::showTables($tables) === ['channel_data_field_' . $id => false, 'channel_grid_field_' . $id => false], 'doomed: tables still exist after the safe drop');
        ee()->db->where('field_id', $id)->delete('grid_columns');
    }

    /**
     * Defect 3b: an entry write to a field created after the channel's custom-field list was cached in the
     * session. Channel::getAllCustomFields() caches that list in ee()->session once an entry has been saved; a
     * field created later is invisible to ChannelEntry, so assigning field_id_N is silently dropped.
     */
    private function lateFieldProbe($group, int $channelId): void
    {
        // Prime the cache the way any earlier entry save in the same request does.
        CpsRefFixture::makeEntry('cpsref-grid-warm', []);
        self::probe('session present before late-field probe', isset(ee()->session) ? 'yes' : 'no');

        // Without refreshing the cached list (what a plain makeField + makeEntry does)
        self::lateGrid($group, 'late1', 20, false);
        $rows = self::lateWrite('late1', 'cpsref-grid-late-1');
        self::probe('late field written, stale cached field list', $rows . ' row(s)');

        // Remedy A: drop the cached list for the channel, then write
        self::refreshFieldList();
        $rows = self::lateWrite('late1', 'cpsref-grid-late-1b');
        self::probe('same field, after dropping the cached list', $rows . ' row(s)');
        $this->expect($rows === 1, 'late1: dropping the cached field list should make the write land');

        // Remedy B: refresh right after creating the field (what gridField() does by default)
        self::lateGrid($group, 'late2', 21, true);
        $rows = self::lateWrite('late2', 'cpsref-grid-late-2');
        self::probe('field created with refresh', $rows . ' row(s)');
        $this->expect($rows === 1, 'late2: refreshing after create should make the write land');
    }

    private static function lateGrid($group, string $suffix, int $order, bool $refresh): void
    {
        self::gridField($group, 'cpsref_grid_' . $suffix, self::defaultGridSettings(), [
            ['name' => 'cpsref_' . $suffix . '_col', 'type' => 'text', 'settings' => self::textSettings()],
        ], $order, [], $refresh);
    }

    /** Write one row to a late field on a new entry and count the Grid rows that landed. */
    private static function lateWrite(string $suffix, string $entryUrlTitle): int
    {
        $field = 'cpsref_grid_' . $suffix;
        $col = CpsRefFixture::gridColumnId($field, 'cpsref_' . $suffix . '_col');
        CpsRefFixture::makeEntry($entryUrlTitle, [
            $field => ['rows' => ['new_row_1' => ['col_id_' . $col => 'late']]],
        ]);

        return count(CpsRefFixture::gridRows($field, CpsRefFixture::entryId($entryUrlTitle)));
    }

    // ------------------------------------------------------------------------------------------------ verify

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        $check = function (bool $condition, string $message) use (&$problems) {
            CpsRefFixture::check($problems, $condition, $message);
        };

        // Settings contract: exactly five keys, the values written
        $settings = CpsRefFixture::fieldSettings(self::GRID);
        foreach (['grid_min_rows', 'grid_max_rows', 'allow_reorder', 'vertical_layout', 'row_counter'] as $key) {
            $check(array_key_exists($key, $settings), "grid settings missing $key");
        }
        $check(($settings['grid_min_rows'] ?? null) === 1, 'grid_min_rows did not round-trip as int 1');
        $check(($settings['grid_max_rows'] ?? null) === '3', 'grid_max_rows did not round-trip as string 3');
        $check(($settings['allow_reorder'] ?? null) === 'n', 'allow_reorder did not store n');
        $check(($settings['vertical_layout'] ?? null) === 'horizontal', 'vertical_layout did not store horizontal');
        $check(($settings['row_counter'] ?? null) === 'y', 'row_counter did not store y');

        // Storage: data table, fixed columns, one col_id_N per column with the type its fieldtype returns
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $table = 'channel_grid_field_' . $gridId;
        foreach (['row_id' => 'int(10) unsigned', 'entry_id' => 'int(10) unsigned', 'row_order' => 'int(10) unsigned',
            'fluid_field_data_id' => 'int(10) unsigned'] as $column => $type) {
            $check(CpsRefFixture::columnType($table, $column) === $type, "$column type is " . CpsRefFixture::columnType($table, $column));
        }
        $expected = [
            self::TEXT => 'text', self::NUM => 'float', self::DATE => 'varchar(60)',
            self::FLAG => 'tinyint(1)', self::REL => 'varchar(8)',
        ];
        $columns = self::columns(self::GRID);
        $check(array_keys($columns) === array_keys($expected), 'grid_columns order/names: ' . implode(',', array_keys($columns)));
        $order = 0;
        foreach ($expected as $name => $type) {
            $column = $columns[$name] ?? null;
            $check($column !== null, "column $name missing");
            if ($column === null) {
                continue;
            }
            $actual = CpsRefFixture::columnType($table, 'col_id_' . $column['col_id']);
            $check($actual === $type, "column $name data type is $actual, expected $type");
            $check((int) $column['field_id'] === $gridId && $column['content_type'] === 'channel', "column $name field_id/content_type wrong");
            $check((int) $column['col_order'] === $order, "column $name col_order is " . $column['col_order']);
            $check(is_array(json_decode($column['col_settings'], true)), "column $name col_settings is not JSON");
            $order++;
        }
        $check(ee()->db->query('SELECT COUNT(*) AS n FROM exp_grid_columns WHERE field_id IS NULL OR field_id = 0')->row_array()['n'] === '0', 'orphan grid_columns rows (field_id NULL/0)');

        // Rows and the relationship cell
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $text = 'col_id_' . ($columns[self::TEXT]['col_id'] ?? 0);
        $flag = 'col_id_' . ($columns[self::FLAG]['col_id'] ?? 0);
        $check(array_column($rows, $text) === ['first', 'second'], 'main rows text wrong');
        $check(array_map('intval', array_column($rows, $flag)) === [0, 1], 'toggle column wrong');
        $relRows = self::relationshipRows($entryId, $gridId);
        $check(count($relRows) === 1 && (int) $relRows[0]['grid_col_id'] === (int) ($columns[self::REL]['col_id'] ?? -1), 'relationship cell rows wrong: ' . json_encode($relRows));
        $check(CpsRefFixture::fieldValue(self::GRID, $entryId) === null, 'field_search n: the field column must stay NULL');

        // Mutations: final state
        $mutId = CpsRefFixture::fieldId(self::MUT);
        $mut = self::columns(self::MUT);
        $check(array_keys($mut) === ['cpsref_mut_renamed', self::MUT_ADDED], 'mut columns: ' . implode(',', array_keys($mut)));
        $mutTable = 'channel_grid_field_' . $mutId;
        $check(CpsRefFixture::columnType($mutTable, 'col_id_' . ($mut['cpsref_mut_renamed']['col_id'] ?? 0)) === 'mediumtext', 'retyped column is not mediumtext');
        $check(self::relationshipRows(CpsRefFixture::entryId(self::MUT_ENTRY), $mutId) === [], 'mut: relationship rows remain');

        // Row contract final state
        $rowsId = CpsRefFixture::entryId(self::ROWS_ENTRY);
        $final = CpsRefFixture::gridRows(self::ROWS, $rowsId);
        $check(array_column($final, 'col_id_' . CpsRefFixture::gridColumnId(self::ROWS, self::ROWS_T)) === ['final-a', 'final-b'], 'rows final state wrong');

        // Search
        $check(CpsRefFixture::fieldValue(self::SEARCH, CpsRefFixture::entryId(self::SEARCH_ONE)) === 'alpha|beta', 'search value wrong');

        // Fluid child: the Grid row carries fluid_field_data_id
        $fluidEntry = CpsRefFixture::entryId('cpsref-grid-fluid');
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $fluidEntry);
        $childRows = CpsRefFixture::gridRows(self::CHILD, $fluidEntry);
        $check(count($fluid) === 1 && count($childRows) === 1, 'fluid: expected one fluid row and one Grid row');
        $check(count($fluid) === 1 && count($childRows) === 1 && (int) $childRows[0]['fluid_field_data_id'] === (int) $fluid[0]['id'], 'fluid: grid row fluid_field_data_id does not match');

        return $problems;
    }
}
