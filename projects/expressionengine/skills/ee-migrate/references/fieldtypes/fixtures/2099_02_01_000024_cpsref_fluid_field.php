<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: fluid_field (Plan 2 Task 7). Proves, on the throwaway cpsref_fixture channel:
 *
 *  - the settings contract (field_channel_fields / field_channel_field_groups) and the children it lists
 *    (text, url, toggle, a Grid and a relationship field);
 *  - the storage layout: exp_fluid_field_data rows plus one row per child value in the CHILD's own
 *    exp_channel_data_field_N table (entry_id = 0), Grid rows and relationship rows tagged with
 *    fluid_field_data_id;
 *  - the content write contract: new_field_N appends, field_<fluid_field_data.id> updates, omitted rows are deleted
 *    (with their Grid and relationship rows), array order is row order;
 *  - the Fluid caches that make a second write in the same request fail, and how to clear them;
 *  - changing the child list on a Fluid field that holds data (direct settings write vs the set() path vs deleting
 *    the child field), and what deleting a Fluid field leaves behind;
 *  - a Fluid field created after the channel's field list was cached (entry writes silently dropped).
 *
 * Everything the run observed and that a reference may rely on is asserted in up() (a deviation throws) or in
 * verify(); PROBE lines in the migrate log record the rest. down() removes every cpsref* row and table.
 */
class CpsrefFluidField extends Migration
{
    const FLUID = 'cpsref_fl_fluid';
    const TEXT = 'cpsref_fl_text';
    const URL = 'cpsref_fl_url';
    const FLAG = 'cpsref_fl_flag';
    const GRID = 'cpsref_fl_grid';
    const GRID_COL = 'cpsref_fl_grid_text';
    const REL = 'cpsref_fl_rel';
    const CHILD_A = 'cpsref_fl_child_a';
    const CHILD_B = 'cpsref_fl_child_b';
    const CHILD_C = 'cpsref_fl_child_c';
    const UNLISTED = 'cpsref_fl_unlisted';
    const DROPPED = 'cpsref_fl_dropped';
    const LATE = 'cpsref_fl_late';

    const TARGET = 'cpsref-fl-target';
    const KEEP = 'cpsref-fl-keep';
    const MUT = 'cpsref-fl-mut';
    const STALE = 'cpsref-fl-stale';
    const CHILDREN = 'cpsref-fl-children';
    const DROP_ENTRY = 'cpsref-fl-drop';

    /** @var string[] */
    private $problems = [];

