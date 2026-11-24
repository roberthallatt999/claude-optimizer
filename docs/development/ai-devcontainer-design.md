# ai-devcontainer: design

Status: phase 1 (resolver + dev container) implemented 2026-11-23 as ai-devcontainer 2.0.0;
phase 2 (Enclave) next. Replaces `devcontainer-kit/cps-devcontainer.py` (kit 1.16.0). Setup and
settings: [docs/guides/sandbox.md](../guides/sandbox.md). Where this proposal and the code differ,
the code and the guide are right: the project section is `[sandbox]`, the token list is
`token-hosts.conf`, and the new state folder links to the old one (not the reverse), so running
1.x containers never see their mounts move.

## Goal

`ai-config --devcontainer --project=<dir>` gives any project, for any organization, a sandboxed
VS Code dev container for Claude Code, with the project's Claude config already deployed. Nothing
in the kit names an organization. What a container can reach and which services it can sign in
to are chosen per profile and per project, from add-on files ("integrations").

## Sandboxes are optional, and there's more than one

A sandbox is opt-in: without a flag, ai-config sets up the project exactly as today. Two
backends share one resolver:

```sh
ai-config --project=. --sandbox=devcontainer   # VS Code dev container (this kit); --devcontainer is shorthand
ai-config --project=. --sandbox=enclave        # Eclipse Enclave, already installed on this Mac
ai-config --project=. --sandbox=none           # turn a sticky choice off (files are left in place)
```

The resolver (`devcontainer-kit/sandbox_policy.py`, used by both) turns the profile, the
project's `[sandbox]` section and the chosen integrations into one result: hosts to allow, hosts
to block, credentials to inject, skills and folders to mount read-only. Each backend writes that
in its own form:

| | devcontainer | enclave |
| --- | --- | --- |
| Allowlist | `.devcontainer/allowed-domains.txt` + `domains.conf` | `allow_domains` in Enclave's project config (outside the repo, keyed by Enclave's project hash) |
| Add a domain from inside | `sandbox-domains allow` → Mac dialog | Enclave's own `enclave network add-domain` on the Mac (Enclave's project-level policy is "not yet supported" upstream, so global until it is) |
| Tokens | Egress proxy injects them | Enclave's `auth` stores; integrations that need injection are reported as unsupported |
| Claude config | Mounted read-only from the project | Enclave's `host_config_paths` + the project folder |

Phase 1 builds the resolver and the devcontainer backend. Phase 2 adds the Enclave backend,
after checking which of Enclave's settings can be written from outside (`enclave config` shows
global and project values; the project file is plain JSON). Until then Enclave stays your
separate process, and nothing in phase 1 gets in its way.

The `[devcontainer]` section in the examples below is `[sandbox]` in the implementation, so a
project's choices carry over if it switches backend.

## What changes

| Today (cps-devcontainer 1.16.0) | ai-devcontainer 2.0.0 |
| --- | --- |
| `devcontainer-kit/cps-devcontainer.py`, skill `cps-devcontainer` | `devcontainer-kit/ai-devcontainer.py`, skill `ai-devcontainer`, flag `ai-config --devcontainer` |
| CPS domains, CPS site hosts, Plausible, Cloudflare, Mailtrap, Mailchimp, Moneris, Airtable, Flowbite, CleanShot hard-coded into every container | A small core, plus the integrations the profile and project switch on |
| Token injection hard-coded for GitHub, `plausible.cps.ca`, Cloudflare | Each integration declares its host, Keychain item and header; the proxy builds its rules from that list |
| Allowlist edited on the Mac only | `sandbox-domains allow/block` inside; adding asks in a Mac dialog, blocking doesn't |
| Relay only for DDEV projects | Relay for every project (domain requests need it); the DDEV commands still need DDEV |
| `~/.cache/cps-devcontainer/` | `~/.cache/ai-devcontainer/` (old path moved and linked, so old containers keep working) |

