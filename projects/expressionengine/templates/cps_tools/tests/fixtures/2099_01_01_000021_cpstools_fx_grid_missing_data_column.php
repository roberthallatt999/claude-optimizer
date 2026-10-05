<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: a Grid field whose data table lost a col_id_N column.
 * down() re-adds the column before deleting the field so EE's own cleanup cannot trip on it.
 */
class CpstoolsFxGridMissingDataColumn extends Migration
{
    const GRID_FIELD = 'cpstools_fx_gridmiss';
    const COL_NAME = 'cpstools_fx_gm_col';

    public function up()
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();
        ee()->load->model('grid_model');

        $siteId = (int) ee()->config->item('site_id');

        $field = ee('Model')->make('ChannelField');
        $field->site_id = $siteId;
        $field->field_name = self::GRID_FIELD;
        $field->field_label = self::GRID_FIELD;
        $field->field_type = 'grid';
        $field->field_instructions = '';
        $field->field_required = 'n';
        $field->field_search = 'n';
        $field->field_is_hidden = 'n';
        $field->field_order = 1;
        $field->legacy_field_data = 'n';
        $field->field_settings = [
            'grid_min_rows' => 0, 'grid_max_rows' => '', 'allow_reorder' => 'y',
            'vertical_layout' => 'n', 'row_counter' => 'n',
        ];
        $field->save();

        ee()->grid_model->create_field($field->field_id, 'channel');
        ee()->grid_model->save_col_settings([
            'field_id' => $field->field_id,
            'content_type' => 'channel',
            'col_order' => 0,
            'col_type' => 'text',
            'col_label' => 'Col',
            'col_name' => self::COL_NAME,
            'col_instructions' => '',
            'col_required' => 'n',
            'col_search' => 'n',
            'col_width' => 0,
            'col_settings' => json_encode([
                'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr',
                'field_maxl' => 256, 'field_show_fmt' => 'n',
            ]),
        ], false, 'channel');

        // The defect: the column row exists but its data column is gone.
        $colId = $this->columnId($field->field_id);
        ee()->db->query('ALTER TABLE `' . $this->table($field->field_id) . '` DROP COLUMN `col_id_' . $colId . '`');
    }

    public function down()
    {
        $field = ee('Model')->get('ChannelField')->filter('field_name', self::GRID_FIELD)->first();
        if (!$field) {
            return;
        }

        $fieldId = (int) $field->field_id;
        $colId = $this->columnId($fieldId);
        $table = $this->table($fieldId);
        $has = ee()->db->query('SHOW COLUMNS FROM `' . $table . '` LIKE ' . ee()->db->escape('col_id_' . $colId));
        if ($colId > 0 && $has->num_rows() === 0) {
            ee()->db->query('ALTER TABLE `' . $table . '` ADD COLUMN `col_id_' . $colId . '` text');
        }

        $field->delete();
        ee()->db->where('field_id', $fieldId)->delete('grid_columns');
    }

    private function table(int $fieldId): string
    {
        return ee()->db->dbprefix . 'channel_grid_field_' . $fieldId;
    }

    private function columnId(int $fieldId): int
    {
        $row = ee()->db->select('col_id')->where('field_id', $fieldId)->where('col_name', self::COL_NAME)
            ->get('grid_columns')->row_array();
        return (int) ($row['col_id'] ?? 0);
    }
}
