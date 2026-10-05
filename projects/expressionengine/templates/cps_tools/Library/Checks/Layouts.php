<?php

namespace CPS\Tools\Library\Checks;

use CPS\Tools\Library\Report;

/**
 * Compares publish layouts with the fields actually attached to each channel.
 * A layout naming a detached field fails; an attached field the layout never places is a warn.
 */
class Layouts
{
    private const CHECK = 'layouts';

    /**
     * @param Report $report
     * @return void
     */
    public function run(Report $report): void
    {
        $prefix = ee()->db->dbprefix;
        $layouts = ee()->db->select('l.layout_id, l.layout_name, l.channel_id, l.field_layout, c.channel_name')
            ->from('layout_publish l')
            ->join('channels c', 'c.channel_id = l.channel_id', 'left')
            ->get()
            ->result_array();

        $fieldNames = [];
        foreach (ee()->db->select('field_id, field_name')->get('channel_fields')->result_array() as $row) {
            $fieldNames[(int) $row['field_id']] = $row['field_name'];
        }

        $problems = 0;
        foreach ($layouts as $layout) {
            if ($layout['channel_name'] === null) {
                $report->add(
                    self::CHECK,
                    'layout ' . $layout['layout_id'],
                    'fail',
                    'layout belongs to channel_id ' . $layout['channel_id'] . ' which does not exist'
                );
                $problems++;
                continue;
            }

            $subject = $layout['channel_name'] . '/' . $layout['layout_name'];
            $placed = $this->placedFieldIds((string) $layout['field_layout']);
            if ($placed === null) {
                $report->add(self::CHECK, $subject, 'warn', 'layout could not be decoded');
                continue;
            }

            $attached = $this->attachedFieldIds((int) $layout['channel_id'], $prefix);

            foreach ($placed as $fieldId) {
                if (!isset($attached[$fieldId])) {
                    $name = $fieldNames[$fieldId] ?? ('field_id_' . $fieldId);
                    $report->add(
                        self::CHECK,
                        $subject,
                        'fail',
                        $name . ' is in the layout but not attached to the channel'
                    );
                    $problems++;
                }
            }

            foreach (array_keys($attached) as $fieldId) {
                if (!isset($placed[$fieldId])) {
                    $name = $fieldNames[$fieldId] ?? ('field_id_' . $fieldId);
                    $report->add(self::CHECK, $subject, 'warn', $name . ' is attached but not placed in the layout');
                    $problems++;
                }
            }
        }

        if ($problems === 0) {
            $report->add(self::CHECK, '*', 'pass', 'all layouts match attached fields');
        }
    }

    /**
     * Custom field ids named in a layout (core fields such as title are ignored).
     *
     * @param string $raw
     * @return array<int, int>|null id => id, or null when undecodable
     */
    private function placedFieldIds(string $raw): ?array
    {
        $tabs = @unserialize($raw, ['allowed_classes' => false]);
        if (!is_array($tabs)) {
            $tabs = json_decode($raw, true);
        }
        if (!is_array($tabs)) {
            return null;
        }

        $ids = [];
        foreach ($tabs as $tab) {
            foreach ($tab['fields'] ?? [] as $item) {
                if (preg_match('/^field_id_(\d+)$/', (string) ($item['field'] ?? ''), $m)) {
                    $ids[(int) $m[1]] = (int) $m[1];
                }
            }
        }
        return $ids;
    }

    /**
     * Fields attached directly or via a field group.
     *
     * @param int $channelId
     * @param string $prefix
     * @return array<int, int>
     */
    private function attachedFieldIds(int $channelId, string $prefix): array
    {
        $rows = ee()->db->query(
            'SELECT field_id FROM ' . $prefix . 'channels_channel_fields WHERE channel_id = ?
             UNION
             SELECT gf.field_id FROM ' . $prefix . 'channels_channel_field_groups cg
             JOIN ' . $prefix . 'channel_field_groups_fields gf ON gf.group_id = cg.group_id
             WHERE cg.channel_id = ?',
            [$channelId, $channelId]
        )->result_array();

        $ids = [];
        foreach ($rows as $row) {
            $ids[(int) $row['field_id']] = (int) $row['field_id'];
        }
        return $ids;
    }
}
