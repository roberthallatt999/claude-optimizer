<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: playa (Plan 2 Task 10), LEGACY and READ-ONLY.
 * Playa (EEHarbor, EE2 era) must never be created by a migration, so up() and down() change nothing. All the work
 * is in verify(), which reads the site's EXISTING playa fields and asserts the data model playa.md documents:
 * settings keys, the exp_playa_relationships table, the field's text column, and that the stored rows point at
 * entries that exist. Only runs on cpsp (playa.md says fixture_site: cpsp); the runner skips it elsewhere.
 */
class CpsrefPlaya extends Migration
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

        $fields = ee()->db->select('field_id, field_name')->where('field_type', 'playa')
            ->order_by('field_id')->get('channel_fields')->result_array();
        CpsRefFixture::check($problems, count($fields) > 0, 'no playa fields exist on this site');

        CpsRefFixture::check($problems, CpsRefFixture::tableExists('playa_relationships'), 'exp_playa_relationships missing');
        foreach (['rel_id', 'parent_entry_id', 'parent_field_id', 'parent_col_id', 'parent_row_id', 'parent_var_id',
            'parent_is_draft', 'child_entry_id', 'rel_order'] as $column) {
            CpsRefFixture::check($problems, CpsRefFixture::columnExists('playa_relationships', $column), "playa_relationships.$column missing");
        }

        $totalRows = 0;
        foreach ($fields as $field) {
            $name = $field['field_name'];
            $fieldId = (int) $field['field_id'];

            // Settings: the keys playa.md documents. 'multi' is 'y'/'n'; channels is an array of channel id strings.
            $settings = CpsRefFixture::fieldSettings($name);
            foreach (['multi', 'expired', 'future', 'orderby', 'sort', 'field_wide'] as $key) {
                CpsRefFixture::check($problems, array_key_exists($key, $settings), "$name settings missing $key");
            }
            CpsRefFixture::check($problems, in_array($settings['multi'] ?? '', ['y', 'n'], true), "$name multi is not y/n");
            CpsRefFixture::check($problems, in_array($settings['sort'] ?? '', ['ASC', 'DESC'], true), "$name sort is not ASC/DESC");
            if (isset($settings['channels'])) {
                CpsRefFixture::check($problems, is_array($settings['channels']), "$name channels is not an array");
                foreach ((array) $settings['channels'] as $channelId) {
                    $exists = ee()->db->where('channel_id', (int) $channelId)->count_all_results('channels') === 1;
                    CpsRefFixture::check($problems, $exists, "$name channels names missing channel $channelId");
                }
            }

            // The field's own column holds search keywords ("[id] [url_title] title" per line), not the relationships.
            CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data', 'field_id_' . $fieldId), "channel_data.field_id_$fieldId missing");

            // The relationships: rows keyed by parent_field_id; children must be real entries.
            $rows = ee()->db->where('parent_field_id', $fieldId)->get('playa_relationships')->result_array();
            $totalRows += count($rows);
            foreach ($rows as $row) {
                CpsRefFixture::check($problems, (int) $row['parent_col_id'] === 0 || $row['parent_col_id'] === null, "$name relationship has parent_col_id");
            }
            $orphans = ee()->db->query(
                'SELECT COUNT(*) AS n FROM ' . ee()->db->dbprefix . 'playa_relationships r'
                . ' LEFT JOIN ' . ee()->db->dbprefix . 'channel_titles t ON t.entry_id = r.child_entry_id'
                . ' WHERE r.parent_field_id = ' . $fieldId . ' AND t.entry_id IS NULL'
            )->row_array();
            CpsRefFixture::check($problems, (int) ($orphans['n'] ?? 0) === 0, "$name has relationships to missing entries");
        }
        CpsRefFixture::check($problems, $totalRows > 0, 'playa fields exist but exp_playa_relationships holds no rows for them');

        // Value shape: the first non-empty field value starts with "[<entry_id>] [<url_title>] ".
        if ($fields) {
            $column = 'field_id_' . (int) $fields[0]['field_id'];
            if (CpsRefFixture::columnExists('channel_data', $column)) {
                $row = ee()->db->query("SELECT `$column` AS v FROM " . ee()->db->dbprefix . "channel_data WHERE `$column` <> '' LIMIT 1")->row_array();
                if ($row) {
                    CpsRefFixture::check($problems, preg_match('/^\[\d+\] \[[^\]]*\] /', (string) $row['v']) === 1, 'playa keyword text is not "[id] [url_title] title"');
                }
            }
        }

        return $problems;
    }
}
