# Philter (redacting personal data)

[philter-guard](https://github.com/roberthallatt999/philter-guard) runs a local
[Philter](https://github.com/philterd/philter) server that redacts personal and customer data
before it reaches Claude. Names, emails, phone numbers, addresses and similar details in logs,
command output, query results and data files arrive as placeholders such as
`{{{REDACTED-email-address}}}`. Source code reads are not scrubbed, so Claude can still edit code.

It is optional. ai-config works the same without it.

## How the pieces fit

| Layer | Where it lives | Set up by | Applies to |
|---|---|---|---|
| Philter server + `philter` MCP server | Docker on your computer | philter-guard's `setup.sh`, once per computer | Every Claude Code session |
| `philter-scrub` plugin (`/scrub`) | Your user-level Claude Code plugins | `/plugin install`, once per computer | Every Claude Code session |
| Policy set for one codebase | `.philter` at the project root (committed) | ai-config, from `philter = <set>` in `ai-config.conf` | Sessions started in that project |
| The set's rules | `sets/<name>.json` in the philter-guard repo | You, then `./sync-policy.sh` | Every computer that pulls and syncs |

**ai-config does not install Philter, and `--refresh` does not add it.** ai-config's only job is
the third row: writing `.philter` when the project asks for a set. It never calls Philter and never
reads its keys.

## 1. Set up the computer (once)

You need Docker (Docker Desktop or OrbStack), `jq` and Claude Code.

```bash
git clone https://github.com/roberthallatt999/philter-guard.git ~/docker/philter-mcp
cd ~/docker/philter-mcp
./setup.sh
```

`setup.sh` creates `.env` with keys for this computer, starts the containers, uploads the
policies and registers the `philter` MCP server with Claude Code. **Back up `.env`** (a password
manager is fine): Philter can't read its stored data without the encryption key.

### What runs in Docker

`docker-compose.yaml` in philter-guard starts two containers (compose project `philter-mcp`):

| Container | Image | Job |
|---|---|---|
| `philter` | `philterd/philter:4.0.1` | The redaction engine. Stores policies in SQLite on the `philter-data` volume |
| `philter-mcp` | `philterd/philter-mcp:latest` | The MCP server Claude Code talks to. Calls `philter` over the private Docker network |

Both use `restart: always`, so they come back after a reboot once Docker is running. Only amd64
images are published; on Apple Silicon they run under emulation, and `philter` can take a minute
to start.

To start them without `setup.sh` (for example after writing `.env` by hand):

```bash
cd ~/docker/philter-mcp
docker compose up -d
./sync-policy.sh                     # upload the policies
claude mcp add --transport http --scope user philter http://127.0.0.1:27840/mcp
```

Check they're up:

```bash
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep philter
curl -s  http://127.0.0.1:27840/health        # MCP server
curl -sk https://127.0.0.1:27843/api/health   # Philter
```

Update the images with `docker compose pull && docker compose up -d`. The data volume and `.env`
are kept. Stop them with `docker compose down` (add `-v` only if you mean to delete the stored
data).

### Install the plugin

In a Claude Code session:

```
/plugin install philter-scrub --marketplace roberthallatt999/philter-guard
```

Pick the **user** scope. Run `/scrub` to check it's on.

### Ports

The containers listen on `127.0.0.1` only, on uncommon ports so they don't collide with dev
servers or SSH port forwards:

| Service | URL |
|---|---|
| MCP server | `http://127.0.0.1:27840/mcp` (health: `/health`) |
| Philter API | `https://127.0.0.1:27843` (self-signed certificate) |

To use other ports, set `PHILTER_MCP_HOST_PORT` and/or `PHILTER_API_HOST_PORT` in philter-guard's
`.env` and rerun `./setup.sh`. It recreates the containers and re-registers the MCP server at the
new URL.

Use `127.0.0.1` in the MCP URL, not `localhost`. `localhost` can resolve to the IPv6 address
`::1`, and if anything else listens there (an SSH `LocalForward` does by default) Claude Code
reaches that instead of Philter.

## 2. Configure a codebase

Choose the policy set in the project's committed `ai-config.conf`:

```ini
[options]
philter = comprehensive
```

Then run setup or refresh:

```bash
ai-config --refresh --project=/path/to/project
```

ai-config writes `.philter` at the project root (a comment line, then the set name). **Commit
`.philter`** so everyone who clones the project gets the same policy.

| Set name | Meaning |
|---|---|
| `comprehensive` | The base policy: built-in filters, Canadian and US identifiers, credential rules |
| `<name>` | `sets/<name>.json` in philter-guard: the base plus the rule pieces that set includes |

Set names are lowercase letters, digits and hyphens, starting with a letter or digit. Anything
else gets a warning and no file. Projects with no `.philter` use `comprehensive`.

What refresh does with `.philter`:

- No `philter` option: the file is never touched.
- The option changed: the file is rewritten and the change is reported.
- A `.philter` you wrote yourself (without ai-config's comment line), or a symlink: left alone,
  with a warning. Delete it to let ai-config manage it.
- `--clean` and `--uninstall` leave `.philter` in place.

Full option reference: [Project Policy](project-policy.md#philter--set).

## 3. Give a codebase its own rules (optional)

Use a set when the project has its own identifiers the base doesn't know: customer numbers,
member IDs, internal account codes, a list of client names. The steps are in philter-guard's
README under "Adding rules for a new project". In short:

1. Copy `library/_example.json.disabled` to `library/<piece>.json` and add regex `identifiers`
   and word-list `dictionaries` for the client's data.
2. Add tests in `tests/cases/<piece>.py` and run `python3 tests/test_patterns.py`.
3. Copy `sets/_example.json.disabled` to `sets/<client>.json` and list the pieces in `include`.
4. Run `./sync-policy.sh --dry-run`, then `./sync-policy.sh` to upload. Commit the change; other
   computers run `git pull && ./sync-policy.sh`.
5. Set `philter = <client>` in the project's `ai-config.conf` and refresh.

The set must exist on the server. If `.philter` names one that hasn't been synced, the plugin falls
back to the base policy and the status line says `⚠ policy "<name>" not found, using base`.

## 4. Check it works

| Check | Expect |
|---|---|
| `ai-config --doctor --project=.` | `Philter guard installed; policy set '<name>' from .philter` |
| `/scrub` in a session started in the project | `Philter scrubbing is ON … Policy: <name> (set-<name>)` |
| Status line | `🛡 Philter: N redacted · set <name>` |

The plugin reads `.philter` once, when the session starts, from the starting folder upward to the
repository root. **Start a new session after changing `.philter`**, and start sessions from inside
the project. Changing directory mid-session doesn't change the policy.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `philter` failed to connect: endpoint not found | The MCP URL points at something else on that port. Use `127.0.0.1` and the port from the table above: `claude mcp remove -s user philter && claude mcp add --transport http -s user philter http://127.0.0.1:27840/mcp` |
| `ECONNREFUSED` | The containers aren't running, or the MCP URL has an old port. `cd ~/docker/philter-mcp && docker compose up -d`, then check `curl -s http://127.0.0.1:27840/health` |
| Messages not sent, tool output withheld | Philter is down; the plugin fails closed. Start the containers, then `/mcp` to reconnect |
| `⚠ policy "<name>" not found, using base` | The set isn't on the server. Run `./sync-policy.sh` in philter-guard |
| `⚠ .philter unreadable or invalid, using base` | The first line isn't a valid set name. Fix `philter =` in `ai-config.conf` and refresh |
| `--doctor`: `Philter guard not installed (optional)` | The `philter` MCP server isn't registered on this computer. Run philter-guard's `setup.sh` |
| A new set doesn't apply | `.philter` is read at session start. Start a new session |

## Limits

- Some inputs never go through Philter: `CLAUDE.md`, memory files (`MEMORY.md`, `.okf/`),
  slash-command arguments, and images you choose to send. Keep personal data out of them; the
  [memory protocol](memory-system.md) already says so.
- Philter is a backstop for ai-config's safety guard, not a replacement. Secret files are still
  denied by the guard before Philter would see them.
- Pattern matching over-redacts some ordinary numbers and misses unusual formats. If something
  slips through, add a rule to the project's set.
