<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: a Grid column saved without its field (field_id 0, the
 * save_col_settings defect pattern; the column is NOT NULL so 0 is how it lands) and one relationship row
 * pointing at a nonexistent entry. down() removes both by name/value.
 */
class CpstoolsFxGridOrphanColumn extends Migration
{
    const COL_NAME = 'cpstools_fx_orphan';
    const MISSING_ENTRY = 999999999;

    public function up()
    {
        ee()->db->insert('grid_columns', [
            'field_id' => 0,
            'content_type' => 'channel',
            'col_order' => 0,
            'col_type' => 'text',
            'col_label' => 'Orphan',
            'col_name' => self::COL_NAME,
            'col_instructions' => '',
            'col_required' => 'n',
            'col_search' => 'n',
            'col_width' => 0,
            'col_settings' => json_encode([]),
        ]);

        ee()->db->insert('relationships', [
            'parent_id' => 999999998,
            'child_id' => self::MISSING_ENTRY,
            'order' => 0,
            'field_id' => 0,
            'grid_field_id' => 0,
            'grid_col_id' => 0,
            'grid_row_id' => 0,
            'fluid_field_data_id' => 0,
        ]);
    }

    public function down()
    {
        ee()->db->where('col_name', self::COL_NAME)->delete('grid_columns');
        ee()->db->where('child_id', self::MISSING_ENTRY)->delete('relationships');
    }
}