## `ai-config --devcontainer`

1. Runs the normal deploy (or `--refresh` when the project already has ai-config), so `CLAUDE.md`,
   `.claude/`, the safety guard and `ai-config.conf` exist before the container mounts them
   read-only.
2. Runs `ai-devcontainer.py --project <dir> --write`, which resolves the profile (`profile.sh`, as
   every other ai-config step does) and the project's `[devcontainer]` section.
3. An existing `.devcontainer/` is regenerated only if ai-devcontainer wrote it and it's unedited
   (same manifest rule as every other file); otherwise the new version goes to
   `.claude/ai-config/pending/.devcontainer/`. `domains.conf` is never overwritten.
4. Records `devcontainer = true` in `ai-config.conf [options]` (sticky, like `--okf-memory`), so a
   later `--refresh` keeps the container current. `--no-devcontainer` stops that; it never deletes
   the folder.

Inside the container, Claude gets the same setup as on the Mac: the project's config (mounted),
the global safety guard (mounted read-only from this checkout), the global skills that exist on
the Mac (`noslop`, `humanizer`, plus whatever an integration names), and the profiles
(`~/.config/ai-config/profiles` and `profile`, read-only).

## Core (always on)

Claude Code, VS Code and its extension CDN, GitHub (git, gh, token through the proxy), Philter
(when installed on the Mac), the stack's package hosts as detected today (npm, Composer, PyPI,
WordPress, Craft), and the hosts in a composer.json `repositories` list. The firewall, egress
proxy, managed settings, read-only guardrail mounts and no-Mac-credentials rules are unchanged.

## Integrations

