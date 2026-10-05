<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: wygwam (Plan 2 Task 8, third-party, add-on version recorded in wygwam.md).
 * Proves the settings contract (config_id by NAME, defer, db_column_type text vs mediumtext, the three keys
 * save_settings() adds), what happens with a nonexistent config_id, what save() does to the HTML (file URLs
 * become {file:ID:url}, cachebusters and empty paragraphs go, braces in <code> are entitized) and that the entry
 * save writes exp_file_usage rows, at top level, as a Grid column and as a Fluid child.
 * Portable inside CPS: configs are resolved generically (named Basic / Full when present, else the lowest ids),
 * files come from the first upload directory holding unused files. Reads existing file rows only: no files or
 * upload directories are created. down() removes everything cpsref*.
 */
class CpsrefWygwam extends Migration
{
    const FIELD = 'cpsref_wygwam';
    const BIG = 'cpsref_wygwam_big';
    const BARE = 'cpsref_wygwam_bare';
    const ORPHAN = 'cpsref_wygwam_orphan';
    const GRID = 'cpsref_wygwam_grid';
    const COL = 'cpsref_wygwam_col';
    const FLUID = 'cpsref_wygwam_fluid';
    const ENTRY = 'cpsref-wygwam';
    const CONFIG_BASIC = 'Basic';
    const CONFIG_FULL = 'Full';

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
     * Config id by NAME from exp_wygwam_configs (a real migration looks the name up and throws when it is missing,
     * as 2026_09_11_100000_create_events_channel does). The fixture prefers $preferred and otherwise takes the
     * lowest id not in $exclude so it runs on every CPS site. Returned as int; the stored setting is a string.
     */
    private static function configId(string $preferred, array $exclude = []): int
    {
        $named = ee()->db->select('config_id')->where('config_name', $preferred)->get('wygwam_configs')->row_array();
        if ($named && ! in_array((int) $named['config_id'], $exclude, true)) {
            return (int) $named['config_id'];
        }
        $query = ee()->db->select('config_id')->order_by('config_id');
        if ($exclude) {
            $query->where_not_in('config_id', $exclude);
        }
        $row = $query->limit(1)->get('wygwam_configs')->row_array();
        if (! $row) {
            throw new \RuntimeException('prerequisite missing: no Wygwam config in exp_wygwam_configs');
        }

        return (int) $row['config_id'];
    }

    /** [basicId, fullId] (equal when the site has a single config). */
    private static function configIds(): array
    {
        $basic = self::configId(self::CONFIG_BASIC);
        try {
            $full = self::configId(self::CONFIG_FULL, [$basic]);
        } catch (\RuntimeException $e) {
            $full = $basic;
        }

        return [$basic, $full];
    }

