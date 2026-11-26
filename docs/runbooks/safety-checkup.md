# Monthly safety check

Ten minutes, once a month, so you know the protections still work instead of assuming they do. Every step only
looks; any fix is yours to run.

The commands below assume ai-config lives in `~/.ai-config`, and your projects in `~/sites`. Change those if
yours are elsewhere.

## 1. Every project's guard still works

```bash
ai-config-fleet --root=~/sites
```

For each project, this feeds the safety guard a fake secret and expects it to be blocked. It also checks the
commit check, the protected files, the profile and the sandbox. **Fix any ✗ first.** A guard that fails is a guard
that isn't there.

## 2. This computer's guard is intact

The computer-wide guard:

```bash
~/.ai-config/scripts/install-global-guard.sh --check
```

The managed settings, if you installed them:

```bash
~/.ai-config/scripts/install-managed-settings.sh --check
```

Each one says what changed and how to put it back.

## 3. No secrets in old conversations

```bash
~/.ai-config/scripts/scan-transcripts.sh
```

This looks through Claude Code's saved conversations for keys and tokens. It lists file names and counts, never
the values.

If it finds one: **change that password or key first** (assume it's exposed), then delete the conversation file.

Claude Code keeps conversations for 30 days. To keep them for 14, add `"cleanupPeriodDays": 14` to
`~/.claude/settings.json`.

## 4. Philter is running

In Claude Code, type:

```text
/scrub
```

It shows whether Philter is running and which rules this project uses. If Philter is down, the plugin blocks
messages rather than send them unfiltered. That's safe, but it stops you working.

## 5. Package installs can't run surprise code (optional)

`npm install` can run scripts from any package, with your permissions. Inside a dev container that's contained;
on your Mac it isn't. To make the Mac strict:

```bash
npm config set ignore-scripts true
```

Some packages need their install script, such as `sharp` or `esbuild`. Run those on purpose. Replace `<package>`
with the package's name:

```bash
npm rebuild <package>
```

For client projects, prefer running installs in the dev container.

## 6. Tokens are still narrow

Look over the tokens the sandboxes use. This confirms a Keychain item exists without printing it; replace
`<item>` with its name:

```bash
security find-generic-password -s <item>
```

The GitHub token should be fine-grained, limited to the repositories you work on, and set to expire. Revoke any
you no longer use. Revoking it on GitHub cuts off every container at once.

## If something looks wrong

| You found | Do this first |
|---|---|
| A guard test failed | Refresh that project (`ai-config --refresh --project=.` in its folder), then run `--doctor` again |
| A secret in a conversation | Change it where it was issued, then delete the conversation file |
| Managed settings differ | Re-run `install-managed-settings.sh` and the `sudo` command it prints |
| Philter is down | Start it (`docker compose up -d` in its folder), then type `/scrub` |
