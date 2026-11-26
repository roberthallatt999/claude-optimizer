# Claude Code sandbox, step by step

This is the lightest sandbox. Claude Code runs its terminal commands in a sandbox built into your computer
(Seatbelt on a Mac, bubblewrap on Linux), and they can reach only the sites you allow. There's no Docker, no
container and no new editor. Background: [Sandboxes](../guides/sandbox.md). Claude Code's own docs:
[Sandboxing](https://code.claude.com/docs/en/sandboxing).

## What it covers

It contains the **commands Claude runs in Terminal**. It doesn't contain file reads and edits, web fetches, MCP
services or hooks. The permission rules and the safety guard look after those, as usual.

Your own logins still work inside, so it doesn't keep tokens out of reach. For that, use the
[dev container](devcontainer.md).

Some tools ignore proxy settings, such as plain `ssh` and most database drivers. Those can't reach even allowed
sites.

## Before you start

On a Mac you need nothing extra. On Linux or WSL, install two tools:

```bash
sudo apt-get install bubblewrap socat
```

## Set up a project

**1. Go to the project folder** (change the path):

```bash
cd ~/sites/my-site
```

**2. Turn on the sandbox:**

```bash
ai-config --sandbox=claude --project=.
```

**3. Start Claude Code** as usual, then type `/sandbox` to see the mode and the allow list.

ai-config writes a `sandbox` section into `.claude/settings.local.json`. It's set up so that:

- if the sandbox can't start, Claude Code stops rather than running without it
- Claude can't retry a blocked command outside the sandbox
- a domain from your settings such as `.example.org` covers `example.org` and all its subdomains

## Choose what it can reach

It uses the same settings as the other sandboxes: your profile's `devcontainer_*` lines and `[sandbox]` in
`ai-config.conf`. See [Choose what it can reach](devcontainer.md#choose-what-it-can-reach). Then refresh. New
sites are listed and you're asked first:

```bash
ai-config --refresh --project=.
```

Sites you add to the `sandbox` section yourself are kept. ai-config replaces only what it wrote last time.

## A site is blocked

Claude Code asks you when a command tries to reach a site that isn't on the list. "Yes, and don't ask again" saves
it for this project. To make it part of the project's settings for everyone, add it under `[sandbox]` in
`ai-config.conf` instead, and refresh.

## Stop using it

This stops ai-config updating the sandbox:

```bash
ai-config --refresh --sandbox=none --project=.
```

Then turn it off in Claude Code: type `/sandbox` and set the mode to off. You can also delete the `sandbox`
section from `.claude/settings.local.json`.

## Make the safety rules permanent on this computer (optional)

Project settings can be edited. To install rules that no project or user setting can remove, see
[A floor for the whole computer](../guides/sandbox.md#a-floor-for-the-whole-computer).
