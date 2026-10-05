<?php

namespace CPS\Tools\Commands;

use ExpressionEngine\Cli\Cli;

/**
 * Run a migration's optional verify() hook without running the migration itself.
 *
 * Exit codes: 0 pass (or no verify()), 1 verify() reported failures, 2 migration not found.
 */
class CommandMigrateVerify extends Cli
{
    /**
     * @var string
     */
    public $name = 'CPS Migrate Verify';

    /**
     * @var string
     */
    public $signature = 'cps:migrate-verify';

    /**
     * @var string
     */
    public $usage = 'php eecli.php cps:migrate-verify <migration_name>';

    /**
     * @var string
     */
    public $description = 'Run a migration\'s verify() hook, if it has one (read-only).';

    /**
     * @var string
     */
    public $summary = 'Run a migration verify() hook (read-only)';

    /**
     * @var array
     */
    public $commandOptions = [];

    /**
     * Run the command.
     *
     * @return void
     */
    public function handle()
    {
        $name = (string) ($this->arguments[0] ?? '');
        $file = SYSPATH . 'user/database/migrations/' . $name . '.php';
        if ($name === '' || !is_file($file)) {
            $this->error('Migration not found: ' . $name);
            exit(2);
        }

        $model = ee('Model')->make('Migration', ['migration' => $name, 'migration_location' => 'ExpressionEngine']);
        $instance = ee('Migration', $model)->getMigrateInstance();

        if (!method_exists($instance, 'verify')) {
            $this->info('no verify() - nothing to check');
            return;
        }

        $failures = (array) $instance->verify();
        if ($failures === []) {
            $this->info('PASS verify() ' . $name);
            return;
        }

        foreach ($failures as $failure) {
            $this->error('FAIL ' . $failure);
        }
        exit(1);
    }
}
