<?php

namespace CPS\Tools\Commands;

use CPS\Tools\Library\Report;
use ExpressionEngine\Cli\Cli;

/**
 * Read-only schema health check with baseline/compare.
 *
 * Exit codes: 0 no (new) failures, 1 (new) failures, 2 could not run.
 */
class CommandSchemaCheck extends Cli
{
    /**
     * @var string
     */
    public $name = 'CPS Schema Check';

    /**
     * @var string
     */
    public $signature = 'cps:schema-check';

    /**
     * @var string
     */
    public $usage = 'php eecli.php cps:schema-check [--json] [--no-smoke] [--baseline=FILE] [--compare=FILE]';

    /**
     * @var string
     */
    public $description = 'Check channel field/Grid settings and storage against fieldtype contracts (read-only).';

    /**
     * @var string
     */
    public $summary = 'Check EE schema health (read-only)';

    /**
     * @var array
     */
    public $commandOptions = [
        'json' => 'cps_tools_option_json',
        'no-smoke' => 'cps_tools_option_no_smoke',
        'baseline:' => 'cps_tools_option_baseline',
        'compare:' => 'cps_tools_option_compare',
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

        try {
            $report = $this->runChecks();
            $baselinePath = (string) $this->option('--baseline', '');
            $comparePath = (string) $this->option('--compare', '');
            $json = (bool) $this->option('--json', false);

            if ($baselinePath !== '') {
                $report->writeBaseline($baselinePath);
            }

            $newFailures = null;
            if ($comparePath !== '') {
                $newFailures = $report->compare(Report::readBaseline($comparePath));
            }
        } catch (\Throwable $e) {
            $this->error('schema-check could not run: ' . $e->getMessage());
            exit(2);
        }

        $failing = $newFailures ?? array_filter($report->results(), fn ($r) => $r['status'] === 'fail');

        if ($json) {
            $out = ['results' => $report->results(), 'summary' => $report->summary()];
            if ($newFailures !== null) {
                $out['new_failures'] = count($newFailures);
                $out['new_failure_results'] = $newFailures;
            }
            // Not $this->write(): it strips backslashes, which corrupts JSON escapes.
            fwrite(STDOUT, json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
        } else {
            foreach ($report->results() as $result) {
                if ($result['status'] === 'pass') {
                    continue;
                }
                $this->write(sprintf(
                    '%s [%s] %s: %s',
                    strtoupper($result['status']),
                    $result['check'],
                    $result['subject'],
                    $result['message']
                ));
            }
            $summary = $report->summary();
            $this->write(sprintf('%d pass, %d warn, %d fail', $summary['pass'], $summary['warn'], $summary['fail']));
            if ($newFailures !== null) {
                $this->write('New failures vs baseline: ' . count($newFailures));
            }
        }

        if (count($failing) > 0) {
            exit(1);
        }
    }

    /**
     * @return Report
     */
    private function runChecks(): Report
    {
        $report = new Report();
        $notices = [];
        // Site and third-party code can raise deprecations/notices (or echo) mid-check; EE's CLI handler
        // would print them ahead of the JSON. Collect them quietly and surface them as warnings instead.
        $previous = set_error_handler(static function (int $no, string $msg, string $file, int $line) use (&$notices): bool {
            $quiet = E_DEPRECATED | E_USER_DEPRECATED | E_NOTICE | E_USER_NOTICE | E_WARNING | E_USER_WARNING | E_STRICT;
            if (($no & $quiet) !== 0) {
                $notices[$msg . '|' . $file . '|' . $line] = [$msg, $file, $line];
                return true;
            }
            return false;
        });
        ob_start();
        try {
            $this->runAll($report);
        } finally {
            ob_end_clean();
            restore_error_handler();
        }
        unset($previous);
        foreach ($notices as [$msg, $file, $line]) {
            $report->add('php_notices', basename($file) . ':' . $line, 'warn', substr($msg, 0, 160), 'php');
        }
        return $report;
    }

    /**
     * @param Report $report
     * @return void
     */
    private function runAll(Report $report): void
    {
        $checks = [
            \CPS\Tools\Library\Checks\SettingsContract::class,
            \CPS\Tools\Library\Checks\Storage::class,
            \CPS\Tools\Library\Checks\Orphans::class,
            \CPS\Tools\Library\Checks\Layouts::class,
            \CPS\Tools\Library\Checks\References::class,
        ];
        foreach ($checks as $class) {
            (new $class())->run($report);
        }
        if (!(bool) $this->option('--no-smoke', false)) {
            (new \CPS\Tools\Library\SmokeTest())->run($report);
        }
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
