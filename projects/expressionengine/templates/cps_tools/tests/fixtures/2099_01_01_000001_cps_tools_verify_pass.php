<?php

use ExpressionEngine\Service\Migration\Migration;

/** Test fixture: never run. Exists only to exercise cps:migrate-* commands. */
class CpsToolsVerifyPass extends Migration
{
    public function up()
    {
    }

    public function down()
    {
    }

    public function verify(): array
    {
        return [];
    }
}
