<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: a well-shaped relationship field whose channels setting names
 * channel id "999999". down() removes the field by name.
 */
class CpstoolsFxBadRelationshipTarget extends Migration
{
    const REL_FIELD = 'cpstools_fx_badtarget';

    public function up()
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();

        $field = ee('Model')->make('ChannelField');
        $field->site_id = (int) ee()->config->item('site_id');
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
            'channels' => ['999999'], 'expired' => 0, 'future' => 0,
            'categories' => [], 'authors' => [], 'statuses' => [], 'limit' => 100,
            'order_field' => 'title', 'order_dir' => 'asc', 'allow_multiple' => true,
            'display_entry_id' => false, 'display_status' => false, 'deferred_loading' => false,
            'rel_min' => 0, 'rel_max' => '',
        ];
        $field->save();
    }

    public function down()
    {
        $field = ee('Model')->get('ChannelField')->filter('field_name', self::REL_FIELD)->first();
        if ($field) {
            $field->delete();
        }
    }
}
