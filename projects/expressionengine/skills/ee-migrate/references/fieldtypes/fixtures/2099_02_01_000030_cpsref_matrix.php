<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: matrix (Plan 2 Task 10), LEGACY and READ-ONLY.
 * Matrix (EEHarbor, EE2 era) must never be created by a migration, so up() and down() change nothing. verify()
 * reads the site's EXISTING matrix fields and asserts the data model matrix.md documents: settings keys, the
 * exp_matrix_cols definitions, the col_id_N columns of exp_matrix_data, and that stored rows (if any) are
 * well-formed. It does NOT require matrix rows to exist: on cpsp exp_matrix_data is empty.
 */
class CpsrefMatrix extends Migration
{
    public function up()
    {
        // Intentionally empty: legacy fieldtype, never created.
    }

    public function down()
    {
        // Intentionally empty: nothing was created.
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];

        $fields = ee()->db->select('field_id, field_name')->where('field_type', 'matrix')
            ->order_by('field_id')->get('channel_fields')->result_array();
        CpsRefFixture::check($problems, count($fields) > 0, 'no matrix fields exist on this site');

        foreach (['matrix_cols', 'matrix_data'] as $table) {
            CpsRefFixture::check($problems, CpsRefFixture::tableExists($table), "exp_$table missing");
        }
        foreach (['row_id', 'site_id', 'entry_id', 'field_id', 'var_id', 'row_order'] as $column) {
            CpsRefFixture::check($problems, CpsRefFixture::columnExists('matrix_data', $column), "matrix_data.$column missing");
        }

        foreach ($fields as $field) {
            $name = $field['field_name'];
            $fieldId = (int) $field['field_id'];

            // Settings: min_rows/max_rows are strings, col_ids is the ordered list of exp_matrix_cols ids.
            $settings = CpsRefFixture::fieldSettings($name);
            foreach (['min_rows', 'max_rows', 'col_ids', 'field_wide'] as $key) {
                CpsRefFixture::check($problems, array_key_exists($key, $settings), "$name settings missing $key");
            }
            $colIds = array_map('intval', (array) ($settings['col_ids'] ?? []));
            CpsRefFixture::check($problems, count($colIds) > 0, "$name has no col_ids");

            // Column definitions: one exp_matrix_cols row per col_id, owned by this field, in col_order.
            $cols = ee()->db->where('field_id', $fieldId)->order_by('col_order')->get('matrix_cols')->result_array();
            CpsRefFixture::check($problems, array_map('intval', array_column($cols, 'col_id')) === $colIds, "$name col_ids do not match matrix_cols rows in col_order");
            foreach ($cols as $col) {
                $colId = (int) $col['col_id'];
                CpsRefFixture::check($problems, $col['col_name'] !== '' && $col['col_type'] !== '', "col $colId lacks name or type");
                // col_settings is base64(serialize(array)), like channel_fields.field_settings.
                $decoded = @unserialize(base64_decode((string) $col['col_settings']));
                CpsRefFixture::check($problems, is_array($decoded), "col $colId col_settings does not decode");
                // Every column owns a col_id_N text column on exp_matrix_data.
                CpsRefFixture::check($problems, CpsRefFixture::columnExists('matrix_data', 'col_id_' . $colId), "matrix_data.col_id_$colId missing");
            }

            // The field's own column holds search keywords (or a flag), not the rows.
            CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data', 'field_id_' . $fieldId), "channel_data.field_id_$fieldId missing");

            // Rows, if any: keyed by entry_id + field_id, ordered by row_order from 1, entries exist.
            $rows = ee()->db->where('field_id', $fieldId)->order_by('entry_id')->order_by('row_order')
                ->get('matrix_data')->result_array();
            foreach ($rows as $row) {
                CpsRefFixture::check($problems, (int) $row['row_order'] >= 1, "$name row {$row['row_id']} has row_order < 1");
                $exists = ee()->db->where('entry_id', (int) $row['entry_id'])->count_all_results('channel_titles') === 1;
                CpsRefFixture::check($problems, $exists, "$name row {$row['row_id']} points at missing entry {$row['entry_id']}");
            }
        }

        return $problems;
    }
}
