<?php

use ExpressionEngine\Service\Migration\Migration;

/**
 * Test fixture for cps_tools schema-check: a channel whose cat_group lists a category group that does not
 * exist. down() removes the channel by name.
 */
class CpstoolsFxMissingCatGroup extends Migration
{
    const CHANNEL = 'cpstools_fixture';

    public function up()
    {
        $channel = ee('Model')->make('Channel');
        $channel->site_id = (int) ee()->config->item('site_id');
        $channel->channel_name = self::CHANNEL;
        $channel->channel_title = 'CPS Tools fixture';
        $channel->channel_url = '';
        $channel->channel_lang = 'en';
        $channel->deft_status = 'open';
        $channel->save();

        // The defect: a category group id with no category group behind it.
        ee()->db->where('channel_id', $channel->channel_id)->update('channels', ['cat_group' => '999999']);
    }

    public function down()
    {
        $channel = ee('Model')->get('Channel')->filter('channel_name', self::CHANNEL)->first();
        if ($channel) {
            $channel->delete();
        }
    }
}
