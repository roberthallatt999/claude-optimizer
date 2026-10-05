<?php

namespace CPS\Tools\Library\Checks;

use CPS\Tools\Library\Report;

/**
 * Verifies the data tables and columns EE needs for every channel field exist.
 * Pure SELECT / SHOW; safe on any environment.
 */
class Storage
{
    private const CHECK = 'storage';

    /**
     * @param Report $report
     * @return void
     */
    public function run(Report $report): void
    {
        $prefix = ee()->db->dbprefix;
        $fields = ee()->db->select('field_id, field_name, field_type, legacy_field_data')
            ->get('channel_fields')
            ->result_array();

        $problems = 0;
        foreach ($fields as $field) {
            $fieldId = (int) $field['field_id'];
            $name = (string) $field['field_name'];
            $type = (string) $field['field_type'];

            if ($field['legacy_field_data'] === 'n') {
                $table = $prefix . 'channel_data_field_' . $fieldId;
                $columns = $this->columns($table);
                if ($columns === null) {
                    $report->add(self::CHECK, $name, 'fail', 'missing table ' . $table, $type);
                    $problems++;
                } elseif (!in_array('field_id_' . $fieldId, $columns, true)) {
                    $message = 'missing column field_id_' . $fieldId . ' in ' . $table;
                    $report->add(self::CHECK, $name, 'fail', $message, $type);
                    $problems++;
                }
            }

            if (in_array($type, ['grid', 'file_grid'], true)) {
                $problems += $this->checkGrid($report, $prefix, $fieldId, $name, $type);
            }
        }

        if ($problems === 0) {
            $report->add(self::CHECK, '*', 'pass', 'all field data tables and columns present');
        }
    }

    /**
     * @param Report $report
     * @param string $prefix
     * @param int $fieldId
     * @param string $name
     * @param string $type
     * @return int number of failures recorded
     */
    private function checkGrid(Report $report, string $prefix, int $fieldId, string $name, string $type): int
    {
        $table = $prefix . 'channel_grid_field_' . $fieldId;
        $columns = $this->columns($table);
        if ($columns === null) {
            $report->add(self::CHECK, $name, 'fail', 'missing grid table ' . $table, $type);
            return 1;
        }

        $cols = ee()->db->select('col_id, col_name')
            ->where('field_id', $fieldId)
            ->where('content_type', 'channel')
            ->get('grid_columns')
            ->result_array();

        $failures = 0;
        foreach ($cols as $col) {
            if (!in_array('col_id_' . $col['col_id'], $columns, true)) {
                $report->add(
                    self::CHECK,
                    $name . '.' . $col['col_name'],
                    'fail',
                    'missing column col_id_' . $col['col_id'] . ' in ' . $table,
                    $type
                );
                $failures++;
            }
        }
        return $failures;
    }

    /**
     * Column names of a table, or null when it does not exist.
     * SHOW TABLES LIKE rather than table_exists(), which caches per request.
     *
     * @param string $table
     * @return array<int, string>|null
     */
    private function columns(string $table): ?array
    {
        $like = str_replace(['\\', '_', '%'], ['\\\\', '\\_', '\\%'], $table);
        $exists = ee()->db->query('SHOW TABLES LIKE ' . ee()->db->escape($like))->num_rows() > 0;
        if (!$exists) {
            return null;
        }

        $names = [];
        foreach (ee()->db->query('SHOW COLUMNS FROM `' . $table . '`')->result_array() as $row) {
            $names[] = $row['Field'];
        }
        return $names;
    }
}
