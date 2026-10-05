<?php

namespace CPS\Tools\Library\Checks;

use CPS\Tools\Library\Report;

/**
 * Verifies that channels, relationship fields and groups only reference things that exist.
 */
class References
{
    private const CHECK = 'references';

    /**
     * @param Report $report
     * @return void
     */
    public function run(Report $report): void
    {
        $problems = $this->relationshipTargets($report);
        $problems += $this->channelReferences($report);

        if ($problems === 0) {
            $report->add(self::CHECK, '*', 'pass', 'all channel and relationship references resolve');
        }
    }

    /**
     * @param Report $report
     * @return int
     */
    private function relationshipTargets(Report $report): int
    {
        $channelIds = $this->ids('channels', 'channel_id');
        $problems = 0;

        $fields = ee()->db->select('field_name, field_type, field_settings')
            ->where('field_type', 'relationship')
            ->get('channel_fields')
            ->result_array();
        foreach ($fields as $field) {
            $settings = @unserialize(base64_decode((string) $field['field_settings']), ['allowed_classes' => false]);
            $problems += $this->checkTargets($report, $field['field_name'], $settings, $channelIds);
        }

        $cols = ee()->db->select('g.col_settings, g.col_name, f.field_name')
            ->from('grid_columns g')
            ->join('channel_fields f', 'f.field_id = g.field_id', 'left')
            ->where('g.col_type', 'relationship')
            ->get()
            ->result_array();
        foreach ($cols as $col) {
            $subject = ($col['field_name'] ?? 'orphan') . '.' . $col['col_name'];
            $settings = json_decode((string) $col['col_settings'], true);
            $problems += $this->checkTargets($report, $subject, $settings, $channelIds);
        }
        return $problems;
    }

    /**
     * @param Report $report
     * @param string $subject
     * @param mixed $settings
     * @param array<int, int> $channelIds
     * @return int
     */
    private function checkTargets(Report $report, string $subject, $settings, array $channelIds): int
    {
        if (!is_array($settings) || !is_array($settings['channels'] ?? null)) {
            return 0;
        }

        $problems = 0;
        foreach ($settings['channels'] as $id) {
            if (is_numeric($id) && !isset($channelIds[(int) $id])) {
                // A deleted target leaves a dead picker option, not a crash: leftover, so warn.
                $report->add(
                    self::CHECK,
                    $subject,
                    'warn',
                    'relationship targets channel ' . $id . ' which does not exist',
                    'relationship'
                );
                $problems++;
            }
        }
        return $problems;
    }

    /**
     * @param Report $report
     * @return int
     */
    private function channelReferences(Report $report): int
    {
        $prefix = ee()->db->dbprefix;
        $catGroups = $this->ids('category_groups', 'group_id');
        $fieldGroups = $this->ids('field_groups', 'group_id');
        $statuses = $this->ids('statuses', 'status_id');
        $problems = 0;

        $channels = ee()->db->select('channel_id, channel_name, cat_group')->get('channels')->result_array();
        foreach ($channels as $channel) {
            $name = $channel['channel_name'];
            foreach (array_filter(explode('|', (string) $channel['cat_group']), 'strlen') as $id) {
                if (!isset($catGroups[(int) $id])) {
                    $report->add(
                        self::CHECK,
                        $name,
                        'fail',
                        'cat_group references category group ' . $id . ' which does not exist'
                    );
                    $problems++;
                }
            }
        }

        $pivots = [
            ['channel_category_groups', 'group_id', $catGroups, 'category group'],
            ['channels_channel_field_groups', 'group_id', $fieldGroups, 'field group'],
            ['channels_statuses', 'status_id', $statuses, 'status'],
        ];
        $names = [];
        foreach ($channels as $channel) {
            $names[(int) $channel['channel_id']] = $channel['channel_name'];
        }
        foreach ($pivots as [$table, $column, $known, $label]) {
            $sql = 'SELECT channel_id, ' . $column . ' AS ref FROM ' . $prefix . $table;
            $rows = ee()->db->query($sql)->result_array();
            foreach ($rows as $row) {
                $name = $names[(int) $row['channel_id']] ?? ('channel_id ' . $row['channel_id']);
                if (!isset($names[(int) $row['channel_id']])) {
                    $report->add(self::CHECK, $name, 'warn', $table . ' row for a channel that does not exist');
                    $problems++;
                } elseif (!isset($known[(int) $row['ref']])) {
                    $report->add(
                        self::CHECK,
                        $name,
                        'fail',
                        'assigned ' . $label . ' ' . $row['ref'] . ' which does not exist'
                    );
                    $problems++;
                }
            }
        }
        return $problems;
    }

    /**
     * @param string $table
     * @param string $column
     * @return array<int, int>
     */
    private function ids(string $table, string $column): array
    {
        $ids = [];
        foreach (ee()->db->select($column)->get($table)->result_array() as $row) {
            $ids[(int) $row[$column]] = (int) $row[$column];
        }
        return $ids;
    }
}
