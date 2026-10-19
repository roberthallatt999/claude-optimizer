---
name: "cps-devcontainer"
description: "Convert a CPS project (or all of them) to a sandboxed VS Code dev container for Claude Code: survey, generate, resolve follow-ups, rebuild, verify, commit."
---

# CPS dev container rollout

Gives projects under `~/Web/code/github.com/canadian-paediatric-society` the Claude sandbox proven on Statements Studio: Claude runs in a VS Code dev container, DDEV keeps running on the Mac, a default-deny firewall limits egress, and the project's guardrails are mounted read-only.

The generator lives in `claude-config-repo/devcontainer-kit/` (`cps-devcontainer.py`, `files/`, `README.md`). Read that README once before starting.

## Where this runs

Claude on the **Mac**, in a plain terminal at the CPS root. Never inside a dev container: `.devcontainer/` is read-only there and there's no Docker. If the current working directory is `/workspace`, stop and say so.

## 1. Survey

```bash
cd ~/Web/code/github.com/canadian-paediatric-society
K=claude-config-repo/devcontainer-kit/cps-devcontainer.py
python3 $K --root . --list
```

Show the table. Ask which projects to convert (AskUserQuestion, multi-select). Recommend starting with a simple one (an EE site such as cpsp, or a Laravel app such as expenses) before the complex ones. Skip `claude-config-repo` and `deployment-workflows` unless asked: they're tooling, not apps. Projects marked `HAS .devcontainer` (Statements Studio) are compared, never overwritten (see step 7).

Convert one project fully, through verification, before starting the next.

## 2. Assess the project

```bash
python3 $K --project <folder>
python3 $K --project <folder> --out ~/devcontainer-preview
```

`+` lines are handled automatically. Each `!` line is a follow-up to resolve. Use the project's `CLAUDE.md`, `.ddev/` files, `.env.example` and README for context. Never read `.env`, `.env.php`, `auth.json` or other secrets: the project's own guardrails forbid it, and the values aren't needed.

## 3. Branch and generate

```bash
cd <folder>
git status --short
git switch -c chore/claude-devcontainer
cd .. && python3 $K --project <folder> --write
```

If the working tree is dirty, ask before branching. `--write` refuses to overwrite an existing `.devcontainer/`. Use `--force` only after showing the user what would be lost.

## 4. Resolve follow-ups

Edit the generated files in `<folder>/.devcontainer/`. Known patterns:

| Follow-up | Resolution |
| --- | --- |
| DDEV mounts something outside the project (a sibling repo) | Mount it read-only in `docker-compose.yml`. Add a writable overlay only for folders the app must write to (Statements Studio: `../../cps:/var/www/cps:ro` + `../../cps/public/uploads:/var/www/cps/public/uploads:rw`). Check the writable folder is gitignored in that repo. |
| `~/.aws`, `~/.ssh` and other credentials | Never mounted. Anything needing them (S3, deploys, SSH) runs on the Mac. |
| DDEV `web_environment` variables | Add only the non-secret ones the app reads from the environment (DB hosts, feature flags, bucket names). Never copy passwords, tokens or keys into `docker-compose.yml`; it gets committed. Set write-path kill switches (e.g. `EE_WRITES_ENABLED`) to `false` in the sandbox. |
| Private Composer repos | Leave them on the allowlist for reads, but `composer install/update` runs on the Mac via DDEV (no auth.json inside). |
| Host-side DDEV commands | Mac only; note them in the project's `.devcontainer/README.md`. |
| MCP server that can't run | Leave it; it fails to connect harmlessly. Note it. |
| Remote MCP server / extra API Claude must reach | Add the host to `allowed-domains.txt` only if the user agrees. |
| No `safety-guard.sh` | Suggest running ai-config on the project; the managed deny/ask rules still apply. |
| Git identity | `GIT_*` comes from the repo's git config. Confirm it's the address the user commits with (roberth@cps.ca). |

## 5. Rebuild

Ask the user to run, in VS Code with the project open: **Dev Containers: Reopen in Container** (first time) or **Rebuild Container**. For DDEV projects, `ddev start` first.

If the Dev Containers CLI is installed (`command -v devcontainer`), Claude can build and check it directly instead:

```bash
devcontainer up --workspace-folder <folder>
devcontainer exec --workspace-folder <folder> <command>
```

## 6. Verify

Run these in the container (via `devcontainer exec`, or ask the user to paste the output). Every row must pass before committing.

