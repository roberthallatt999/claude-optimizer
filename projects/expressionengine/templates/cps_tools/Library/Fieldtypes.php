<?php

namespace CPS\Tools\Library;

/**
 * Small helpers shared by the checks that call fieldtype code (settings contract, smoke test).
 */
class Fieldtypes
{
    /**
     * Add-on directory for a fieldtype, so its helper libraries and models can load.
     *
     * @param string $type
     * @return string|null
     */
    public static function packagePath(string $type): ?string
    {
        foreach ([PATH_ADDONS, PATH_THIRD] as $base) {
            if (is_dir($base . $type)) {
                return $base . $type . '/';
            }
        }
        return null;
    }

    /**
     * Make sure the channel fields API and its fieldtype list are loaded.
     *
     * @return void
     */
    public static function boot(): void
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();
    }
}
