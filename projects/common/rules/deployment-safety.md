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

Detail for guardrails #2 and #3 in `CLAUDE.md`. The harness asks before pushes,
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

## Asking for permission

State what you intend to run, against which target, and why — then wait for an
explicit yes. Prefer dry-run or preview modes (`--pretend`, `--dry-run`,
`terraform plan`, `project-config/diff`) to show impact first.
