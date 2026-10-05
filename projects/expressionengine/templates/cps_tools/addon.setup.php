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
        'cps:migrate-status' => CPS\Tools\Commands\CommandMigrateStatus::class,
        'cps:migrate-verify' => CPS\Tools\Commands\CommandMigrateVerify::class,
        'cps:schema-check' => CPS\Tools\Commands\CommandSchemaCheck::class,
    ],
];
