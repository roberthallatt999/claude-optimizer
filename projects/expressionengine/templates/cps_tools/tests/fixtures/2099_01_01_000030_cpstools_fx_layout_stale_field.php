<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: a publish layout listing field B after B was detached from the
 * channel, with newly attached field C never placed. Everything is resolved by name in down().
 */
class CpstoolsFxLayoutStaleField extends Migration
{
    const CHANNEL = 'cpstools_fixture';
    const GROUP = 'cpstools_fixture';
    const LAYOUT = 'cpstools_fx_layout';
    const FIELDS = ['cpstools_fx_a', 'cpstools_fx_b', 'cpstools_fx_c'];

    public function up()
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();

        $siteId = (int) ee()->config->item('site_id');

        $group = ee('Model')->make('ChannelFieldGroup');
        $group->site_id = $siteId;
        $group->group_name = self::GROUP;
        // Newer EE schemas require a short_name on field groups; older ones have no such column.
        if (ee()->db->field_exists('short_name', 'field_groups')) {
            $group->short_name = self::GROUP;
        }
        $group->save();

        $channel = ee('Model')->make('Channel');
        $channel->site_id = $siteId;
        $channel->channel_name = self::CHANNEL;
        $channel->channel_title = 'CPS Tools fixture';
        $channel->channel_url = '';
        $channel->channel_lang = 'en';
        $channel->deft_status = 'open';
        $channel->save();
        $channel->FieldGroups = $group;
        $channel->save();

        $ids = [];
        foreach (self::FIELDS as $order => $name) {
            $field = ee('Model')->make('ChannelField');
            $field->site_id = $siteId;
            $field->field_name = $name;
            $field->field_label = $name;
            $field->field_type = 'text';
            $field->field_instructions = '';
            $field->field_required = 'n';
            $field->field_search = 'n';
            $field->field_is_hidden = 'n';
            $field->field_order = $order + 1;
            $field->legacy_field_data = 'n';
            $field->field_settings = [
                'field_fmt' => 'none', 'field_content_type' => 'all', 'field_text_direction' => 'ltr',
                'field_maxl' => 256, 'field_show_fmt' => 'n',
            ];
            // Fields A and B start attached; C is attached after the layout exists.
            if ($name !== 'cpstools_fx_c') {
                $field->ChannelFieldGroups = $group;
            }
            $field->save();
            $ids[$name] = (int) $field->field_id;
        }

        $tabFields = [];
        foreach (['title', 'field_id_' . $ids['cpstools_fx_a'], 'field_id_' . $ids['cpstools_fx_b']] as $item) {
            $tabFields[] = ['field' => $item, 'visible' => true, 'collapsed' => false];
        }
        ee()->db->insert('layout_publish', [
            'site_id' => $siteId,
            'channel_id' => $channel->channel_id,
            'layout_name' => self::LAYOUT,
            'field_layout' => serialize([
                ['id' => 'publish', 'name' => 'publish', 'visible' => true, 'fields' => $tabFields],
            ]),
        ]);

        // The defect: B is detached (layout still lists it) and C is attached but not placed.
        ee()->db->where('field_id', $ids['cpstools_fx_b'])->where('group_id', $group->group_id)
            ->delete('channel_field_groups_fields');
        ee()->db->insert('channel_field_groups_fields', [
            'field_id' => $ids['cpstools_fx_c'],
            'group_id' => $group->group_id,
        ]);
    }

    public function down()
    {
        $channel = ee('Model')->get('Channel')->filter('channel_name', self::CHANNEL)->first();
        if ($channel) {
            ee()->db->where('channel_id', $channel->channel_id)->delete('layout_publish');
            $channel->delete();
        }

        foreach (self::FIELDS as $name) {
            $field = ee('Model')->get('ChannelField')->filter('field_name', $name)->first();
            if ($field) {
                $field->delete();
            }
        }

        $group = ee('Model')->get('ChannelFieldGroup')->filter('group_name', self::GROUP)->first();
        if ($group) {
            $group->delete();
        }
    }
}
