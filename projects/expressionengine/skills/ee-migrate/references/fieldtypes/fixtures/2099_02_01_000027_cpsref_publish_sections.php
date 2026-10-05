<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: publish_sections (Plan 2 Task 8, third-party, add-on version recorded in
 * publish_sections.md). A layout-only heading: it stores no entry data (save() returns null), takes its heading
 * text from the field LABEL and the paragraph below it from the field INSTRUCTIONS, and accepts only the
 * channel content type (no Grid column, no Fluid child). Proves the settings contract, that a value written
 * to it is discarded, both CPS attachment conventions (through a field group; directly to the channel) and a
 * publish layout that places the heading. down() removes everything cpsref*, layout included.
 */
class CpsrefPublishSections extends Migration
{
    const GROUPED = 'cpsref_section_grouped';
    const DIRECT = 'cpsref_section_direct';
    const BODY = 'cpsref_section_body';
    const ENTRY = 'cpsref-publish-sections';
    const LAYOUT = 'cpsref_section_layout';
    const COLOUR = '#228BE6';
    const INSTRUCTIONS = 'Shown as a paragraph under the heading.';

    public function up()
    {
        try {
            $this->build();
        } catch (\Throwable $e) {
            try {
                $this->down();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    /** The five keys save_settings() reads from the POST (show_heading is always null on this install) + 2 display keys. */
    private static function settings(array $override = []): array
    {
        return array_merge([
            'show_heading' => null, 'display_style' => 'medium', 'display_icon' => 'info-circle',
            'bg_color' => self::COLOUR, 'collapse_state' => 'collapsible',
            'field_fmt' => 'none', 'field_show_fmt' => 'n',
        ], $override);
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];
        $channel = $container['channel'];

        // Convention 1 (events): attached through the field group the channel already uses
        CpsRefFixture::makeField($group, self::GROUPED, 'publish_sections', self::settings(), 1, [
            'field_instructions' => self::INSTRUCTIONS, 'field_fmt' => 'none',
        ]);
        // Convention 2 (cccymh): no field group; attached to the channel directly through the CustomFields
        // association (Collection::add() on the magic getter silently writes nothing; see 2026_09_09_090000)
        $direct = CpsRefFixture::makeField(null, self::DIRECT, 'publish_sections', self::settings([
            'display_style' => 'small', 'display_icon' => 'calendar', 'bg_color' => '', 'collapse_state' => 'collapsed',
        ]), 2, ['field_fmt' => 'none']);
        $channel->getAssociation('CustomFields')->add($direct);
        $channel->save();
        CpsRefFixture::makeField($group, self::BODY, 'text', [
            'field_text_direction' => 'ltr', 'field_maxl' => 256, 'field_fmt' => 'none',
        ], 3, ['field_fmt' => 'none']);

        // Publish layout: headings are placed like any other field, by 'field_id_N'
        $layout = ee('Model')->make('ChannelLayout');
        $layout->site_id = CpsRefFixture::siteId();
        $layout->channel_id = $channel->channel_id;
        $layout->layout_name = self::LAYOUT;
        $layout->field_layout = [[
            'id' => 'publish', 'name' => 'publish', 'visible' => true, 'fields' => [
                ['field' => 'title', 'visible' => true, 'collapsed' => false],
                ['field' => 'field_id_' . CpsRefFixture::fieldId(self::GROUPED), 'visible' => true, 'collapsed' => false],
                ['field' => 'field_id_' . CpsRefFixture::fieldId(self::BODY), 'visible' => true, 'collapsed' => false],
                ['field' => 'field_id_' . CpsRefFixture::fieldId(self::DIRECT), 'visible' => true, 'collapsed' => false],
            ],
        ]];
        $layout->save();

        // A value written to a heading is discarded: save() returns null
        CpsRefFixture::makeEntry(self::ENTRY, [
            self::GROUPED => 'this value is discarded',
            self::BODY => 'body text',
        ]);
    }

    public function down()
    {
        // Remove the layout first (resolved by name), then everything else named cpsref*
        $layouts = ee('Model')->get('ChannelLayout')->filter('layout_name', self::LAYOUT)->all();
        foreach ($layouts as $layout) {
            $layout->delete();
        }
        CpsRefFixture::removeAll();
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        $contract = ['show_heading', 'display_style', 'display_icon', 'bg_color', 'collapse_state', 'field_fmt', 'field_show_fmt'];

        $grouped = CpsRefFixture::fieldSettings(self::GROUPED);
        $direct = CpsRefFixture::fieldSettings(self::DIRECT);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $grouped), "grouped settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $direct), "direct settings missing $key");
        }
        CpsRefFixture::check($problems, array_key_exists('show_heading', $grouped) && $grouped['show_heading'] === null, 'show_heading should be null');
        CpsRefFixture::check($problems, ($grouped['bg_color'] ?? null) === self::COLOUR, 'bg_color did not store');
        CpsRefFixture::check($problems, ($direct['collapse_state'] ?? null) === 'collapsed', 'collapse_state collapsed did not store');
        include PATH_THIRD . 'publish_sections/libraries/icons.php';
        CpsRefFixture::check($problems, in_array($grouped['display_icon'] ?? '', $icons, true), 'info-circle is not in the add-on icon list');
        CpsRefFixture::check($problems, in_array($direct['display_icon'] ?? '', $icons, true), 'calendar is not in the add-on icon list');

        // Heading text = label, paragraph = instructions (display_field() reads both; the label is not a setting)
        CpsRefFixture::check($problems, CpsRefFixture::nativeColumn(self::GROUPED, 'field_label') === self::GROUPED, 'label should be the heading text');
        CpsRefFixture::check($problems, CpsRefFixture::nativeColumn(self::GROUPED, 'field_instructions') === self::INSTRUCTIONS, 'instructions did not store');

        // Storage: no settings_modify_column override, so the default text column and a field_ft_N column exist,
        // but the entry stores nothing, even when a value was written
        $fieldId = CpsRefFixture::fieldId(self::GROUPED);
        $directId = CpsRefFixture::fieldId(self::DIRECT);
        $type = CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId);
        CpsRefFixture::check($problems, $type === 'text', "column type is $type, expected text");
        CpsRefFixture::check($problems, CpsRefFixture::columnType('channel_data_field_' . $directId, 'field_id_' . $directId) === 'text', 'direct column is not text');
        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::GROUPED, $entryId) === null, 'the heading column should stay NULL even though a value was written');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::DIRECT, $entryId) === null, 'the direct heading column should be NULL');
        CpsRefFixture::check($problems, CpsRefFixture::fieldValue(self::BODY, $entryId) === 'body text', 'the ordinary field did not store');

        // Attachment: grouped = field group pivot only; direct = channel pivot only
        $channelId = (int) (ee()->db->select('channel_id')->where('channel_name', CpsRefFixture::CHANNEL)->get('channels')->row()->channel_id ?? 0);
        $viaGroup = ee()->db->where('field_id', $fieldId)->count_all_results('channel_field_groups_fields');
        $viaChannel = ee()->db->where(['field_id' => $directId, 'channel_id' => $channelId])->count_all_results('channels_channel_fields');
        CpsRefFixture::check($problems, $viaGroup === 1, 'grouped heading should be in one field group');
        CpsRefFixture::check($problems, $viaChannel === 1, 'direct heading should be attached to the channel');
        CpsRefFixture::check($problems, ee()->db->where('field_id', $directId)->count_all_results('channel_field_groups_fields') === 0, 'direct heading should be in no field group');
        CpsRefFixture::check($problems, ee()->db->where('field_id', $fieldId)->count_all_results('channels_channel_fields') === 0, 'grouped heading should not be attached directly');
        // Both reach the entry as custom fields
        $entry = ee('Model')->get('ChannelEntry', $entryId)->first();
        $names = array_map(function ($f) { return $f->getShortName(); }, $entry->getCustomFields());
        CpsRefFixture::check($problems, in_array(self::GROUPED, $names, true) && in_array(self::DIRECT, $names, true), 'both headings should be custom fields of the entry: ' . json_encode($names));

        // Layout places the headings by field_id_N and round-trips
        $layout = ee('Model')->get('ChannelLayout')->filter('layout_name', self::LAYOUT)->first();
        CpsRefFixture::check($problems, (bool) $layout, 'layout not found');
        $placed = $layout ? array_column($layout->field_layout[0]['fields'], 'field') : [];
        CpsRefFixture::check($problems, $placed === ['title', 'field_id_' . $fieldId, 'field_id_' . CpsRefFixture::fieldId(self::BODY), 'field_id_' . $directId], 'layout order did not round-trip: ' . json_encode($placed));

        // Content types: channel only, so no Grid column and no Fluid child (accepts_content_type())
        ee()->api_channel_fields->include_handler('publish_sections');
        $fieldtype = new \Publish_sections_ft();
        foreach (['channel' => true, 'grid' => false, 'fluid_field' => false, 'blocks/1' => false, 'low_variables' => false] as $name => $want) {
            CpsRefFixture::check($problems, $fieldtype->accepts_content_type($name) === $want, "accepts_content_type('$name') should be " . var_export($want, true));
        }

        $result = $entry->validate();
        CpsRefFixture::check($problems, $result->isValid(), 'entry did not validate: ' . json_encode($result->getAllErrors()));

        return $problems;
    }
}
