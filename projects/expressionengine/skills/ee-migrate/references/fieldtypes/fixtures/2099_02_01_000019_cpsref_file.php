<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: file (Plan 2 Task 5). Proves the settings contract (content type, allowed
 * directory resolved by NAME, show_existing, num_existing), the stored value formats ({file:ID:url},
 * {filedir_N}name, bare id) and the exp_file_usage rows the entry save writes (top level only; Grid and Fluid are not tracked), at top level, as a Grid column
 * and as a Fluid child. Reads existing exp_files rows only: no files or upload directories are created, moved
 * or deleted. down() removes everything cpsref*; entry delete removes the usage rows and recounts total_records.
 */
class CpsrefFile extends Migration
{
    const TAG = 'cpsref_file';
    const LEGACY = 'cpsref_file_legacy';
    const NUMERIC = 'cpsref_file_numeric';
    const ANYDIR = 'cpsref_file_anydir';
    const GRID = 'cpsref_file_grid';
    const COL = 'cpsref_file_col';
    const FLUID = 'cpsref_file_fluid';
    const ENTRY = 'cpsref-file';
    const UPLOAD_DIRECTORY = 'Handout images';

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
     * file_upload_preferences_model::get_paths(), called by every entry save (file-usage tracking), reads
     * ee()->session, which does not exist under eecli. Private helper: candidate for promotion.
     */
    private static function ensureSession(): void
    {
        try {
            ee()->session;
        } catch (\Throwable $e) {
            ee()->load->library('session');
        }
        ee()->load->model('file_upload_preferences_model');
    }

    private static function uploadDirectoryId(): int
    {
        $dir = ee()->db->select('id')->where('name', self::UPLOAD_DIRECTORY)->get('upload_prefs')->row_array();
        if (! $dir) {
            throw new \RuntimeException('upload directory ' . self::UPLOAD_DIRECTORY . ' not found');
        }

        return (int) $dir['id'];
    }

    /** Lowest-id files in the directory that nothing uses (total_records goes 0 -> 1 -> 0). */
    private static function unusedFiles(int $directoryId, int $count): array
    {
        $files = ee()->db->query(
            'SELECT f.file_id, f.upload_location_id, f.file_name FROM exp_files f'
            . ' LEFT JOIN exp_file_usage u ON u.file_id = f.file_id'
            . ' WHERE u.file_id IS NULL AND f.total_records = 0 AND f.upload_location_id = ' . $directoryId
            . ' ORDER BY f.file_id LIMIT ' . $count
        )->result_array();
        if (count($files) < $count) {
            throw new \RuntimeException("need $count unused files in upload directory " . self::UPLOAD_DIRECTORY);
        }

        return $files;
    }

