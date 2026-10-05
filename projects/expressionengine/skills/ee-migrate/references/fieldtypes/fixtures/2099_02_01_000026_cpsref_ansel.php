<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: ansel (Plan 2 Task 8, third-party, add-on version recorded in ansel.md).
 * Ansel stores each image as a row in exp_ansel_images (plus two exp_files rows) and writes processed image
 * files to disk from post_save(), so this fixture proves everything EXCEPT content: the settings contract
 * (directories as 'ee:<id>' strings), storage of the field's own column, Grid/Fluid creation, and that deleting
 * a field removes its exp_ansel_images rows. It never saves an image value, never writes to exp_ansel_images
 * except one throwaway probe row (no file ids), and creates no files or upload directories.
 * Directories are the site's first upload directories (read only). down() removes everything cpsref*.
 */
class CpsrefAnsel extends Migration
{
    const FIELD = 'cpsref_ansel';
    const CPS = 'cpsref_ansel_cps';
    const PROBE = 'cpsref_ansel_probe';
    const GRID = 'cpsref_ansel_grid';
    const COL = 'cpsref_ansel_col';
    const FLUID = 'cpsref_ansel_fluid';
    const ENTRY = 'cpsref-ansel';

    public function up()
    {
        try {
            $this->build();
        } catch (\Throwable $e) {
            try {
                $this->down();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    /**
     * Three distinct upload directories (read only). A real migration resolves them by NAME; Ansel requires the
     * upload and save directories to be different (validateUniqueDirectory), the preview one optional.
     */
    private static function directories(): array
    {
        $rows = ee()->db->select('id')->order_by('id')->limit(3)->get('upload_prefs')->result_array();
        if (count($rows) < 3) {
            throw new \RuntimeException('prerequisite missing: need three upload directories in exp_upload_prefs');
        }

        return array_map(function ($row) { return 'ee:' . (int) $row['id']; }, $rows);
    }

    /** Every key save_settings() can return (FieldSettings model properties minus the excluded ones, + field_wide). */
    private static function fullSettings(array $dirs): array
    {
        return [
            'upload_directory' => $dirs[0], 'save_directory' => $dirs[1], 'preview_directory' => $dirs[2],
            'tile_view' => 'y', 'min_qty' => 1, 'max_qty' => 3, 'prevent_upload_over_max' => 'y',
            'quality' => 85, 'force_jpg' => 'n', 'force_webp' => 'y', 'retina_mode' => 'n',
            'min_width' => 200, 'min_height' => 100, 'max_width' => 1600, 'max_height' => 1200, 'ratio' => '16:9',
            'show_title' => 'y', 'require_title' => 'n', 'title_label' => 'Caption',
            'show_description' => 'y', 'require_description' => 'n', 'description_label' => 'Alt text',
            'show_cover' => 'y', 'require_cover' => 'n', 'cover_label' => 'Cover',
            'prepend_to_table' => 'n', 'field_wide' => true,
        ];
    }

    /** The shape of the one existing cps field (committee_photo): no preview directory, tile_view, force_webp, prepend. */
    private static function cpsSettings(array $dirs): array
    {
        return [
            'upload_directory' => $dirs[0], 'save_directory' => $dirs[1], 'min_qty' => 0, 'max_qty' => 0,
            'prevent_upload_over_max' => 'n', 'quality' => 90, 'force_jpg' => 'n', 'retina_mode' => 'n',
            'min_width' => 500, 'min_height' => 500, 'max_width' => 500, 'max_height' => 500, 'ratio' => '1:1',
            'show_title' => 'n', 'require_title' => 'n', 'title_label' => '', 'show_cover' => 'n',
            'require_cover' => 'n', 'cover_label' => '', 'field_wide' => true, 'show_description' => 'n',
            'require_description' => 'n', 'description_label' => '',
        ];
    }

    private function build(): void
    {
        CpsRefFixture::ensureSession();
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $dirs = self::directories();

        CpsRefFixture::makeField($group, self::FIELD, 'ansel', self::fullSettings($dirs), 1);
        CpsRefFixture::makeField($group, self::CPS, 'ansel', self::cpsSettings($dirs), 2);
        // Grid column and Fluid child: accepts_content_type() allows both. There is no grid_save_settings(), so the
        // column keeps whatever the settings form posts; the unprefixed keys here are what the model reads.
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COL, 'type' => 'ansel', 'label' => 'Photo', 'settings' => self::cpsSettings($dirs)],
        ], 3);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::CPS], 4);

        // Deleting a field must remove its image rows (Extensions/AfterChannelFieldDelete). Proved with a probe
        // field and one probe row that has no file ids, so nothing on disk or in exp_files is involved.
        $probe = CpsRefFixture::makeField($group, self::PROBE, 'ansel', self::cpsSettings($dirs), 5);
        $probeId = (int) $probe->field_id;
        ee()->db->insert('ansel_images', [
            'site_id' => CpsRefFixture::siteId(), 'source_id' => 0, 'content_id' => 0, 'field_id' => $probeId,
            'content_type' => 'channel', 'filename' => 'cpsref-probe', 'extension' => 'jpg',
            'upload_date' => ee()->localize->now,
        ]);
        $probe->delete();
        CpsRefFixture::dropDataTableIfExists($probeId);
        $left = ee()->db->where('field_id', $probeId)->count_all_results('ansel_images');
        if ($left !== 0) {
            ee()->db->where('field_id', $probeId)->delete('ansel_images');
            throw new \RuntimeException('deleting an ansel field left its exp_ansel_images rows behind');
        }

        // No image value: Ansel writes image files from post_save(); a migration must not.
        CpsRefFixture::makeEntry(self::ENTRY, []);
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
        $dirs = self::directories();

        // Settings contract: top level (full) and the existing-cps shape
        $full = CpsRefFixture::fieldSettings(self::FIELD);
        foreach (array_keys(self::fullSettings($dirs)) as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $full), "full settings missing $key");
        }
        CpsRefFixture::check($problems, ($full['upload_directory'] ?? null) === $dirs[0], 'upload_directory should be the string ee:<id>');
        CpsRefFixture::check($problems, ($full['field_wide'] ?? null) === true, 'field_wide should be boolean true');
        CpsRefFixture::check($problems, ($full['quality'] ?? null) === 85 && ($full['max_qty'] ?? null) === 3, 'quality/max_qty should be integers');
        CpsRefFixture::check($problems, ($full['prevent_upload_over_max'] ?? null) === 'y', 'booleans are stored as y/n strings');
        $cps = CpsRefFixture::fieldSettings(self::CPS);
        foreach (array_keys(self::cpsSettings($dirs)) as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $cps), "cps-shaped settings missing $key");
        }
        $col = CpsRefFixture::gridColumnSettings(self::GRID, self::COL);
        CpsRefFixture::check($problems, ($col['upload_directory'] ?? null) === $dirs[0] && ($col['quality'] ?? null) === 90, 'grid column settings did not store');

        // Storage: default text column plus field_ft_N; the grid column is text too
        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $cpsId = CpsRefFixture::fieldId(self::CPS);
        CpsRefFixture::check($problems, CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId) === 'text', 'data column is not text');
        CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data_field_' . $fieldId, 'field_ft_' . $fieldId), 'field_ft column missing');
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COL);
        $gridTable = 'channel_grid_field_' . CpsRefFixture::fieldId(self::GRID);
        CpsRefFixture::check($problems, CpsRefFixture::columnType($gridTable, 'col_id_' . $colId) === 'text', 'grid column is not text');

        // Ansel's own table and what an unset field writes
        foreach (['id', 'site_id', 'source_id', 'content_id', 'field_id', 'content_type', 'row_id', 'col_id', 'file_id',
            'original_file_id', 'upload_location_id', 'filename', 'extension', 'width', 'height', 'x', 'y', 'position',
            'cover', 'title', 'description', 'disabled'] as $column) {
            CpsRefFixture::check($problems, CpsRefFixture::columnExists('ansel_images', $column), "exp_ansel_images.$column missing");
        }
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        $stored = CpsRefFixture::fieldValue(self::FIELD, $entryId);
        CpsRefFixture::check($problems, $stored === null, 'an entry saved without an ansel value should leave the column NULL; it holds: ' . var_export($stored, true));
        $images = ee()->db->where_in('field_id', [$fieldId, $cpsId])->count_all_results('ansel_images');
        CpsRefFixture::check($problems, $images === 0, 'no image rows should exist for the fixture fields');
        CpsRefFixture::check($problems, ee()->db->where('field_id', CpsRefFixture::fieldId(self::PROBE))->count_all_results('ansel_images') === 0, 'probe rows should be gone');

        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));

        return $problems;
    }
}
