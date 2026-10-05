<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: image_cropper (Plan 2 Task 10), READ-ONLY.
 * image_cropper is a CPS-written add-on (namespace CPS\ImageCropper, not EEHarbor/EE2) that exists only on cpsp,
 * so a migration must never create its fields: up() and down() change nothing. verify() reads the EXISTING
 * fields and asserts the data model image_cropper.md documents: the three settings keys, the field's own
 * data table, the exp_image_crops table, and that crop rows belong to a field of this type.
 */
class CpsrefImageCropper extends Migration
{
    public function up()
    {
        // Intentionally empty: not created by migrations.
    }

    public function down()
    {
        // Intentionally empty: nothing was created.
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];

        $fields = ee()->db->select('field_id, field_name, legacy_field_data')->where('field_type', 'image_cropper')
            ->order_by('field_id')->get('channel_fields')->result_array();
        CpsRefFixture::check($problems, count($fields) > 0, 'no image_cropper fields exist on this site');

        foreach (['crop_id', 'entry_id', 'field_id', 'original_file', 'cropped_file', 'variant_name', 'crop_x', 'crop_y',
            'crop_width', 'crop_height', 'output_width', 'output_height', 'aspect_ratio', 'canvas_data', 'cropbox_data'] as $column) {
            CpsRefFixture::check($problems, CpsRefFixture::columnExists('image_crops', $column), "image_crops.$column missing");
        }

        $totalCrops = 0;
        foreach ($fields as $field) {
            $name = $field['field_name'];
            $fieldId = (int) $field['field_id'];

            // Settings: exactly the three keys save_settings() writes; the upload directory must exist.
            $settings = CpsRefFixture::fieldSettings($name);
            foreach (['upload_location_id', 'output_width', 'output_height'] as $key) {
                CpsRefFixture::check($problems, array_key_exists($key, $settings), "$name settings missing $key");
            }
            $dirExists = ee()->db->where('id', (int) ($settings['upload_location_id'] ?? 0))->count_all_results('upload_prefs') === 1;
            CpsRefFixture::check($problems, $dirExists, "$name upload_location_id does not name an upload directory");

            // Value storage: the field's own column holds the original file reference (URL or /path). Where the
            // field has its own data table (legacy_field_data = 'n') it is channel_data_field_N, else channel_data.
            $table = $field['legacy_field_data'] === 'y' ? 'channel_data' : 'channel_data_field_' . $fieldId;
            CpsRefFixture::check($problems, CpsRefFixture::columnExists($table, 'field_id_' . $fieldId), "$table.field_id_$fieldId missing");

            // Crop rows: one per entry + variant, tied to this field.
            $crops = ee()->db->where('field_id', $fieldId)->get('image_crops')->result_array();
            $totalCrops += count($crops);
            foreach ($crops as $crop) {
                CpsRefFixture::check($problems, $crop['variant_name'] !== '' && $crop['cropped_file'] !== '', "crop {$crop['crop_id']} lacks variant or cropped_file");
                CpsRefFixture::check($problems, (int) $crop['crop_width'] > 0 && (int) $crop['crop_height'] > 0, "crop {$crop['crop_id']} has no size");
                foreach (['canvas_data', 'cropbox_data'] as $json) {
                    CpsRefFixture::check($problems, $crop[$json] === null || is_array(json_decode($crop[$json], true)), "crop {$crop['crop_id']} $json is not JSON");
                }
            }
        }
        CpsRefFixture::check($problems, $totalCrops > 0, 'image_cropper fields exist but exp_image_crops holds no rows for them');

        return $problems;
    }
}
