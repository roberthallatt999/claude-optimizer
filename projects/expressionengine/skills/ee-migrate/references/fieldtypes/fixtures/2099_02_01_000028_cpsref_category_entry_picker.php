<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: category_entry_picker (Plan 2 Task 9, cyntc only; CPS-custom add-on).
 * Top-level field only: the fieldtype does not override accepts_content_type(), so it is not a Grid column
 * or Fluid child. The value is a JSON object {"entry_id":N,"category_id":N}. down() removes everything cpsref*.
 *
 * NEVER RUN TO PASS: the add-on is not installed in any CPS site's live database (code is in the cyntc repo,
 * installed only in a stale local database), so run-fixtures.sh SKIPs it. It becomes the verification once the
 * add-on (module + fieldtype) is installed on the target site.
 */
class CpsrefCategoryEntryPicker extends Migration
{
    const FIELD = 'cpsref_category_entry_picker';
    const ENTRY = 'cpsref-category-entry-picker';
    const TARGET = 'cpsref-category-entry-picker-target';

    public function up()
    {
        try {
            $this->build();
        } catch (\Throwable $e) {
            try {
                CpsRefFixture::removeAll();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    /** First category group on the site (settings must not depend on specific content); 0 when there is none. */
    private static function firstCategoryGroupId(): int
    {
        $row = ee()->db->select_min('group_id', 'id')->get('category_groups')->row_array();

        return (int) ($row['id'] ?? 0);
    }

    private static function firstCategoryId(int $groupId): int
    {
        if ($groupId <= 0) {
            return 0;
        }
        $row = ee()->db->select_min('cat_id', 'id')->where('group_id', $groupId)->get('categories')->row_array();

        return (int) ($row['id'] ?? 0);
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $groupId = self::firstCategoryGroupId();

        // Complete settings, exactly the three keys save_settings() returns (all strings)
        CpsRefFixture::makeField($container['group'], self::FIELD, 'category_entry_picker', [
            'channel_id' => (string) $container['channel']->channel_id,
            'cat_group_id' => $groupId > 0 ? (string) $groupId : '',
            'allow_nested' => 'y',
            // validate() indexes $this->settings['field_required'] directly: always write it
            'field_required' => 'n',
        ], 1);

        // The picked entry: a second entry in the fixture channel (no dependence on site content)
        $targetId = CpsRefFixture::makeEntry(self::TARGET, []);
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::FIELD => ['entry_id' => $targetId, 'category_id' => self::firstCategoryId($groupId)],
        ]);
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];

        $settings = CpsRefFixture::fieldSettings(self::FIELD);
        foreach (['channel_id', 'cat_group_id', 'allow_nested'] as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $settings), "settings missing $key");
        }
        CpsRefFixture::check($problems, ($settings['allow_nested'] ?? '') === 'y', 'allow_nested should be y');

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        CpsRefFixture::check($problems, CpsRefFixture::columnExists('channel_data_field_' . $fieldId, 'field_id_' . $fieldId), 'data column missing');

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        $targetId = CpsRefFixture::entryId(self::TARGET);
        CpsRefFixture::check($problems, $entryId > 0 && $targetId > 0, 'entries not found');

        // The stored value is the JSON string produced by save(), with integer members
        $stored = CpsRefFixture::fieldValue(self::FIELD, $entryId);
        $decoded = json_decode((string) $stored, true);
        CpsRefFixture::check($problems, is_array($decoded), 'stored value is not JSON: ' . var_export($stored, true));
        CpsRefFixture::check($problems, ($decoded['entry_id'] ?? null) === $targetId, 'entry_id did not read back');
        CpsRefFixture::check($problems, is_int($decoded['category_id'] ?? null), 'category_id should be an int');

        // validate() with field_required = n accepts any value; with y it reads $data['entry_id']
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));

        return $problems;
    }
}
