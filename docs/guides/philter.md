# Hide personal data (Philter)

[philter-guard](https://github.com/roberthallatt999/philter-guard) runs [Philter](https://github.com/philterd/philter)
on your computer. It replaces names, emails, phone numbers, addresses and similar details before Claude sees
them, in logs, command output, database results and data files. Claude sees a placeholder such as
`{{{REDACTED-email-address}}}` instead. Source code isn't changed, so Claude can still edit it.

It's optional. ai-config works the same without it.

## Who does what

| Part | Set up by | How often |
|---|---|---|
| The Philter server (runs in Docker) | philter-guard's `setup.sh` | Once per computer |
| The `/scrub` plugin for Claude Code | You, inside Claude Code | Once per computer |
| Which rule set a project uses | ai-config, from a line in `ai-config.conf` | Once per project |

ai-config doesn't install Philter. Its only job is to write the rule set's name into a `.philter` file in the
project.

## 1. Set up your computer (once)

You need Docker (Docker Desktop or OrbStack), `jq` and Claude Code. Run these one at a time:

```bash
git clone https://github.com/roberthallatt999/philter-guard.git ~/docker/philter-mcp
```

```bash
cd ~/docker/philter-mcp
```

```bash
./setup.sh
```

`setup.sh` creates the keys, starts Philter, loads the rules and connects it to Claude Code.

**Back up the `.env` file it creates** (a password manager is fine). Philter can't read its stored data without
it.

Then install the plugin. Inside Claude Code, type:

```text
/plugin install philter-scrub --marketplace roberthallatt999/philter-guard
```

Choose the **user** scope. Then type `/scrub` to confirm it's on.

## 2. Choose a rule set for a project

Add this to the project's `ai-config.conf`:

```ini
[options]
philter = comprehensive
```

`comprehensive` is the standard set. Use a different name only if you've made a set for this project (step 3).
Then refresh:

```bash
ai-config --refresh --project=.
```

ai-config writes a `.philter` file in the project. **Commit it**, so everyone who clones the project gets the
same rules.

Start a new Claude Code session afterwards. The plugin reads `.philter` only when a session starts.

## 3. Rules for one project's own data (optional)

Make your own set when a project has identifiers the standard set doesn't know, such as member numbers, account
codes or client names. philter-guard's README explains each step under "Adding rules for a new project". In
short:

1. Copy `library/_example.json.disabled` to `library/<name>.json` and add the patterns.
2. Add tests in `tests/cases/` and run `python3 tests/test_patterns.py`.
3. Copy `sets/_example.json.disabled` to `sets/<client>.json` and list your pieces.
4. Upload it with `./sync-policy.sh`, then commit. Other computers run `git pull`, then `./sync-policy.sh`.
5. Set `philter = <client>` in the project's `ai-config.conf`, and refresh.

## Check it works

| Check | You should see |
|---|---|
| `ai-config --doctor --project=.` | `Philter guard installed; policy set '<name>' from .philter` |
| `/scrub` in Claude Code | `Philter scrubbing is ON` and the set's name |
| The status line | `🛡 Philter: N redacted` |

## Everyday commands

Run these from the philter-guard folder:

```bash
cd ~/docker/philter-mcp
```

Is it running?

```bash
docker ps | grep philter
```

Start it:

```bash
docker compose up -d
```

Update it:

```bash
docker compose pull
```

```bash
docker compose up -d
```

Stop it:

```bash
docker compose down
```

Philter starts again on its own after a restart, once Docker is running. On Apple Silicon Macs it can take a
minute.

## Problems

| What you see | What to do |
|---|---|
| Messages aren't sent, or tool output is withheld | Philter is stopped. The plugin blocks rather than send data unfiltered. Start it with `docker compose up -d`, then type `/mcp` in Claude Code to reconnect |
| `ECONNREFUSED` | Philter isn't running. Start it as above |
| `policy "<name>" not found, using base` | The set isn't uploaded. Run `./sync-policy.sh` in the philter-guard folder |
| `.philter unreadable or invalid` | Fix the `philter =` line in `ai-config.conf`, then refresh |
| A new set doesn't apply | Start a new Claude Code session |
| `philter failed to connect` | It's connected to the wrong address. Run `./setup.sh` again |

Philter listens on `127.0.0.1` only, on ports 27840 and 27843. To change them, edit philter-guard's `.env` and run
`./setup.sh` again.

## What it doesn't cover

- `CLAUDE.md`, `MEMORY.md`, the `.okf/` folder, slash-command text and images you send never go through Philter.
  Keep personal data out of them.
- It backs up the safety guard; it doesn't replace it. Secret files are still blocked before Philter would see
  them.
- Pattern matching sometimes hides ordinary numbers and sometimes misses unusual formats. If something gets
  through, add a rule to the project's set.
