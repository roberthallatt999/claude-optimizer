<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: rte (Plan 2 Task 5). Proves the settings contract (toolset by NAME, defer,
 * db_column_type text vs mediumtext), what save() does to the HTML (file URLs become {file:ID:url}) and that
 * the entry save writes exp_file_usage rows, at top level, as a Grid column and as a Fluid child.
 * Reads one existing file row; creates no files and no upload directories. down() removes everything cpsref*.
 */
class CpsrefRte extends Migration
{
    const FIELD = 'cpsref_rte';
    const BIG = 'cpsref_rte_big';
    const ORPHAN = 'cpsref_rte_orphan';
    const GRID = 'cpsref_rte_grid';
    const COL = 'cpsref_rte_col';
    const FLUID = 'cpsref_rte_fluid';
    const ENTRY = 'cpsref-rte';
    const UPLOAD_DIRECTORY = 'Handout images';
    const TOOLSET_BASIC = 'Basic';
    const TOOLSET_FULL = 'Full';

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
     * file_upload_preferences_model::get_paths() (used by RTE save() and by the entry's file-usage tracking)
     * reads ee()->session, which does not exist under eecli. Private helper: candidate for promotion.
     */
    private static function ensureSession(): void
    {
        try {
            ee()->session;
        } catch (\Throwable $e) {
            ee()->load->library('session');
        }
    }

    /** Resolve an RTE toolset id by NAME (never hard-code the id; it differs per site). */
    private static function toolsetId(string $name): int
    {
        $toolset = ee('Model')->get('rte:Toolset')->filter('toolset_name', $name)->first();
        if (! $toolset) {
            throw new \RuntimeException("RTE toolset '$name' not found");
        }

        return (int) $toolset->toolset_id;
    }

    /** Lowest-id file in the named upload directory that nothing uses (so total_records goes 0 -> 1 -> 0). */
    private static function unusedFile(): array
    {
        $dir = ee()->db->select('id')->where('name', self::UPLOAD_DIRECTORY)->get('upload_prefs')->row_array();
        if (! $dir) {
            throw new \RuntimeException('upload directory ' . self::UPLOAD_DIRECTORY . ' not found');
        }
        $file = ee()->db->query(
            'SELECT f.file_id, f.upload_location_id, f.file_name FROM exp_files f'
            . ' LEFT JOIN exp_file_usage u ON u.file_id = f.file_id'
            . ' WHERE u.file_id IS NULL AND f.total_records = 0 AND f.upload_location_id = ' . (int) $dir['id']
            . ' ORDER BY f.file_id LIMIT 1'
        )->row_array();
        if (! $file) {
            throw new \RuntimeException('no unused file in upload directory ' . self::UPLOAD_DIRECTORY);
        }

        return $file;
    }

    private function build(): void
    {
        self::ensureSession();
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        $basic = self::toolsetId(self::TOOLSET_BASIC);
        $full = self::toolsetId(self::TOOLSET_FULL);
        $missing = (int) ee()->db->select_max('toolset_id', 'id')->get('rte_toolsets')->row()->id + 1000;

        // Top level, what save_settings() returns (plus the three display keys it adds)
        CpsRefFixture::makeField($group, self::FIELD, 'rte', [
            'toolset_id' => $basic, 'defer' => 'n', 'db_column_type' => 'text',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 1, ['field_fmt' => 'none']);
        CpsRefFixture::makeField($group, self::BIG, 'rte', [
            'toolset_id' => $full, 'defer' => 'y', 'db_column_type' => 'mediumtext',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 2, ['field_fmt' => 'none']);
        // A toolset id that does not exist: nothing validates it when the field is saved. The field is deleted
        // again at once: cps:schema-check's smoke test (display_field) fails on it with
        // 'Unregistered service "rte:Service"', which is the behaviour the reference documents.
        CpsRefFixture::makeField($group, self::ORPHAN, 'rte', [
            'toolset_id' => $missing, 'defer' => 'n', 'db_column_type' => 'text',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 3, ['field_fmt' => 'none']);
        if ((int) (CpsRefFixture::fieldSettings(self::ORPHAN)['toolset_id'] ?? 0) !== $missing) {
            throw new \RuntimeException('a field with a nonexistent toolset_id should save without validation');
        }
        $orphanId = CpsRefFixture::fieldId(self::ORPHAN);
        ee('Model')->get('ChannelField')->filter('field_name', self::ORPHAN)->first()->delete();
        // Model delete() drops the data table through smartforge, whose table_exists() is cached per request and
        // does not know a table created moments ago: drop it explicitly.
        ee()->db->query('DROP TABLE IF EXISTS `' . ee()->db->dbprefix . 'channel_data_field_' . $orphanId . '`');

        // Grid column: grid_save_settings() returns the posted rte[] array as is (no field_* display keys)
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL, 'type' => 'rte', 'label' => 'Body', 'settings' => [
                'toolset_id' => $basic, 'defer' => 'n', 'db_column_type' => 'mediumtext',
            ]],
        ], 4);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 5);

        $file = self::unusedFile();
        ee()->load->model('file_upload_preferences_model');
        $paths = ee()->file_upload_preferences_model->get_paths();
        $url = $paths[(int) $file['upload_location_id']] . $file['file_name'];

        // Leading empty paragraph (trimmed), cachebuster query (removed), <code> braces (entitized), a file URL
        // and a {filedir_N} tag (both become {file:ID:url})
        $html = '<p>&nbsp;</p><p>Hello</p><p><img src="' . $url . '?cachebuster:123"></p>'
            . '<p>{filedir_' . $file['upload_location_id'] . '}' . $file['file_name'] . '</p>'
            . '<code>{not_a_tag}</code>';

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $col = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => $html,
            self::BIG => '<p>Big</p>',
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $col => '<p>Grid cell</p>']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $fieldId => '<p>Fluid child</p>']]],
        ]);
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        self::ensureSession();
        $problems = [];

        // Settings contract (top level)
        $basic = self::toolsetId(self::TOOLSET_BASIC);
        $full = self::toolsetId(self::TOOLSET_FULL);
        $top = CpsRefFixture::fieldSettings(self::FIELD);
        foreach (['toolset_id', 'defer', 'db_column_type', 'field_wide', 'field_fmt', 'field_show_fmt'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $top), "top-level settings missing $key");
        }
        CpsRefFixture::check($problems, (int) ($top['toolset_id'] ?? 0) === $basic, 'toolset_id is not the Basic toolset id');
        $big = CpsRefFixture::fieldSettings(self::BIG);
        CpsRefFixture::check($problems, (int) ($big['toolset_id'] ?? 0) === $full, 'big field toolset_id is not the Full toolset id');
        CpsRefFixture::check($problems, ($big['defer'] ?? '') === 'y', 'defer y did not store');

        // Grid column contract
        $col = CpsRefFixture::gridColumnSettings(self::GRID, self::COL);
        foreach (['toolset_id', 'defer', 'db_column_type'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $col), "grid column settings missing $key");
        }

        // Storage: db_column_type drives the data column type via settings_modify_column()
        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $bigId = CpsRefFixture::fieldId(self::BIG);
        $table = 'channel_data_field_' . $fieldId;
        CpsRefFixture::check($problems, CpsRefFixture::columnType($table, 'field_id_' . $fieldId) === 'text',
            'text column type is ' . CpsRefFixture::columnType($table, 'field_id_' . $fieldId));
        CpsRefFixture::check($problems, CpsRefFixture::columnType('channel_data_field_' . $bigId, 'field_id_' . $bigId) === 'mediumtext',
            'mediumtext column type is ' . CpsRefFixture::columnType('channel_data_field_' . $bigId, 'field_id_' . $bigId));
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $gridTable = 'channel_grid_field_' . CpsRefFixture::fieldId(self::GRID);
        CpsRefFixture::check($problems, CpsRefFixture::columnType($gridTable, 'col_id_' . $colId) === 'mediumtext',
            'grid column type is ' . CpsRefFixture::columnType($gridTable, 'col_id_' . $colId));

        // Value written through the Model: save() ran (URLs became tags, whitespace trimmed, braces entitized)
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        $stored = (string) CpsRefFixture::fieldValue(self::FIELD, $entryId);
        $file = ee()->db->query(
            'SELECT file_id FROM exp_file_usage WHERE entry_id = ' . (int) $entryId . ' ORDER BY file_id'
        )->result_array();
        $fileId = (int) ($file[0]['file_id'] ?? 0);
        $expected = '<p>Hello</p><p><img src="{file:' . $fileId . ':url}"></p><p>{file:' . $fileId . ':url}</p>'
            . '<code>&#123;not_a_tag&#125;</code>';
        CpsRefFixture::check($problems, $stored === $expected, 'stored HTML differs: ' . $stored);
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::BIG, $entryId) === '<p>Big</p>', 'mediumtext value did not read back');

        // File usage: the entry save wrote one exp_file_usage row for the one distinct file and recounted it
        CpsRefFixture::check($problems, count($file) === 1, 'expected 1 file_usage row, found ' . count($file));
        $total = ee()->db->select('total_records')->where('file_id', $fileId)->get('files')->row_array();
        CpsRefFixture::check($problems, (int) ($total['total_records'] ?? -1) === 1, 'files.total_records should be 1');

        // Grid and Fluid
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1 && ($rows[0]['col_id_' . $colId] ?? null) === '<p>Grid cell</p>', 'grid cell did not read back');
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get($table)->row_array();
            CpsRefFixture::check($problems, ($stored['v'] ?? null) === '<p>Fluid child</p>', 'fluid value did not read back');
        }

        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));

        return $problems;
    }
}
