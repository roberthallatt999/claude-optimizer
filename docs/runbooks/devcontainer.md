# Runbook: dev container sandbox

Run Claude Code for one project inside a VS Code dev container. The container reaches only the
sites you allow, holds no real tokens, and can't edit its own guardrails. Background and settings:
[Sandbox guide](../guides/sandbox.md).

## Before you start (once per Mac)

| Need | Check |
| --- | --- |
| Docker Desktop, running | `docker info` |
| VS Code + Dev Containers extension | `code --list-extensions \| grep ms-vscode-remote.remote-containers` |
| `python3` | `python3 --version` |
| ai-config installed | `ai-config --help` |
| Your profile set (optional, recommended) | `~/.claude/skills/noslop/scripts/profile.sh` |

Store the GitHub token the sandbox uses, in **your own terminal** (it asks for the token without
showing it). Use a fine-grained token limited to the repos you work on: Contents, Pull requests and
Actions read/write.

```sh
security add-generic-password -U -s <profile>-devcontainer-github -a "$USER" -w
```

`<profile>` is the project's profile name, or `ai` when no profile applies (item
`ai-devcontainer-github`). The project's `.devcontainer/README.md` names the exact item.

Tokens for other services come from the Keychain items their integrations name (`plausible-api`,
`cloudflare-api-<profile>`). Set those up the way each skill describes; skip any you don't use.

## Set up a project

```sh
cd ~/sites/my-project
ai-config --devcontainer --project=.
```

1. Read the `Sandbox:` lines: `+` is handled, `!` needs you (a missing setting, a mount outside
   the project, a private Composer repo).
2. Commit `.devcontainer/` and `ai-config.conf` (created if the project had none).
3. In VS Code: **Dev Containers: Reopen in Container**. The first build takes a few minutes.
4. In the container terminal: `claude`, and sign in once (it persists).

## Choose what it can reach

| Want | Do |
| --- | --- |
| A service for every project in a context | Add it to `devcontainer_integrations` in your profile |
| A service for this project only | `integrations = +stripe` under `[sandbox]` in `ai-config.conf` |
| Drop one the profile adds | `integrations = -mailtrap` |
| Your organization's sites | `devcontainer_domains` / `devcontainer_hosts` in the profile |
| One client domain | `domains = .client.example` or `hosts = api.client.example` under `[sandbox]` |
| Keep a host out | `block = ads.example.com` under `[sandbox]` |

Then `ai-config --refresh --project=.`. If the change lets the sandbox reach a new host, or send a
token to one, the refresh lists it and asks; answer `y`. Then **Rebuild Container**.

## Daily use

| Task | Where | How |
| --- | --- | --- |
| Edit, test, build, commit | Container | As usual |
| Allow a site for now | Container | `sandbox-domains allow api.example.com "why"`, then click Allow on the Mac |
| Block a site | Container | `sandbox-domains block ads.example.com` (no dialog) |
| See the lists | Container | `sandbox-domains list` |
| `ddev start/stop/logs/snapshot` | Container | As usual: the relay runs them on the Mac |
| `ddev ssh`, deploys, anything with SSH or production | Mac terminal | Never from inside |
| `git push`, `gh pr merge` | Container | Claude asks first, every time |

## Keep it current

| When | Do |
| --- | --- |
| ai-config was updated | `ai-config --refresh --project=.`, then **Rebuild and Reopen in Container** |
| A file in `.devcontainer/` was edited by hand | The refresh keeps it; the new version is in `.claude/ai-config/pending/.devcontainer/` to compare |
| Claude Code needs updating | **Rebuild Container** without cache |

Plain **Reopen in Container** keeps the old container and its old mounts; use Rebuild after any
kit change.

## Check it works

Inside the container:

```sh
curl -sS -m 5 https://example.com                      # fails: not allowed
curl -s -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org   # 200
echo "$GH_TOKEN"                                       # ai-egress-placeholder
gh auth status                                         # logged in (GH_TOKEN)
touch .devcontainer/x                                  # Read-only file system
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| A site is blocked | `sandbox-domains allow <name>`, or add it to `.devcontainer/domains.conf` on the Mac |
| `sandbox-domains`: relay isn't answering | Reopen the container; Mac log: `~/.cache/ai-devcontainer/relay/relay.log` |
| `gh`/`git push` not logged in | The container's start log lists missing Keychain items; store it, reopen |
| An integration "left out" | It needs a setting from the profile (`requires`); set it there |
| "This refresh widens the sandbox" with nobody to answer | Rerun in a terminal, or with `--force` once you've checked the list |
| Relay "key already belongs to …" | Two folders shared a key (a `.devcontainer/` from before project keys carried a hash): refresh this project to get its own |
| Philter withholds output | Philter runs on the Mac: `/scrub` shows its state |

## Stop using it

```sh
ai-config --refresh --sandbox=none --project=.    # stops updating it; deletes nothing
```

Delete `.devcontainer/` yourself if you no longer want it, then reopen the folder locally.