    private function build(): void
    {
        CpsRefFixture::ensureSession();
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        [$basic, $full] = self::configIds();
        $missing = (int) ee()->db->select_max('config_id', 'id')->get('wygwam_configs')->row()->id + 1000;

        // Top level: what save_settings() returns = the posted wygwam[] keys + field_wide, field_fmt, field_show_fmt
        CpsRefFixture::makeField($group, self::FIELD, 'wygwam', [
            'config_id' => (string) $basic, 'defer' => 'n', 'db_column_type' => 'text',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 1, ['field_fmt' => 'none']);
        CpsRefFixture::makeField($group, self::BIG, 'wygwam', [
            'config_id' => (string) $full, 'defer' => 'y', 'db_column_type' => 'mediumtext',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 2, ['field_fmt' => 'none']);
        // db_column_type is optional: older CPS fields have only config_id + defer and get a text column
        CpsRefFixture::makeField($group, self::BARE, 'wygwam', [
            'config_id' => (string) $basic, 'defer' => 'n',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 3, ['field_fmt' => 'none']);
        // A config id that does not exist: nothing validates it on save, and display falls back to the default
        // config ('default0'), so this field stays in place and the runner's schema-check smoke test displays it.
        CpsRefFixture::makeField($group, self::ORPHAN, 'wygwam', [
            'config_id' => (string) $missing, 'defer' => 'n', 'db_column_type' => 'text',
            'field_wide' => true, 'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], 4, ['field_fmt' => 'none']);

        // Grid column: grid_save_settings() returns the posted wygwam[] array as is (no field_* display keys)
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL, 'type' => 'wygwam', 'label' => 'Body', 'settings' => [
                'config_id' => (string) $basic, 'defer' => 'n', 'db_column_type' => 'mediumtext',
            ]],
        ], 5);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 6);

        $directory = CpsRefFixture::firstUploadDirectoryWithFile(4);
        [$a, $b, $c, $d] = $directory['files'];
        $paths = ee()->file_upload_preferences_model->get_paths();
        $urlA = $paths[(int) $a['upload_location_id']] . $a['file_name'];

        // Leading empty paragraph (trimmed), cachebuster (removed), file URL (becomes {file:ID:url}),
        // a legacy {filedir_N} tag inside an href (converted), braces in <code> (entitized), &quot; (decoded)
        $html = '<p>&nbsp;</p><p>Hello &quot;quoted&quot;</p><p><img src="' . $urlA . '?cachebuster:123"></p>'
            . '<p><a href="{filedir_' . $b['upload_location_id'] . '}' . $b['file_name'] . '">Legacy</a></p>'
            . '<p>{filedir_' . $d['upload_location_id'] . '}' . $d['file_name'] . '</p>'
            . '<code>{not_a_tag}</code>';

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $col = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => $html,
            self::BIG => '<p>Big</p>',
            self::BARE => '<p>Bare</p>',
            self::ORPHAN => '<p>Orphan</p>',
            self::GRID => ['rows' => ['new_row_1' => [
                'col_id_' . $col => '<p><img src="{file:' . $c['file_id'] . ':url}">Grid cell</p>',
            ]]],
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
        CpsRefFixture::ensureSession();
        $problems = [];

        // Settings contract (top level): the three posted keys plus the three display keys save_settings() adds
        [$basic, $full] = self::configIds();
        $top = CpsRefFixture::fieldSettings(self::FIELD);
        foreach (['config_id', 'defer', 'db_column_type', 'field_wide', 'field_fmt', 'field_show_fmt'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $top), "top-level settings missing $key");
        }
        CpsRefFixture::check($problems, ($top['config_id'] ?? null) === (string) $basic, 'config_id should be the Basic config id as a string');
        CpsRefFixture::check($problems, ($top['field_wide'] ?? null) === true, 'field_wide should be boolean true');
        $big = CpsRefFixture::fieldSettings(self::BIG);
        CpsRefFixture::check($problems, ($big['config_id'] ?? null) === (string) $full, 'big config_id is not the Full config id');
        CpsRefFixture::check($problems, ($big['defer'] ?? '') === 'y', 'defer y did not store');
        $bare = CpsRefFixture::fieldSettings(self::BARE);
        CpsRefFixture::check($problems, ! array_key_exists('db_column_type', $bare), 'bare field should not carry db_column_type');
        $orphan = CpsRefFixture::fieldSettings(self::ORPHAN);
        CpsRefFixture::check($problems, ! (bool) ee('Model')->get('wygwam:Config')->filter('config_id', (int) ($orphan['config_id'] ?? 0))->first(), 'the orphan config id should not exist');

        // Grid column contract: the three posted keys only
        $col = CpsRefFixture::gridColumnSettings(self::GRID, self::COL);
        foreach (['config_id', 'defer', 'db_column_type'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $col), "grid column settings missing $key");
        }
        CpsRefFixture::check($problems, ! array_key_exists('field_wide', $col), 'grid column settings should not carry field_wide');

        // Storage: db_column_type drives the data column type via settings_modify_column(); default text
        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $bigId = CpsRefFixture::fieldId(self::BIG);
        $bareId = CpsRefFixture::fieldId(self::BARE);
        $table = 'channel_data_field_' . $fieldId;
        $columnTypes = [
            'text' => CpsRefFixture::columnType($table, 'field_id_' . $fieldId),
            'mediumtext' => CpsRefFixture::columnType('channel_data_field_' . $bigId, 'field_id_' . $bigId),
            'bare (no db_column_type) -> text' => CpsRefFixture::columnType('channel_data_field_' . $bareId, 'field_id_' . $bareId),
        ];
        CpsRefFixture::check($problems, $columnTypes['text'] === 'text', 'text column type is ' . $columnTypes['text']);
        CpsRefFixture::check($problems, $columnTypes['mediumtext'] === 'mediumtext', 'mediumtext column type is ' . $columnTypes['mediumtext']);
        CpsRefFixture::check($problems, $columnTypes['bare (no db_column_type) -> text'] === 'text', 'bare column type is ' . $columnTypes['bare (no db_column_type) -> text']);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $gridTable = 'channel_grid_field_' . CpsRefFixture::fieldId(self::GRID);
        CpsRefFixture::check($problems, CpsRefFixture::columnType($gridTable, 'col_id_' . $colId) === 'mediumtext',
            'grid column type is ' . CpsRefFixture::columnType($gridTable, 'col_id_' . $colId));

