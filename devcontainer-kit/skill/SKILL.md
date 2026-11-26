---
name: "ai-devcontainer"
description: "Give a project (or several) a sandboxed VS Code dev container for Claude Code with ai-config --devcontainer: assess, generate, resolve follow-ups, rebuild, verify, commit. Also reviews existing dev containers against the codebase they run and suggests per-project [vscode] / [sandbox] changes (\"review the dev containers\", \"what should this container have\"). Optional; for projects that want egress limits and tokens kept on the Mac."
---

# Dev container sandbox rollout

Gives a project the Claude sandbox from ai-config's `devcontainer-kit/`: Claude runs in a VS Code dev container, DDEV (if any) keeps running on the Mac, a default-deny firewall and an egress proxy limit what it can reach, tokens stay in the Mac's Keychain, and the project's guardrails are mounted read-only. It's optional: a project without it is set up exactly as before.

What a container may reach comes from the active ai-config profile (`devcontainer_*` keys), the project's `[sandbox]` section in `ai-config.conf`, and the integrations they switch on. Read `docs/guides/sandbox.md` in the ai-config checkout (`$AI_CONFIG_REPO`) once before starting.

## Where this runs

Claude on the **Mac**, in a plain terminal. Never inside a dev container: `.devcontainer/` is read-only there and there's no Docker. If the current working directory is `/workspace`, stop and say so.

## 1. Assess

```bash
K="$AI_CONFIG_REPO/devcontainer-kit/ai-devcontainer.py"
python3 "$K" --root <folder-of-projects> --list      # several projects
python3 "$K" --project <folder>                       # one: + handled, ! follow-ups
python3 "$K" --project <folder> --out ~/devcontainer-preview
```

If several, ask which to convert (AskUserQuestion, multi-select) and recommend a simple one first. Convert one fully, through verification, before the next. Check the `Profile:` and `Integrations:` lines: if the profile is wrong, fix the folder map (`~/.config/ai-config/folders`) or `profile =` under `[options]`, not the generated files.

Use the project's `CLAUDE.md`, `.ddev/` files, `.env.example` and README for context. Never read `.env`, `auth.json` or other secrets.

## 2. Branch and generate

```bash
cd <folder> && git status --short && git switch -c chore/claude-devcontainer
ai-config --devcontainer --project=.
```

This deploys or refreshes the project's Claude config, then writes `.devcontainer/`. If the working tree is dirty, ask before branching. A `.devcontainer/` that ai-config didn't write is left alone; `--force` replaces it after backing it up to `.claude/ai-config/backups/`. Show the user what would change first (`--out` preview and a diff).

Change what it reaches through settings, not by editing generated files:

| Want | Where |
| --- | --- |
| A service (Plausible, Cloudflare, Mailtrap, Stripe, Doppler, …) | `integrations = +name` under `[sandbox]`, or `devcontainer_integrations` in the profile |
| The organization's own domains | `devcontainer_domains` / `devcontainer_hosts` in the profile, or `domains` / `hosts` under `[sandbox]` |
| Keep a host out | `block = name` under `[sandbox]` |
| A service not built in | a private integration file in `~/.config/ai-config/devcontainer/integrations/<name>.conf` |
| A one-off domain | `sandbox-domains allow <name>` inside (asks on the Mac), or `domains.conf` `[allow]` on the Mac |

Then `ai-config --refresh --project=.`: files you haven't edited are rewritten, edited ones are kept and the new version staged in `.claude/ai-config/pending/.devcontainer/`.

## 3. Resolve follow-ups

| Follow-up | Resolution |
| --- | --- |
| DDEV mounts something outside the project | Mount it read-only in `docker-compose.yml`; a writable overlay only for folders the app must write, and check that folder is gitignored there. |
| `~/.aws`, `~/.ssh` and other credentials | Never mounted. Anything needing them runs on the Mac. |
| DDEV `web_environment` variables | Add only non-secret ones the app reads from the environment. Never copy passwords, tokens or keys into `docker-compose.yml`; it's committed. |
| Private Composer repos | An `auth.json` next to `composer.json` (gitignored) works inside; otherwise run `composer install` on the Mac via DDEV. |
| Remote MCP server / extra API | Allow its host only if the user agrees (`[sandbox] hosts` or `domains.conf`). |
| Integration left out ("needs …") | Set the named key in the profile or under `[sandbox]`. |
| Git identity | `GIT_*` comes from the repo's git config; confirm it's the address the user commits with. |

## 4. Rebuild

The user runs, in VS Code with the project open: **Dev Containers: Reopen in Container** (first time) or **Rebuild Container**. After any kit change to compose, mounts or the Dockerfile, use **Rebuild and Reopen in Container**: plain Reopen restarts the old container with its old mounts.

