#!/usr/bin/env bash
# test-secret-scanning.sh — Content scanning in safety-guard.sh.
#
# Path rules only block what we can name. These tests cover the other half: a file
# whose name looks harmless but whose CONTENT carries a credential — a server log with
# a stack trace, a docker-compose.yml, a seeder, a Postman collection.
#
# Usage: ./test-secret-scanning.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/projects/common/hooks/safety-guard.sh"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rep() { printf "%${2}s" | tr ' ' "$1"; }

# Credentials the guard must never echo back in its reason string. Built from split
# literals and runs of a repeated character so the fixtures keep the SHAPE of a real key
# without ever being one — GitHub push protection rejects this repository otherwise, and
# it is right to: a literal AKIA... in a committed file is indistinguishable from a leak.
LIVE_AWS_KEY="AK""IA$(rep Q 16)"
LIVE_ANTHROPIC="sk-""ant-api03-$(rep z 30)"

# decision <tool> <json-tool-input> → deny | ask | allow
decision() {
  local out
  out=$(printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2" \
    | (cd "$WORK" && CLAUDE_PROJECT_DIR="$WORK" bash "$GUARD" 2>/dev/null))
  [[ -z "$out" ]] && { echo "allow"; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<< "$out" 2>/dev/null || echo "allow"
}

reason() {
  local out
  out=$(printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2" \
    | (cd "$WORK" && CLAUDE_PROJECT_DIR="$WORK" bash "$GUARD" 2>/dev/null))
  jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$out" 2>/dev/null
}

read_of()  { printf '{"file_path":"%s"}' "$1"; }
bash_of()  { jq -n --arg c "$1" '{command:$c}'; }
write_of() { jq -n --arg p "$1" --arg c "$2" '{file_path:$p, content:$c}'; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"; FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  fi
}

# ============================================================================
echo -e "\n${CYAN}=== Server logs: readable when clean, blocked when dirty ===${NC}\n"
# ============================================================================

mkdir -p "$WORK/storage/logs" "$WORK/wp-content"

cat > "$WORK/storage/logs/clean.log" <<'EOF'
[2026-09-18 09:14:02] production.INFO: Cache warmed in 412ms
[2026-09-18 09:14:07] production.ERROR: View [home.index] not found
  at /var/www/app/Http/Controllers/PageController.php:88
EOF

cat > "$WORK/storage/logs/laravel.log" <<EOF
[2026-09-18 09:14:02] production.INFO: Booting
[2026-09-18 09:14:09] production.ERROR: SQLSTATE[HY000] [1045] Access denied
  connection: mysql://forge:Tr0ub4dor-b1ll@10.0.0.14:3306/forge_production
  at /var/www/app/Providers/AppServiceProvider.php:41
EOF

cat > "$WORK/wp-content/debug.log" <<EOF
[18-Sep-2026 09:20:11 UTC] PHP Notice: undefined index 'foo'
[18-Sep-2026 09:20:12 UTC] Stripe call failed, key=${LIVE_ANTHROPIC}
EOF

assert_eq "clean log is readable" "allow" "$(decision Read "$(read_of storage/logs/clean.log)")"
assert_eq "log with a DB connection string is denied" "deny" "$(decision Read "$(read_of storage/logs/laravel.log)")"
assert_eq "log with an API token is denied" "deny" "$(decision Read "$(read_of wp-content/debug.log)")"

r=$(reason Read "$(read_of storage/logs/laravel.log)")
assert_true "denial names the offending line number" grep -qE 'line' <<< "$r"
assert_false "denial never echoes the password" grep -qF 'Tr0ub4dor-b1ll' <<< "$r"
r=$(reason Read "$(read_of wp-content/debug.log)")
assert_false "denial never echoes the API token" grep -qF "$LIVE_ANTHROPIC" <<< "$r"

# ============================================================================
echo -e "\n${CYAN}=== Bash reads of the same files ===${NC}\n"
# ============================================================================

assert_eq "cat of a clean log is allowed" "allow" \
  "$(decision Bash "$(bash_of 'cat storage/logs/clean.log')")"
assert_eq "cat of a dirty log is denied" "deny" \
  "$(decision Bash "$(bash_of 'cat storage/logs/laravel.log')")"
assert_eq "tail of a dirty log is denied" "deny" \
  "$(decision Bash "$(bash_of 'tail -100 storage/logs/laravel.log')")"
assert_eq "grep over a dirty log is denied" "deny" \
  "$(decision Bash "$(bash_of 'grep -i error storage/logs/laravel.log')")"
assert_eq "ls of a dirty log is allowed (no content read)" "allow" \
  "$(decision Bash "$(bash_of 'ls -la storage/logs/laravel.log')")"

# ============================================================================
echo -e "\n${CYAN}=== Files that hide credentials but are not named like secrets ===${NC}\n"
# ============================================================================

cat > "$WORK/docker-compose.yml" <<'EOF'
services:
  db:
    image: mariadb:11
    environment:
      MYSQL_ROOT_PASSWORD: x9Kq2LmZpR4tVwYb
EOF

cat > "$WORK/UserSeeder.php" <<EOF
<?php
// Imports the ops account
\$token = '${LIVE_AWS_KEY}';
EOF

cat > "$WORK/postman_collection.json" <<EOF
{"auth":{"bearer":[{"key":"token","value":"${LIVE_ANTHROPIC}"}]}}
EOF

cat > "$WORK/runbook.md" <<'EOF'
# Restoring production
Connect with: postgres://deploy:9fJ2-kPq7Wm@db.internal:5432/app
EOF

assert_eq "docker-compose with a real root password is denied" "deny" \
  "$(decision Read "$(read_of docker-compose.yml)")"
assert_eq "seeder with an AWS key is denied" "deny" "$(decision Read "$(read_of UserSeeder.php)")"
assert_eq "postman collection with a bearer token is denied" "deny" \
  "$(decision Read "$(read_of postman_collection.json)")"
assert_eq "runbook with a connection string is denied" "deny" "$(decision Read "$(read_of runbook.md)")"

# ============================================================================
echo -e "\n${CYAN}=== Placeholders stay readable (or the guard is unusable) ===${NC}\n"
# ============================================================================

cat > "$WORK/.env.example" <<'EOF'
DB_PASSWORD=your_password_here
API_KEY=<your-api-key>
STRIPE_SECRET=sk_live_xxxxxxxxxxxxxxxxx
DATABASE_URL=mysql://user:password@localhost:3306/app
EOF

cat > "$WORK/config.sample.yml" <<'EOF'
database:
  password: ${DB_PASSWORD}
  token: CHANGEME
EOF

cat > "$WORK/app.ts" <<'EOF'
const key = process.env.API_KEY;
export const db = { password: process.env.DB_PASSWORD };
EOF

cat > "$WORK/README.md" <<'EOF'
Set DATABASE_URL=postgres://user:pass@host:5432/db in your .env
EOF

assert_eq ".env.example placeholders are readable" "allow" "$(decision Read "$(read_of .env.example)")"
assert_eq "sample config with \${VAR} is readable" "allow" "$(decision Read "$(read_of config.sample.yml)")"
assert_eq "source reading from process.env is readable" "allow" "$(decision Read "$(read_of app.ts)")"
assert_eq "README with a documented placeholder URL is readable" "allow" "$(decision Read "$(read_of README.md)")"

# AWS publishes AKIAIOSFODNN7EXAMPLE in its own docs. Blocking every page that quotes it
# would train people to ignore the guard, so a line saying "example" is forgiven.
printf 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE\n' > "$WORK/aws-docs.md"
assert_eq "AWS's documented example key is forgiven" "allow" "$(decision Read "$(read_of aws-docs.md)")"

# ============================================================================
echo -e "\n${CYAN}=== Scan limits: fail closed, skip binaries ===${NC}\n"
# ============================================================================

printf 'ordinary source line\n%.0s' $(seq 1 50) > "$WORK/big.txt"
out=$(printf '{"tool_name":"Read","tool_input":{"file_path":"big.txt"}}' \
  | (cd "$WORK" && CLAUDE_PROJECT_DIR="$WORK" AI_CONFIG_SCAN_MAX_BYTES=64 bash "$GUARD" 2>/dev/null))
assert_true "a file too large to scan is denied, not waved through" \
  grep -q '"permissionDecision":"deny"' <<< "$out"
assert_true "the too-large denial explains itself" grep -qi "large" <<< "$out"

head -c 4096 /dev/urandom > "$WORK/image.bin"
assert_eq "binary files are not scanned or blocked" "allow" "$(decision Read "$(read_of image.bin)")"

assert_eq "a missing file is not blocked by the scanner" "allow" "$(decision Read "$(read_of does-not-exist.log)")"

# ============================================================================
echo -e "\n${CYAN}=== Writes: memory and knowledge files are denied, not merely asked ===${NC}\n"
# ============================================================================

assert_eq "credential written to MEMORY.md is denied" "deny" \
  "$(decision Write "$(write_of MEMORY.md "DB password is Tr0ub4dor-b1ll for mysql://forge:Tr0ub4dor-b1ll@10.0.0.14/db")")"
assert_eq "credential written to .okf/ is denied" "deny" \
  "$(decision Write "$(write_of .okf/concepts/db.md "token: $LIVE_ANTHROPIC")")"
assert_eq "credential written to ordinary source still asks" "ask" \
  "$(decision Write "$(write_of src/config.ts "const k = '$LIVE_AWS_KEY'")")"
assert_eq "placeholder written to MEMORY.md is allowed" "allow" \
  "$(decision Write "$(write_of MEMORY.md "Set DB_PASSWORD=<your-password> in .env")")"

# ============================================================================
echo -e "\n${CYAN}=== Every credential class is reachable through the anchor regex ===${NC}\n"
# ============================================================================
# secret_scan only runs the precise regexes over lines the cheap anchor pass returned.
# A pattern with no matching anchor is dead code, so each class gets a case here.

# Tokens are split across two literals ("AK" "IA") for the same reason test-safety-guard.sh
# does it: so this repository's own files never contain a credential-shaped string.
T_PEM="-----BEGIN RSA PRIVATE KEY-----"
T_AWS="AK""IA$(rep Q 16)"
T_STS="AS""IA$(rep Q 16)"
T_ANT="sk-""ant-api03-$(rep z 30)"
T_OAI="sk-""proj-$(rep z 30)"
T_STRIPE="sk_""live_$(rep 7 24)"
T_STRIPE_RK="rk_""live_$(rep 7 24)"
T_GHP="gh""p_$(rep A 36)"
T_GHPAT="github_""pat_$(rep A 44)"
T_GLPAT="gl""pat-$(rep A 24)"
T_SLACK="xo""xb-$(rep 7 16)"
T_GOOGLE="AI""za$(rep B 35)"
T_SENDGRID="S""G.$(rep A 20).$(rep B 20)"
T_NPM="np""m_$(rep A 36)"
T_DO="dop_""v1_$(rep a 64)"
T_JWT="ey""J$(rep a 12).ey""J$(rep b 12).$(rep c 16)"

CLASSES="private key|$T_PEM
AWS access key|$T_AWS
AWS STS key|$T_STS
Anthropic key|$T_ANT
OpenAI project key|$T_OAI
Stripe live key|$T_STRIPE
Stripe restricted key|$T_STRIPE_RK
GitHub token|$T_GHP
GitHub fine-grained PAT|$T_GHPAT
GitLab PAT|$T_GLPAT
Slack token|$T_SLACK
Google API key|$T_GOOGLE
SendGrid key|$T_SENDGRID
npm token|$T_NPM
DigitalOcean token|$T_DO
JWT|$T_JWT
MySQL DSN|mysql://svc:R7kQm2Wp@10.0.0.9:3306/app
Postgres DSN|postgres://svc:R7kQm2Wp@10.0.0.9:5432/app
MongoDB SRV DSN|mongodb+srv://svc:R7kQm2Wp@cluster.mongodb.net/app
Redis DSN|redis://svc:R7kQm2Wp@10.0.0.9:6379
AMQP DSN|amqp://svc:R7kQm2Wp@10.0.0.9:5672
Basic-auth URL|https://svc:R7kQm2Wp@internal.corp.net/hook
DB_PASSWORD assignment|DB_PASSWORD=R7kQm2WpZx4v
AWS secret assignment|aws_secret_access_key=$(rep A 20)$(rep b 20)
client_secret assignment|client_secret=R7kQm2WpZx4vB8n
api_key assignment|api_key=R7kQm2WpZx4vB8n
"

while IFS='|' read -r label payload; do
  [[ -n "$label" && -n "$payload" ]] || continue
  printf 'line one\n%s\nline three\n' "$payload" > "$WORK/class-probe.txt"
  assert_eq "caught: $label" "deny" "$(decision Read "$(read_of class-probe.txt)")"
done <<< "$CLASSES"
rm -f "$WORK/class-probe.txt"

# ============================================================================
echo -e "\n${CYAN}=== Ordinary work is unaffected ===${NC}\n"
# ============================================================================

cat > "$WORK/Nav.vue" <<'EOF'
<template><nav><slot /></nav></template>
<script setup lang="ts">defineProps<{ items: string[] }>()</script>
EOF
mkdir -p "$WORK/src"
cat > "$WORK/src/index.ts" <<'EOF'
export function add(a: number, b: number) { return a + b }
EOF

assert_eq "a Vue component is readable" "allow" "$(decision Read "$(read_of Nav.vue)")"
assert_eq "a TS module is readable" "allow" "$(decision Read "$(read_of src/index.ts)")"
assert_eq "grep across the tree is allowed" "allow" "$(decision Bash "$(bash_of 'grep -rn add src/')")"

# ============================================================================
echo ""
echo -e "${CYAN}================================${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  FAIL: $FAIL"
echo -e "${CYAN}================================${NC}"
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}✗ $FAIL test(s) failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ All $PASS tests passed${NC}"