    private function build(): void
    {
        self::ensureSession();
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $directoryId = self::uploadDirectoryId();

        // The five settings save_settings() returns. allowed_directories is 'all' or ONE directory id as a string.
        $imagesOnly = [
            'field_content_type' => 'image', 'allowed_directories' => (string) $directoryId,
            'show_existing' => 'y', 'num_existing' => '20', 'field_fmt' => 'none',
        ];
        $anything = [
            'field_content_type' => 'all', 'allowed_directories' => 'all',
            'show_existing' => 'n', 'num_existing' => '0', 'field_fmt' => 'none',
        ];
        CpsRefFixture::makeField($group, self::TAG, 'file', $imagesOnly, 1);
        CpsRefFixture::makeField($group, self::LEGACY, 'file', $imagesOnly, 2);
        CpsRefFixture::makeField($group, self::NUMERIC, 'file', $imagesOnly, 3);
        CpsRefFixture::makeField($group, self::ANYDIR, 'file', $anything, 4);
        // Grid column: same keys in col_settings (grid_display_settings() reuses display_settings())
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL, 'type' => 'file', 'label' => 'Image', 'settings' => $imagesOnly],
        ], 5);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::TAG], 6);

        // A: top-level {file:ID:url}; B: top-level {filedir_N}name; C: bare id; D: Grid; E: Fluid
        [$a, $b, $c, $d, $e] = self::unusedFiles($directoryId, 5);
        $tagFieldId = CpsRefFixture::fieldId(self::TAG);
        $col = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::TAG => '{file:' . $a['file_id'] . ':url}',
            self::LEGACY => '{filedir_' . $b['upload_location_id'] . '}' . $b['file_name'],
            self::NUMERIC => (string) $c['file_id'],
            self::GRID => ['rows' => ['new_row_1' => ['col_id_' . $col => '{file:' . $d['file_id'] . ':url}']]],
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $tagFieldId => '{file:' . $e['file_id'] . ':url}']]],
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
        $directoryId = self::uploadDirectoryId();

        // Settings contract
        $contract = ['field_content_type', 'allowed_directories', 'show_existing', 'num_existing', 'field_fmt'];
        $top = CpsRefFixture::fieldSettings(self::TAG);
        $any = CpsRefFixture::fieldSettings(self::ANYDIR);
        $grid = CpsRefFixture::gridColumnSettings(self::GRID, self::COL);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $top), "top-level settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $grid), "grid column settings missing $key");
        }
        CpsRefFixture::check($problems, ($top['allowed_directories'] ?? null) === (string) $directoryId, 'allowed_directories should be the directory id as a string');
        CpsRefFixture::check($problems, ($any['allowed_directories'] ?? null) === 'all', 'allowed_directories all did not store');
        CpsRefFixture::check($problems, ($top['field_content_type'] ?? null) === 'image', 'field_content_type image did not store');

        // Storage: default text column, same as the other single-value fieldtypes
        $fieldId = CpsRefFixture::fieldId(self::TAG);
        $table = 'channel_data_field_' . $fieldId;
        CpsRefFixture::check($problems, CpsRefFixture::columnType($table, 'field_id_' . $fieldId) === 'text', 'data column type is ' . CpsRefFixture::columnType($table, 'field_id_' . $fieldId));

        // save() stores the value as given: three formats, no normalisation
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        $tag = (string) CpsRefFixture::fieldValue(self::TAG, $entryId);
        $legacy = (string) CpsRefFixture::fieldValue(self::LEGACY, $entryId);
        $numeric = (string) CpsRefFixture::fieldValue(self::NUMERIC, $entryId);
        CpsRefFixture::check($problems, preg_match('/^\{file:\d+:url\}$/', $tag) === 1, "tag value stored as: $tag");
        CpsRefFixture::check($problems, preg_match('/^\{filedir_' . $directoryId . '\}[^{}]+$/', $legacy) === 1, "legacy value stored as: $legacy (save() does not convert it to a tag)");
        CpsRefFixture::check($problems, ctype_digit($numeric), "numeric value stored as: $numeric");

        // File usage rows: ChannelEntry::updateFilesUsage() walks $_POST or, when that is empty (CLI, Model save),
        // $this->getValues(). Top-level {file:ID:url} and {filedir_N}name values are tracked; a bare id is not; and a
        // Grid cell or Fluid child written through the Model is NOT seen (found: only the two top-level files)
        $usage = array_map('intval', array_column(
            ee()->db->query('SELECT file_id FROM exp_file_usage WHERE entry_id = ' . (int) $entryId . ' ORDER BY file_id')->result_array(),
            'file_id'
        ));
        preg_match('/^\{file:(\d+):url\}$/', $tag, $tagMatch);
        $tagFileId = (int) ($tagMatch[1] ?? 0);
        $legacyFileId = (int) (ee()->db->select('file_id')->where('upload_location_id', $directoryId)
            ->where('file_name', preg_replace('/^\{filedir_\d+\}/', '', $legacy))->get('files')->row()->file_id ?? 0);
        sort($usage);
        $expectedUsage = [$tagFileId, $legacyFileId];
        sort($expectedUsage);
        CpsRefFixture::check($problems, $usage === $expectedUsage, 'expected usage rows for the tag and legacy files only, found ' . json_encode($usage));
        CpsRefFixture::check($problems, ! in_array((int) $numeric, $usage, true), 'a bare file id should not create a usage row');
        foreach ($usage as $fileId) {
            $total = ee()->db->select('total_records')->where('file_id', $fileId)->get('files')->row_array();
            CpsRefFixture::check($problems, (int) ($total['total_records'] ?? -1) === 1, "files.total_records for $fileId should be 1");
        }

        // Grid and Fluid
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $rows = CpsRefFixture::gridRows(self::GRID, $entryId);
        CpsRefFixture::check($problems, count($rows) === 1 && preg_match('/^\{file:\d+:url\}$/', (string) ($rows[0]['col_id_' . $colId] ?? '')) === 1, 'grid cell did not read back');
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $entryId);
        CpsRefFixture::check($problems, count($fluid) === 1, 'expected 1 fluid row, found ' . count($fluid));
        if (count($fluid) === 1) {
            $stored = ee()->db->select('field_id_' . $fieldId . ' AS v')->where('id', $fluid[0]['field_data_id'])->get($table)->row_array();
            CpsRefFixture::check($problems, preg_match('/^\{file:\d+:url\}$/', (string) ($stored['v'] ?? '')) === 1, 'fluid value did not read back');
        }

        // validate(): an unchanged stored value passes; a nonexistent file id fails with invalid_selection
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));
        $entry->{'field_id_' . $fieldId} = '{file:999999999:url}';
        CpsRefFixture::check($problems, ! $entry->validate()->isValid(), 'a nonexistent file should fail validate()');

        return $problems;
    }
}
