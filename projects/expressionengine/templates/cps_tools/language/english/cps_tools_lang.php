<?php

$lang = [
    'cps_logs_module_name' => 'CPS Logs',
    'cps_logs_module_description' => 'Read-only CLI access to the developer log and EE log files.',

    'command_cps_logs_description' => 'Show recent entries from the EE developer log and EE log files (read-only).',
    'command_cps_logs_summary' => 'Show recent EE log entries (read-only)',

    'cps_logs_option_limit' => 'Number of entries to show (1-200, default 20)',
    'cps_logs_option_since' => 'Only entries since 30m, 2h, 7d, YYYY-MM-DD or "YYYY-MM-DD HH:MM"',
    'cps_logs_option_source' => 'Log source: devlog, files or all (default all)',
    'cps_logs_option_grep' => 'Case-insensitive substring filter on the message',
    'cps_logs_option_full' => 'Do not truncate long messages (default truncates at 300 characters)',
    'cps_logs_option_deprecated' => 'Include deprecation notices (excluded by default)',

    'cps_tools_option_json' => 'Output machine-readable JSON',
    'cps_tools_option_no_smoke' => 'Skip the fieldtype validate/display smoke test',
    'cps_tools_option_baseline' => 'Write the results to this file as a baseline',
    'cps_tools_option_compare' => 'Compare to a baseline file; only new failures count',
];
