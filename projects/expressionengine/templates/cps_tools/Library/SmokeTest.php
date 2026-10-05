<?php

namespace CPS\Tools\Library;

/**
 * Calls each field's and Grid column's validate()/display_field() with sample values and reports any
 * thrown exception: that is what would break a publish screen or save (e.g. in_array() on a missing
 * setting). A returned validation message is fine.
 *
 * DDEV only: fieldtype code may touch caches or load models. Runs inside a transaction that is rolled
 * back, and compares row counts before/after (DDL commits implicitly, so the transaction alone is not
 * proof). Never calls save/post_save/delete.
 */
class SmokeTest
{
    private const CHECK = 'smoke';

    /**
     * Tables whose row counts must not change. exp_developer_log is excluded on purpose: validate() and
     * display_field() may legitimately log deprecation notices.
     */
    private const GUARDED_TABLES = [
        'channel_titles',
        'channel_data',
        'relationships',
        'grid_columns',
        'channel_fields',
        'migrations',
    ];

    private const SAMPLES = ['', 'Sample text', 'www.example.ca', '/relative/path', '999999999', 'not-an-option'];

    /**
     * Container types validate whole structured payloads; arbitrary strings are not meaningful input,
     * and their columns/children are exercised individually.
     */
    private const CONTAINER_TYPES = ['grid', 'file_grid', 'fluid_field', 'relationship'];

    /**
     * @param Report $report
     * @return void
     */
    public function run(Report $report): void
    {
        if (getenv('IS_DDEV_PROJECT') !== 'true') {
            $report->add(self::CHECK, '*', 'warn', 'smoke skipped: not DDEV');
            return;
        }

        Fieldtypes::boot();
        $this->loadPublishContext();
        $before = $this->rowCounts();

        ee()->db->trans_begin();
        $errors = [];
        set_error_handler(static fn (): bool => true);
        try {
            $errors = $this->exerciseFields($report);
            $errors = array_merge($errors, $this->exerciseColumns($report));
        } finally {
            restore_error_handler();
            ee()->db->trans_rollback();
        }

        $after = $this->rowCounts();
        if ($before !== $after) {
            $changed = array_keys(array_diff_assoc($after, $before));
            $report->add(self::CHECK, '*', 'fail', 'smoke test changed data: ' . implode(', ', $changed));
        }
    }

    /**
     * display_field() implementations expect the control panel's libraries (session, javascript; cp is CP-request only),
     * which a CLI request does not load. Load what is available; whatever stays missing is reported as
     * a warning (a limit of this check), not a failure (see isEnvironmentGap()).
     *
     * @return void
     */
    private function loadPublishContext(): void
    {
        foreach (['session', 'javascript'] as $library) {
            try {
                ee()->load->library($library);
            } catch (\Throwable $e) {
                continue;
            }
        }
    }

    /**
     * @return array<string, int>
     */
    private function rowCounts(): array
    {
        $counts = [];
        foreach (self::GUARDED_TABLES as $table) {
            if (!ee()->db->table_exists($table)) {
                continue;
            }
            $counts[$table] = (int) ee()->db->count_all($table);
        }
        return $counts;
    }

    /**
     * @param Report $report
     * @return array
     */
    private function exerciseFields(Report $report): array
    {
        $fields = ee()->db->select('field_id, field_name, field_type, field_settings')
            ->get('channel_fields')
            ->result_array();

        foreach ($fields as $field) {
            $subject = $field['field_name'];
            $type = $field['field_type'];
            $settings = $this->decode((string) $field['field_settings']);
            $settings['field_type'] = $type;
            $settings['field_name'] = $field['field_name'];
            $settings['field_id'] = (int) $field['field_id'];

            $messages = [];
            try {
                ee()->api_channel_fields->set_settings((int) $field['field_id'], $settings);
                $handler = ee()->api_channel_fields->setup_handler((int) $field['field_id'], true);
            } catch (\Throwable $e) {
                $messages[$this->describe($e)] = true;
                $handler = false;
            }

            if (is_object($handler)) {
                $values = in_array($type, self::CONTAINER_TYPES, true) ? [''] : self::SAMPLES;
                foreach ($values as $value) {
                    $this->attempt($messages, 'validate', fn () => ee()->api_channel_fields->apply('validate', [$value]));
                }
                $this->attempt($messages, 'display_field', function () {
                    ob_start();
                    try {
                        return ee()->api_channel_fields->apply('display_field', ['']);
                    } finally {
                        ob_end_clean();
                    }
                });
            }
            $this->record($report, $subject, $type, $messages);
        }
        return [];
    }

