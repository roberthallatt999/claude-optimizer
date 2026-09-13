# Updating Projects

Guide to updating existing project configurations.

## Quick Update

Update an existing project with the latest configuration:

```bash
ai-config --refresh --project=/path/to/project
```

This will:
- Auto-detect your stack from `CLAUDE.md`
- Re-scan for technology changes
- Update all configuration files
- Preserve `.claude/` customizations

## Scenarios

### Technology Added to Project

You added Tailwind CSS to your ExpressionEngine project:

```bash
ai-config --refresh --project=/path/to/project
```

**Result:**
- Detects Tailwind CSS
- Adds `tailwind-css.md` rule
- Updates VSCode settings for Tailwind IntelliSense
- Regenerates `CLAUDE.md` with Tailwind context

### VSCode Settings Changed

Repository updated VSCode settings and you want the latest:

```bash
ai-config --refresh --project=/path/to/project
```

**Result:**
- Updates `.vscode/settings.json`
- Preserves your custom settings (if any)

## Update Strategies

### Refresh (Recommended)

```bash
--refresh
```

**Behavior:**
- Re-scans project
- Adds anything new; updates a file only if you haven't edited it
- Keeps your edits and stages new versions in `.claude/ai-config/pending/`
- Backs up every file it modifies to `.claude/ai-config/backups/<run>/`
- Safe for regular updates

### Force

```bash
--force
```

**Behavior:**
- Skips the "existing configuration" and VSCode prompts
- Same additive rules as refresh: edited files are kept (new versions staged), unedited
  files are updated with a backup, `MEMORY.md` is never modified

### Adopt Staged Updates

```bash
--refresh --apply-pending
```

**Behavior:**
- Replaces each edited file with its staged version from `.claude/ai-config/pending/`,
  backing up your version first

**Use when:**
- You reviewed the staged files (`diff CLAUDE.md .claude/ai-config/pending/CLAUDE.md`)
  and want the new versions
- The project was deployed by an older ai-config and you never edited its generated
  `CLAUDE.md`

### Clean + Force

```bash
--clean --force --stack=expressionengine --project=/path/to/project
```

**Behavior:**
- Moves `CLAUDE.md` and `.claude/` to `.claude/ai-config/backups/<run>/` (nothing is deleted)
- Fresh deployment
- `MEMORY.md` is untouched

**Use when:**
- Switching stacks (not recommended)
- Complete reconfiguration needed
- Major version upgrade

## Health Check

Every refresh ends with a health check that verifies the configuration works, not just that the
files exist — including a live test that `safety-guard.sh` blocks a secret read. Problems are
listed with the fix (usually `--refresh`); a critical failure makes the run exit 1. To check a
project without changing anything:

```bash
ai-config --doctor --project=/path/to/project
```

## Dry Run First

Always preview changes:

```bash
ai-config --refresh --dry-run --project=/path/to/project
```

Review output before committing to changes.

## What Happens to Customizations

### How Refresh Decides (Additive Updates)

`--refresh`, `--force` redeploys, and `--clean` never discard your work:

| Project file | What ai-config does |
|---|---|
| Missing | Added |
| Identical to the shipped version | Left alone |
| Unedited since ai-config wrote it | Updated; previous copy saved to `.claude/ai-config/backups/<run>/` |
| Edited by you | **Kept.** New version staged at `.claude/ai-config/pending/<same path>` |

"Unedited" is checked against `.claude/ai-config/manifest.tsv` (hashes of what ai-config
last wrote). For projects deployed before the manifest existed, shipped files are matched
against every committed version in this repo's git history, so untouched legacy files still
update. A legacy `CLAUDE.md` / `AGENTS.md` can't be matched that way (it is rendered per
project), so it is kept with only its managed blocks refreshed — run `--apply-pending` if
you never edited it.

Files changed in place are backed up once per run and written only when the content really
changes:

- `settings.local.json` — entries are only added; nothing is removed or reordered
- `.gitignore` — append-only
- `CLAUDE.md` / `AGENTS.md` managed blocks — only the text between the
  `<!-- BEGIN … -->` / `<!-- END … -->` markers
- `MEMORY.md` — never modified