Once per Mac, the GitHub token goes in the Keychain, in the user's own terminal (the README in `.devcontainer/` names the item, `<profile>-devcontainer-github`):

```sh
security add-generic-password -U -s <item> -a "$USER" -w
```

With the Dev Containers CLI (`command -v devcontainer`), Claude can build and check it directly: `devcontainer up --workspace-folder <folder>`, `devcontainer exec --workspace-folder <folder> <command>`.

## 5. Verify

Every row must pass before committing.

| Check | Command (inside) | Expected |
| --- | --- | --- |
| Firewall up | last lines of the start log | `Firewall active: example.com blocked, api.anthropic.com reachable.` |
| Internet blocked | `curl -sS -m 5 https://example.com` | fails |
| Allowlist works | `curl -s -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org` | `200` |
| Domain request | `sandbox-domains allow example.net "test"`, click Deny on the Mac | refused, nothing written |
| Block | `sandbox-domains block registry.npmjs.org`, then the curl above | `403`; then remove it from `domains.conf` on the Mac |
| Database (DDEV + PHP) | `mariadb -h db -u db -pdb db -e 'SELECT DATABASE()'` | the site's database |
| No sudo escape | `sudo -n iptables -F` | refused |
| No Mac secrets | `ls ~/.aws ~/.ssh; echo ${SSH_AUTH_SOCK:-none}` | missing, `none` |
| Tokens are placeholders | `echo "$GH_TOKEN"` | `ai-egress-placeholder` |
| GitHub via the proxy | `gh auth status`, then `git push --dry-run origin HEAD` | logged in (GH_TOKEN); dry run succeeds over HTTPS |
| Guardrails locked | `touch .devcontainer/x .claude/hooks/x` | `Read-only file system` |
| App runs | the project's tests / build | same result as on the Mac, apart from expected sandbox differences |
| Claude settings | in `claude`: `/status`, `/hooks` | managed settings listed; `safety-guard.sh` under PreToolUse |

### Known fixes

| Symptom | Fix |
| --- | --- |
| Claude Code extension never appears | Its publisher's `*.gallerycdn.vsassets.io` hosts are missing: refresh, reopen. If it worked before, the CDN rotated: `sudo /usr/local/sbin/sandbox-firewall.sh`. |
| `SSL is required, but the server does not support it` | The `99-ddev-no-ssl.cnf` Dockerfile line is missing. |
| DB unreachable after `ddev restart`, npm/Composer timing out | `sudo /usr/local/sbin/sandbox-firewall.sh`. |
| `git push` asks for a username, or `gh` isn't logged in | Check the initializeCommand output ("tokens injected for: …"); store the missing Keychain item and reopen. A TLS error for github.com: `sudo /usr/local/sbin/sandbox-trust-ca.sh`. |
| `sandbox-domains`: relay isn't answering | Reopen the container (`ensure-relay.sh` starts it); log in `~/.cache/ai-devcontainer/relay/relay.log` on the Mac. |
| Dev server page spins on the Mac, `curl` inside works | Vite on `[::1]` only; `NODE_OPTIONS=--dns-result-order=ipv4first` is in compose: recreate the container. |
| `npm ci` fails with `EACCES` on `node_modules` | `sudo /usr/local/sbin/sandbox-own-volumes.sh`. |

## 6. Commit

On the Mac: `git add .devcontainer` (plus `ai-config.conf` if it changed), commit as `chore: add Claude Code dev container`. **Never push or open a PR without the user's explicit yes for that action.**

## Review an existing container

For projects that already have a container: find what the codebase needs that the kit's rules
missed, and suggest per-project changes. Read-only until the user approves a suggestion.

### 1. Gather facts

```bash
K="$AI_CONFIG_REPO/devcontainer-kit/ai-devcontainer.py"
python3 "$K" --project <folder> --json                      # one project
python3 "$K" --root <folder-of-projects> --json --only a,b  # several, as a list
```

The fact sheet holds names only: the detected stack and runtimes, integrations, the extensions
and settings the kit would generate next to what `devcontainer.json` has now, allowed hosts,
`[vscode]` / `[sandbox]` from `ai-config.conf`, `.vscode/settings.json` overrides, config files in
use (`signals`), template folders with file counts per type, dependency names, and follow-ups.
Add the project's `CLAUDE.md` and README. Never open secret files for a review.

### 2. Compare

The container first:

- `container.written_by_kit` false, or `kit_version_on_disk` older than `kit_version`: it predates
  the current kit. Suggest a refresh (`ai-config --refresh --devcontainer`) before anything else;
  many other findings go away with it.
- `edited_files_with_pending_updates`: kit updates waiting on a file someone edited. Say which.
- `extensions.missing_on_disk` / `settings.differs_on_disk`: drift between the kit's choice and
  the file. Usually a refresh; if the file was edited on purpose, the change belongs in `[vscode]`.
