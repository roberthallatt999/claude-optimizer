# Runbook: Enclave sandbox

Run Claude Code for one project in Eclipse Enclave, with the same allow lists the dev container
would use. Enclave keeps its project settings outside the repo, so Claude can't change them.
Background: [Sandbox guide → Enclave](../guides/sandbox.md#enclave).

## Dev container or Enclave?

| | Dev container | Enclave |
| --- | --- | --- |
| Editor | VS Code attached to the container | Your usual terminal and editor |
| Block list | Yes; a block beats every allow | No (blocked hosts are only left off the list) |
| Tokens | Any integration's, added by the proxy | GitHub only, through Enclave's gateway |
| Ask for a domain from inside | `sandbox-domains allow` → Mac dialog | No: check Enclave's log, add it, refresh |
| Guardrail files read-only | Each file | Folders only (`.claude/hooks`, `.git/hooks`, `.ddev`, `.devcontainer`) |
| DDEV commands from inside | Through the relay | Not set up by ai-config |

Pick Enclave for quick, terminal-first sessions; the dev container when you need more than GitHub
tokens, a block list, or DDEV.

## Before you start (once per Mac)

| Need | Check |
| --- | --- |
| Enclave installed | `enclave --help` |
| Docker or Podman, running | `docker info` |
| ai-config installed, profile set | `ai-config --help`, `~/.claude/skills/noslop/scripts/profile.sh` |
| GitHub token in Enclave's store | `enclave auth --help` (Enclave's own login flow) |

## Set up a project

```sh
cd ~/sites/my-project
ai-config --sandbox=enclave --project=.
```

1. Read the `Sandbox:` lines. `!` lines name what Enclave can't do for this project (tokens other
   than GitHub, blocked hosts, Playwright).
2. The output ends with "Enclave validated it". If Enclave rejected the config, ai-config rolled it
   back and says why.
3. Start Claude: `enclave --tool claude`.

ai-config wrote, outside the repo:

- `~/Library/Application Support/org.eclipse.enclave/config/projects/<hash>/config.json`
  (`allow_domains`, `add_readonly_dirs`, `features`);
- `…/patches/claude/settings.json` (the safety hook and deny rules);
- `…/ai-config-owned.json` (what ai-config wrote, so your own entries are kept).

In the repo it only leaves `.claude/ai-config/enclave.json`, a marker that keeps the choice sticky.

## Choose what it can reach

Same settings as the dev container: the profile's `devcontainer_*` keys and `[sandbox]` in
`ai-config.conf` (see the [dev container runbook](devcontainer.md#choose-what-it-can-reach)).
After a change:

```sh
ai-config --refresh --project=.
```

New hosts are listed and asked about, because Claude can edit `ai-config.conf` inside Enclave.
Answer `y`, or rerun with `--force` once you've checked them.

## A site is blocked

1. On the Mac: `enclave network log --verdict deny` shows what was refused.
2. Add the host under `[sandbox]` (`hosts = api.example.com`), then `ai-config --refresh`.
3. Restart the session, or `enclave network apply` for a running gateway.

`enclave network add-domain <name> --global` also works, but applies to every project.

## Keep it current

`ai-config --refresh --project=.` after ai-config or profile changes. Your own edits to Enclave's
project config are kept; ai-config replaces only the entries it wrote last time.

## Stop using it

```sh
ai-config --refresh --sandbox=none --project=.    # stops updating; deletes nothing
```

To remove the policy, delete the project's folder under
`~/Library/Application Support/org.eclipse.enclave/config/projects/` (find it with
`enclave config --json`, `.project.hash`).
