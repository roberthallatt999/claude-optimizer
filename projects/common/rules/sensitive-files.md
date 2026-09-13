---
paths:
  - "**/.gitignore"
  - "**/.env.example"
  - "**/*.{env,envrc}"
  - "**/{config,settings}/**"
  - "**/*config*.{php,js,mjs,cjs,ts,json,yml,yaml}"
  - "**/docker-compose*.{yml,yaml}"
  - "**/.ddev/**"
  - "**/.github/workflows/**"
---

# Sensitive File Protection

Guardrail #1 in `CLAUDE.md` (never read or expose secrets) applies. The harness blocks
most of these paths via `.claude/settings.local.json` deny rules and
`.claude/hooks/safety-guard.sh`; a block is a signal to ask, not to find another route.

## Never read, print, copy, or summarize

- **Environment:** `.env`, `.env.*`, `*.env`, `.envrc` — `.env.example` / `.sample` /
  `.template` are fine.
- **App/DB config with credentials:** `wp-config.php`, `wp-config-local.php`,
  `system/user/config/config.php` (EE), `config.local.php`, `database.yml`,
  `auth.json` (Composer), `.ddev/db_snapshots/`, `.ddev/import-db/`.
- **Keys & certificates:** `*.key`, `*.pem`, `*.p12`, `*.pfx`, `*.crt`, `*.cer`,
  `*.jks`, `*.keystore`, `id_rsa` / `id_ed25519` (and other SSH keys), `.ssh/`.
- **Credential stores:** `credentials.json`, `*-credentials.json`,
  `service-account*.json`, `secrets.{json,yml,yaml}`, `vault.{yml,yaml}`,
  `.git-credentials`, `.netrc`, `.npmrc`, `.yarnrc`, `.pypirc`, `.pgpass`, `.my.cnf`,
  `.htpasswd`, `.aws/`, `.azure/`, `*.secret`, `*.token`, `*.password`.

## Instead

| Need | Do this |
| --- | --- |
| Which env vars exist | Read `.env.example`, or grep code for `env(` / `process.env.` |
| DB connection details | Ask the developer, or suggest `ddev describe` for them to run |
| A config key's shape | Read the sample file (`wp-config-sample.php`, `.env.example`) |
| A real secret value | Ask; reference it via an environment variable in code |

Also: never hardcode, log, or echo secret values; keep secret file patterns in
`.gitignore`; record variable **names** (never values) in `MEMORY.md`.