`CLAUDE.md`, `MEMORY.md`, and `.claude/` are gitignored by default, so these backups are the
only history those files have. `.claude/ai-config/` itself is always gitignored.

### Preserved During --refresh

Your custom rules, agents, commands, skills, and hooks stay intact — including edits you
made to files ai-config originally shipped.

**Library curation is preserved too.** A refresh updates the libraries you still
have under `.claude/libraries/`, but it does **not** re-add ones you deleted —
unless the refresh newly detects that technology (e.g. you just added Tailwind).
So curating `.claude/libraries/` down to what the project actually uses sticks
across refreshes. (Detection-backed: `tailwind.md`, `alpinejs.md`,
`foundation.md`, `scss.md`; framework libraries are stack-implied and never
re-added once removed.)

### Updated During --refresh

- `CLAUDE.md` - Regenerated if unedited; otherwise only its managed blocks (safety
  guardrails, memory protocol, response style, orchestrator policy) are refreshed
- `settings.local.json` - Shared deny/ask rules and the safety-guard hook are added.
  Nothing is removed: allow rules that overlap an ask/deny rule stay (ask/deny take
  precedence), and `enableAllProjectMcpServers` is only set when absent
- `.claude/hooks/safety-guard.sh` - Updated if unedited (refresh warns if you edited it)
- Shared rules - `token-optimization.md` / `memory-management.md` updated if present and unedited;
  `deployment-safety.md` / `sensitive-files.md` restored if missing
- `.claude/libraries/` - Existing libraries updated; missing ones added only when
  newly detected (see above)

### Moved Aside During --clean

Nothing is deleted. `CLAUDE.md` and `.claude/` are moved to
`.claude/ai-config/backups/<run>/` (earlier backups and the manifest carry over), then a
fresh configuration is deployed. `MEMORY.md` is untouched.

## Updating Multiple Projects

`ai-config-fleet` finds every ai-config project under a folder (by `.claude/ai-config/manifest.tsv`,
or the Safety Guardrails block in `CLAUDE.md` for older projects) and prints one summary:

```bash
ai-config-fleet --root=~/sites --list                 # projects, stack, deployed ai-config version
ai-config-fleet --root=~/sites                        # --doctor each project (default)
ai-config-fleet --root=~/sites --refresh --dry-run    # preview a refresh everywhere
ai-config-fleet --root=~/sites --refresh -- --skip-superpowers-update
```

Each project's full output goes to a log folder (printed once). The table shows ✓ ok, ⚠ N warnings,
or ✗ failed per project, and the run exits 1 if any project failed. `--depth=N` (default 3) limits
the search; `node_modules`, `vendor`, and hidden folders are skipped. Every deploy or refresh records
the ai-config commit in `.claude/ai-config/version`, and `--doctor` notes when ai-config has changed
since.

## After Updating

1. **Review changes**
   ```bash
   cd /path/to/project
   git diff
   ```

2. **Test with Claude Code**
   - Open Claude Code in project
   - Verify CLAUDE.md loads
   - Test commands

3. **Reload VSCode** (if settings changed)
   - `Cmd+Shift+P` → "Developer: Reload Window"

## Version Tracking

The configuration doesn't include version numbers. Track updates via:

1. **Git in claude-optimizer repo**
   ```bash
   cd claude-optimizer
   git log --oneline
   ```

2. **Project git history**
   ```bash
   cd /path/to/project
   git log CLAUDE.md
   ```

## Troubleshooting

### Stack Not Auto-Detected

**Problem:** `--refresh` says "stack is required"

**Solution:** Your `CLAUDE.md` might be old format. Manually specify:
```bash
ai-config --refresh --stack=expressionengine --project=/path/to/project
```

### Files Not Updating

**Problem:** Expected files aren't changing.

**Possible causes:**
1. Using `--skip-vscode` flag
2. Files don't exist in source template
3. Detection logic doesn't match (e.g., Tailwind not detected)

**Solution:**
1. Check source template exists
2. Use `--dry-run` to see detection results
3. Ensure technology files are in expected locations

## Next Steps

- **[Setup Script](setup-script.md)** - All options detailed
- **[Conditional Deployment](conditional-deployment.md)** - Detection logic
- **[Installation](../getting-started/installation.md)** - Shell aliases setup