One file per service. Built-ins live in `devcontainer-kit/integrations/`; your own (or a
client's) go in the private `~/.config/ai-config/devcontainer/integrations/` and win on a name
clash. Format (INI, read with Python's `configparser`; `{key}` is filled from the profile and
project settings):

```ini
# devcontainer-kit/integrations/plausible.conf
[integration]
description = Plausible Analytics API (the plausible skill)
requires = plausible_host            ; setting it can't run without

[hosts]                               ; added to allowed-domains.txt
{plausible_host}

[credential]                          ; optional: the proxy adds the token on HTTPS to these hosts
hosts = {plausible_host}
keychain = plausible-api              ; Mac Keychain service (account = $USER)
header = Bearer {token}

[mount]                               ; optional, read-only, skipped when missing on the Mac
skill = plausible
config = ~/.config/plausible          ; copied with the key file replaced by the placeholder
placeholder = api-key

[deny]                                ; added to managed-settings.json
Read(**/.config/plausible/api-key)
```

Built-ins to ship (each one off until switched on, apart from those marked core):

| Name | What it adds |
| --- | --- |
| `github` (core) | Today's GitHub hosts and token (`<profile>-devcontainer-github`, so the cps profile keeps `cps-devcontainer-github`) |
| `playwright` | Python Playwright + Chromium layer, its CDN, the `webapp-testing` skill |
| `plausible` | As above; needs `plausible_host` |
| `google-analytics` | `analyticsdata.googleapis.com`, `analyticsadmin.googleapis.com`, `oauth2.googleapis.com`; token: optional `keychain = <name>` holding a short-lived token or a refresh helper (see open question 1) |
| `cloudflare` | `api.cloudflare.com` + `share_domain`, wrangler on Node 22, the page-record volume `<profile>-cloudflare-config`; Keychain `cloudflare-api-<profile>` (`cloudflare-api` for cps, as `cloudflare.sh` already does) |
| `mailtrap`, `mailchimp`, `mandrill` | Their API and SMTP hosts |
| `moneris`, `stripe` | Docs and test gateways |
| `airtable`, `flowbite`, `cleanshot`, `context7` | Their hosts (context7 also switches on when `.mcp.json` names it, as today) |

Choosing them:

```ini
# ~/.config/ai-config/profiles/cps.conf   (defaults for every project in this profile)
devcontainer_integrations = plausible, cloudflare, playwright, mailtrap, mailchimp, mandrill, moneris, airtable
devcontainer_domains = .cps.ca, .healthygenerations.ca, …     ; your organization's domains (leading dot = subdomains)
devcontainer_hosts = cps.ca, stg.cps.ca, …                    ; exact names, for tools that ignore the proxy
plausible_host = plausible.cps.ca
github_org = canadian-paediatric-society                      ; named in the token advice

# <project>/ai-config.conf
[devcontainer]
integrations = +google-analytics, -moneris    ; + adds to, - removes from the profile's list; no sign replaces it
domains = .client.example
hosts = staging.client.example
block = .facebook.com
```

The CPS lists move out of this public repo into the private `cps.conf` (they're in git history
already, but nothing new should add to that).

## Allowing and blocking from inside

`sandbox-domains` is installed in the image:

```sh
sandbox-domains list                       # what's allowed, and where each entry came from
sandbox-domains allow api.example.com "why" # asks on the Mac; Deny is the default, 2-minute timeout
sandbox-domains block ads.example.com      # takes effect at once, no dialog
sandbox-domains unblock ads.example.com    # asks on the Mac (it widens access again)
```

It talks to the relay with the container's token. The relay (on the Mac) validates the name
(letters, digits, dots, hyphens, an optional leading dot; no IPs, no `*`, no bare TLD), shows the
Allow/Deny dialog for `allow` and `unblock`, then writes `.devcontainer/domains.conf` in that
project only, and logs the request. The proxy re-reads within 15 s; the command then runs
`sudo sandbox-firewall.sh` for tools that ignore the proxy.

```ini
# .devcontainer/domains.conf — written by the relay or by you on the Mac; never regenerated
[allow]
api.example.com          # 2026-11-23, from inside: "needed for the webhook test"
[block]
ads.example.com          # 2026-11-23, from inside
```

Blocks win over everything except the core hosts Claude Code itself needs (blocking those is
refused with a message). The file stays read-only inside, so Claude can ask but never grant.

## Compatibility

- Profile-derived names (`<profile>-devcontainer-github`, `<profile>-cloudflare-config`) keep the
  cps profile on the Keychain items and volumes it already has.
- First run of the new scripts on a Mac moves `~/.cache/cps-devcontainer` to
  `~/.cache/ai-devcontainer` and leaves a link at the old path, so containers generated by 1.16.0
  keep working until each is regenerated.
- Relay protocol: same port (20090), magic `CPSRELAY1` still accepted alongside `AIRELAY1`; env
  vars `CPS_DDEV_RELAY_*` still read, `AI_DEVCONTAINER_RELAY_*` preferred.
- `cps-devcontainer.py` stays one release as a wrapper that prints the new command and runs it.
- The EE-migration template path stops pointing into the CPS folder; it comes from the
  `ee_migrate_template` profile key (unset: the `ee-migrate` command is refused with that hint).

## Tests

`test-devcontainer.sh` (new): generation per stack with no profile, with a profile, with project
overrides (`+`/`-`), integration loading and clashes, missing `requires`, `domains.conf` merge and
block precedence, proxy credential rules from integrations, relay `domains` requests (allow with
the test-only dialog answer, block, invalid names, core-host block refused), cache migration,
`ai-config --devcontainer` stickiness and the pending rule. Existing `test-egress-proxy.sh`,
`test-ddev-relay.sh` and `test-ddev-shim.sh` updated for the new names.

## Open questions

1. Google Analytics tokens: GA's API uses OAuth. Simplest is hosts only (Claude uses GA through
   you, or through a service account key you keep on the Mac and an `initializeCommand` helper
   that mints a 1-hour token into the Keychain). Proposal: ship hosts only now, token helper later.
2. Should `allow` requests from inside also be offered for "this session only" (not written to
   `domains.conf`)? Proposal: no; one list, easy to review and prune.
