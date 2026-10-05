<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: reproduces the Events URL defect (spec section 1).
 * Creates channel cpstools_fixture with a URL field and a Grid field holding a url column, then strips
 * allowed_url_schemes / url_scheme_placeholder from both. down() removes everything, resolved by name.
 */
class CpstoolsFxUrlMissingSchemes extends Migration
{
    const CHANNEL = 'cpstools_fixture';
    const GROUP = 'cpstools_fixture';
    const URL_FIELD = 'cpstools_fx_url';
    const GRID_FIELD = 'cpstools_fx_grid';

    public function up()
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();
        ee()->load->model('grid_model');

        $siteId = (int) ee()->config->item('site_id');

        $group = ee('Model')->make('ChannelFieldGroup');
        $group->site_id = $siteId;
        $group->group_name = self::GROUP;
        // Newer EE schemas require a short_name on field groups; older ones have no such column.
        if (ee()->db->field_exists('short_name', 'field_groups')) {
            $group->short_name = self::GROUP;
        }
        $group->save();

        $urlSettings = [
            'field_fmt' => 'none', 'field_required' => 'n',
            'allowed_url_schemes' => ['http://', 'https://'], 'url_scheme_placeholder' => 'https://',
        ];
        $url = $this->makeField($siteId, $group, self::URL_FIELD, 'url', $urlSettings, 1);

        $grid = $this->makeField($siteId, $group, self::GRID_FIELD, 'grid', [
            'grid_min_rows' => 0, 'grid_max_rows' => '', 'allow_reorder' => 'y',
            'vertical_layout' => 'n', 'row_counter' => 'n',
        ], 2);
        ee()->grid_model->create_field($grid->field_id, 'channel');
        ee()->grid_model->save_col_settings([
            'field_id' => $grid->field_id,
            'content_type' => 'channel',
            'col_order' => 0,
            'col_type' => 'url',
            'col_label' => 'Link',
            'col_name' => 'cpstools_fx_link',
            'col_instructions' => '',
            'col_required' => 'n',
            'col_search' => 'n',
            'col_width' => 0,
            'col_settings' => json_encode($urlSettings),
        ], false, 'channel');

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

        // The defect: settings rows written without the keys the URL fieldtype needs.
        $keys = ['allowed_url_schemes', 'url_scheme_placeholder'];
        $stripped = array_diff_key($urlSettings, array_flip($keys));
        ee()->db->where('field_id', $url->field_id)
            ->update('channel_fields', ['field_settings' => base64_encode(serialize($stripped))]);
        ee()->db->where('field_id', $grid->field_id)->where('col_name', 'cpstools_fx_link')
            ->update('grid_columns', ['col_settings' => json_encode($stripped)]);
    }

    public function down()
    {
        $channel = ee('Model')->get('Channel')->filter('channel_name', self::CHANNEL)->first();
        if ($channel) {
            $channel->delete();
        }

        foreach ([self::GRID_FIELD, self::URL_FIELD] as $name) {
            $field = ee('Model')->get('ChannelField')->filter('field_name', $name)->first();
            if ($field) {
                $fieldId = (int) $field->field_id;
                $field->delete();
                ee()->db->where('field_id', $fieldId)->delete('grid_columns');
            }
        }

        $group = ee('Model')->get('ChannelFieldGroup')->filter('group_name', self::GROUP)->first();
        if ($group) {
            $group->delete();
        }
    }

    private function makeField($siteId, $group, $name, $type, array $settings, $order)
    {
        $field = ee('Model')->make('ChannelField');
        $field->site_id = $siteId;
        $field->field_name = $name;
        $field->field_label = $name;
        $field->field_type = $type;
        $field->field_instructions = '';
        $field->field_required = 'n';
        $field->field_search = 'n';
        $field->field_is_hidden = 'n';
        $field->field_order = $order;
        $field->legacy_field_data = 'n';
        $field->field_settings = $settings;
        $field->ChannelFieldGroups = $group;
        $field->save();

        return $field;
    }
}
