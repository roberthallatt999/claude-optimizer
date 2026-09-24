---
paths:
  - "**/.github/**"
  - "**/.gitlab-ci.yml"
  - "**/.ddev/**"
  - "**/{Dockerfile,Envoy.blade.php,Procfile,deploy.php}"
  - "**/{docker-compose,fly,vercel,netlify,wrangler,firebase,railway}*.{yml,yaml,json,toml,jsonc}"
  - "**/{deploy,scripts,bin,infra,terraform,ansible,k8s,helm}/**"
  - "**/*.{tf,sql,sql.gz}"
  - "**/{migrations,database/migrations,seeders}/**"
  - "**/config/project/**"
---

# Deployment & Production Safety

Detail for guardrails #2, #3 and #4 in `CLAUDE.md`. The harness asks before pushes,
publishes, deploys, remote shells, cloud/infra CLIs, destructive git, and destructive
SQL (`.claude/hooks/safety-guard.sh` plus `ask` rules). Approval is per action.

## Publishing (guardrail #2)

- **Fine without asking:** `git add`, `git commit`, `git status`, `git diff`,
  `git log`, creating local branches.
- **Needs explicit approval each time:** `git push` (any form, including tags and
  `--force`), `gh pr create|merge|edit|comment`, releases, `npm publish`,
  `docker push`.
- Don't set up hooks, aliases, or CI steps that push or deploy as a side effect.

## Production & remote environments (guardrail #3)

Needs explicit approval for the specific action:

- Deploys and releases (Vercel `--prod`, Netlify, Wrangler, Forge, Envoy, rsync/scp
  to servers, `ddev push`).
- Database writes on any non-local DB: migrations, `UPDATE`/`DELETE`/`DROP`/
  `TRUNCATE`, seeding, backfills, imports (`ddev import-db`, `ddev pull` also
  overwrite the local DB — confirm first).
- Config, secrets, DNS, feature flags, or infrastructure (`terraform`, `kubectl`,
  `helm`, cloud CLIs).

Treat a target as production unless confirmed otherwise: hostnames without
`local`/`dev`/`staging`/`test`/`ddev.site`, `.env.production`, `--prod` flags, or
live customer data.

## Remote servers & databases (guardrail #4)

The hook parses every remote invocation (`ssh`, `scp`/`rsync`, `wp @alias`/`--ssh=`,
`mysql`/`psql`/`mongosh`/`redis-cli` with a non-local host, any tool given a remote
database URI) and classifies the commands it would run:

| What the command does | Staging / undeclared | Production |
|---|---|---|
| Read-only, output-safe: versions, status, listings, `COUNT(*)`, hashes | runs | runs |
| Returns contents: `cat`/`tail`, `wp option get`, `config get`, `SELECT` rows, logs | asks | asks |
| Writes, or isn't recognised | asks | **denied** |
| Can't be inspected: interactive shell, `bash script.sh`, `< file`, tunnels | asks | **denied** |

Production is whatever `ai-config.conf` declares:

```ini
[remote]
production = /var/www/example.org, example_prod, prod-ssh-alias, @production
staging    = /var/www/stg.example.org, example_stage
assert-database = true   # optional: staging writes must run SELECT DATABASE() first
```

When a production change is needed, give the developer the exact command and let them
run it (in Claude Code, prefixed with `!`). Don't split a command, move it into a script
or pipe it through stdin to get past the check. Keep remote commands inline so they can
be read: `ssh host 'bash -s' <<'EOF' … EOF` is inspected, `ssh host bash -s < file` is not.

## Asking for permission

State what you intend to run, against which target, and why — then wait for an
explicit yes. Prefer dry-run or preview modes (`--pretend`, `--dry-run`,
`terraform plan`, `project-config/diff`) to show impact first.