    public function up()
    {
        try {
            $this->build();
            if ($this->problems !== []) {
                throw new \RuntimeException('fluid_field fixture up() assertions failed: ' . implode('; ', $this->problems));
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

    private static function textSettings(): array
    {
        return [
            'field_maxl' => 100, 'field_content_type' => 'all',
            'field_show_smileys' => 'n', 'field_show_file_selector' => 'n',
        ];
    }

    private static function textNative(): array
    {
        return ['field_maxl' => 100, 'field_text_direction' => 'ltr', 'field_fmt' => 'none'];
    }

    /** A text field that is not attached to any field group: the normal shape of a Fluid child. */
    private static function makeTextChild(string $name, int $order)
    {
        return CpsRefFixture::makeField(null, $name, 'text', self::textSettings(), $order, self::textNative());
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

    /**
     * Channel::getAllCustomFields() caches the channel's field list in the session once any entry in the channel has
     * been saved in this request; a field created afterwards is invisible to ChannelEntry and assigning field_id_N on
     * the entry is silently dropped. Drop that cache entry after creating a top-level field.
     */
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

    /**
     * ee()->db->table_exists() answers from a table list cached for the whole request, so a table created earlier in
     * this request is "missing" to code such as FluidField::onAfterDelete(). A real migration runs in one request, so
     * the fixture resets the list to behave like a Fluid edit made in a later request.
     */
    private static function resetTableCache(): void
    {
        unset(ee()->db->data_cache['table_names']);
    }

    /**
     * ft.fluid_field.php::getFieldData() caches the entry's FluidField collection in the session under
     * "FluidField/<fluid field id>/<entry id>", and the first save of a new entry caches it EMPTY. A second write to
     * the same entry in the same request then does not see its rows. Clear it before every write to an existing entry.
     */
    private static function forgetFluidCache(string $fluidName, int $entryId): void
    {
        ee()->session->set_cache('FluidField', 'FluidField/' . CpsRefFixture::fieldId($fluidName) . '/' . $entryId, false);
    }

    /** Write Fluid rows to an existing entry through the Model, clearing the Fluid cache first. */
    private static function writeFluid(string $entryUrlTitle, string $fluidName, array $fields, bool $forget = true): void
    {
        $entryId = CpsRefFixture::entryId($entryUrlTitle);
        if ($forget) {
            self::forgetFluidCache($fluidName, $entryId);
        }
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $entry->{'field_id_' . CpsRefFixture::fieldId($fluidName)} = ['fields' => $fields];
        // A field-only change leaves the entry row clean and the Model skips the save: set edit_date.
        $entry->edit_date = ee()->localize->now;
        $entry->save();
    }

    private static function dataRow(string $fieldName, int $dataId): array
    {
        $fieldId = CpsRefFixture::fieldId($fieldName);
        $table = ee()->db->dbprefix . 'channel_data_field_' . $fieldId;

        return ee()->db->query('SELECT * FROM `' . $table . '` WHERE id = ' . (int) $dataId)->row_array() ?: [];
    }

    private static function dataValue(string $fieldName, int $dataId): ?string
    {
        $row = self::dataRow($fieldName, $dataId);

        return $row['field_id_' . CpsRefFixture::fieldId($fieldName)] ?? null;
    }

    /** Rows in a child's own data table with entry_id = 0 (the rows Fluid owns). */
    private static function childRowCount(string $fieldName): int
    {
        $table = ee()->db->dbprefix . 'channel_data_field_' . CpsRefFixture::fieldId($fieldName);

        return (int) ee()->db->query('SELECT COUNT(*) AS n FROM `' . $table . '` WHERE entry_id = 0')->row()->n;
    }

    private static function fluidRowCount(int $fieldId): int
    {
        return (int) ee()->db->where('field_id', $fieldId)->count_all_results('fluid_field_data');
    }

    private static function relationshipRows(int $entryId, int $fieldId): array
    {
        return ee()->db->where(['parent_id' => $entryId, 'field_id' => $fieldId])
            ->order_by('order')->get('relationships')->result_array();
    }

    /** Row ids of the Fluid rows, in order. */
    private static function rowIds(array $rows): array
    {
        return array_map('intval', array_column($rows, 'id'));
    }

    /** The field ids of the Fluid rows, in order. */
    private static function rowFieldIds(array $rows): array
    {
        return array_map('intval', array_column($rows, 'field_id'));
    }

    /** Merge new children into the Fluid field's settings with a direct property write (what migrations use). */
    private static function setChildren(string $fluidName, array $childNames): void
    {
        $fluid = ee('Model')->get('ChannelField')->filter('field_name', $fluidName)->first();
        $settings = $fluid->field_settings;
        $settings['field_channel_fields'] = array_map([CpsRefFixture::class, 'fieldId'], $childNames);
        $fluid->field_settings = $settings;
        $fluid->save();
    }

    private static function children(string $fluidName): array
    {
        $settings = CpsRefFixture::fieldSettings($fluidName);

        return array_map('intval', (array) ($settings['field_channel_fields'] ?? []));
    }

    /** The initial row set used for the KEEP and MUT entries; ids are those of the child fields. */
    private static function initialFields(int $targetId): array
    {
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::GRID_COL);

        return [
            'new_field_1' => ['field_id_' . CpsRefFixture::fieldId(self::TEXT) => 'alpha'],
            'new_field_2' => ['field_id_' . CpsRefFixture::fieldId(self::GRID) => ['rows' => [
                'new_row_1' => ['col_id_' . $colId => 'g1'],
                'new_row_2' => ['col_id_' . $colId => 'g2'],
            ]]],
            'new_field_3' => ['field_id_' . CpsRefFixture::fieldId(self::REL) => ['data' => [$targetId]]],
            'new_field_4' => ['field_id_' . CpsRefFixture::fieldId(self::URL) => 'https://example.com/fluid'],
            'new_field_5' => ['field_id_' . CpsRefFixture::fieldId(self::FLAG) => 1],
            'new_field_6' => ['field_id_' . CpsRefFixture::fieldId(self::TEXT) => 'omega'],
        ];
    }

    // ------------------------------------------------------------------------------------------------ build

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $channelId = (int) $container['channel']->channel_id;

        // Children first: Fluid settings reference them by field id. They are NOT attached to a field group.
        self::makeTextChild(self::TEXT, 1);
        CpsRefFixture::makeField(null, self::URL, 'url', [
            'field_fmt' => 'none', 'field_required' => 'n',
            'allowed_url_schemes' => ['http://', 'https://'], 'url_scheme_placeholder' => 'https://',
        ], 2);
        CpsRefFixture::makeField(null, self::FLAG, 'toggle', ['field_default_value' => '0'], 3);
        CpsRefFixture::makeGridField(null, self::GRID, [[
            'name' => self::GRID_COL, 'type' => 'text', 'label' => 'Grid text', 'settings' => [
                'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr',
                'field_maxl' => 100, 'field_required' => 'n',
            ],
        ]], 4);
        CpsRefFixture::makeField(null, self::REL, 'relationship', self::relationshipSettings($channelId), 5);

        // The Fluid field: ids are integers (the control panel posts strings; both work, see the reference).
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::TEXT, self::URL, self::FLAG, self::GRID, self::REL], 10);

        $targetId = CpsRefFixture::makeEntry(self::TARGET, []);
        $fluidId = CpsRefFixture::fieldId(self::FLUID);
        $textId = CpsRefFixture::fieldId(self::TEXT);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $relId = CpsRefFixture::fieldId(self::REL);

        self::probe(
            'table_exists() on a table created this request (cached list)',
            ee()->db->table_exists(ee()->db->dbprefix . 'channel_data_field_' . $textId) ? 'true' : 'false'
        );
        self::resetTableCache();

        // 1. Create two entries with identical Fluid content: KEEP stays untouched for verify(), MUT is mutated.
        CpsRefFixture::makeEntry(self::KEEP, [self::FLUID => ['fields' => self::initialFields($targetId)]]);
        CpsRefFixture::makeEntry(self::MUT, [self::FLUID => ['fields' => self::initialFields($targetId)]]);
        $keepId = CpsRefFixture::entryId(self::KEEP);
        $keepRows = CpsRefFixture::fluidRows(self::FLUID, $keepId);
        $this->expect(count($keepRows) === 6, 'create: expected 6 fluid rows, found ' . count($keepRows));
        self::probe('create: fluid_field_data rows', json_encode($keepRows));
        self::probe('create: Fluid field own column', var_export(CpsRefFixture::fieldValue(self::FLUID, $keepId), true));

        // 2. Same-request cache: a second write to an existing entry without clearing the Fluid cache.
        $this->staleCacheProbe();

        // 3. Update / reorder / append / omit
        $this->updateContract($targetId);

        // 4. Child list changes with data
        $this->childListChanges();

        // 4b. Deleting an entry that holds Fluid rows
        $this->entryDelete($targetId);

        // 5. Deleting a Fluid field that holds data
        $this->dropFluidField($targetId);

        // 6. A Fluid field created after the channel's field list was cached
        $this->lateFieldProbe();
    }

