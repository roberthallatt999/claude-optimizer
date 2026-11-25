# Sandbox (optional)

ai-config already limits what Claude does on your Mac: deny rules for secret files, a safety hook that
scans what Claude reads and runs, a commit-time secret check, and Philter redaction. A **sandbox**
adds containment: Claude runs somewhere that can reach only the sites you allow, holds no real
tokens, and can't edit its own guardrails.

It's optional. Without `--devcontainer` or `--sandbox=…`, nothing on this page happens.

| Choice | What you get | Status |
| --- | --- | --- |
| `--sandbox=devcontainer` (or `--devcontainer`) | A VS Code dev container: default-deny firewall, egress proxy, tokens added on the way out, guardrails read-only | Ready |
| `--sandbox=enclave` | Eclipse Enclave's per-project policy, built from the same settings ([below](#enclave)) | Ready (fewer features) |
| `--sandbox=claude` | Claude Code's own sandbox for Bash (Seatbelt / bubblewrap) with the same allowlist; no Docker ([runbook](../runbooks/claude-sandbox.md)) | Ready (Bash only) |

Step-by-step: [dev container](../runbooks/devcontainer.md), [Enclave](../runbooks/enclave.md),
[Claude Code sandbox](../runbooks/claude-sandbox.md).
| `--sandbox=none` | Stop updating a sandbox (nothing is deleted) | Ready |

## Quick start (dev container)

Needs Docker Desktop, VS Code with the Dev Containers extension, and `python3`.

```bash
# 1. Once per Mac: the GitHub token the sandbox uses (a fine-grained token for the repos you work on).
#    Run it in your own terminal; it asks for the token without echoing it.
security add-generic-password -U -s <profile>-devcontainer-github -a "$USER" -w

# 2. Per project: deploy the Claude config and write .devcontainer/
ai-config --devcontainer --project=.

# 3. In VS Code: Dev Containers: Reopen in Container. Then, in the container terminal:
claude
```

`<profile>` is the project's [profile](profiles.md) (`ai-devcontainer-github` when none applies). The
generated `.devcontainer/README.md` names the exact Keychain item and the hosts each token goes to.

The choice is sticky: later `ai-config --refresh` runs keep the container current. `--sandbox=none`
stops that without deleting anything.

## What's in the container

