# Enclave, step by step

This runs Claude Code for one project in Eclipse Enclave, with the same allow list a dev container would use.
Enclave keeps its settings outside the repository, so Claude can't change them. Background:
[Sandboxes](../guides/sandbox.md).

## Enclave or the dev container?

| | Dev container | Enclave |
|---|---|---|
| Editor | VS Code, attached to the container | Your usual Terminal and editor |
| Block list | Yes | No: a blocked site is just left off the list |
| Tokens available inside | Any integration's | GitHub only |
| Ask for a site from inside | Yes, with a dialog on the Mac | No: check Enclave's log, add the site, refresh |
| Safety files locked | Each file | Folders only |
| `ddev` commands from inside | Yes | No |

Choose Enclave for quick, Terminal-first sessions. Choose the dev container when you need more than a GitHub
token, a block list, or DDEV.

## Once per Mac

Check each of these prints something, not an error.

Enclave:

```bash
enclave --help
```

Docker (or Podman), running:

```bash
docker info
```

Then sign Enclave in to GitHub with its own login. This shows how:

```bash
enclave auth --help
```

## Set up a project

**1. Go to the project folder** (change the path):

```bash
cd ~/sites/my-site
```

**2. Write Enclave's settings:**

```bash
ai-config --sandbox=enclave --project=.
```

**3. Read the lines that start with `Sandbox:`.** `!` lines name what Enclave can't do for this project.

**4. Check the last line says "Enclave validated it".** If Enclave rejected the settings, ai-config undid them
and says why.

**5. Start Claude in Enclave:**

```bash
enclave --tool claude
```

ai-config writes Enclave's settings under `~/Library/Application Support/org.eclipse.enclave/config/projects/`.
Your own entries there are kept. In the project it leaves only `.claude/ai-config/enclave.json`, so it remembers
the choice.

## Choose what it can reach

It uses the same settings as the dev container: your profile's `devcontainer_*` lines and `[sandbox]` in
`ai-config.conf`. See [Choose what it can reach](devcontainer.md#choose-what-it-can-reach). Then refresh:

```bash
ai-config --refresh --project=.
```

New sites are listed and you're asked first, because Claude can edit `ai-config.conf` inside Enclave. Type `y`, or
re-run with `--force` once you've checked them.

## A site is blocked

**1. See what was refused** (on the Mac):

```bash
enclave network log --verdict deny
```

**2. Add the site** under `[sandbox]` in `ai-config.conf`, for example `hosts = api.example.com`. Then refresh:

```bash
ai-config --refresh --project=.
```

**3. Restart the session**, or apply it to a running one:

```bash
enclave network apply
```

## Keep it current

After you update ai-config or your profile:

```bash
ai-config --refresh --project=.
```

## Stop using it

This stops updating Enclave's settings. It deletes nothing:

```bash
ai-config --refresh --sandbox=none --project=.
```

To remove the settings too, find the project's folder:

```bash
enclave config --json
```

Look for `.project.hash`, then delete that folder under
`~/Library/Application Support/org.eclipse.enclave/config/projects/`.
