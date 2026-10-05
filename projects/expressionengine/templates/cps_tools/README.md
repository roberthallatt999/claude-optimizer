# CPS Tools

Read-only CLI access to EE's developer log (`exp_developer_log`) and EE log files
(`system/user/logs/log-*.php`). Nothing is written: no DB writes, rows are not marked viewed,
no files are created. EE connects through its own config, so no DB credentials file is ever named
in a command.

## Usage

```bash
php system/ee/eecli.php cps:logs
php system/ee/eecli.php cps:logs -l 5 --source=devlog
php system/ee/eecli.php cps:logs --since=2h
php system/ee/eecli.php cps:logs --since=2026-09-22 -g migration -l 3
php system/ee/eecli.php cps:logs --deprecated --full
```

The add-on does not need to be installed in the Control Panel; EE loads the command from the
add-on folder.

## Options

| Option | Meaning |
|---|---|
| `--limit`, `-l` | Entries to show, 1-200 (default 20) |
| `--since`, `-s` | `30m`, `2h`, `7d`, `YYYY-MM-DD` or `"YYYY-MM-DD HH:MM"`; invalid exits non-zero |
| `--source` | `devlog`, `files` or `all` (default) |
| `--grep`, `-g` | Case-insensitive substring filter on the message |
| `--full` | Do not truncate messages (default truncates at 300 characters) |
| `--deprecated` | Include deprecation notices (excluded by default) |

Timestamps are shown with PHP `date()` in the server's configured timezone, the same way EE's
own log files are stamped. The developer-log `--grep` matches the raw description (before HTML is
stripped). File logs: only the 7 most recent files are read, and the match total covers those files.

## Limitations

- EE's `show_exception()` (`system/ee/legacy/core/Exceptions.php:227`) only writes SQL
  (SQLSTATE) exceptions to the log. Other uncaught exceptions appear only in the HTTP response
  body, so for a CP 500 check the browser Network tab's Response.
- EE file logs only exist when config `log_threshold` is greater than 0.

## Maintenance

Canonical source: claude-config-repo `projects/expressionengine/templates/cps_tools`; install with
`ee-migrate-install.sh`. Bump the version in `addon.setup.php` when changing it.

## cps:schema-check limits

- The settings contract and the smoke test call fieldtype code, so they run only in DDEV
  (local gate and rehearsals on a target copy). On servers each reports one `warn` "skipped: not DDEV".
- The smoke test runs from the CLI, not a Control Panel request. Field behaviour that needs the CP
  (e.g. `ee()->cp`) cannot be exercised; such errors are reported as `warn`, not `fail`.
- Severity: `fail` means the field would break a publish screen, a save or a migration. Leftovers
  from deleting things (orphaned rows, pivot rows for deleted channels, relationship targets that no
  longer exist) are `warn`. Gate migrations with `--compare` against a baseline: no *new* failures.
