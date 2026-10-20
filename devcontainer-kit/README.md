# devcontainer-kit

Gives a project a sandboxed VS Code dev container for Claude Code, following the pattern
proven on Statements Studio (October 2026). Run it on the Mac, never inside a container.

```bash
cd ~/Web/code/github.com/canadian-paediatric-society
K=claude-config-repo/devcontainer-kit/cps-devcontainer.py

python3 $K --root . --list                      # one line per project
python3 $K --project cps                        # report: automatic vs manual follow-ups
python3 $K --root . --out ~/devcontainer-preview  # preview every project's files
python3 $K --project cps --write                # create cps/.devcontainer/
python3 $K --project cps --write --force        # overwrite an existing one (loses edits)
```

What it decides per project:

| Signal | Result |
| --- | --- |
| `.ddev/config.yaml` + PHP | Joins `ddev_default`; `ddev-<name>-db` as host `db`; MariaDB client with TLS off; `initializeCommand` runs `ensure-ddev.sh` on the Mac (below) |
| `.ddev` overrides | `external_links` carried over; mounts outside the project flagged; `~/.aws`/`~/.ssh` never carried |
| DDEV add-ons | `ddev-<name>-<addon>` reachable as `<addon>` |
| `.ddev/commands/web/*` | Run through the `ddev` shim with `/var/www/html` → `/workspace` (so `ddev ee`, `ddev mcp-serve`, `ddev wp` work) |
| PHP version | DDEV `php_version`, else composer.json, else 8.3; memory limit off, Xdebug off, GD with WebP |
| Node only | `javascript-node` image (user `node`); dev-server ports forwarded |
| Any other image | Node feature added (the Claude Code feature installs through npm); version from DDEV `nodejs_version`, `.nvmrc` or `engines`, else LTS. `package.json` is looked for at the root, the DDEV docroot, then `public/` |
| `requirements.txt` | Python image or feature, PyPI allowed |
| composer.json repos, Craft, `.mcp.json` context7 | Added to `allowed-domains.txt`; private repos flagged (no auth.json inside) |
| `.claude/hooks/safety-guard.sh` | Re-registered in root-owned managed settings |
| Guardrail files that exist | Mounted read-only, along with `.devcontainer/` itself |
| Shell history (always) | `command-history` volume at `/commandhistory`; bash and zsh write to it after every command, so it survives rebuilds |
| GitHub (always, 1.3.0) | git push/pull and `gh` work inside through one `gh auth login`, kept on the `cps-gh-config` volume every CPS container shares; git's GitHub helper is `gh auth git-credential` and SSH remotes are rewritten to HTTPS inside only. Use a fine-grained token scoped to the org's repos. Managed settings still ask before `git push`, PR create/merge/edit, `gh workflow run`, `gh run rerun` and `gh api`, and deny `gh auth token`, `gh repo delete` and reading `~/.config/gh` |
| Mac credentials (always) | None inside: `SSH_AUTH_SOCK`, `GIT_ASKPASS` and VS Code's `VSCODE_GIT_*` blanked, `GIT_TERMINAL_PROMPT=0`, `git.terminalAuthentication` and `github.gitAuthentication` off. Pair with the Mac user settings `dev.containers.copyGitConfig: false` and `dev.containers.gitCredentialHelperConfigLocation: "none"` |
| `package.json` (1.3.0) | `node_modules` next to it is a per-project Docker volume, so Linux and macOS native modules (sharp, esbuild) don't overwrite each other; run `npm ci` in the container once. Owned by the container user via the root-owned, argument-free `sandbox-own-volumes.sh` |
| Preview (1.3.0) | DDEV PHP sites: `ddev-router` linked as `<name>.<project_tld>` so BrowserSync/Vite can proxy the site; BrowserSync (3000, 3001) and Vite (5173) get labels and are auto-forwarded once a dev server listens (1.4.0: no static `forwardPorts`, which held the Mac's ports and stopped DDEV's router starting other projects) |
| VS Code tooling (1.4.0) | Every container: Claude Code (shares the CLI's login, so no second sign-in), REST Client, EditorConfig, Prettier, Error Lens, Git Graph, DotENV. By stack: Intelephense + Xdebug (PHP), Laravel Pint as the PHP formatter where `laravel/pint` is required, PHP CodeSniffer where `squizlabs/php_codesniffer` is, Laravel + Blade (Laravel), ExpressionEngine + Apache (EE), Twig (Craft), Tailwind, Alpine, ESLint. Format on save touches only changed lines and Prettier needs a repo config; EE templates (`system/user/templates/**`) map to the ExpressionEngine language with format-on-save off. Extensions the container can't download (the gallery CDN is outside the firewall) are fetched by VS Code on the Mac and copied in |

`files/init-firewall.sh` is the firewall (installed as `/usr/local/sbin/sandbox-firewall.sh`).
`files/ddev-shim.sh` is installed as `ddev` inside the container.

The `cps-devcontainer` skill drives this end to end: survey, generate, resolve follow-ups,
rebuild, verify, commit.

## DDEV starts and stops with the container

`initializeCommand` runs `files/ensure-ddev.sh` on the Mac before the container starts. It starts the
folder's own DDEV project and every project `docker-compose.yml` links to (`ddev-<name>-db/web`, or
`ddev-router:<name>.…` → project `<name>`). It then leaves a detached watcher that waits for the
container (found by VS Code's `devcontainer.local_folder` label) to stop, waits 90 s in case it's a
rebuild, and runs `ddev stop` on the projects it started. It does not stop a project that was already
running when the container opened, or one that another open dev container needs. A reopen replaces the
watcher and inherits its projects. State and log: `~/.cache/cps-devcontainer/`.

