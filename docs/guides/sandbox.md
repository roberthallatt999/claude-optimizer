# Sandboxes

ai-config's safety rules limit what Claude does on your computer. A sandbox goes further: Claude runs somewhere
that can reach only the websites you allow. In most setups it also holds no real passwords and can't change its
own safety rules.

Sandboxes are optional. Without one of the options below, nothing on this page happens.

## Pick one

| | Claude Code sandbox | Dev container | Enclave |
|---|---|---|---|
| Set up with | `--sandbox=claude` | `--devcontainer` | `--sandbox=enclave` |
| You need | Nothing extra on a Mac | Docker and VS Code | Enclave and Docker |
| What's contained | Terminal commands only | Everything Claude does | Everything Claude does |
| Only allowed websites | Yes | Yes | Yes |
| Block list | Yes | Yes | No |
| Your tokens kept out of reach | No | Yes | GitHub only |
| Safety files can't be edited | No (the guard asks first) | Yes | Folders only |
| Step-by-step guide | [Claude Code sandbox](../runbooks/claude-sandbox.md) | [Dev container](../runbooks/devcontainer.md) | [Enclave](../runbooks/enclave.md) |

**In short:** the Claude Code sandbox is an easy everyday extra layer. The dev container is the strongest; use it
for client work where tokens or containment matter.

Your choice is remembered: later refreshes keep the sandbox up to date. To stop updating it (nothing is
deleted):

```bash
ai-config --refresh --sandbox=none --project=.
```

## What it can reach

All three sandboxes use the same allow list, built in four layers. Each layer can add to the ones before it.

**1. The stack, always.** Claude Code itself, VS Code and its extensions, GitHub, and the package sites the
project uses (npm, Packagist, PyPI, WordPress.org, Craft).

**2. Your profile**, for every project in that context. In `~/.config/ai-config/profiles/<name>.conf`:

```ini
devcontainer_integrations = playwright, plausible, cloudflare
devcontainer_domains = .example.org
devcontainer_hosts = staging.example.org
devcontainer_block = .tracker.example
```

A leading dot means "this domain and every subdomain".

**3. The project**, in `ai-config.conf`:

```ini
[sandbox]
integrations = +google-analytics, -mailtrap
domains = .client.example
hosts = api.client.example
block = ads.client.example
```

`+` adds an integration and `-` removes one the profile added. A list with no signs replaces the profile's list.

**4. `.devcontainer/domains.conf`**, dev container only: sites approved from inside the container. It's yours and
never regenerated.

A block always beats an allow. Claude Code's own sites can't be blocked.

After a change, refresh. If the change lets the sandbox reach a new site, or send a token to one, the refresh
lists it and asks you first:

```bash
ai-config --refresh --project=.
```

### Why some settings come only from your profile

Claude can edit the project's files from inside the sandbox. So nothing in the project can widen the sandbox
unseen:

- Where a token is sent, and which folders from your computer are shared, come only from your profile.
- `ai-config.conf` is read-only inside the dev container.
- A refresh that widens the sandbox asks first. With no one to answer, it leaves the new sites out. `--force`
  accepts them once you've checked the list.

## Integrations

An integration is one service: its sites, and optionally its token, tools and skills. Turn them on in your
profile or under `[sandbox]`.

