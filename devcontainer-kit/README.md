# devcontainer-kit

Gives a project an optional, sandboxed VS Code dev container for Claude Code (ai-devcontainer 2.x;
`cps-devcontainer` before 2.0). Run it on the Mac, never inside a container. The usual way in is
ai-config, which deploys the project's Claude config first:

```bash
ai-config --devcontainer --project=.            # sticky: later --refresh runs keep it current
```

Or the generator directly:

```bash
K="$AI_CONFIG_REPO/devcontainer-kit/ai-devcontainer.py"
python3 $K --root ~/sites --list                 # one line per project
python3 $K --project site                        # report: automatic (+) vs manual follow-ups (!)
python3 $K --root ~/sites --out ~/devcontainer-preview  # preview every project's files
python3 $K --project site --write                # create site/.devcontainer/
python3 $K --project site --update               # regenerate unedited files, stage the rest
python3 $K --project site --profile acme         # another ai-config profile than the active one
```

What the container may reach and sign in to comes from `sandbox_policy.py`: the profile's
`devcontainer_*` keys, the project's `[sandbox]` section in `ai-config.conf`, and the integrations
they switch on (`integrations/*.conf`, or private ones in
`~/.config/ai-config/devcontainer/integrations/`). Nothing in the kit names an organization. Setup,
settings and the integration format: [docs/guides/sandbox.md](../docs/guides/sandbox.md).

## 2.3.0

- Coilpack projects with EE templates (`ee/system/user/templates`) get the ExpressionEngine extension,
  the template association and format on save off for templates, like a plain EE site. Before,
  their templates opened as HTML and Prettier could format them on save.
