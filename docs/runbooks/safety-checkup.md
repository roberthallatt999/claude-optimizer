# Runbook: monthly safety check-up

Ten minutes, once a month, to know the safeguards are still on, rather than assume it. Every step
reads only; the ones that change something are yours to run.

## 1. Every project's guard still works

```sh
ai-config-fleet --root=~/sites --doctor
```

`--doctor` runs a live test of the safety guard in each project (it feeds the hook a fake secret
read and expects a deny), and checks the commit hook, the protected paths, the profile and the
sandbox. Fix any `✗` before anything else: a failing guard is a missing guard.

## 2. This Mac's floor is intact

```sh
scripts/install-global-guard.sh --check       # the global guard is registered and current
scripts/install-managed-settings.sh --check   # managed settings (if you installed them) are current
```

Either one reports what changed and the command to put it back.

## 3. Nothing leaked into old conversations

```sh
scripts/scan-transcripts.sh
```

Scans `~/.claude/projects/*.jsonl` for private keys and vendor token shapes and lists files and
line counts, never values. For a hit: **rotate the credential first** (assume it's exposed), then
delete that transcript file. To keep fewer transcripts, set `"cleanupPeriodDays": 14` in
`~/.claude/settings.json` (the default is 30).

## 4. Philter is up and redacting

In Claude Code: `/scrub`. It shows whether Philter is reachable and which policy set this project
uses. If it's down, the plugin blocks prompts rather than sending them unredacted. That's safe,
but it stops you working.

## 5. Package installs can't run surprise code (optional, on the Mac)

`npm install` and `composer install` run package scripts with everything you can reach. Inside a
dev container that's contained; on the Mac it isn't. If you want the Mac strict:

```sh
npm config set ignore-scripts true     # then run a package's scripts on purpose: npm rebuild <pkg>
```

Some packages (native modules like `sharp`, `esbuild`) need their install script; rebuild those
explicitly. Prefer running installs in the dev container for client projects.

## 6. Tokens are still narrow

Look over the tokens the sandboxes use (`security find-generic-password -s <item>` shows that an
item exists without printing it). The GitHub one should be fine-grained, limited to the repos you
work on, with an expiry. Revoke any you no longer use: revoking on GitHub cuts off every container
at once.

## When something looks wrong

| Finding | First step |
| --- | --- |
| A guard test fails in `--doctor` | `ai-config --refresh --project=<dir>`, then `--doctor` again |
| A credential in a transcript | Rotate it at the provider, then delete the transcript |
| Managed settings differ | Rerun `scripts/install-managed-settings.sh` and its printed `sudo` line |
| Philter down | Start it on the Mac (philter-guard's instructions), then `/scrub` |
