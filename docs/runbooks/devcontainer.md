# Dev container, step by step

This runs Claude Code for one project inside a VS Code container. The container reaches only the sites you
allow, holds no real tokens, and can't change its own safety rules. Background: [Sandboxes](../guides/sandbox.md).

## Once per Mac

**1. Check you have what's needed.** Each command should print something, not an error.

Docker Desktop, running:

```bash
docker info
```

The VS Code Dev Containers extension:

```bash
code --list-extensions | grep ms-vscode-remote.remote-containers
```

Python 3:

```bash
python3 --version
```

**2. Store a GitHub token in your Mac's Keychain.** The container uses it to push and open pull requests, but
never sees it: it's added on the way out.

Create a **fine-grained** token on GitHub, limited to the repositories you work on, with read and write access
to Contents, Pull requests and Actions. Then run this in your own Terminal, not through Claude. Replace
`<profile>` with your [profile](../guides/profiles.md) name, or `ai` if you don't use profiles:

```bash
security add-generic-password -U -s <profile>-devcontainer-github -a "$USER" -w
```

It asks for the token and doesn't show what you type. The project's `.devcontainer/README.md` names the exact
Keychain item once it's created.

Other services' tokens (Plausible, Cloudflare) are set up the way each skill describes. Skip any you don't use.

## Set up a project

**1. Go to the project folder** (change the path):

```bash
cd ~/sites/my-site
```

**2. Write the container:**

```bash
ai-config --devcontainer --project=.
```

**3. Read the lines that start with `Sandbox:`.** `+` means handled. `!` means it needs you, for example a missing
setting.

**4. Commit** `.devcontainer/` and `ai-config.conf` (it's created if the project had none).

**5. Open it.** In VS Code, press `Cmd+Shift+P` and choose **Dev Containers: Reopen in Container**. The first
build takes a few minutes.

**6. Start Claude** in the container's terminal, and sign in once (it remembers you):

```bash
claude
```

## Choose what it can reach

| You want | Do this |
|---|---|
| A service for every project in a context | Add it to `devcontainer_integrations` in your profile |
| A service for this project only | `integrations = +stripe` under `[sandbox]` in `ai-config.conf` |
| Drop a service the profile adds | `integrations = -mailtrap` under `[sandbox]` |
| Your organization's sites | `devcontainer_domains` in your profile |
| One client's site | `domains = .client.example` under `[sandbox]` |
| Keep a site out | `block = ads.example.com` under `[sandbox]` |

Then refresh. If the change reaches a new site, it lists it and asks; type `y`:

```bash
ai-config --refresh --project=.
```

Then, in VS Code, choose **Dev Containers: Rebuild Container**.

## Everyday use

| Task | Where | How |
|---|---|---|
| Edit, test, build, commit | Container | As usual |
| Allow a site | Container | `sandbox-domains allow api.example.com "why"`, then click Allow on the Mac |
| Block a site | Container | `sandbox-domains block ads.example.com` |
| See the lists | Container | `sandbox-domains list` |
| `ddev start`, `stop`, `logs`, `snapshot` | Container | As usual. They run on the Mac for you |
| `ddev ssh`, deploys, anything touching production | **Mac** Terminal | Never from inside the container |
| `git push`, `gh pr merge` | Container | Claude asks you first, every time |

## Keep it current

After you update ai-config, refresh the project:

```bash
ai-config --refresh --project=.
```

Then choose **Dev Containers: Rebuild and Reopen in Container**. A plain Reopen keeps the old container.

To get a newer Claude Code, choose **Dev Containers: Rebuild Container Without Cache**.

A file in `.devcontainer/` you edited by hand is kept. The new version waits in
`.claude/ai-config/pending/.devcontainer/` for you to compare.

## Check it works

Run these in the container's terminal:

| Command | Expected result |
|---|---|
| `curl -sS -m 5 https://example.com` | Fails: the site isn't allowed |
| `curl -s -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org` | `200` |
| `echo "$GH_TOKEN"` | `ai-egress-placeholder`, not a real token |
| `gh auth status` | Logged in |
| `touch .devcontainer/x` | `Read-only file system` |

## Problems

| What you see | What to do |
|---|---|
| A site is blocked | `sandbox-domains allow <site>`, or add it to `.devcontainer/domains.conf` on the Mac |
| `sandbox-domains` gets no answer | Reopen the container. Log: `~/.cache/ai-devcontainer/relay/relay.log` |
| `gh` or `git push` isn't logged in | The container's start-up output lists missing Keychain items. Add it, then reopen |
| An integration is "left out" | It needs a setting from your profile. Add it there |
| "This refresh widens the sandbox" and no one to answer | Run the refresh in a Terminal, or add `--force` once you've checked the list |
| "key already belongs to …" | Two folders shared a key. Refresh this project to give it its own |
| Philter withholds output | Philter runs on the Mac. Type `/scrub` to see its state |

## Stop using it

This stops updating the container. It deletes nothing:

```bash
ai-config --refresh --sandbox=none --project=.
```

If you no longer want the container, delete `.devcontainer/` yourself, then reopen the folder normally in VS Code.