| Layer | How |
| --- | --- |
| Egress | `iptables` default-deny, plus a Squid proxy that allows only listed host names (CDN address changes don't matter) |
| Tokens | Stay in the Mac's Keychain. Before the container starts, `egress-credentials.sh` hands the ones your integrations name to the proxy only; the proxy adds `Authorization` on HTTPS to those hosts. Inside: placeholders |
| Guardrails | `.claude/hooks`, `.claude/settings*.json`, `ai-config.conf`, `.mcp.json`, `.git/hooks`, `.git/config`, `.ddev/` and `.devcontainer/` are mounted read-only. Root-owned managed settings re-register the safety hook and turn off claude.ai connectors |
| Mac credentials | None inside: no `~/.ssh`, `~/.aws`, `~/.gitconfig`, SSH agent, Docker socket or VS Code git login |
| Claude config | The project's own (deployed by ai-config first), the global safety guard, the global skills on your Mac (`noslop`, `humanizer`, plus any an integration names) and your profiles, all read-only |
| DDEV | Keeps running on the Mac. The container joins its network (`db` is the database); `ddev start/stop/logs/snapshot/import-db` go through a relay on the Mac, risky ones after a Mac dialog |

## What it can reach

Four layers, later ones adding to or overriding earlier ones:

1. **The stack** (always): Claude Code, VS Code and its extension CDNs, GitHub, and the package hosts
   the project uses (npm, Packagist, PyPI, WordPress.org, Craft), plus `composer.json` repositories.
2. **The profile** (`~/.config/ai-config/profiles/<name>.conf`), for every project in that context:

   ```ini
   devcontainer_integrations = playwright, plausible, cloudflare, mailtrap
   devcontainer_domains = .example.org, .example-fr.org     ; leading dot = every subdomain (proxy)
   devcontainer_hosts = example.org, staging.example.org   ; exact names, for tools that ignore the proxy
   devcontainer_block = .tracker.example
   plausible_host = stats.example.org                     ; settings integrations fill in
   share_domain = share.example.org
   github_org = example-org                               ; named in the token advice
   ```

3. **The project** (`ai-config.conf`, committed):

   ```ini
   [sandbox]
   integrations = +google-analytics, -mailtrap   ; + adds, - removes; a plain list replaces the profile's
   domains = .client.example
   hosts = api.client.example
   block = ads.client.example
   plausible_host = stats.client.example         ; overrides the profile's value for this project
   ```

4. **`.devcontainer/domains.conf`** (yours, never regenerated): domains approved from inside, or added
   by you on the Mac.

A block wins over every allow, including a wildcard. Claude Code's own hosts can't be blocked.

Three rules keep the project, which Claude can write from inside, from widening its own sandbox:

- **Tokens follow the profile only.** Settings an integration uses to decide where a token goes
  or which Mac folder is mounted (`plausible_host` in `[credential]`, Keychain items, volumes)
  come from the profile. The same key under `[sandbox]` is ignored, with a note.
- **`ai-config.conf` is read-only inside.** It's always mounted read-only; if the project has
  none, ai-config creates an empty one first (commit it).
- **A refresh that widens asks first.** New hosts to reach or to send a token to are listed;
  on a terminal you're asked, otherwise they're left out. `ai-config --refresh --force` (or the
  generator's `--yes`) applies them. The first generation doesn't ask.

## Integrations

Each service is one file. Switch one on in the profile or under `[sandbox]`.

| Name | Adds |
| --- | --- |
| `github` (always) | git, gh, release assets, Actions logs; token through the proxy |
| `playwright` | Python Playwright + headless Chromium in the image, its CDN, the `webapp-testing` skill |
| `plausible` | Plausible API (needs `plausible_host`); key through the proxy; the `plausible` skill |
| `google-analytics` | GA Data and Admin API hosts (no token: GA uses short-lived OAuth) |
| `cloudflare` | `api.cloudflare.com` + `share_domain`, wrangler, the page-record volume; token through the proxy; `noslop` |
| `doppler` | Doppler CLI and API hosts (see below before adding a token) |
| `mailtrap`, `mailchimp`, `mandrill` | Their API and SMTP hosts |
| `moneris`, `stripe` | Docs and API hosts (test-mode keys only in a sandbox) |
| `airtable`, `flowbite`, `cleanshot`, `context7` | Their hosts (`context7` switches on by itself when `.mcp.json` names it) |

Your own, or a client's, go in `~/.config/ai-config/devcontainer/integrations/<name>.conf` (private;
a file there wins over a built-in of the same name). The format:

```ini
[integration]
description = Example analytics API
requires = example_host            ; a setting it can't run without (left out, with a note, if unset)

[hosts]                             ; allowed; {key} comes from the profile or [sandbox]
{example_host}

[credential]                        ; optional: the proxy adds the token on HTTPS to these hosts
variable = EXAMPLE_API_KEY
keychain = example-api              ; Mac Keychain service (account = your macOS user)
scheme = bearer                     ; bearer, token, or github
hosts = {example_host}

[mount]                             ; optional: the Mac's config, read-only, key file replaced
source = ~/.config/example
target = ~/.config/example
copy = config
placeholder = api-key

[skills]                            ; Mac skills to mount read-only, when present
example

[deny]                              ; added to the container's managed settings
Read(**/.config/example/api-key)

[image]                             ; built-in image blocks: playwright, wrangler
```

## Adding or blocking a domain from inside

```sh
sandbox-domains list                         # what's allowed and blocked
sandbox-domains allow api.example.com "why"  # a dialog on the Mac; Deny is the default (2-minute timeout)
sandbox-domains block ads.example.com        # at once, no dialog
sandbox-domains unblock ads.example.com      # a dialog on the Mac
```

The relay on the Mac checks the name (no IPs, wildcards, schemes or paths), shows the dialog, writes
`.devcontainer/domains.conf` for that project only, and logs it in
`~/.cache/ai-devcontainer/relay/relay.log`. The proxy picks it up within 15 seconds and the command
reloads the firewall. Claude can ask for a domain but never grant one: both lists are read-only inside.

## Updating

`ai-config --refresh` regenerates every file you haven't edited. An edited file is kept and its new
version staged in `.claude/ai-config/pending/.devcontainer/` (`--apply-pending` adopts it).
`domains.conf` is never touched. After a change to the Dockerfile, mounts or integrations, use
**Dev Containers: Rebuild and Reopen in Container**; plain Reopen keeps the old container.

## Enclave

If you use Eclipse Enclave (the `enclave` CLI) instead of a dev container, the
same settings become Enclave's project policy:

```bash
ai-config --sandbox=enclave --project=.     # sticky, like the dev container
enclave --tool claude                       # start Claude in it, as usual
```

`devcontainer-kit/enclave-policy.py` writes, outside the repo (Enclave keeps project settings where
the agent can't reach them, `~/Library/Application Support/org.eclipse.enclave/config/projects/<hash>/`):

| File | What |
| --- | --- |
| `config.json` | `allow_domains` (the same hosts the dev container allows, minus blocks), `add_readonly_dirs` (`.claude/hooks`, `.git/hooks`, `.ddev`, `.devcontainer`), `features: +github-cli` |
| `patches/claude/settings.json` | The safety hook and the integrations' deny rules, merged onto Claude's settings in the container |

Your own entries in those files are kept: `ai-config-owned.json`, next to Enclave's config and
outside the repo, records what ai-config wrote, and only those entries are replaced. Enclave
validates the result; an invalid one is rolled back from `ai-config-backups/`, also next to
Enclave's config. Nothing ai-config writes into the project follows a link, since the agent could
have replaced a file there with one.

Inside Enclave the project folder is writable (Enclave makes folders read-only, not single files),
so `ai-config.conf` could be edited from inside. A refresh that would add hosts lists them and asks
first on a terminal; without a terminal it leaves them out, and `--force` accepts them.
`.devcontainer/domains.conf` isn't used here.

What Enclave doesn't do, and ai-config reports when it matters:

| Dev container | Enclave |
| --- | --- |
| Block list beats every allow | No block list: a blocked host is only left off the project's list, so a global Enclave allow still reaches it |
| Proxy injects any integration's token | Its gateway injects the GitHub token (`github-cli` feature); other integrations' tokens aren't available inside |
| `sandbox-domains allow` asks on the Mac | No request from inside: check `enclave network log --verdict deny`, add the host under `[sandbox]`, refresh |
| Playwright and wrangler in the image | Add them with an Enclave feature |

## Machine-wide floor (managed settings)

`scripts/install-global-guard.sh` registers the safety guard and the secret-file deny rules in
`~/.claude/settings.json`, which you (or a plugin, or a careless edit) can change. Claude Code's
managed settings rank above every other source, and their lists merge with the rest, so a deny
rule there can't be removed by a user, project or plugin settings file.

```sh
scripts/install-managed-settings.sh            # builds the file and prints the one sudo command to run
scripts/install-managed-settings.sh --check    # is the installed copy current?
scripts/install-managed-settings.sh --remove   # prints the command that removes it
```

It installs a single drop-in, `managed-settings.d/50-ai-config.json` (macOS:
`/Library/Application Support/ClaudeCode/`, Linux: `/etc/claude-code/`), so an existing
`managed-settings.json` is never replaced. It holds the shared deny rules,
`disableBypassPermissionsMode: "disable"` (no `--dangerously-skip-permissions`), and the global
safety guard as a hook. `--strict` adds `allowManagedHooksOnly` and
`allowManagedPermissionRulesOnly`: only managed hooks and permission rules load, so every project's
own hooks and rules are ignored. Use it only where one fixed policy should govern every session.
The script never writes the system folder itself: it prints the `sudo install …` line for you to
run. Restart Claude Code afterwards; `/status` lists the managed source.

## Doppler

Doppler's [Claude Code guide](https://www.doppler.com/agents-claude-code) gives an agent its own
config with a read-only, expiring service token, and runs commands under `doppler run`. Inside a
sandbox:

- Allow the hosts with `integrations = +doppler`.
- If Claude must run commands with secrets, give it a **read-only service token for an agent-only
  dev config** (never a personal or CLI token, never production). Values `doppler run` injects reach
  processes Claude controls, so put there only what you'd accept leaking.
- Skip Doppler's MCP server: it returns secret values to the model.
- Keep the Keychain as the egress proxy's token source; Doppler is an option alongside it.

The safety guard knows Doppler everywhere, sandbox or not:

| Command | Guard |
| --- | --- |
| `doppler secrets`, `secrets get`, `secrets download`, `--plain`/`--raw`/`--json` | Denied (prints values) |
| `doppler configure get`, `doppler configs tokens create` | Denied (prints a token) |
| `doppler run -- env`, `doppler run --command 'printenv'` | Denied (prints every injected secret) |
| `doppler secrets names`, `doppler run -- npm test`, `doppler projects`, `--help` | Allowed |
| `~/.doppler/` (the CLI's offline copy of fetched secrets) | A secret path |
| `dp.st.…`, `dp.sa.…`, `dp.pt.…`, `dp.ct.…`, `dp.scim.…`, `dp.audit.…` token shapes | Caught by the content and commit scans |

## Mac-side state

| Path | What |
| --- | --- |
| `~/.cache/ai-devcontainer/relay/` | The relay, one token per project, the request log |
| `~/.cache/ai-devcontainer/egress/ca.*` | This Mac's interception CA (the key never enters the claude service) |
| `~/.cache/ai-devcontainer/egress/projects/<key>/` | That project's tokens (`credentials.env`, mode 600, proxy only) and placeholder config |

`<key>` is the project's DDEV or folder name plus 8 hex digits of a hash of its path, so two
projects with the same name never share a token. A key already held by another folder is refused.

## Moving from cps-devcontainer (kit 1.x)

- `cps-devcontainer.py` still runs for one release; it calls `ai-devcontainer.py`.
- The CPS domain lists moved from the kit into the private `cps` profile. With `profile = cps`, the
  generated allowlist matches 1.16.0's.
- Names follow the profile, so the cps profile keeps its Keychain items (`cps-devcontainer-github`,
  `plausible-api`, `cloudflare-api`) and volume (`cps-cloudflare-config`).
- On a Mac that ran 1.x, `~/.cache/ai-devcontainer` is a link to `~/.cache/cps-devcontainer`, so
  1.x containers keep working until each is regenerated.
- A 1.x `.devcontainer/` has no manifest, so `ai-config --devcontainer` leaves it alone and says so.
  `--force` backs it up to `.claude/ai-config/backups/` and writes the new one.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| A site is blocked | `sandbox-domains allow <name>`, or add it to `domains.conf` on the Mac. Proxy refusals show as `TCP_DENIED` in `docker logs` of the `egress-proxy` container |
| `gh` isn't logged in | The initializeCommand output lists missing Keychain items; store it and reopen |
| `sandbox-domains`: relay isn't answering | Reopen the container (it starts the relay); see `relay.log` |
| An integration is "left out" | It needs a setting (`requires`); set it in the profile or `[sandbox]` |
| Philter withholds output | Philter runs on the Mac; `/scrub` shows its state |

Kit internals and per-signal detail: [devcontainer-kit/README.md](../../devcontainer-kit/README.md).
Design notes: [docs/development/ai-devcontainer-design.md](../development/ai-devcontainer-design.md).
