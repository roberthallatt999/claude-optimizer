<?php

namespace CPS\Tools\Library\Checks;

use CPS\Tools\Library\Report;

/**
 * Compares each channel field's and Grid column's stored settings against what the fieldtype
 * itself would save (save_settings([]) / grid_save_settings([])), plus a small per-type rule table.
 *
 * Catches settings written by hand or by migrations that skipped keys the fieldtype requires.
 */
class SettingsContract
{
    private const CHECK = 'settings_contract';

    /**
     * @var array<string, array|null> contract cache per fieldtype and kind
     */
    private array $contracts = [];

    /**
     * @param Report $report
     * @return void
     */
    public function run(Report $report): void
    {
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();

        $channels = $this->channelNames();

        $fields = ee()->db->select('field_id, field_name, field_type, field_settings')
            ->get('channel_fields')
            ->result_array();

        foreach ($fields as $field) {
            $stored = $this->decodeFieldSettings((string) $field['field_settings']);
            $this->checkSettings($report, $field['field_name'], $field['field_type'], $stored, false, $channels);
        }

        if (!ee()->db->table_exists('grid_columns')) {
            return;
        }

        $columns = ee()->db->select('g.col_id, g.col_name, g.col_type, g.col_settings, f.field_name')
            ->from('grid_columns g')
            ->join('channel_fields f', 'f.field_id = g.field_id', 'left')
            ->get()
            ->result_array();

        foreach ($columns as $col) {
            $subject = ($col['field_name'] ?? 'orphan') . '.' . $col['col_name'];
            $stored = json_decode((string) $col['col_settings'], true);
            if (!is_array($stored)) {
                $report->add(self::CHECK, $subject, 'fail', 'column settings are not valid JSON', $col['col_type']);
                continue;
            }
            $this->checkSettings($report, $subject, $col['col_type'], $stored, true, $channels);
        }
    }

    /**
     * @param Report $report
     * @param string $subject
     * @param string $type
     * @param array $stored
     * @param bool $isColumn
     * @param array<int, string> $channels channel_id => name
     * @return void
     */
    private function checkSettings(
        Report $report,
        string $subject,
        string $type,
        array $stored,
        bool $isColumn,
        array $channels
    ): void {
        $problems = [];

        $contract = $this->contract($type, $isColumn);
        if ($contract === null) {
            $report->add(self::CHECK, $subject, 'warn', 'contract unavailable', $type);
        } else {
            foreach ($contract as $key => $default) {
                if (!array_key_exists($key, $stored)) {
                    $problems[] = 'missing setting ' . $key;
                } elseif (is_array($default) && !is_array($stored[$key])) {
                    $problems[] = 'setting ' . $key . ' should be an array';
                }
            }
        }

        if ($type === 'relationship') {
            $problems = array_merge($problems, $this->relationshipProblems($stored, $channels));
        }

        if ($problems === []) {
            $report->add(self::CHECK, $subject, 'pass', 'settings match contract', $type);
            return;
        }

        foreach ($problems as $problem) {
            $report->add(self::CHECK, $subject, 'fail', $problem, $type);
        }
    }

    /**
     * Relationship rules: channels is an array of numeric strings naming existing channels (or empty
     * for any); order_field is title or entry_date.
     *
     * @param array $stored
     * @param array<int, string> $channels
     * @return array<int, string>
     */
    private function relationshipProblems(array $stored, array $channels): array
    {
        $problems = [];

        if (isset($stored['channels'])) {
            if (!is_array($stored['channels'])) {
                $problems[] = 'channels should be an array';
            } else {
                foreach ($stored['channels'] as $id) {
                    if (!is_string($id) || !ctype_digit($id)) {
                        $problems[] = 'channels must hold numeric strings (type mismatch: ' . gettype($id) . ')';
                        break;
                    }
                }
                foreach ($stored['channels'] as $id) {
                    if ((is_string($id) || is_int($id)) && !isset($channels[(int) $id])) {
                        $problems[] = 'channels names nonexistent channel id ' . $id;
                    }
                }
            }
        }

        if (isset($stored['order_field']) && !in_array($stored['order_field'], ['title', 'entry_date'], true)) {
            $problems[] = 'invalid order_field value ' . var_export($stored['order_field'], true);
        }

        return $problems;
    }

    /**
     * Keys (with default values) the fieldtype saves for empty input, or null if unavailable.
     *
     * @param string $type
     * @param bool $isColumn
     * @return array|null
     */
    private function contract(string $type, bool $isColumn): ?array
    {
        $cacheKey = $type . ($isColumn ? ':col' : ':field');
        if (array_key_exists($cacheKey, $this->contracts)) {
            return $this->contracts[$cacheKey];
        }

        $contract = null;
        $packagePath = $this->packagePath($type);
        if ($packagePath !== null) {
            // Core settings forms load helper libraries (e.g. Relationships_ft_cp) from the add-on.
            ee()->load->add_package_path($packagePath);
        }
        // Calling a settings method with no input makes some core types read undefined keys; the
        // notices are expected and not a finding, so swallow them for the duration of the call.
        set_error_handler(static fn (): bool => true);
        try {
            // Core settings methods can read POSTed values; give them an empty, quiet request.
            $_POST = [];
            $handler = ee()->api_channel_fields->setup_handler($type, true);
            if (is_object($handler)) {
                // Some save_settings() implementations write (e.g. Toggle queues a re-index prompt and
                // updates site prefs when field_id is null); a non-null id keeps this check read-only.
                $handler->field_id = 0;
                $methods = $isColumn ? ['grid_save_settings', 'save_settings'] : ['save_settings'];
                foreach ($methods as $method) {
                    if (!method_exists($handler, $method)) {
                        continue;
                    }
                    $result = $handler->$method([]);
                    if (is_array($result)) {
                        $contract = $result;
                        break;
                    }
                }
            }
        } catch (\Throwable $e) {
            $contract = null;
        } finally {
            restore_error_handler();
        }
        if ($packagePath !== null) {
            ee()->load->remove_package_path($packagePath);
        }

        $this->contracts[$cacheKey] = $contract;
        return $contract;
    }

    /**
     * @param string $type
     * @return string|null
     */
    private function packagePath(string $type): ?string
    {
        foreach ([PATH_ADDONS, PATH_THIRD] as $base) {
            if (is_dir($base . $type)) {
                return $base . $type . '/';
            }
        }
        return null;
    }

    /**
     * @param string $raw base64-encoded serialized settings
     * @return array
     */
    private function decodeFieldSettings(string $raw): array
    {
        $decoded = base64_decode($raw, true);
        if ($decoded === false) {
            return [];
        }
        $settings = @unserialize($decoded, ['allowed_classes' => false]);
        return is_array($settings) ? $settings : [];
    }

    /**
     * @return array<int, string>
     */
    private function channelNames(): array
    {
        $names = [];
        foreach (ee()->db->select('channel_id, channel_name')->get('channels')->result_array() as $row) {
            $names[(int) $row['channel_id']] = $row['channel_name'];
        }
        return $names;
    }
}