| Name | Adds |
|---|---|
| `github` (always on) | git, `gh`, releases, Actions logs. The token is added on the way out |
| `playwright` | A headless browser for testing, and the `webapp-testing` skill |
| `plausible` | The Plausible analytics API (needs `plausible_host` in your profile) and the `plausible` skill |
| `google-analytics` | The Google Analytics API sites |
| `cloudflare` | The Cloudflare API, your share domain, `wrangler` and the `noslop` skill |
| `doppler` | The Doppler CLI and API. [Read the Doppler notes](#doppler) before adding a token |
| `mailtrap`, `mailchimp`, `mandrill` | Their API and mail servers |
| `moneris`, `stripe` | Their docs and API. Use test-mode keys only |
| `airtable`, `flowbite`, `cleanshot`, `context7` | Their sites |

### Write your own integration

Put a file in `~/.config/ai-config/devcontainer/integrations/<name>.conf`. A file there replaces a built-in one
with the same name. Every section except `[integration]` and `[hosts]` is optional:

```ini
[integration]
description = Example analytics API
requires = example_host

[hosts]
{example_host}

[credential]
variable = EXAMPLE_API_KEY
keychain = example-api
scheme = bearer
hosts = {example_host}

[mount]
source = ~/.config/example
target = ~/.config/example
copy = config
placeholder = api-key

[skills]
example

[deny]
Read(**/.config/example/api-key)
```

| Section | What it does |
|---|---|
| `[integration]` | A description, and any setting it can't work without (`requires`) |
| `[hosts]` | Sites to allow. `{example_host}` is filled in from your profile |
| `[credential]` | A token from your Mac's Keychain, added to requests for those sites only. `scheme` is `bearer`, `token` or `github` |
| `[mount]` | A config folder from your Mac, shared read-only, with the key file replaced by a placeholder |
| `[skills]` | Skills from your Mac to share read-only |
| `[deny]` | Extra files Claude must never read |
| `[image]` | Tools built into the container: `playwright` or `wrangler` |

## Allow or block a site from inside the dev container

See the lists:

```bash
sandbox-domains list
```

Ask to allow a site. A dialog appears on your Mac; it says no unless you click Allow within two minutes:

```bash
sandbox-domains allow api.example.com "why it's needed"
```

Block a site straight away (no dialog):

```bash
sandbox-domains block ads.example.com
```

Unblock one (asks on the Mac):

```bash
sandbox-domains unblock ads.example.com
```

Claude can ask for a site but can never grant one itself.

## VS Code extensions and settings

Inside a dev container, VS Code settings come from three places. Later ones win:

| Place | What belongs there |
|---|---|
| Your Mac's own VS Code settings | Personal taste: theme, rulers, word wrap. They apply in containers too, so set them once |
| `.devcontainer/devcontainer.json` | What the codebase needs: extensions, formatters, file types. Set per project with `[vscode]` |
| The project's `.vscode/settings.json` | Wins over both. A stale copy can quietly undo the other two |

To change a container's extensions or settings, add `[vscode]` to `ai-config.conf`. Don't edit
`devcontainer.json`: once edited, it stops getting updates.

```ini
[vscode]
extensions = +streetsidesoftware.code-spell-checker, -usernamehw.errorlens
editor.wordWrap = "on"
twig: editor.formatOnSave = true
```

- `+` adds an extension and `-` removes one. Claude Code itself can't be removed.
- A setting's value is JSON, so text goes in quotes. `twig:` makes a setting apply to one language.
- Settings that keep the container cut off from your Mac's logins and network are locked. That covers git and
  GitHub sign-in, terminal environment and shells, and `http.*`, `remote.*`, `dev.containers.*` and `security.*`.

`ai-config --doctor` warns about anything in `.vscode/settings.json` that overrides the container. It never
changes that file.

To have Claude suggest `[vscode]` and `[sandbox]` lines that fit a codebase, ask it to **review the dev
containers**. It reads the project, suggests lines with a reason for each, and changes nothing until you agree.

## Updating a dev container

Refresh as usual:

```bash
ai-config --refresh --project=.
```

Then, in VS Code, choose **Dev Containers: Rebuild and Reopen in Container**. A plain Reopen keeps the old
container.

A file in `.devcontainer/` you edited by hand is kept. The new version is saved in
`.claude/ai-config/pending/.devcontainer/` for you to compare.

### Committing container changes without deploying the site

`.devcontainer/` is part of the repository. On a site that deploys on every push to `main` or `staging`, a
container-only commit would deploy the site. To stop that, add `paths-ignore` to each deploy workflow's push
trigger:

```yaml
on:
  push:
    branches:
      - main
    paths-ignore:
      - '.devcontainer/**'
```

Until then, end the commit message with `[skip ci]`. Start container work from `main`, not `staging`, so
unreleased work can't reach production with it.

## Enclave

Eclipse Enclave (the `enclave` command) is another way to sandbox Claude. ai-config turns the same
allow list into Enclave's project settings, which Enclave keeps outside the repository where Claude can't reach
them. Enclave has no block list, and only the GitHub token is available inside. Setup:
[Enclave](../runbooks/enclave.md).

## A floor for the whole computer

The installer turns the safety guard on in your own Claude settings. Anything running as you could change
those. **Managed settings** sit above every other settings file, and nobody can remove their rules short of
admin access.

Build them. The script prints one `sudo` command for you to run yourself:

```bash
~/.ai-config/scripts/install-managed-settings.sh
```

Check they're current:

```bash
~/.ai-config/scripts/install-managed-settings.sh --check
```

Remove them (prints the command to run):

```bash
~/.ai-config/scripts/install-managed-settings.sh --remove
```

They hold the shared "never read" rules, a root-owned copy of the safety guard, and a setting that disables
`--dangerously-skip-permissions`. `--strict` goes further: every project's own hooks and rules are then ignored.
Use it only where one fixed policy should govern every session.

Restart Claude Code afterwards. Re-run the script after you update ai-config; `--check` tells you when it's out
of date.

## Doppler

If you use [Doppler](https://www.doppler.com/agents-claude-code) for secrets inside a sandbox:

- Allow its sites with `integrations = +doppler`.
- If Claude must run commands with secrets, give it a **read-only service token for a dev config made just for
  Claude**. Never a personal token, never production. Anything Doppler hands to a command can reach Claude.
- Don't use Doppler's MCP server. It returns secret values to Claude.

The safety guard knows Doppler everywhere, sandbox or not:

| Command | Guard |
|---|---|
| `doppler secrets`, `secrets get`, `secrets download` | Blocked (prints values) |
| `doppler configure get`, `doppler configs tokens create` | Blocked (prints a token) |
| `doppler run -- env`, `doppler run --command 'printenv'` | Blocked (prints every secret) |
| `doppler secrets names`, `doppler run -- npm test`, `doppler projects` | Allowed |

Doppler tokens (`dp.st.…`, `dp.pt.…` and similar) are caught by the content and commit checks.

## Where things are kept on your Mac

| Folder | What's there |
|---|---|
| `~/.cache/ai-devcontainer/relay/` | The helper that runs `ddev` commands and site requests for containers, and its log |
| `~/.cache/ai-devcontainer/egress/` | The proxy's certificate, and each project's tokens (only the proxy can read them) |

Each project gets its own folder there, named after the project plus a short code made from its path. Two
projects with the same name never share tokens.

## Moving from the old cps-devcontainer (version 1)

- `cps-devcontainer.py` still works for one more release; it calls the new script.
- An old `.devcontainer/` is left alone. To replace it (the old one is backed up first):

```bash
ai-config --refresh --devcontainer --force --project=.
```

- With `profile = cps`, the new allow list matches the old one, and the Keychain items keep their names.

## Problems

| What you see | What to do |
|---|---|
| A site is blocked | `sandbox-domains allow <site>`, or add it to `.devcontainer/domains.conf` on the Mac |
| `gh` isn't logged in | The container's start-up output lists missing Keychain items. Add the missing one, then reopen |
| `sandbox-domains` gets no answer | Reopen the container. The log is `~/.cache/ai-devcontainer/relay/relay.log` |
| An integration is "left out" | It needs a setting. Add it to your profile or `[sandbox]` |
| Philter withholds output | Philter runs on the Mac. Type `/scrub` to see its state |

How the container works inside: [devcontainer-kit/README.md](../../devcontainer-kit/README.md). Design notes:
[ai-devcontainer-design.md](../development/ai-devcontainer-design.md).
