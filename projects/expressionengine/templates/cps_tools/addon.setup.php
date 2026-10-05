<?php

return [
    'author'      => 'Canadian Paediatric Society',
    'author_url'  => 'https://cps.ca/',
    'name'        => 'CPS Tools',
    'description' => 'Read-only CLI tools: logs, migration status/verify, schema check.',
    'version'     => '2.0.0',
    'namespace'   => 'CPS\Tools',
    'commands'    => [
        'cps:logs' => CPS\Tools\Commands\CommandLogs::class,
        // cps:migrate-status, cps:migrate-verify, cps:schema-check are registered by later tasks,
        // once their classes exist (EE fatals on `eecli list` if a registered class is missing).
    ],
];
