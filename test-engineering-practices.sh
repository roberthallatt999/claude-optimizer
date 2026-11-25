#!/usr/bin/env bash
# test-engineering-practices.sh — the Engineering Practices block and rule, their opt-out, the
# --refresh backfill for projects deployed before them, and the --doctor CI check.
#
# Usage: ./test-engineering-practices.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }
export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"

PROJECTS=()
make_nuxt_project() {
  local dir
  dir="$(mktemp -d)"
  touch "$dir/nuxt.config.ts"
  echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$dir/package.json"
  PROJECTS+=("$dir")
  echo "$dir"
}
cleanup_all() { local d; for d in "${PROJECTS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

deploy() {
  local project_dir="$1"
  shift
  "$SETUP_SCRIPT" --project="$project_dir" --force --skip-vscode --no-superpowers "$@" >/dev/null 2>&1
}
doctor() { "$SETUP_SCRIPT" --project="$1" --doctor 2>&1; }
block_count() { grep -c "<!-- BEGIN $2" "$1/CLAUDE.md" 2>/dev/null || true; }
RULE=".claude/rules/engineering-practices.md"
MANIFEST=".claude/ai-config/manifest.tsv"

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}
assert_true() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name"
    FAIL=$((FAIL + 1))
  fi
}
assert_false() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${RED}FAIL${NC} $name"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  fi
}
contains() { grep -qF -- "$2" <<< "$1"; }
strip_block() {
  perl -0777 -i -pe 's{\n?<!-- BEGIN ENGINEERING PRACTICES.*?<!-- END ENGINEERING PRACTICES -->\n?}{\n}s' "$1/CLAUDE.md"
}

# ============================================================================
echo -e "\n${CYAN}=== Fresh deploy ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p"
assert_eq "block present once" "1" "$(block_count "$p" "ENGINEERING PRACTICES")"
assert_true "rule deployed" test -f "$p/$RULE"
assert_true "rule is path-scoped" grep -q '^paths:' "$p/$RULE"
assert_true "block sits before Response Style" \
  perl -0777 -ne 'exit(/BEGIN ENGINEERING PRACTICES.*BEGIN RESPONSE STYLE/s ? 0 : 1)' "$p/CLAUDE.md"
deploy "$p"
deploy "$p" --refresh
assert_eq "block still once after redeploy + refresh" "1" "$(block_count "$p" "ENGINEERING PRACTICES")"

# ============================================================================
echo -e "\n${CYAN}=== Refresh backfills a project deployed before the practices ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p"
strip_block "$p"
rm -f "$p/$RULE"
/usr/bin/grep -v 'engineering-practices.md' "$p/$MANIFEST" > "$p/$MANIFEST.tmp" && mv "$p/$MANIFEST.tmp" "$p/$MANIFEST"
assert_eq "simulated legacy project has no block" "0" "$(block_count "$p" "ENGINEERING PRACTICES")"
deploy "$p" --refresh
assert_eq "refresh adds the block" "1" "$(block_count "$p" "ENGINEERING PRACTICES")"
assert_true "refresh adds the rule" test -f "$p/$RULE"

rm -f "$p/$RULE"
deploy "$p" --refresh
assert_false "a rule deleted on purpose (in the manifest) stays deleted" test -f "$p/$RULE"

# ============================================================================
echo -e "\n${CYAN}=== Opt-out ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p" --no-engineering-practices
assert_eq "--no-engineering-practices omits the block" "0" "$(block_count "$p" "ENGINEERING PRACTICES")"
assert_false "--no-engineering-practices omits the rule" test -f "$p/$RULE"

p=$(make_nuxt_project)
deploy "$p"
printf '[options]\nengineering-practices = false\n' > "$p/ai-config.conf"
deploy "$p" --refresh
assert_eq "engineering-practices = false strips a deployed block" "0" "$(block_count "$p" "ENGINEERING PRACTICES")"
echo '{}' > "$p/composer.lock"   # would trigger the CI warning if the opt-out were ignored
out=$(doctor "$p")
assert_false "--doctor doesn't nag about CI when opted out" contains "$out" "CI doesn't run"

