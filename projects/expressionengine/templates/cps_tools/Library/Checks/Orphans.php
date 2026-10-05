<?php

namespace CPS\Tools\Library\Checks;

use CPS\Tools\Library\Report;

/**
 * Finds Grid, Fluid and relationship rows pointing at things that no longer exist.
 * A Grid column with no field_id and a Fluid row pointing at a missing field fail (they break saves);
 * leftovers from deleted things only warn (live sites accumulate them).
 */
class Orphans
{
    private const CHECK = 'orphans';

    /**
     * @param Report $report
     * @return void
     */
    public function run(Report $report): void
    {
        $found = 0;
        $found += $this->gridColumns($report);
        $found += $this->fluid($report);
        $found += $this->relationships($report);

        if ($found === 0) {
            $report->add(self::CHECK, '*', 'pass', 'no orphaned rows');
        }
    }

    /**
     * @param Report $report
     * @return int
     */
    private function gridColumns(Report $report): int
    {
        $rows = ee()->db->query(
            'SELECT g.col_id, g.col_name, g.field_id FROM ' . ee()->db->dbprefix . 'grid_columns g
             LEFT JOIN ' . ee()->db->dbprefix . 'channel_fields f ON f.field_id = g.field_id
             WHERE g.content_type = ? AND f.field_id IS NULL',
            ['channel']
        )->result_array();

        foreach ($rows as $row) {
            $parent = (int) ($row['field_id'] ?? 0);
            if ($parent === 0) {
                // The save_col_settings defect pattern: a column saved without its field.
                $report->add(
                    self::CHECK,
                    'grid_columns.' . $row['col_name'],
                    'fail',
                    'Grid column ' . $row['col_id'] . ' has a NULL/0 field_id'
                );
                continue;
            }
            $report->add(
                self::CHECK,
                'grid_columns.' . $row['col_name'],
                'warn',
                'Grid column ' . $row['col_id'] . ' is a leftover from deleted field ' . $parent
            );
        }
        return count($rows);
    }

    /**
     * @param Report $report
     * @return int
     */
    private function fluid(Report $report): int
    {
        $prefix = ee()->db->dbprefix;
        $count = 0;
        $checks = [
            'field_id' => 'field',
            'fluid_field_id' => 'fluid field',
        ];
        foreach ($checks as $column => $label) {
            $row = ee()->db->query(
                'SELECT COUNT(*) AS n FROM ' . $prefix . 'fluid_field_data d
                 LEFT JOIN ' . $prefix . 'channel_fields f ON f.field_id = d.' . $column . '
                 WHERE f.field_id IS NULL'
            )->row_array();
            $n = (int) ($row['n'] ?? 0);
            if ($n > 0) {
                $report->add(
                    self::CHECK,
                    'fluid_field_data.' . $column,
                    'fail',
                    $n . ' fluid_field_data row(s) reference a deleted ' . $label
                );
                $count++;
            }
        }
        return $count;
    }

    /**
     * @param Report $report
     * @return int
     */
    private function relationships(Report $report): int
    {
        $prefix = ee()->db->dbprefix;
        $count = 0;
        foreach (['parent_id', 'child_id'] as $column) {
            $where = 'r.' . $column . ' <> 0 AND t.entry_id IS NULL';
            $join = 'LEFT JOIN ' . $prefix . 'channel_titles t ON t.entry_id = r.' . $column;
            $total = ee()->db->query(
                'SELECT COUNT(*) AS n FROM ' . $prefix . 'relationships r ' . $join . ' WHERE ' . $where
            )->row_array();
            $n = (int) ($total['n'] ?? 0);
            if ($n === 0) {
                continue;
            }

            $sample = ee()->db->query(
                'SELECT r.relationship_id FROM ' . $prefix . 'relationships r ' . $join
                . ' WHERE ' . $where . ' ORDER BY r.relationship_id LIMIT 5'
            )->result_array();
            $ids = implode(',', array_column($sample, 'relationship_id'));
            $report->add(
                self::CHECK,
                'relationships.' . $column,
                'warn',
                $n . ' relationship row(s) have a ' . $column . ' that is not an entry (first ids: ' . $ids . ')'
            );
            $count++;
        }
        return $count;
    }
}