    /** Update a Fluid row of an existing entry in the same request that created it, without clearing the cache. */
    private function staleCacheProbe(): void
    {
        $textKey = 'field_id_' . CpsRefFixture::fieldId(self::TEXT);
        CpsRefFixture::makeEntry(self::STALE, [self::FLUID => ['fields' => ['new_field_1' => [$textKey => 'one']]]]);
        $entryId = CpsRefFixture::entryId(self::STALE);
        $rowId = (int) (CpsRefFixture::fluidRows(self::FLUID, $entryId)[0]['id'] ?? 0);

        $outcome = 'no error';
        try {
            self::writeFluid(self::STALE, self::FLUID, ['field_' . $rowId => [$textKey => 'two']], false);
        } catch (\Throwable $e) {
            $outcome = get_class($e) . ': ' . $e->getMessage();
        }
        $rows = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $value = $rows ? self::dataValue(self::TEXT, (int) $rows[0]['field_data_id']) : null;
        self::probe('stale cache: update without clearing', $outcome . ' / rows=' . count($rows) . ' / value=' . $value);

        // With the cache cleared the same update lands.
        self::writeFluid(self::STALE, self::FLUID, ['field_' . $rowId => [$textKey => 'three']]);
        $rows = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $this->expect(count($rows) === 1, 'stale: expected 1 fluid row after the cleared-cache update');
        $this->expect(
            $rows && self::dataValue(self::TEXT, (int) $rows[0]['field_data_id']) === 'three',
            'stale: cleared-cache update did not land'
        );
        $this->expect($rows && (int) $rows[0]['id'] === $rowId, 'stale: an update must keep the fluid row id');
        $this->expect(
            $outcome !== 'no error' || ($value !== 'two'),
            'stale: a second write without clearing the cache unexpectedly worked'
        );
    }

    /** Existing rows update by field_<fluid_field_data.id>, new rows by new_field_N, omitted rows are deleted. */
    private function updateContract(int $targetId): void
    {
        $textId = CpsRefFixture::fieldId(self::TEXT);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $relId = CpsRefFixture::fieldId(self::REL);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::GRID_COL);
        $entryId = CpsRefFixture::entryId(self::MUT);
        $before = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $ids = self::rowIds($before);
        [$alphaRow, $gridRow, $relRow, $urlRow, $flagRow, $omegaRow] = $ids;
        $urlData = (int) $before[3]['field_data_id'];
        $gridRowsBefore = CpsRefFixture::gridRows(self::GRID, $entryId);
        $firstGridRowId = (int) $gridRowsBefore[0]['row_id'];