    /**
     * Mirrors Grid_parser::instantiate_fieldtype() and Grid_parser::call().
     *
     * @param Report $report
     * @return array
     */
    private function exerciseColumns(Report $report): array
    {
        if (!ee()->db->table_exists('grid_columns')) {
            return [];
        }

        $columns = ee()->db->select('g.*, f.field_name')
            ->from('grid_columns g')
            ->join('channel_fields f', 'f.field_id = g.field_id', 'left')
            ->get()
            ->result_array();

        foreach ($columns as $col) {
            $subject = ($col['field_name'] ?? 'orphan') . '.' . $col['col_name'];
            $type = $col['col_type'];
            $colSettings = json_decode((string) $col['col_settings'], true);
            $messages = [];

            if (!is_array($colSettings)) {
                $this->record($report, $subject, $type, []);
                continue;
            }

            try {
                $handler = ee()->api_channel_fields->setup_handler($type, true);
                if (is_object($handler)) {
                    $handler->_init([
                        'field_id' => $col['col_id'],
                        'field_name' => 'col_id_' . $col['col_id'],
                        'content_id' => 0,
                        'content_type' => 'grid',
                    ]);
                    $handler->settings = array_merge($colSettings, [
                        'field_label' => $col['col_label'],
                        'field_required' => $col['col_required'],
                        'col_id' => $col['col_id'],
                        'col_name' => $col['col_name'],
                        'col_required' => $col['col_required'],
                        'entry_id' => 0,
                        'grid_field_id' => $col['field_id'],
                        'grid_row_name' => null,
                        'grid_content_type' => 'channel',
                        'fluid_field_data_id' => 0,
                        'in_modal_context' => false,
                    ]);
                }
            } catch (\Throwable $e) {
                $messages[$this->describe($e)] = true;
                $handler = false;
            }

            if (is_object($handler)) {
                $api = ee()->api_channel_fields;
                $validate = $api->check_method_exists('grid_validate') ? 'grid_validate' : 'validate';
                $display = $api->check_method_exists('grid_display_field') ? 'grid_display_field' : 'display_field';
                $values = in_array($type, self::CONTAINER_TYPES, true) ? [''] : self::SAMPLES;
                foreach ($values as $value) {
                    $this->attempt($messages, $validate, fn () => $api->apply($validate, [$value]));
                }
                $this->attempt($messages, $display, function () use ($api, $display) {
                    ob_start();
                    try {
                        return $api->apply($display, ['']);
                    } finally {
                        ob_end_clean();
                    }
                });
            }
            $this->record($report, $subject, $type, $messages);
        }
        return [];
    }

    /**
     * @param array<string, bool> $messages
     * @param string $method
     * @param callable $call
     * @return void
     */
    private function attempt(array &$messages, string $method, callable $call): void
    {
        try {
            $call();
        } catch (\Throwable $e) {
            $messages[$method . '() threw ' . $this->describe($e)] = true;
        }
    }

    /**
     * @param \Throwable $e
     * @return string
     */
    private function describe(\Throwable $e): string
    {
        return get_class($e) . ': ' . $e->getMessage() . ' (' . basename($e->getFile()) . ':' . $e->getLine() . ')';
    }

    /**
     * @param Report $report
     * @param string $subject
     * @param string $type
     * @param array<string, bool> $messages
     * @return void
     */
    private function record(Report $report, string $subject, string $type, array $messages): void
    {
        if ($messages === []) {
            $report->add(self::CHECK, $subject, 'pass', 'validate/display ran without exceptions', $type);
            return;
        }
        foreach (array_keys($messages) as $message) {
            if ($this->isEnvironmentGap($message)) {
                $report->add(self::CHECK, $subject, 'warn', 'not exercised (CLI context): ' . $message, $type);
                continue;
            }
            $report->add(self::CHECK, $subject, 'fail', $message, $type);
        }
    }

    /**
     * A missing EE facade property means the CLI request lacks a control-panel service, not that the
     * field is broken; such cases cannot be judged here.
     *
     * @param string $message
     * @return bool
     */
    private function isEnvironmentGap(string $message): bool
    {
        return str_contains($message, 'InvalidArgumentException: No such property:')
            && str_contains($message, 'Facade.php');
    }

    /**
     * @param string $raw base64-encoded serialized settings
     * @return array
     */
    private function decode(string $raw): array
    {
        $decoded = base64_decode($raw, true);
        if ($decoded === false) {
            return [];
        }
        $settings = @unserialize($decoded, ['allowed_classes' => false]);
        return is_array($settings) ? $settings : [];
    }
}
