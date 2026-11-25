# Runbook: Claude Code sandbox

Run a project with Claude Code's own sandbox: its Bash commands run in an OS sandbox (Seatbelt on
macOS, bubblewrap on Linux) with a network allowlist, and nothing else changes. No Docker, no
container, no new editor. The same allow lists as the other two sandboxes. Background:
[Sandbox guide](../guides/sandbox.md); Claude Code's docs: [Sandboxing](https://code.claude.com/docs/en/sandboxing).

## Which sandbox?

| | Claude Code sandbox | Dev container | Enclave |
| --- | --- | --- | --- |
| Setup | One flag | Docker + VS Code | Enclave + Docker |
| What's contained | Bash commands only | Everything Claude runs | Everything Claude runs |
| Network allowlist | Yes (its proxy) | Yes (firewall + proxy) | Yes (gateway) |
| Block list | Yes | Yes | No |
| Tokens kept out of reach | No: commands use your login | Yes | GitHub only |
| Ask for a domain from inside | Claude Code asks you (per host) | `sandbox-domains allow` | No |
| Guardrail files read-only | No (the safety guard asks before edits) | Yes | Folders only |

Use it as the everyday layer on top of the safety guard; switch to the dev container for
client work where tokens or containment matter.

What it does **not** sandbox: Read, Edit, Write, WebFetch and WebSearch (the permission rules and
the safety guard govern those), MCP servers, hooks, and commands you exclude. Tools that ignore
proxy settings (plain `ssh`, most database drivers) can't reach even allowed hosts.

## Before you start

| Need | Check |
| --- | --- |
| Claude Code | `claude --version` |
| macOS | nothing else (Seatbelt is built in) |
| Linux / WSL2 | `sudo apt-get install bubblewrap socat` |
| ai-config installed, profile set | `ai-config --help`, `~/.claude/skills/noslop/scripts/profile.sh` |

## Set up a project

```sh
cd ~/sites/my-project
ai-config --sandbox=claude --project=.
```

It writes the `sandbox` block of `.claude/settings.local.json`:

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "allowedDomains": ["api.anthropic.com", "github.com", "*.example.org", "example.org"],
      "deniedDomains": ["ads.example.org"]
    }
  }
}
```

- `failIfUnavailable`: if the sandbox can't start, Claude Code stops instead of running unsandboxed.
- `allowUnsandboxedCommands: false`: Claude can't retry a blocked command outside the sandbox.
- A leading-dot domain from your settings (`.example.org`) becomes `*.example.org` plus `example.org`.

Start Claude as usual, then run `/sandbox` to see the mode and the lists.

## Choose what it can reach

The same settings as the other sandboxes: the profile's `devcontainer_*` keys and `[sandbox]` in
`ai-config.conf` ([dev container runbook](devcontainer.md#choose-what-it-can-reach)). Then
`ai-config --refresh --project=.`; new hosts are listed and asked about.

Entries you add to `sandbox.network` yourself are kept: ai-config replaces only what it wrote
last time (its record is outside the project, in `~/.cache/ai-devcontainer/claude-sandbox/`).

## A site is blocked

Claude Code asks when a sandboxed command reaches an unlisted host. "Yes, and don't ask again"
saves a `WebFetch(domain:…)` rule to `.claude/settings.local.json`, which also feeds the
allowlist. To make it part of the project's policy, add it under `[sandbox]` instead and refresh.

## Stop using it

```sh
ai-config --refresh --sandbox=none --project=.    # stops updating it
```

Then `/sandbox` → Mode → off, or delete the `sandbox` block from `.claude/settings.local.json`.

## Make it the floor on this Mac (optional)

Project settings can be edited. To make the safety floor impossible to remove for every session
on this Mac, install the managed settings ([below in the guide](../guides/sandbox.md#machine-wide-floor-managed-settings)).
