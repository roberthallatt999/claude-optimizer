<?php

namespace CPS\Tools\Commands;

use ExpressionEngine\Cli\Cli;

/**
 * Read-only viewer for the EE developer log and EE log files.
 *
 * Never writes: no DB writes, no "viewed" flags, no file writes.
 */
class CommandLogs extends Cli
{
    private const DEFAULT_LIMIT = 20;
    private const MAX_LIMIT = 200;
    private const TRUNCATE_AT = 300;
    private const MAX_FILES = 7;

    /**
     * @var string
     */
    public $name = 'CPS Logs';

    /**
     * @var string
     */
    public $signature = 'cps:logs';

    /**
     * @var string
     */
    public $usage = 'php eecli.php cps:logs [--limit=20] [--since=2h] [--source=all] [--grep=text] [--full] '
        . '[--deprecated]';

    /**
     * Plain strings: the constructor resolves these before the add-on lang file can load.
     *
     * @var string
     */
    public $description = 'Show recent entries from the EE developer log and EE log files (read-only).';

    /**
     * @var string
     */
    public $summary = 'Show recent EE log entries (read-only)';

    /**
     * @var array
     */
    public $commandOptions = [
        'limit,l:' => 'cps_logs_option_limit',
        'since,s:' => 'cps_logs_option_since',
        'source:' => 'cps_logs_option_source',
        'grep,g:' => 'cps_logs_option_grep',
        'full' => 'cps_logs_option_full',
        'deprecated' => 'cps_logs_option_deprecated',
    ];

    /**
     * The CLI only loads its own lang file, so load this add-on's strings
     * before the option descriptions are translated.
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

        $limit = (int) $this->option('--limit', self::DEFAULT_LIMIT);
        $limit = max(1, min(self::MAX_LIMIT, $limit > 0 ? $limit : self::DEFAULT_LIMIT));

        $sinceInput = $this->option('--since', null);
        $since = null;
        if ($sinceInput !== null && $sinceInput !== false && $sinceInput !== '') {
            $since = $this->parseSince((string) $sinceInput);
            if ($since === null) {
                $this->fail('Invalid --since value. Use 30m, 2h, 7d, YYYY-MM-DD or "YYYY-MM-DD HH:MM".');
            }
        }

        $source = strtolower((string) $this->option('--source', 'all'));
        if (!in_array($source, ['devlog', 'files', 'all'], true)) {
            $this->fail('Invalid --source value. Use devlog, files or all.');
        }

        $grep = (string) $this->option('--grep', '');
        $full = (bool) $this->option('--full', false);
        $deprecated = (bool) $this->option('--deprecated', false);

        $entries = [];
        $total = 0;
        $sources = [];
        $filesAvailable = true;

        if ($source !== 'files') {
            [$rows, $count] = $this->readDevLog($limit, $since, $grep, $deprecated);
            $entries = array_merge($entries, $rows);
            $total += $count;
            $sources[] = 'devlog';
        }

        if ($source !== 'devlog') {
            $logDir = SYSPATH . 'user/logs/';
            if (is_dir($logDir)) {
                $rows = $this->readLogFiles($logDir, $since, $grep);
                $entries = array_merge($entries, $rows);
                $total += count($rows);
                $sources[] = 'files';
            } else {
                $filesAvailable = false;
            }
        }

        usort($entries, static fn (array $a, array $b): int => $b['time'] <=> $a['time']);
        $shown = array_slice($entries, 0, $limit);

        $site = ee()->config->item('site_url') ?: ee()->config->item('base_url');
        $sourceLabel = implode(', ', $sources) ?: 'none';
        if (!$filesAvailable) {
            $sourceLabel .= '; file logs unavailable (no user/logs directory)';
        }

        $this->write(sprintf(
            'cps:logs — %s — showing %d of %d matching (sources: %s)',
            $site,
            count($shown),
            $total,
            $sourceLabel
        ));

        if (empty($shown)) {
            $this->write('No log entries matched.');
            return;
        }

        foreach ($shown as $entry) {
            $this->write('');
            $message = $full ? $entry['message'] : $this->truncate($entry['message']);
            $this->write(sprintf(
                '[%s] %s  %s',
                date('Y-m-d H:i:s', $entry['time']),
                $entry['label'],
                $message
            ));
            foreach ($entry['context'] as $line) {
                $this->write('    ' . $line);
            }
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

    /**
     * Convert a --since value to a unix timestamp.
     *
     * @param string $value 30m, 2h, 7d, YYYY-MM-DD or "YYYY-MM-DD HH:MM"
     * @return int|null Null when the value is invalid
     */
    private function parseSince(string $value): ?int
    {
        $value = trim($value);

        if (preg_match('/^(\d+)([mhd])$/i', $value, $matches)) {
            $units = ['m' => 60, 'h' => 3600, 'd' => 86400];
            return time() - ((int) $matches[1] * $units[strtolower($matches[2])]);
        }

        foreach (['!Y-m-d H:i', '!Y-m-d'] as $format) {
            $date = \DateTime::createFromFormat($format, $value);
            $errors = \DateTime::getLastErrors();
            $clean = $errors === false || ($errors['warning_count'] === 0 && $errors['error_count'] === 0);
            if ($date !== false && $clean) {
                return $date->getTimestamp();
            }
        }

        return null;
    }

