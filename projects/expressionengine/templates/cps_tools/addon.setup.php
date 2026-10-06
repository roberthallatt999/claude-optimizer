<?php

return [
    'author'      => 'Canadian Paediatric Society',
    'author_url'  => 'https://cps.ca/',
    'name'        => 'CPS Tools',
    'description' => 'CLI tools: logs, migration status/verify, schema check (read-only) and cache clean.',
    'version'     => '2.2.2',
    'namespace'   => 'CPS\Tools',
    'commands'    => [
        'cps:cache-clean' => CPS\Tools\Commands\CommandCacheClean::class,
        'cps:logs' => CPS\Tools\Commands\CommandLogs::class,
        'cps:migrate-status' => CPS\Tools\Commands\CommandMigrateStatus::class,
        'cps:migrate-verify' => CPS\Tools\Commands\CommandMigrateVerify::class,
        'cps:schema-check' => CPS\Tools\Commands\CommandSchemaCheck::class,
    ],
];
