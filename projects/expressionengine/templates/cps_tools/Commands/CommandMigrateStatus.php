<?php

namespace CPS\Tools\Commands;

use ExpressionEngine\Cli\Cli;

/**
 * Read-only migration status: pending files, applied-but-missing files, row counts, deployed commit.
 */
class CommandMigrateStatus extends Cli
{
    /**
     * @var string
     */
    public $name = 'CPS Migrate Status';

    /**
     * @var string
     */
    public $signature = 'cps:migrate-status';

    /**
     * @var string
     */
    public $usage = 'php eecli.php cps:migrate-status [--json]';

    /**
     * @var string
     */
    public $description = 'Show pending migrations, missing migration files and baseline counts (read-only).';

    /**
     * @var string
     */
    public $summary = 'Show EE migration status (read-only)';

    /**
     * @var array
     */
    public $commandOptions = [
        'json' => 'cps_tools_option_json',
    ];

    /**
     * Load add-on strings before the option descriptions are translated.
     *
     * @return void
     */
    protected function parseCommandOptions()
    {
        $this->loadAddonLang();
        parent::parseCommandOptions();
    }

    /**
     * Run the command.
     *
     * @return void
     */
    public function handle()
    {
        $this->loadAddonLang();
        $migration = ee('Migration');
        $migration->ensureMigrationTableExists();

        // EE's own list, in the order `migrate --core` will run them.
        $pending = array_values($migration->getNewMigrations('ExpressionEngine'));

        $dir = SYSPATH . 'user/database/migrations/';
        $missing = [];
        $applied = ee()->db->select('migration')
            ->where('migration_location', 'ExpressionEngine')
            ->get('migrations')
            ->result_array();
        foreach ($applied as $row) {
            if (!is_file($dir . $row['migration'] . '.php')) {
                $missing[] = $row['migration'];
            }
        }

        $hashFile = $this->releaseRoot() . '.commit_hash';
        $data = [
            'pending' => $pending,
            'missing_files' => $missing,
            'commit' => is_file($hashFile) ? trim((string) file_get_contents($hashFile)) : null,
            'counts' => [
                'tables' => (int) ee()->db->query(
                    'SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = DATABASE()'
                )->row('n'),
                'channel_titles' => (int) ee()->db->count_all('channel_titles'),
                'channel_fields' => (int) ee()->db->count_all('channel_fields'),
            ],
        ];

        if ($this->option('--json', false)) {
            $this->write(json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
            return;
        }

        $this->write(sprintf('Pending migrations: %d', count($pending)));
        foreach ($pending as $name) {
            $this->write('  ' . $name);
        }
        $this->write(sprintf('Applied but file missing: %d', count($missing)));
        foreach ($missing as $name) {
            $this->write('  ' . $name);
        }
        $this->write(sprintf(
            'Counts: %d tables, %d channel_titles, %d channel_fields',
            $data['counts']['tables'],
            $data['counts']['channel_titles'],
            $data['counts']['channel_fields']
        ));
        $this->write('Commit: ' . ($data['commit'] ?? 'unknown'));
    }

    /**
     * Release root = parent of `system/` (or of `ee/system/`).
     *
     * @return string
     */
    private function releaseRoot(): string
    {
        $root = dirname(rtrim(SYSPATH, '/')) . '/';
        return basename(rtrim($root, '/')) === 'ee' ? dirname(rtrim($root, '/')) . '/' : $root;
    }

    /**
     * Load this add-on's language file into EE's language array.
     *
     * @return void
     */
    private function loadAddonLang(): void
    {
        $path = __DIR__ . '/../language/english/cps_tools_lang.php';
        if (!is_file($path)) {
            return;
        }

        $lang = [];
        include $path;
        ee()->lang->language = array_merge(ee()->lang->language, $lang);
    }
}