| Check | Command | Expected |
| --- | --- | --- |
| Firewall up | last lines of the build log | `Firewall active: example.com blocked, api.anthropic.com reachable.` |
| Internet blocked | `curl -sS -m 5 https://example.com` | fails |
| Allowlist works | `curl -s -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org` | `200` |
| Database (DDEV + PHP) | `mariadb -h db -u db -pdb db -e 'SELECT DATABASE()'` | `db` |
| No sudo escape | `sudo -n iptables -F` | refused |
| No Mac secrets | `ls ~/.aws ~/.ssh; echo ${SSH_AUTH_SOCK:-none}` | missing, `none` |
| No git credentials | in a **VS Code** terminal in the container (the CLI doesn't attach VS Code's Git extension): `env \| grep -cE 'ASKPASS\|VSCODE_GIT_IPC'`; `GIT_TERMINAL_PROMPT=0 git push --dry-run origin HEAD` | `0`; the push fails for lack of credentials |
| Guardrails locked | `touch .devcontainer/x .claude/hooks/x` | `Read-only file system` |
| App runs | the project's test command / build, e.g. `php artisan test`, `npm run build` | same result as on DDEV, apart from expected sandbox differences |
| Claude settings | in `claude`: `/status` | Setting sources include *Enterprise managed settings (file)*; no claude.ai MCP servers |
| Hook | in `claude`: `/hooks` | `safety-guard.sh` under PreToolUse (if the project has it) |

Compare test counts with the same suite on DDEV (`ddev artisan test` etc.). A failure only in the container needs an explanation, either a sandbox restriction or a gap to fix.

### Known fixes (all hit on Statements Studio)

| Symptom | Fix |
| --- | --- |
| Claude Code feature fails: `Node.js and npm are required` | Kit before 2026-10-19 skipped the Node feature when `package.json` wasn't at the root. Add `"ghcr.io/devcontainers/features/node:1": { "version": "<DDEV nodejs_version>" }` or regenerate the preview. |
| Firewall dies after `Fetching GitHub IP ranges...`, DNS `EAI_AGAIN` | The image runs a different firewall script. Compare `md5sum /usr/local/sbin/sandbox-firewall.sh` with `.devcontainer/init-firewall.sh`; rebuild without cache. |
| `SSL is required, but the server does not support it` | The `99-ddev-no-ssl.cnf` line is missing from the Dockerfile. |
| `Access denied … host=db` for the wrong database | `db` alias points at the wrong container; check `external_links`. |
| `Allowed memory size of 134217728 bytes exhausted` | The `memory_limit = -1` line is missing. |
| `Call to undefined function imagewebp()` | GD built without WebP (`libwebp-dev`, `--with-webp`). |
| Xdebug warning on every command | `XDEBUG_MODE: "off"` missing from the environment. |
| A test needs to write into a sibling repo | Add a writable overlay for that folder only (step 4). |
| DB unreachable after `ddev restart`, npm/Composer timing out | `sudo /usr/local/sbin/sandbox-firewall.sh` in the container. |
| Can't save `.devcontainer/` files in the container window | Expected: edit on the Mac. |
| `git push` works from the container over HTTPS | VS Code's Git extension answers the password prompt with the Mac's GitHub login. Kit 1.1.0 blanks `GIT_ASKPASS`/`VSCODE_GIT_*` and turns off `git.terminalAuthentication`; port that into older `.devcontainer/devcontainer.json` files and rebuild. |

## 7. Projects that already have a .devcontainer

Don't regenerate. Generate a preview with `--out` and diff it against the existing folder. Port improvements by hand and keep the project's own customisations. At minimum, copy the kit's `files/init-firewall.sh` over `.devcontainer/init-firewall.sh`: the kit's version resets the default policies, so a re-run no longer blocks GitHub.

## 8. Commit

In the project on the Mac:

- If the project uses `.okf/`, add one line under today's date in `.okf/log.md` and run `bash .claude/scripts/okf-check.sh`.
- `git add .devcontainer` (plus the OKF log, and `.claude/settings.local.json` only if the project tracks it; it's usually gitignored).
- Commit as `chore: add Claude Code dev container`.
- **Never push or open a PR without the user's explicit yes for that action.** Every CPS project's guardrails require per-action approval for publishing.

## 9. Report

End with one table: project, status (converted / verified / skipped / blocked), follow-ups left open. Point out anything the user must do on the Mac (rebuild, push, Composer installs).

## Rules

- Never put secret values into `.devcontainer/` files. They're committed.
- Never mount `~/.aws`, `~/.ssh`, `~/.gitconfig`, `~/.config/gh` or the Docker socket.
- Never widen `allowed-domains.txt` without telling the user why.
- Never loosen the read-only guardrail mounts or the sudoers rule to make something work. Find another way, or ask.
- Follow each project's own `CLAUDE.md` guardrails while working in it.