- `workspace_overrides` with `source: kit`: `.vscode/settings.json` undoes the container's
  choice. Suggest removing the key there (gitignored in most projects, so no commit), or moving a
  deliberate one into `[vscode]`.

Then the codebase against the extensions. Suggest only what a fact supports, and check each
extension ID on the Marketplace before suggesting it:

| Fact | Suggest (when not already in `extensions.generated`) |
| --- | --- |
| `signals.phpstan` | `sanderronde.phpstan-vscode` |
| `signals.psalm` | `getpsalm.psalm-vscode-plugin` |
| `signals.pint` without `laravel/pint` in dependencies | `open-southeners.laravel-pint`, and `php: editor.defaultFormatter` |
| `signals.phpcs` without `squizlabs/php_codesniffer` | `obliviousharmony.vscode-php-codesniffer` (it needs phpcs installed) |
| `signals.php-cs-fixer` | `junstyle.php-cs-fixer` |
| `signals.phpunit`, or `pestphp/pest` | `recca0120.vscode-phpunit` |
| `signals.stylelint` | `stylelint.vscode-stylelint` |
| `signals.markdownlint` | `davidanson.vscode-markdownlint` |
| `signals.vitest` / `jest` / `playwright` | `vitest.explorer` / `orta.vscode-jest` / `ms-playwright.playwright` |
| `.blade.php` templates outside a Laravel stack (Sage, Acorn) | `onecentlin.laravel-blade`, `shufo.vscode-blade-formatter` |
| `.twig` templates outside Craft | `mblode.twig-language-2`, `twig: editor.formatOnSave = false` |
| `.vue` / `.svelte` / `.astro` files the stack didn't catch | `vue.volar` / `svelte.svelte-vscode` / `astro-build.astro-vscode` |
| `signals.github-actions` | `github.vscode-github-actions` |

Settings worth suggesting come from the codebase too: the formatter a repo standardizes on,
format on save off for template types its formatter mangles, `files.associations` for template
folders under unusual paths. Never suggest personal preferences (rulers, wrapping, themes): they
belong in the user's own settings, which VS Code applies in every container already.

Then what the container reaches:

- An integration whose hosts nothing in the codebase or its config mentions (search for the host
  name, never in secret files): suggest `integrations = -name` under `[sandbox]`.
- A dependency that downloads at install or run time (Playwright browsers, Puppeteer, `sharp`,
  Cypress, a private Composer or npm registry) with no matching host in `allowed_hosts` or
  `domains_conf`: suggest the integration or the `hosts` line, with the reason.
- A host in `domains_conf.allow` that a `[sandbox]` line or an integration would cover better.

Suggest narrowing as readily as widening.

### 3. Report

One section per project: a one-line verdict ("current, two additions", or "predates kit 2.x:
refresh first"), a table of findings (what, why, which fact), then the exact lines for
`ai-config.conf`:

```ini
[vscode]
extensions = +sanderronde.phpstan-vscode, +stylelint.vscode-stylelint
php: editor.defaultFormatter = "open-southeners.laravel-pint"

[sandbox]
integrations = -mailtrap
```

For several projects, end with the suggestions that came up in more than one. Those are
candidates for a kit rule in `vscode_tooling()` or `allowed_groups()` in the ai-config repo, so
every project gets them without a `[vscode]` line. Offer that as a separate change.

### 4. Apply what the user approves

Per project, only the approved lines: edit `ai-config.conf` (editing it asks first), then
`ai-config --refresh --project=<folder>`. The refresh lists any new host, including a new extension
publisher's download hosts, and asks; say why before the user answers. Then **Dev Containers:
Rebuild and Reopen in Container**. Commit `ai-config.conf` (and `.devcontainer/` if the refresh
changed it) on the Mac as `chore(devcontainer): <what changed>`. Never edit generated files to apply
a suggestion, and never push without the user's explicit yes for that push.

## Rules

- Ship `.devcontainer/` changes to the main branch from the Mac promptly, and don't stack feature work on them: inside the container `.devcontainer/` is read-only, so a checkout between commits that differ there stops halfway.
- Never put secret values into `.devcontainer/` files. They're committed.
- Never mount `~/.aws`, `~/.ssh`, `~/.gitconfig`, the Mac's `~/.config/gh`, the Docker socket, or `~/.cache/ai-devcontainer/egress/projects/*/credentials.env` into the claude service.
- Never widen what the sandbox reaches without telling the user why; prefer an integration or `[sandbox]` setting over editing generated files.
- Never loosen the read-only guardrail mounts or the sudoers rule to make something work. Find another way, or ask.
- Follow each project's own `CLAUDE.md` guardrails while working in it.
