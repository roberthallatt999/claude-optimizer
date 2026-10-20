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
| `.ddev/config.yaml` + PHP | Joins `ddev_default`; `ddev-<name>-db` as host `db`; MariaDB client with TLS off; `initializeCommand` checks the DB is running |
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
| Preview (1.3.0) | DDEV PHP sites: `ddev-router` linked as `<name>.<project_tld>` so BrowserSync/Vite can proxy the site; BrowserSync (3000, 3001) and Vite (5173) ports forwarded to the Mac |

`files/init-firewall.sh` is the firewall (installed as `/usr/local/sbin/sandbox-firewall.sh`).
`files/ddev-shim.sh` is installed as `ddev` inside the container.

The `cps-devcontainer` skill drives this end to end: survey, generate, resolve follow-ups,
rebuild, verify, commit.
