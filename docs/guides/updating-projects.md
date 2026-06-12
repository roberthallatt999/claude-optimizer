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
- Updates templates
- Preserves `.claude/` customizations
- Safe for regular updates

### Force

```bash
--refresh --force
```

**Behavior:**
- Overwrites all files
- No prompts
- **Loses customizations**

**Use when:**
- You want a clean slate
- Templates significantly changed
- Troubleshooting issues

### Clean + Force

```bash
--clean --force --stack=expressionengine --project=/path/to/project
```

**Behavior:**
- Deletes ALL Claude config
- Fresh deployment
- **Complete reset**

**Use when:**
- Switching stacks (not recommended)
- Complete reconfiguration needed
- Major version upgrade

## Dry Run First

Always preview changes:

```bash
ai-config --refresh --dry-run --project=/path/to/project
```

Review output before committing to changes.

## What Happens to Customizations

### Preserved During --refresh

`.claude/` directory contents are not regenerated. Your custom:
- Rules
- Agents
- Commands

All stay intact.

**Library curation is preserved too.** A refresh updates the libraries you still
have under `.claude/libraries/`, but it does **not** re-add ones you deleted —
unless the refresh newly detects that technology (e.g. you just added Tailwind).
So curating `.claude/libraries/` down to what the project actually uses sticks
across refreshes. (Detection-backed: `tailwind.md`, `alpinejs.md`,
`foundation.md`, `scss.md`; framework libraries are stack-implied and never
re-added once removed.)

### Regenerated During --refresh

- `CLAUDE.md` - Regenerated from template, then the managed safety-guardrails and
  memory-protocol blocks are re-applied in place
- `.vscode/` - Updated with latest settings
- `settings.local.json` - Updated with permissions
- `.claude/libraries/` - Existing libraries updated; missing ones added only when
  newly detected (see above)

### Lost During --clean

Everything is deleted:
- `CLAUDE.md`, `.claude/`

## Updating Multiple Projects

Update all your projects:

```bash
for project in ~/projects/*/; do
  ai-config --refresh --project="$project"
done
```

With confirmation:

```bash
for project in ~/projects/*/; do
  echo "Update $project? (y/n)"
  read -r response
  if [[ "$response" == "y" ]]; then
    ai-config --refresh --project="$project"
  fi
done
```

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
