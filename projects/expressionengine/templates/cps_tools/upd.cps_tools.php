<?php

if (!defined('BASEPATH')) {
    exit('No direct script access allowed');
}

use ExpressionEngine\Service\Addon\Installer;

/**
 * Minimal installer. The add-on only provides a CLI command, so there is
 * nothing to create, migrate or remove.
 */
class Cps_tools_upd extends Installer
{
    public $has_cp_backend = 'n';
    public $has_publish_fields = 'n';

    /**
     * @return bool
     */
    public function install()
    {
        parent::install();

        return true;
    }

    /**
     * @return bool
     */
    public function uninstall()
    {
        parent::uninstall();

        return true;
    }

    /**
     * @param string $current
     * @return bool
     */
    public function update($current = '')
    {
        return true;
    }
}