# ============================================================================
echo -e "\n${CYAN}=== --doctor: CI audits, tests, static analysis ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p"
echo '{}' > "$p/composer.lock"
echo '{}' > "$p/package-lock.json"
touch "$p/phpunit.xml" "$p/phpstan.neon"
mkdir -p "$p/tests/Unit" "$p/.github/workflows"
touch "$p/tests/Unit/ExampleTest.php"
printf 'jobs:\n  deploy:\n    steps:\n      - run: rsync -a . server:/\n' > "$p/.github/workflows/deploy.yml"
out=$(doctor "$p")
assert_true "reports composer audit missing" contains "$out" "composer-audit"
assert_true "reports npm audit missing" contains "$out" "npm-audit"
assert_true "reports PHP tests missing" contains "$out" "php-tests"
assert_true "reports PHPStan missing" contains "$out" "phpstan"

cat > "$p/.github/workflows/checks.yaml" <<'YML'
jobs:
  checks:
    steps:
      - run: composer audit
      - run: npm audit --audit-level=high
      - run: php artisan test
      - run: vendor/bin/phpstan analyse
YML
out=$(doctor "$p")
assert_false "no CI warning once every step runs (.yml + .yaml both read)" contains "$out" "CI doesn't run"

p=$(make_nuxt_project)
deploy "$p"
echo '{}' > "$p/composer.lock"
echo '{}' > "$p/package-lock.json"
mkdir -p "$p/.github/workflows"
cat > "$p/.github/workflows/deploy-production.yml" <<'YML'
jobs:
  deploy:
    uses: canadian-paediatric-society/deployment-workflows/.github/workflows/base-deploy.yml@main
    with:
      environment: production
YML
out=$(doctor "$p")
assert_false "shared base-deploy.yml counts as running both audits" contains "$out" "CI doesn't run"
printf "      dependency_audit: 'off'\n" >> "$p/.github/workflows/deploy-production.yml"
out=$(doctor "$p")
assert_true "dependency_audit: off brings the warning back" contains "$out" "composer-audit, npm-audit"

p=$(make_nuxt_project)
deploy "$p"
rm -f "$p/package-lock.json"
out=$(doctor "$p")
assert_false "no lockfiles or test config: nothing to report" contains "$out" "CI doesn't run"

# Laravel's skeleton ships phpunit.xml; a site that never wrote a test keeps it with no
# tests/ folder, and there is nothing for CI to run.
p=$(make_nuxt_project)
deploy "$p"
rm -f "$p/package-lock.json"
touch "$p/phpunit.xml"
mkdir -p "$p/tests/Feature"
out=$(doctor "$p")
assert_false "phpunit.xml and an empty tests/ folder are not tests" contains "$out" "php-tests"
mkdir -p "$p/tests/Feature/Auth"
touch "$p/tests/Feature/Auth/LoginTest.php"
out=$(doctor "$p")
assert_true "a test file anywhere under tests/ is" contains "$out" "php-tests"

# A project that only ever runs under DDEV has no CI to add steps to; it opts out of this
# check alone and keeps the rest of Engineering Practices.
p=$(make_nuxt_project)
deploy "$p"
echo '{}' > "$p/composer.lock"
mkdir -p "$p/tests/Feature"
touch "$p/tests/Feature/LoginTest.php"
printf '[options]\nci-checks = false\n' > "$p/ai-config.conf"
out=$(doctor "$p")
assert_false "ci-checks = false silences the CI warning" contains "$out" "CI doesn't run"
assert_true "ci-checks = false is reported as info" contains "$out" "CI checks off"
assert_eq "ci-checks = false keeps the Engineering Practices block" "1" "$(block_count "$p" "ENGINEERING PRACTICES")"
assert_false "ci-checks is a known option" contains "$out" "unknown key 'ci-checks'"

p=$(make_nuxt_project)
deploy "$p"
strip_block "$p"
out=$(doctor "$p")
assert_true "--doctor warns when the block is missing" contains "$out" "no Engineering Practices block"

# ============================================================================
echo -e "\n${CYAN}=== Uninstall ===${NC}\n"
# ============================================================================

p=$(make_nuxt_project)
deploy "$p"
echo "# my notes" >> "$p/CLAUDE.md"
"$SETUP_SCRIPT" --project="$p" --uninstall --force >/dev/null 2>&1
if [[ -f "$p/CLAUDE.md" ]]; then
  assert_eq "--uninstall strips the block from an edited CLAUDE.md" "0" "$(block_count "$p" "ENGINEERING PRACTICES")"
else
  assert_true "--uninstall removed CLAUDE.md" true
fi

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
