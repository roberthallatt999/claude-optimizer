<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Used only by run-fixtures.sh after a fixture's up() left rows behind (a failed up() has no migration row,
 * so it cannot be rolled back). up() removes everything cpsref*; down() does nothing.
 */
class CpsrefCleanup extends Migration
{
    public function up()
    {
        CpsRefFixture::removeAll();
    }

    public function down()
    {
    }
}