    /**
     * Read the developer log (exp_developer_log), newest first.
     *
     * @param int $limit
     * @param int|null $since
     * @param string $grep
     * @param bool $includeDeprecated
     * @return array{0: array, 1: int} Entries and the total number of matches
     */
    private function readDevLog(int $limit, ?int $since, string $grep, bool $includeDeprecated): array
    {
        $apply = function () use ($since, $grep, $includeDeprecated): void {
            if ($since !== null) {
                ee()->db->where('timestamp >=', $since);
            }
            if ($grep !== '') {
                ee()->db->like('description', $grep);
            }
            if (!$includeDeprecated) {
                // Static SQL fragment, no user input; this DB layer has no group_start().
                ee()->db->where("(deprecated_since = '' OR deprecated_since IS NULL)", null, false);
            }
        };

        $apply();
        $count = (int) ee()->db->count_all_results('developer_log');

        $apply();
        $rows = ee()->db
            ->order_by('timestamp', 'DESC')
            ->order_by('log_id', 'DESC')
            ->limit($limit)
            ->get('developer_log')
            ->result_array();

        $entries = [];
        foreach ($rows as $row) {
            $context = [];
            if (!empty($row['file'])) {
                $context[] = 'at ' . $row['file'] . ':' . $row['line'];
            }
            if (!empty($row['template_name'])) {
                $context[] = 'template ' . $row['template_group'] . '/' . $row['template_name'];
            }
            if (!empty($row['addon_module'])) {
                $context[] = 'addon ' . $row['addon_module'] . '::' . $row['addon_method'];
            }

            $entries[] = [
                'time' => (int) $row['timestamp'],
                'label' => 'devlog #' . $row['log_id'],
                'message' => $this->cleanText((string) $row['description']),
                'context' => $context,
            ];
        }

        return [$entries, $count];
    }

    /**
     * Read the most recent EE log files.
     *
     * @param string $logDir
     * @param int|null $since
     * @param string $grep
     * @return array
     */
    private function readLogFiles(string $logDir, ?int $since, string $grep): array
    {
        $files = glob($logDir . 'log-*.php') ?: [];
        rsort($files);
        $files = array_slice($files, 0, self::MAX_FILES);

        $entries = [];
        foreach ($files as $file) {
            $handle = @fopen($file, 'rb');
            if ($handle === false) {
                continue;
            }

            while (($line = fgets($handle)) !== false) {
                // Only timestamped lines are entries; this skips the PHP die() guard and blank lines.
                if (!preg_match('/^([A-Z]+)\s+-\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+-->\s?(.*)$/', $line, $m)) {
                    continue;
                }

                $time = strtotime($m[2]);
                if ($time === false || ($since !== null && $time < $since)) {
                    continue;
                }

                $message = $this->cleanText($m[3]);
                if ($grep !== '' && stripos($message, $grep) === false) {
                    continue;
                }

                $entries[] = [
                    'time' => $time,
                    'label' => 'file ' . $m[1] . ' ' . basename($file),
                    'message' => $message,
                    'context' => [],
                ];
            }
            fclose($handle);
        }

        return array_reverse($entries);
    }

    /**
     * Strip HTML, decode entities and collapse whitespace.
     *
     * @param string $text
     * @return string
     */
    private function cleanText(string $text): string
    {
        $text = html_entity_decode(strip_tags($text), ENT_QUOTES | ENT_HTML5, 'UTF-8');

        return trim((string) preg_replace('/\s+/u', ' ', $text));
    }

    /**
     * @param string $text
     * @return string
     */
    private function truncate(string $text): string
    {
        if (mb_strlen($text) <= self::TRUNCATE_AT) {
            return $text;
        }

        return mb_substr($text, 0, self::TRUNCATE_AT) . '…';
    }
}
