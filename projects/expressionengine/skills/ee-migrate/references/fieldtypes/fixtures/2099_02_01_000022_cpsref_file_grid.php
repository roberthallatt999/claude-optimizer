<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: file_grid (Plan 2 Task 6). file_grid_ft extends Grid_ft (ft.file_grid.php lives in
 * the grid add-on), so this fixture only proves what differs from Grid:
 *
 *  - seven settings keys (Grid's five plus field_content_type and allowed_directories);
 *  - a mandatory first column named 'file' of type file, whose col_settings repeat the two file settings;
 *  - the same storage as Grid (exp_channel_grid_field_N), the file reference stored as {file:ID:url};
 *  - accepts_content_type(): usable in Fluid, NOT as a Grid column (same rule as grid);
 *  - the file column is read-only here: files and upload directories are never created, moved or deleted.
 * Portable: the upload directory is the first one holding two unused files (a real migration resolves it by NAME).
 * down() removes every cpsref* row, table and column.
 */
class CpsrefFileGrid extends Migration
{
    const FIELD = 'cpsref_file_grid';
    const FILE_COL = 'file';
    const CAPTION_COL = 'caption';
    const FLUID = 'cpsref_file_grid_fluid';
    const ENTRY = 'cpsref-file-grid';
    const FLUID_ENTRY = 'cpsref-file-grid-fluid';

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

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    /** The two file settings that appear both on the field and on the file column. */
    private static function fileSettings(int $directoryId): array
    {
        return ['field_content_type' => 'image', 'allowed_directories' => (string) $directoryId];
    }

    /** The complete column array grid_model::save_col_settings() takes: field_id and content_type INSIDE it. */
    private static function addColumn(int $fieldId, int $order, string $name, string $type, array $settings): int
    {
        $settings['field_required'] = 'n';

        return (int) ee()->grid_model->save_col_settings([
            'field_id' => $fieldId,
            'content_type' => 'channel',
            'col_order' => $order,
            'col_type' => $type,
            'col_label' => ucfirst($name),
            'col_name' => $name,
            'col_instructions' => '',
            'col_required' => 'n',
            'col_search' => $type === 'file' ? 'y' : 'n',
            'col_width' => 0,
            'col_settings' => json_encode($settings),
        ], false, 'channel');
    }

    /**
     * Channel::getAllCustomFields() caches the channel's field list in ee()->session once an entry in the channel
     * has been saved in this request; a field created afterwards is invisible to ChannelEntry and its field_id_N
     * assignment is silently dropped. Dropping the cache entry right after creating fields avoids it.
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

    private static function fileTag(array $file): string
    {
        return '{file:' . $file['file_id'] . ':url}';
    }

    private function build(): void
    {
        CpsRefFixture::ensureSession();
        $directory = CpsRefFixture::firstUploadDirectoryWithFile(2);
        $directoryId = $directory['id'];
        [$first, $second] = $directory['files'];

        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        // 1. The field: Grid's five settings plus field_content_type and allowed_directories.
        $field = CpsRefFixture::makeField($group, self::FIELD, 'file_grid', [
            'grid_min_rows' => 0, 'grid_max_rows' => '4', 'allow_reorder' => 'y',
            'vertical_layout' => 'n', 'row_counter' => 'y',
            'field_content_type' => 'image', 'allowed_directories' => (string) $directoryId,
        ], 1);
        ee()->grid_model->create_field($field->field_id, 'channel');

        // 2. Columns: the mandatory 'file' column first, then one ordinary column.
        self::addColumn((int) $field->field_id, 0, self::FILE_COL, 'file', self::fileSettings($directoryId));
        self::addColumn((int) $field->field_id, 1, self::CAPTION_COL, 'text', [
            'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr', 'field_maxl' => 256,
        ]);

        // 3. Fluid child
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 2);
        self::refreshFieldList();

        // 4. Entries (created after the fields; see refreshFieldList())
        $fileCol = 'col_id_' . CpsRefFixture::gridColumnId(self::FIELD, self::FILE_COL);
        $captionCol = 'col_id_' . CpsRefFixture::gridColumnId(self::FIELD, self::CAPTION_COL);
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => ['rows' => [
                'new_row_1' => [$fileCol => self::fileTag($first), $captionCol => 'first'],
                'new_row_2' => [$fileCol => self::fileTag($second), $captionCol => 'second'],
            ]],
        ]);
        CpsRefFixture::makeEntry(self::FLUID_ENTRY, [
            self::FLUID => ['fields' => ['new_field_1' => ['field_id_' . $field->field_id => ['rows' => [
                'new_row_1' => [$fileCol => self::fileTag($first), $captionCol => 'in fluid'],
            ]]]]],
        ]);
    }

    /** accepts_content_type() of a fieldtype, through the same API Grid_lib::_get_fieldtypes() uses. */
    private static function accepts(string $fieldtype, string $contentType): bool
    {
        $handler = ee()->api_channel_fields->setup_handler($fieldtype, true);

        return (bool) $handler->accepts_content_type($contentType);
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        CpsRefFixture::ensureSession();
        $problems = [];
        $check = function (bool $condition, string $message) use (&$problems) {
            CpsRefFixture::check($problems, $condition, $message);
        };

        // Settings contract: seven keys
        $settings = CpsRefFixture::fieldSettings(self::FIELD);
        $keys = ['grid_min_rows', 'grid_max_rows', 'allow_reorder', 'vertical_layout', 'row_counter',
            'field_content_type', 'allowed_directories'];
        foreach ($keys as $key) {
            $check(array_key_exists($key, $settings), "file_grid settings missing $key");
        }
        $check($settings['field_content_type'] === 'image', 'field_content_type did not store image');
        $check(
            $settings['grid_max_rows'] === '4' && $settings['row_counter'] === 'y',
            'grid settings did not round-trip'
        );
        $directoryId = (int) ($settings['allowed_directories'] ?? 0);
        $check($directoryId > 0, 'allowed_directories should be an upload directory id string');
        $check(
            ee()->db->where('id', $directoryId)->count_all_results('upload_prefs') === 1,
            'allowed_directories does not name an upload directory'
        );
        $check(
            ee()->db->select('field_type')->where('field_name', self::FIELD)->get('channel_fields')
                ->row_array()['field_type'] === 'file_grid',
            'field_type is not file_grid'
        );

        // Columns: file first, with the two file settings; storage is Grid's table
        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $columns = ee()->db->where('field_id', $fieldId)->order_by('col_order')->get('grid_columns')->result_array();
        $check(count($columns) === 2, 'expected 2 columns, found ' . count($columns));
        $fileColumn = $columns[0] ?? [];
        $check(
            ($fileColumn['col_name'] ?? '') === 'file' && ($fileColumn['col_type'] ?? '') === 'file',
            'first column must be named file and typed file'
        );
        $check(($fileColumn['col_search'] ?? '') === 'y', 'file column col_search should be y (the CP phantom column)');
        $fileSettings = json_decode($fileColumn['col_settings'] ?? '[]', true) ?: [];
        $check(
            ($fileSettings['field_content_type'] ?? null) === 'image'
                && ($fileSettings['allowed_directories'] ?? null) === (string) $directoryId,
            'file column col_settings does not repeat the field settings: ' . json_encode($fileSettings)
        );
        $table = 'channel_grid_field_' . $fieldId;
        $check(CpsRefFixture::tableExists($table), 'channel_grid_field_N table missing');
        $check(
            CpsRefFixture::columnType($table, 'col_id_' . ($fileColumn['col_id'] ?? 0)) === 'text',
            'file column data type is ' . CpsRefFixture::columnType($table, 'col_id_' . ($fileColumn['col_id'] ?? 0))
        );
        $orphans = ee()->db->query('SELECT col_id FROM exp_grid_columns WHERE field_id IS NULL OR field_id = 0')
            ->result_array();
        $check($orphans === [], 'orphan grid_columns rows: ' . json_encode($orphans));

        // Rows: the file reference is stored as the {file:ID:url} string
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $rows = CpsRefFixture::gridRows(self::FIELD, $entryId);
        $fileKey = 'col_id_' . ($fileColumn['col_id'] ?? 0);
        $check(count($rows) === 2, 'expected 2 rows, found ' . count($rows));
        foreach ($rows as $row) {
            $check(preg_match('/^\{file:\d+:url\}$/', (string) ($row[$fileKey] ?? '')) === 1, 'file cell not a tag');
            preg_match('/^\{file:(\d+):url\}$/', (string) ($row[$fileKey] ?? ''), $match);
            $check(
                ee()->db->where('file_id', (int) ($match[1] ?? 0))->count_all_results('files') === 1,
                'file cell does not resolve to an exp_files row'
            );
        }
        // A Model/CLI save does not write exp_file_usage rows for Grid cells (same as the file fieldtype)
        $check(
            ee()->db->where('entry_id', $entryId)->count_all_results('file_usage') === 0,
            'unexpected exp_file_usage rows for a Grid file cell written through the Model'
        );

        // Fluid child
        $fluidEntry = CpsRefFixture::entryId(self::FLUID_ENTRY);
        $fluid = CpsRefFixture::fluidRows(self::FLUID, $fluidEntry);
        $childRows = CpsRefFixture::gridRows(self::FIELD, $fluidEntry);
        $check(count($fluid) === 1 && count($childRows) === 1, 'fluid: expected one fluid row and one Grid row');
        $check(
            count($fluid) === 1 && count($childRows) === 1
                && (int) $childRows[0]['fluid_field_data_id'] === (int) $fluid[0]['id'],
            'fluid: Grid row fluid_field_data_id does not match the Fluid row'
        );

        // accepts_content_type(): Fluid yes, Grid column no (grid_ft::accepts_content_type returns $name != 'grid')
        $check(self::accepts('file_grid', 'fluid_field'), 'file_grid should be accepted in Fluid');
        $check(self::accepts('file_grid', 'channel'), 'file_grid should be accepted on a channel');
        $check(! self::accepts('file_grid', 'grid'), 'file_grid must not be accepted as a Grid column');
        $check(! self::accepts('grid', 'grid'), 'grid must not be accepted as a Grid column');

        return $problems;
    }
}