        // Reordered: omega, alpha, grid, rel, then a new text row. URL and toggle rows are omitted.
        self::writeFluid(self::MUT, self::FLUID, [
            'field_' . $omegaRow => ['field_id_' . $textId => 'omega-changed'],
            'field_' . $alphaRow => ['field_id_' . $textId => 'alpha-changed'],
            'field_' . $gridRow => ['field_id_' . $gridId => ['rows' => [
                'row_id_' . $firstGridRowId => ['col_id_' . $colId => 'g1-changed'],
                'new_row_1' => ['col_id_' . $colId => 'g3-new'],
            ]]],
            'field_' . $relRow => ['field_id_' . $relId => ['data' => [$targetId]]],
            'new_field_1' => ['field_id_' . $textId => 'appended'],
        ]);

        $after = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        self::probe('update: fluid_field_data rows', json_encode($after));
        $afterIds = self::rowIds($after);
        $this->expect(
            array_slice($afterIds, 0, 4) === [$omegaRow, $alphaRow, $gridRow, $relRow] && count($afterIds) === 5,
            'update: expected rows [omega, alpha, grid, rel, new], got ' . json_encode($afterIds)
        );
        $this->expect(array_map('intval', array_column($after, 'order')) === [1, 2, 3, 4, 5], 'update: order column not 1..5');
        $this->expect(
            self::dataValue(self::TEXT, (int) $after[0]['field_data_id']) === 'omega-changed'
                && self::dataValue(self::TEXT, (int) $after[1]['field_data_id']) === 'alpha-changed'
                && self::dataValue(self::TEXT, (int) $after[4]['field_data_id']) === 'appended',
            'update: text values did not read back'
        );
        $this->expect(
            ! ee()->db->where('id', $urlRow)->count_all_results('fluid_field_data')
                && ! ee()->db->where('id', $flagRow)->count_all_results('fluid_field_data'),
            'update: omitted rows were not deleted from fluid_field_data'
        );
        $this->expect(self::dataRow(self::URL, $urlData) === [], 'update: the omitted URL row survived in its data table');

        $gridRows = CpsRefFixture::gridRows(self::GRID, $entryId);
        self::probe('update: grid rows', json_encode($gridRows));
        $this->expect(count($gridRows) === 2, 'update: expected 2 grid rows (updated, appended; omitted one removed)');
        $this->expect(
            ($gridRows[0]['col_id_' . $colId] ?? '') === 'g1-changed' && (int) $gridRows[0]['row_id'] === $firstGridRowId,
            'update: grid row_id_N did not update in place'
        );
        $this->expect(($gridRows[1]['col_id_' . $colId] ?? '') === 'g3-new', 'update: new grid row not appended');
        $this->expect(
            (int) $gridRows[0]['fluid_field_data_id'] === $gridRow && (int) $gridRows[1]['fluid_field_data_id'] === $gridRow,
            'update: grid rows lost their fluid_field_data_id'
        );
        $this->expect(count(self::relationshipRows($entryId, $relId)) === 1, 'update: relationship row lost');

        // Omit the Grid row and the relationship row: their Grid and relationship rows go with them.
        $textRows = [];
        foreach ($after as $row) {
            if ((int) $row['field_id'] === $textId) {
                $textRows['field_' . $row['id']] = ['field_id_' . $textId => self::dataValue(
                    self::TEXT,
                    (int) $row['field_data_id']
                )];
            }
        }
        self::writeFluid(self::MUT, self::FLUID, $textRows);
        $final = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $this->expect(count($final) === 3, 'omit: expected 3 fluid rows, found ' . count($final));
        $this->expect(CpsRefFixture::gridRows(self::GRID, $entryId) === [], 'omit: Grid rows of the omitted row survived');
        $this->expect(self::relationshipRows($entryId, $relId) === [], 'omit: relationship rows of the omitted row survived');
        $this->expect(
            self::fluidRowCount($gridId) === 1 && self::fluidRowCount($relId) === 1,
            'omit: only the KEEP entry should still own grid / relationship fluid rows'
        );

