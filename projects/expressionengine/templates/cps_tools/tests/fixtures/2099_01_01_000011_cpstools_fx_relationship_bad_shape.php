<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: reproduces the relationship settings-shape defect (spec section 1).
 * Creates channel cpstools_fixture with a relationship field, then rewrites channels to ints and
 * order_field to a nonexistent column. down() removes everything, resolved by name.
 */
class CpstoolsFxRelationshipBadShape extends Migration
{
    const CHANNEL = 'cpstools_fixture';
    const GROUP = 'cpstools_fixture';
    const REL_FIELD = 'cpstools_fx_rel';

    public function up()
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();

        $siteId = (int) ee()->config->item('site_id');

        $group = ee('Model')->make('ChannelFieldGroup');
        $group->site_id = $siteId;
        $group->group_name = self::GROUP;
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

        $field = ee('Model')->make('ChannelField');
        $field->site_id = $siteId;
        $field->field_name = self::REL_FIELD;
        $field->field_label = self::REL_FIELD;
        $field->field_type = 'relationship';
        $field->field_instructions = '';
        $field->field_required = 'n';
        $field->field_search = 'n';
        $field->field_is_hidden = 'n';
        $field->field_order = 1;
        $field->legacy_field_data = 'n';
        $field->field_settings = [
            'channels' => [(string) $channel->channel_id], 'expired' => 0, 'future' => 0,
            'categories' => [], 'authors' => [], 'statuses' => [], 'limit' => 100,
            'order_field' => 'title', 'order_dir' => 'asc', 'allow_multiple' => true,
            'display_entry_id' => false, 'display_status' => false, 'deferred_loading' => false,
            'rel_min' => 0, 'rel_max' => '',
        ];
        $field->ChannelFieldGroups = $group;
        $field->save();

        // The defect: channels as ints, order_field naming no column.
        $broken = $field->field_settings;
        $broken['channels'] = [(int) $channel->channel_id];
        $broken['order_field'] = 'nonexistent';
        ee()->db->where('field_id', $field->field_id)
            ->update('channel_fields', ['field_settings' => base64_encode(serialize($broken))]);
    }

    public function down()
    {
        $channel = ee('Model')->get('Channel')->filter('channel_name', self::CHANNEL)->first();
        if ($channel) {
            $channel->delete();
        }

        $field = ee('Model')->get('ChannelField')->filter('field_name', self::REL_FIELD)->first();
        if ($field) {
            $field->delete();
        }

        $group = ee('Model')->get('ChannelFieldGroup')->filter('group_name', self::GROUP)->first();
        if ($group) {
            $group->delete();
        }
    }
}