        // Value written through the Model: save() ran. The expectations assume file_manager_compatibility_mode is off
        // (the EE 7 default): with it on, replaceFileUrls() stops at {filedir_N} and file usage is not tracked.
        CpsRefFixture::check($problems, ! bool_config_item('file_manager_compatibility_mode'), 'file_manager_compatibility_mode is on; the expectations below assume off');
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        $stored = (string) CpsRefFixture::fieldValue(self::FIELD, $entryId);
        // Trimmed empty paragraph, &quot; decoded, cachebuster removed, the URL and the quoted {filedir_N} became
        // {file:ID:url}, the {filedir_N} NOT followed by a closing quote was left as it was, <code> braces entitized
        $pattern = '#^<p>Hello "quoted"</p><p><img src="\{file:(\d+):url\}"></p>'
            . '<p><a href="\{file:(\d+):url\}">Legacy</a></p><p>\{filedir_(\d+)\}([^<]+)</p>'
            . '<code>&\#123;not_a_tag&\#125;</code>$#';
        $matched = preg_match($pattern, $stored, $m) === 1;
        CpsRefFixture::check($problems, $matched, 'stored HTML differs: ' . $stored);
        $urlFileId = (int) ($m[1] ?? 0);
        $tagFileId = (int) ($m[2] ?? 0);
        CpsRefFixture::check($problems, (bool) ee()->db->where(['upload_location_id' => (int) ($m[3] ?? 0), 'file_name' => $m[4] ?? ''])->get('files')->row_array(), 'the untouched {filedir_N} name should be a real file');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::BIG, $entryId) === '<p>Big</p>', 'mediumtext value did not read back');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::BARE, $entryId) === '<p>Bare</p>', 'bare value did not read back');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::ORPHAN, $entryId) === '<p>Orphan</p>', 'orphan-config value did not read back');

        // File usage: the entry save walks the entry values for {file:ID:url} and quoted {filedir_N} references:
        // exactly the two top-level files get a row and total_records 1; the file only in the Grid cell does not
        $usage = array_map('intval', array_column(ee()->db->query(
            'SELECT file_id FROM exp_file_usage WHERE entry_id = ' . (int) $entryId . ' ORDER BY file_id'
        )->result_array(), 'file_id'));
        $expectedUsage = [$urlFileId, $tagFileId];
        sort($expectedUsage);
        CpsRefFixture::check($problems, $usage === $expectedUsage, 'expected usage rows for the two top-level files, found ' . json_encode($usage));
        foreach ($usage as $fileId) {
            $total = ee()->db->select('total_records')->where('file_id', $fileId)->get('files')->row_array();
            CpsRefFixture::check($problems, (int) ($total['total_records'] ?? -1) === 1, "files.total_records for $fileId should be 1");
        }

        // Grid and Fluid
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        $cell = (string) ($rows[0]['col_id_' . $colId] ?? '');
        CpsRefFixture::check($problems, count($rows) === 1 && preg_match('#^<p><img src="\{file:(\d+):url\}">Grid cell</p>$#', $cell, $g) === 1, 'grid cell did not read back: ' . $cell);
        $gridFileId = (int) ($g[1] ?? 0);
        CpsRefFixture::check($problems, ! in_array($gridFileId, $usage, true), 'a file only in a Grid cell should not get a usage row');
        $gridTotal = ee()->db->select('total_records')->where('file_id', $gridFileId)->get('files')->row_array();
        CpsRefFixture::check($problems, (int) ($gridTotal['total_records'] ?? -1) === 0, 'the Grid-only file total_records should stay 0');
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $value = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])
                ->get($table)->row_array();
            CpsRefFixture::check($problems, ($value['v'] ?? null) === '<p>Fluid child</p>', 'fluid value did not read back');
        }

        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));

        return $problems;
    }
}