        // Writing an empty field list is the same as omitting everything.
        $emptyEntry = CpsRefFixture::entryId(self::STALE);
        self::writeFluid(self::STALE, self::FLUID, []);
        $this->expect(
            CpsRefFixture::fluidRows(self::FLUID, $emptyEntry) === [],
            'omit: an empty fields array should delete every row'
        );
    }

    /** Adding, removing and deleting children of a Fluid field that already holds rows. */
    private function childListChanges(): void
    {
        $base = [self::TEXT, self::URL, self::FLAG, self::GRID, self::REL];
        self::makeTextChild(self::CHILD_A, 20);
        self::makeTextChild(self::CHILD_B, 21);
        self::makeTextChild(self::CHILD_C, 22);
        self::makeTextChild(self::UNLISTED, 23);
        self::resetTableCache();

        // (a) add children: a direct settings write is enough, no save_settings() is involved
        self::setChildren(self::FLUID, array_merge($base, [self::CHILD_A, self::CHILD_B, self::CHILD_C]));
        $children = self::children(self::FLUID);
        $this->expect(
            in_array(CpsRefFixture::fieldId(self::CHILD_A), $children, true) && count($children) === 8,
            'add child: settings did not store the 8 child ids: ' . json_encode($children)
        );

        $write = [
            'new_field_1' => ['field_id_' . CpsRefFixture::fieldId(self::CHILD_A) => 'a-value'],
            'new_field_2' => ['field_id_' . CpsRefFixture::fieldId(self::CHILD_B) => 'b-value'],
            'new_field_3' => ['field_id_' . CpsRefFixture::fieldId(self::CHILD_C) => 'c-value'],
            'new_field_4' => ['field_id_' . CpsRefFixture::fieldId(self::UNLISTED) => 'unlisted-value'],
        ];
        CpsRefFixture::makeEntry(self::CHILDREN, [self::FLUID => ['fields' => $write]]);
        $entryId = CpsRefFixture::entryId(self::CHILDREN);
        $rows = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        $this->expect(count($rows) === 4, 'add child: expected 4 rows incl. the unlisted child, got ' . count($rows));
        self::probe('children: a field NOT in field_channel_fields written anyway', count($rows) === 4 ? 'stored' : 'refused');

        $aId = CpsRefFixture::fieldId(self::CHILD_A);
        $bId = CpsRefFixture::fieldId(self::CHILD_B);
        $cId = CpsRefFixture::fieldId(self::CHILD_C);

        // (b) remove A with a direct settings write: the rows stay (orphans), nothing cleans them
        self::setChildren(self::FLUID, array_merge($base, [self::CHILD_B, self::CHILD_C]));
        $this->expect(! in_array($aId, self::children(self::FLUID), true), 'remove A: still listed');
        $this->expect(self::fluidRowCount($aId) === 1, 'remove A (direct write): the fluid row should be left in place');
        $this->expect(self::childRowCount(self::CHILD_A) === 1, 'remove A (direct write): its data row should be left');

        // (c) remove B through the same set() path the control panel uses: save_settings() deletes its rows
        $this->removeViaSet(self::FLUID, array_merge($base, [self::CHILD_C]), $bId);

        // (d) delete the child FIELD: the Model strips it from every Fluid field and deletes its rows
        foreach ([self::CHILD_A, self::CHILD_C] as $name) {
            $id = CpsRefFixture::fieldId($name);
            $id = CpsRefFixture::fieldId($name);
            ee('Model')->get('ChannelField')->filter('field_name', $name)->first()->delete();
            CpsRefFixture::dropDataTableIfExists($id);
            $this->expect(self::fluidRowCount($id) === 0, "delete child $name: fluid rows survived the field");
        }
        // ChannelField::removeFromFluidFields() is meant to strip the deleted id from every Fluid field's settings;
        // on 7.5.27 it was observed to leave it in place, so the recipe strips it explicitly.
        self::probe('children: settings right after deleting A and C', json_encode(self::children(self::FLUID)));
        self::setChildren(self::FLUID, $base);
        $this->expect(count(self::children(self::FLUID)) === 5, 'children: expected the 5 base children to remain');
        $this->expect(count(CpsRefFixture::fluidRows(self::FLUID, $entryId)) === 1, 'children: only UNLISTED should be left');
    }

    /** Remove a child with $field->set() (the control panel path) and report what save_settings() did to its rows. */
    private function removeViaSet(string $fluidName, array $remaining, int $removedFieldId): void
    {
        // save_settings() flags search_reindex_needed in exp_config; remember it so the fixture leaves no trace.
        $row = ee()->db->where(['site_id' => 0, 'key' => 'search_reindex_needed'])->get('config')->row_array();
        $before = $row ? $row['value'] : null;
        $outcome = 'ok';
        try {
            $fluid = ee('Model')->get('ChannelField')->filter('field_name', $fluidName)->first();
            $fluid->set([
                'field_channel_fields' => array_map([CpsRefFixture::class, 'fieldId'], $remaining),
                'field_channel_field_groups' => [],
            ]);
            $fluid->save();
        } catch (\Throwable $e) {
            $outcome = get_class($e) . ': ' . $e->getMessage();
        }
        if ($before === null) {
            ee()->db->where(['site_id' => 0, 'key' => 'search_reindex_needed'])->delete('config');
        } else {
            ee()->db->where(['site_id' => 0, 'key' => 'search_reindex_needed'])->update('config', ['value' => $before]);
        }
        self::probe('children: remove B through set()/save_settings()', $outcome);
        $this->expect($outcome === 'ok', 'remove B through set(): ' . $outcome);
        $this->expect(self::fluidRowCount($removedFieldId) === 0, 'remove B (set path): save_settings() should delete rows');
        $this->expect(self::childRowCount(self::CHILD_B) === 0, 'remove B (set path): its data row should be deleted');
    }

    /** Deleting an entry removes its Fluid rows, the child data rows, the Grid rows and the relationship rows. */
    private function entryDelete(int $targetId): void
    {
        $relId = CpsRefFixture::fieldId(self::REL);
        CpsRefFixture::makeEntry('cpsref-fl-gone', [self::FLUID => ['fields' => self::initialFields($targetId)]]);
        $entryId = CpsRefFixture::entryId('cpsref-fl-gone');
        $this->expect(count(CpsRefFixture::fluidRows(self::FLUID, $entryId)) === 6, 'entry delete: setup rows');
        $textBefore = self::childRowCount(self::TEXT);
        $urlBefore = self::childRowCount(self::URL);

        ee('Model')->get('ChannelEntry', $entryId)->first()->delete();

        $left = [
            'fluid' => count(CpsRefFixture::fluidRows(self::FLUID, $entryId)),
            'text' => $textBefore - self::childRowCount(self::TEXT),
            'url' => $urlBefore - self::childRowCount(self::URL),
            'grid' => count(CpsRefFixture::gridRows(self::GRID, $entryId)),
            'rel' => count(self::relationshipRows($entryId, $relId)),
        ];
        self::probe('entry delete: fluid rows left, text/url child rows deleted, grid rows left, rel rows left', json_encode($left));
        $this->expect($left['fluid'] === 0 && $left['text'] === 2 && $left['url'] === 1, 'entry delete: Fluid/child rows');
        $this->expect($left['rel'] === 0, 'entry delete: relationship rows should be deleted');
        // Grid rows of a Grid that is a Fluid child are NOT removed by the entry delete: remove them explicitly.
        $this->removeGridOrphans($entryId);
    }

    /** Delete the Grid rows an entry delete left behind for a Grid that is a Fluid child. */
    private function removeGridOrphans(int $entryId): void
    {
        // Resolve the id first: a query inside a pending active-record chain corrupts the chain.
        $table = 'channel_grid_field_' . CpsRefFixture::fieldId(self::GRID);
        ee()->db->where('entry_id', $entryId)->delete($table);
    }

    /** What deleting a Fluid field that holds data removes, and what is left for the entry delete to clean. */
    private function dropFluidField(int $targetId): void
    {
        $textId = CpsRefFixture::fieldId(self::TEXT);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $relId = CpsRefFixture::fieldId(self::REL);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::GRID_COL);
        $group = ee('Model')->get('ChannelFieldGroup')->filter('group_name', CpsRefFixture::GROUP)->first();

        CpsRefFixture::makeFluidField($group, self::DROPPED, [self::TEXT, self::GRID, self::REL], 40);
        self::refreshFieldList();
        CpsRefFixture::makeEntry(self::DROP_ENTRY, [self::DROPPED => ['fields' => [
            'new_field_1' => ['field_id_' . $textId => 'dropped-text'],
            'new_field_2' => ['field_id_' . $gridId => ['rows' => ['new_row_1' => ['col_id_' . $colId => 'dropped-grid']]]],
            'new_field_3' => ['field_id_' . $relId => ['data' => [$targetId]]],
        ]]]);
        $entryId = CpsRefFixture::entryId(self::DROP_ENTRY);
        $droppedId = CpsRefFixture::fieldId(self::DROPPED);
        $rows = CpsRefFixture::fluidRows(self::DROPPED, $entryId);
        $this->expect(count($rows) === 3, 'drop: expected 3 rows before deleting the Fluid field');
        $textRowsBefore = self::childRowCount(self::TEXT);
        $gridIds = array_column(CpsRefFixture::gridRows(self::GRID, $entryId), 'fluid_field_data_id');
        $this->expect(count($gridIds) === 1, 'drop: expected 1 grid row before deleting the Fluid field');

        ee('Model')->get('ChannelField')->filter('field_name', self::DROPPED)->first()->delete();
        CpsRefFixture::dropDataTableIfExists($droppedId);

        $leftFluid = (int) ee()->db->where('fluid_field_id', $droppedId)->count_all_results('fluid_field_data');
        $leftText = $textRowsBefore - self::childRowCount(self::TEXT);
        $leftGrid = count(CpsRefFixture::gridRows(self::GRID, $entryId));
        $leftRel = count(self::relationshipRows($entryId, $relId));
        self::probe(
            'drop Fluid field: fluid rows left / text data rows deleted / grid rows left / relationship rows left',
            "$leftFluid / $leftText / $leftGrid / $leftRel"
        );
        $this->expect($leftFluid === 0, 'drop: fluid_field_data rows survived the Fluid field');
        $this->expect($leftText === 1, 'drop: the text child data row should be deleted with its fluid row');
        $this->expect($leftGrid === 1, 'drop: the Grid child row is expected to be left behind (orphan)');
        $this->expect($leftRel === 1, 'drop: the relationship child row is expected to be left behind (orphan)');

        // The entry delete then removes the orphans (Grid and relationship delete by entry id).
        self::refreshFieldList();
        ee('Model')->get('ChannelEntry', $entryId)->first()->delete();
        self::probe('drop: grid rows left after the entry delete', (string) count(CpsRefFixture::gridRows(self::GRID, $entryId)));
        $this->removeGridOrphans($entryId);
        $this->expect(self::relationshipRows($entryId, $relId) === [], 'drop: entry delete left relationship rows');
    }

    /** A Fluid field created after an entry was saved in this request is invisible to ChannelEntry. */
    private function lateFieldProbe(): void
    {
        $group = ee('Model')->get('ChannelFieldGroup')->filter('group_name', CpsRefFixture::GROUP)->first();
        $textKey = 'field_id_' . CpsRefFixture::fieldId(self::TEXT);
        CpsRefFixture::makeFluidField($group, self::LATE, [self::TEXT], 41);
        $write = [self::LATE => ['fields' => ['new_field_1' => [$textKey => 'late']]]];

        CpsRefFixture::makeEntry('cpsref-fl-late-1', $write);
        $stale = count(CpsRefFixture::fluidRows(self::LATE, CpsRefFixture::entryId('cpsref-fl-late-1')));
        self::probe('late Fluid field, stale cached field list: rows written', (string) $stale);

        self::refreshFieldList();
        CpsRefFixture::makeEntry('cpsref-fl-late-2', $write);
        $fresh = count(CpsRefFixture::fluidRows(self::LATE, CpsRefFixture::entryId('cpsref-fl-late-2')));
        self::probe('late Fluid field, after refreshFieldList(): rows written', (string) $fresh);
        $this->expect($fresh === 1, 'late: refreshing the cached field list should make the write land');
    }

    // ------------------------------------------------------------------------------------------------ verify

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        $check = function (bool $condition, string $message) use (&$problems) {
            CpsRefFixture::check($problems, $condition, $message);
        };

        $fluidId = CpsRefFixture::fieldId(self::FLUID);
        $textId = CpsRefFixture::fieldId(self::TEXT);
        $urlId = CpsRefFixture::fieldId(self::URL);
        $flagId = CpsRefFixture::fieldId(self::FLAG);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        $relId = CpsRefFixture::fieldId(self::REL);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::GRID_COL);

        // Settings contract
        $settings = CpsRefFixture::fieldSettings(self::FLUID);
        foreach (['field_channel_fields', 'field_channel_field_groups'] as $key) {
            $check(array_key_exists($key, $settings), "fluid settings missing $key");
        }
        $listed = array_map('intval', (array) ($settings['field_channel_fields'] ?? []));
        sort($listed);
        $expected = [$textId, $urlId, $flagId, $gridId, $relId];
        sort($expected);
        $check($listed === $expected, 'field_channel_fields should list the 5 base children, got ' . json_encode($listed));
        $check(($settings['field_channel_field_groups'] ?? null) === [], 'field_channel_field_groups should be []');

        // Storage layout
        $check(
            CpsRefFixture::columnType('channel_data_field_' . $fluidId, 'field_id_' . $fluidId) === 'mediumtext',
            'Fluid field column field_id_N should be mediumtext'
        );
        foreach ([
            'id' => 'int(11) unsigned', 'fluid_field_id' => 'int(11) unsigned', 'entry_id' => 'int(11) unsigned',
            'field_id' => 'int(11) unsigned', 'field_data_id' => 'int(11) unsigned', 'order' => 'int(5) unsigned',
            'field_group_id' => 'int(10) unsigned', 'group' => 'int(10) unsigned',
        ] as $column => $type) {
            $check(CpsRefFixture::columnType('fluid_field_data', $column) === $type, "fluid_field_data.$column type");
        }

        // KEEP entry: the initial write, untouched
        $keepId = CpsRefFixture::entryId(self::KEEP);
        $rows = CpsRefFixture::fluidRows(self::FLUID, $keepId);
        $check(count($rows) === 6, 'KEEP: expected 6 fluid rows, found ' . count($rows));
        if (count($rows) === 6) {
            $check(
                self::rowFieldIds($rows) === [$textId, $gridId, $relId, $urlId, $flagId, $textId],
                'KEEP: row field ids ' . json_encode(self::rowFieldIds($rows))
            );
            $check(array_map('intval', array_column($rows, 'order')) === [1, 2, 3, 4, 5, 6], 'KEEP: order column');
            $check(array_map('intval', array_column($rows, 'group')) === [1, 2, 3, 4, 5, 6], 'KEEP: group column');
            $check(array_unique(array_column($rows, 'field_group_id')) === [null], 'KEEP: field_group_id should be NULL');
            $check(array_unique(array_map('intval', array_column($rows, 'fluid_field_id'))) === [$fluidId], 'KEEP: fluid_field_id');
            $check(self::dataValue(self::TEXT, (int) $rows[0]['field_data_id']) === 'alpha', 'KEEP: text alpha');
            $check(self::dataValue(self::TEXT, (int) $rows[5]['field_data_id']) === 'omega', 'KEEP: text omega');
            $check(
                self::dataValue(self::URL, (int) $rows[3]['field_data_id']) === 'https://example.com/fluid',
                'KEEP: url value'
            );
            $check(self::dataValue(self::FLAG, (int) $rows[4]['field_data_id']) === '1', 'KEEP: toggle value');
            $check((int) (self::dataRow(self::TEXT, (int) $rows[0]['field_data_id'])['entry_id'] ?? -1) === 0, 'KEEP: child data row entry_id should be 0');

            $gridRows = CpsRefFixture::gridRows(self::GRID, $keepId);
            $check(count($gridRows) === 2, 'KEEP: expected 2 grid rows');
            foreach ($gridRows as $gridRow) {
                $check((int) $gridRow['fluid_field_data_id'] === (int) $rows[1]['id'], 'KEEP: grid row fluid_field_data_id');
            }
            $check(
                array_column($gridRows, 'col_id_' . $colId) === ['g1', 'g2'],
                'KEEP: grid values ' . json_encode(array_column($gridRows, 'col_id_' . $colId))
            );
            $relRows = self::relationshipRows($keepId, $relId);
            $check(count($relRows) === 1, 'KEEP: expected 1 relationship row, found ' . count($relRows));
            if (count($relRows) === 1) {
                $check((int) $relRows[0]['fluid_field_data_id'] === (int) $rows[2]['id'], 'KEEP: rel fluid_field_data_id');
                $check((int) $relRows[0]['grid_field_id'] === 0, 'KEEP: relationship grid_field_id should be 0');
                $check(
                    (int) $relRows[0]['child_id'] === CpsRefFixture::entryId(self::TARGET),
                    'KEEP: relationship child_id'
                );
            }
        }

        // MUT entry: after update, reorder, append and omit
        $mutId = CpsRefFixture::entryId(self::MUT);
        $rows = CpsRefFixture::fluidRows(self::FLUID, $mutId);
        $check(count($rows) === 3, 'MUT: expected 3 fluid rows, found ' . count($rows));
        if (count($rows) === 3) {
            $check(array_map('intval', array_column($rows, 'order')) === [1, 2, 3], 'MUT: order column');
            $values = array_map(function ($row) {
                return self::dataValue(self::TEXT, (int) $row['field_data_id']);
            }, $rows);
            $check($values === ['omega-changed', 'alpha-changed', 'appended'], 'MUT: values ' . json_encode($values));
        }
        $check(CpsRefFixture::gridRows(self::GRID, $mutId) === [], 'MUT: Grid rows should be gone');
        $check(self::relationshipRows($mutId, $relId) === [], 'MUT: relationship rows should be gone');

        // No orphans: every child data row with entry_id 0 is owned by a fluid_field_data row, and vice versa
        foreach ([self::TEXT, self::URL, self::FLAG, self::CHILD_B, self::UNLISTED] as $name) {
            $check(
                self::childRowCount($name) === self::fluidRowCount(CpsRefFixture::fieldId($name)),
                "$name: child data rows with entry_id 0 do not match fluid_field_data rows"
            );
        }
        $orphans = (int) ee()->db->query(
            'SELECT COUNT(*) AS n FROM `' . ee()->db->dbprefix . 'channel_grid_field_' . $gridId . '` WHERE fluid_field_data_id <> 0'
            . ' AND fluid_field_data_id NOT IN (SELECT id FROM ' . ee()->db->dbprefix . 'fluid_field_data)'
        )->row()->n;
        $check($orphans === 0, "$orphans orphan Grid row(s) point at a missing fluid_field_data row");
        $orphans = (int) ee()->db->query(
            'SELECT COUNT(*) AS n FROM ' . ee()->db->dbprefix . 'relationships WHERE field_id = ' . $relId
            . ' AND fluid_field_data_id <> 0 AND fluid_field_data_id NOT IN (SELECT id FROM '
            . ee()->db->dbprefix . 'fluid_field_data)'
        )->row()->n;
        $check($orphans === 0, "$orphans orphan relationship row(s) point at a missing fluid_field_data row");

        return $problems;
    }
}