- The review fact sheet finds EE templates two levels down (Coilpack's `ee/system/`), not just one.

## 2.2.0

- `--json` prints a review fact sheet per project (read-only; a list with `--root`): stack,
  integrations, generated vs on-disk extensions and settings, allowed hosts, `[vscode]` /
  `[sandbox]`, `.vscode` overrides, config files in use, template file counts and dependency
  names (`review.py`). Names only: no values from scripts, Composer config or secret files. The
  skill's **Review an existing container** step turns it into suggested `ai-config.conf` lines.
- EE templates map by `**/user/templates/**/*.html`, so a renamed system folder is covered.

## 2.1.0

- `[vscode]` in `ai-config.conf` adds or removes extensions (`+id`, `-id`) and sets VS Code settings
  per project (`key = <JSON>`, `lang: key = <JSON>`), merged over the kit's in `devcontainer.json`
  (`vscode_policy.py`). A new publisher's download hosts go through the widening confirmation.
  Isolation settings (`git.terminalAuthentication`, `github.gitAuthentication`, terminal env and
  profiles, `http.*`, `remote.*`, `dev.containers.*`, `security.*`) are locked, and Claude Code can't
  be removed.
- `--vscode-overrides` lists what the project's `.vscode/settings.json` changes from the container,
  from the developer's own settings, and personal preferences it sets. `ai-config --doctor` reports
  it and never edits the file.
- The isolation settings now come last in `customizations.vscode.settings`.

## 2.0.0

- Renamed `ai-devcontainer`; `cps-devcontainer.py` is a one-release wrapper.
- Organization domains, site hosts and services (Plausible, Cloudflare, Mailtrap, Mailchimp,
  Mandrill, Moneris, Airtable, Flowbite, CleanShot, Playwright) became integrations and profile
  settings. Playwright and wrangler are in the image only when their integration is on.
- Token injection is driven by `token-hosts.conf` (generated: variable, Keychain item, scheme,
  hosts); tokens go to `~/.cache/ai-devcontainer/egress/projects/<key>/`, one folder per project, so
  two profiles' tokens never share a file. Schemes: `bearer`, `token`, `github`.
- `sandbox-domains allow|block|unblock|list` inside, through the relay: allowing asks in a Mac dialog,
  blocking doesn't. Both land in `.devcontainer/domains.conf`, which is never regenerated; the proxy
  and firewall read it, and a block beats every allow.
- The relay runs for every project (domain requests), not only DDEV ones; ddev commands are refused
  for a project without DDEV. Protocol `AIRELAY1` (`CPSRELAY1` still accepted).
- `--update` (what `ai-config --refresh` uses) keeps edited files and stages new versions in
  `.claude/ai-config/pending/.devcontainer/`; `.ai-devcontainer.manifest` records what it wrote.
- State moved to `~/.cache/ai-devcontainer/`; on a Mac with `~/.cache/cps-devcontainer`, the new path
  is a link to the old, so 1.x containers keep working.

What it decides per project:

| Signal | Result |
| --- | --- |
| `.ddev/config.yaml` + PHP | Joins `ddev_default`; `ddev-<name>-db` as host `db`; MariaDB client with TLS off; `initializeCommand` runs `ensure-ddev.sh` on the Mac (below) |
| `.ddev` overrides | `external_links` carried over; mounts outside the project flagged; `~/.aws`/`~/.ssh` never carried |
| DDEV add-ons | `ddev-<name>-<addon>` reachable as `<addon>` |
| `.ddev/commands/web/*` | Run through the `ddev` shim with `/var/www/html` → `/workspace` (so `ddev ee`, `ddev mcp-serve`, `ddev wp` work) |
| PHP version | DDEV `php_version`, else composer.json, else 8.3; memory limit off, Xdebug off, GD with WebP |
| Node only | `javascript-node` image (user `node`); dev-server ports forwarded |
| Any other image (1.6.0) | Node copied in from the official `node:<major>-bookworm-slim` image as an ordinary, cached Dockerfile layer; version from DDEV `nodejs_version`, `.nvmrc` or `engines`, else LTS. Global npm installs go to the user-owned `/usr/local/share/npm-global`. `package.json` is looked for at the root, the DDEV docroot, then `public/` |
| Claude Code CLI (1.6.0) | Native installer (`claude.ai/install.sh`) as the container user, in a cached Dockerfile layer above the copied files, so rebuilds reuse it. It doesn't update itself (`DISABLE_AUTOUPDATER`: an update would land in the container layer and be lost on recreate); rebuild without cache to update. Not the npm package or the dev container feature: features run after the Dockerfile and were never reused from the cache (every rebuild reinstalled Node and Claude Code, 1.5–2 min), and current npm releases need Node 22, so Node 18/20 projects were stuck on an old CLI |
| Shared skills (1.11.0) | The Mac's global skills (`noslop`, `humanizer`) and those an integration names (`plausible`, `webapp-testing`) are mounted read-only, only when they exist on the Mac (a missing one would become an empty root-owned folder), with the ai-config profiles (`~/.config/ai-config/profiles` and `profile` only). `AI_CONFIG_PROFILE` is set to the project's profile, since folder maps don't match `/workspace`. Skill config comes from `egress/projects/<key>/mounts/<integration>/` with key files replaced by the placeholder; `managed-settings.json` denies reading the key paths |
| Philter (1.15.0) | The Mac's [philter-guard](https://github.com/roberthallatt999/philter-guard) redacts here too. The firewall opens `host.docker.internal:27840` (Philter's MCP port) and nothing else on Philter: the API port and its key stay on the Mac. `philter-setup.sh` runs at every start as the user: it points the `philter` MCP server at `http://host.docker.internal:27840/mcp` (re-adding it if it points elsewhere) and installs `philter-scrub@philter-guard` once, at user scope on the `claude-config` volume. It never fails the start; when Philter is down the mod blocks prompts and tool output rather than send them unredacted. Mod updates are deliberate: `claude plugin marketplace update philter-guard` inside. Check with `/scrub` |
| Playwright (1.12.0) | Python Playwright 1.64.1 and headless Chromium with its system libraries, baked into a cached layer (about 2.5 min on the first build), with `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` and `python` = python3. The Mac's `webapp-testing` skill is mounted read-only. Chromium honours the proxy, so allowlisted sites and the local DDEV site load (`ignore_https_errors=True` for mkcert certificates) and everything else is refused. `cdn.playwright.dev` is allowed for Firefox/WebKit; Chromium for another Playwright version redirects to `storage.googleapis.com`, which is deliberately not allowed, so pin projects to the kit's version |
| `requirements.txt` | Python image or feature, PyPI allowed |
| composer.json repos, Craft, `.mcp.json` context7 | Added to `allowed-domains.txt`; private repos flagged (no auth.json inside) |
| `.claude/hooks/safety-guard.sh` | Re-registered in root-owned managed settings |
| Guardrail files that exist | Mounted read-only, along with `.devcontainer/` itself and (1.6.1) `.ddev/`, whose `exec-host` hooks run on the Mac at the next `ddev start`. Exception (1.14.0): `.ddev/nginx_full/` is mounted writable on top, since only nginx in the DDEV web container reads it (the directory, not the file: editors save by temp file + rename) |
| Site database (1.8.0) | `ddev mysql` opens `$DDEV_DB_NAME` (default `db`). Many sites import production into a database named after it (`admin_site`) and leave DDEV's `db` empty, so the kit lists the databases in the project's DDEV volume (read-only, through a throwaway `alpine` container), takes the populated one written most recently, and sets `DDEV_DB_NAME` when it isn't `db`. `--db-name` overrides. The name goes in as `--database=`, so `ddev mysql admin_site -e …` works. `ddev mysql --project=<ddev-name> [db]` reaches another running project's server |
| Claude Code traffic (1.7.0) | `DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING`, `DISABLE_BUG_COMMAND`, `DISABLE_AUTOUPDATER`. Not `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, which also stops the plan-usage fetch, so the Account & Usage panel showed "Failed to load usage data" |
| Shell history (always) | `command-history` volume at `/commandhistory`; bash and zsh write to it after every command, so it survives rebuilds |
| Tokens outside the container (1.16.0, 2.0.0) | Tokens stay in the Mac's Keychain. Each integration's `[credential]` names its Keychain item (GitHub: `<profile>-devcontainer-github`; Cloudflare: cloudflare.sh's item for the profile). `files/egress-credentials.sh` (initializeCommand) creates this Mac's interception CA once and writes the items `token-hosts.conf` lists to `egress/projects/<key>/credentials.env` (mode 600), mounted into `egress-proxy` only. The proxy intercepts TLS for those hosts only, drops the client's `Authorization` and adds the real one, on HTTPS only; every other host is spliced untouched. The claude service gets the CA certificate, `GH_TOKEN=ai-egress-placeholder` and placeholder key files. Tests: `test-egress-proxy.sh` |
| GitHub (always, 1.3.0) | git push/pull and `gh` work inside through gh, with the proxy's token. git's GitHub helper is `gh auth git-credential` and SSH remotes are rewritten to HTTPS inside only. Use a fine-grained token scoped to the repos you work on. Managed settings ask before `git push`, `gh pr merge`, releases and workflow runs, and deny `gh auth token`, `gh repo delete` and reading `~/.config/gh` |
| Mac credentials (always) | None inside: `SSH_AUTH_SOCK`, `GIT_ASKPASS` and VS Code's `VSCODE_GIT_*` blanked, `GIT_TERMINAL_PROMPT=0`, `git.terminalAuthentication` and `github.gitAuthentication` off. Pair with the Mac user settings `dev.containers.copyGitConfig: false` and `dev.containers.gitCredentialHelperConfigLocation: "none"` |
| `package.json` (1.3.0) | `node_modules` next to it is a per-project Docker volume, so Linux and macOS native modules (sharp, esbuild) don't overwrite each other; run `npm ci` in the container once. Owned by the container user via the root-owned, argument-free `sandbox-own-volumes.sh` |
| Preview (1.3.0) | DDEV PHP sites: `ddev-router` linked as `<name>.<project_tld>` so BrowserSync/Vite can proxy the site; BrowserSync (3000, 3001) and Vite (5173) get labels and are auto-forwarded once a dev server listens (1.4.0: no static `forwardPorts`, which held the Mac's ports and stopped DDEV's router starting other projects) |
| VS Code tooling (1.4.0) | Every container: Claude Code (shares the CLI's login, so no second sign-in), REST Client, EditorConfig, Prettier, Error Lens, Git Graph, DotENV. By stack: Intelephense + Xdebug (PHP), Laravel Pint as the PHP formatter where `laravel/pint` is required, PHP CodeSniffer where `squizlabs/php_codesniffer` is, Laravel + Blade (Laravel), ExpressionEngine + Apache (EE), Twig (Craft), Tailwind, Alpine, ESLint. Format on save touches only changed lines and Prettier needs a repo config; EE templates (`system/user/templates/**`) map to the ExpressionEngine language with format-on-save off. Each extension publisher's gallery CDN hosts (`<publisher>.gallerycdn.vsassets.io`, `.gallery.vsassets.io`) are allowed, so the container downloads extensions itself; VS Code's fallback of downloading on the Mac and copying in never finished for Claude Code's 135 MB package. 1.6.0: extensions live on a per-project `vscode-extensions` volume, so rebuilds don't download them again |
| Egress proxy (1.10.0) | A Squid `egress-proxy` service on the compose project's own network (never on `ddev_default`, so projects' proxies can't answer for each other). `HTTP(S)_PROXY` point at it, `NO_PROXY` covers `db`, add-ons, linked names, the site and `host.docker.internal`. It allows CONNECT :443 and HTTP :80 only to the allowlist's names, refuses names that resolve to private addresses, caches nothing, and re-reads the allowlist every 15 s. Fixes Composer failing with "Operation not permitted" after `repo.packagist.org` moved address. The IP allowlist stays for clients that ignore the proxy variables |
| Every language's host name (1.14.0) | Bilingual sites often have two domains. Local: each name DDEV serves (the primary, `additional_hostnames` under the project TLD, `additional_fqdns`) gets a `ddev-router` link and a `NO_PROXY` entry, so the second language's name resolves inside like the first; `ensure-ddev.sh` counts a router link as a project only when `~/.ddev/project_list.yaml` knows the label. Remote: list every production and staging name in the profile's `devcontainer_hosts`, because the firewall only allows a wildcard's apex (`.example.org` → `example.org`) |
| IPv6 off (1.10.0) | `net.ipv6.conf.{all,default}.disable_ipv6` in both services: hosts publish AAAA records the container can't route, and PHP tried them first ("Network is unreachable") |
| GitHub hosts (1.10.0) | Every container lists uploads, release assets, Actions logs/artifacts (`productionresultssa0-19.blob.core.windows.net`, `*.actions.githubusercontent.com`) and ghcr, so every `gh` command works. Managed settings ask only before `git push`, `gh pr merge`, `gh release create/upload`, `gh workflow run`, `gh run rerun`, and set `AI_CONFIG_GH_LIGHT_WRITES=allow`, which tells `safety-guard.sh` not to ask for PR and issue writes |
| WordPress (1.10.0) | `downloads.wordpress.org` (core and every wpackagist zip) and `api.wordpress.org` (checksums, version checks); theme `package.json` found under `web/app/themes/*` / `wp-content/themes/*`; a root `.nvmrc` doesn't set the Node version for a theme, and an `engines` floor (`>=18`) means LTS |
| Composer logins (1.10.0) | A project-root `auth.json` (gitignored) is inside the project mount and Composer reads it there; only a missing one is a follow-up. Private GitHub repos fall back to a git clone with the gh login |
| Allowlist (1.6.0) | Read at every start from the read-only `.devcontainer/` mount, not baked into the image: edit on the Mac, then reopen or run `sudo /usr/local/sbin/sandbox-firewall.sh` inside; no rebuild. Hosts are looked up in parallel and loaded with one `ipset restore`. CDN hosts (Akamai) rotate addresses, so a download can fail until the firewall is re-run |

`files/init-firewall.sh` is the firewall (installed as `/usr/local/sbin/sandbox-firewall.sh`).
`files/ddev-shim.sh` is installed as `ddev` inside the container.
`files/ddev-relay-client.sh` (read from the read-only `.devcontainer/` mount) sends what the shim can't run to
`files/ddev-relay.pl` on the Mac.

The `ai-devcontainer` skill (`skill/SKILL.md`) drives this end to end: survey, generate, resolve follow-ups,
rebuild, verify, commit.

## DDEV starts and stops with the container

`initializeCommand` runs `files/ensure-ddev.sh` on the Mac before the container starts. It starts the
folder's own DDEV project and every project `docker-compose.yml` links to (`ddev-<name>-db/web`, or
`ddev-router:<name>.…` → project `<name>`). It then leaves a detached watcher that waits for the
container (found by VS Code's `devcontainer.local_folder` label) to stop, waits 90 s in case it's a
rebuild, and runs `ddev stop` on the projects it started. It does not stop a project that was already
running when the container opened, or one that another open dev container needs. A reopen replaces the
watcher and inherits its projects. State and log: `~/.cache/ai-devcontainer/`.


## DDEV commands from inside (1.9.0)

DDEV itself can't run in the container: it needs the Docker socket, which would let Claude start an
unfirewalled container with any Mac folder mounted. Instead, `ensure-ddev.sh` starts one relay per Mac
(`ddev-relay.pl`, macOS's own perl, `127.0.0.1:20090`) and gives each project a random token in
`~/.cache/ai-devcontainer/relay/tokens/<project>.token`, which `docker-compose.yml` mounts at
`/run/ddev-relay/token` in that project's container only. The firewall opens `host.docker.internal:20090`
and nothing else on the Mac. The token picks the project; a request can't name another one.

| Allowed | Notes |
| --- | --- |
| `start`, `stop`, `restart` | No arguments (no `--all`, no other project) |
| `describe`/`status`, `list` | `-j` only |
| `logs` | `-s SERVICE`, `--tail N`, `-t`; no `-f` |
| `snapshot` | create, `--name NAME`, `--list`; `restore NAME\|--latest` asks first |
| `import-db --file=…` | File must resolve (symlinks followed) inside the project; asks first |
| `export-db --file=….sql[.gz]` | New file only, inside the project, not in a dot folder |
| `ee-migrate <staging\|prod> status\|rehearse\|apply --expect=…` (1.13.0) | Runs the approved copy of `.admin-scripts/ee-migrate.sh` on the Mac with Robert's SSH; `rehearse` and `apply` ask first (no extra DDEV snapshot: rehearse takes and restores its own); one run per project at a time |

"Asks first" is a macOS Allow/Deny dialog (Deny after 120 s), then an automatic
`relay-before-<verb>-<time>` snapshot before the command runs. Refused for good: `exec` and `ssh` (the web
container mounts `.ddev` writable, and an `exec-host` hook planted there would run on the Mac at the next
start), `config`, `add-on`, `delete`, `poweroff`, `push`, `pull`. Every request is logged in
`~/.cache/ai-devcontainer/relay/relay.log`. The shared relay copy only moves forward: a repo with a newer
`$VERSION` replaces it and restarts the relay.

**EE migrations (1.13.0).** `ee-migrate.sh` (runner 1.6.0+) hands `staging`/`prod` commands to the relay
itself, so Claude runs `.admin-scripts/ee-migrate.sh staging rehearse` as on the Mac. The container can edit
that script, so the relay never runs the repo's file. It runs `~/.cache/ai-devcontainer/relay/approved/<project>/ee-migrate.sh`,
and only while the repo's file is byte-identical to it. Approve in a Mac terminal (it reads the answer from
`/dev/tty`, so nothing can pipe a yes): `perl ~/.cache/ai-devcontainer/relay/ddev-relay.pl --approve-ee-migrate [project…]`
shows the diff against the last approved copy, whether the logic matches the kit template, and the site
config block. Relay runs keep their stamps in `~/.cache/ai-devcontainer/relay/ee-migrate-stamps/<project>/`,
out of the container's reach, because a forged rehearsal stamp would unlock `prod apply`. Stamps from Mac
terminal runs don't count for relay runs, or the other way round. The relay also refuses while any symlink sits in
`.admin-scripts/` or `.admin-scripts/.ee-migrate/`, since the dump it downloads is written there. Tests:
`test-ddev-relay.sh`, `test-ddev-shim.sh`.
