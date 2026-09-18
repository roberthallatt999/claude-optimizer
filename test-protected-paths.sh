#!/usr/bin/env bash
# test-protected-paths.sh — Stack-aware protected paths: the two tiers, the generated
# .claudeignore, the deny rules they produce, and the safety-guard enforcement behind them.
#
# Usage: ./test-protected-paths.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
GUARD="$SCRIPT_DIR/projects/common/hooks/safety-guard.sh"
COMMON_CONF="$SCRIPT_DIR/projects/common/protected-paths.conf"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"

# ============================================================================
# Helpers
# ============================================================================

PROJECTS=()
cleanup_all() { local d; for d in "${PROJECTS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

make_project() {   # make_project <kind>
  local dir
  dir="$(mktemp -d)"
  case "$1" in
    nuxt)
      touch "$dir/nuxt.config.ts"
      echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$dir/package.json"
      ;;
    wordpress)
      touch "$dir/wp-config.php"
      mkdir -p "$dir/wp-content/themes"
      ;;
    t3-stack)
      touch "$dir/next.config.js"
      mkdir -p "$dir/prisma"
      touch "$dir/prisma/schema.prisma"
      echo '{"name":"t3","dependencies":{"next":"14.0.0","@trpc/server":"10.0.0"}}' > "$dir/package.json"
      ;;
  esac
  PROJECTS+=("$dir")
  echo "$dir"
}

deploy() {
  local project_dir="$1"
  shift
  "$SETUP_SCRIPT" --project="$project_dir" --force --skip-vscode --no-superpowers "$@" >/dev/null 2>&1
}

settings() { echo "$1/.claude/settings.local.json"; }
jqs() { jq -r "$2" "$(settings "$1")" 2>/dev/null; }

# guard_decision <project> <tool> <path> → "deny" | "ask" | "allow"
guard_decision() {
  local project="$1" tool="$2" path="$3" out
  out=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path" \
    | (cd "$project" && CLAUDE_PROJECT_DIR="$project" bash "$project/.claude/hooks/safety-guard.sh" 2>/dev/null))
  if [[ -z "$out" ]]; then echo "allow"; return; fi
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<< "$out" 2>/dev/null || echo "allow"
}

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
echo -e "\n${CYAN}=== Template hygiene: protected-paths.conf files ===${NC}\n"
# ============================================================================

assert_true "common protected-paths.conf exists" test -f "$COMMON_CONF"

missing=""
for d in "$SCRIPT_DIR"/projects/*/; do
  name=$(basename "$d")
  [[ "$name" == "common" ]] && continue
  [[ -f "$d/CLAUDE.md.template" ]] || continue
  [[ -f "$d/protected-paths.conf" ]] || missing="$missing $name"
done
assert_eq "every stack ships a protected-paths.conf" "" "$missing"

# Only [deny] / [ignore] sections, comments, blanks and patterns.
bad=""
for f in "$SCRIPT_DIR"/projects/*/protected-paths.conf; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*) continue ;;
      '[deny]'|'[ignore]') continue ;;
      '['*) bad="$bad ${f##*/projects/}:$line" ;;
    esac
  done < "$f"
done
assert_eq "conf files use only [deny] and [ignore] sections" "" "$bad"

# Tier discipline: build noise must never be denied — denying it breaks real debugging.
noise=""
for f in "$SCRIPT_DIR"/projects/*/protected-paths.conf; do
  section=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '[deny]') section=deny; continue ;;
      '[ignore]') section=ignore; continue ;;
      ''|'#'*) continue ;;
    esac
    [[ "$section" == deny ]] || continue
    case "$line" in
      node_modules/*|node_modules|vendor/|vendor|.next/|dist/|build/|.nuxt/|.output/|.svelte-kit/)
        noise="$noise ${f##*/projects/}:$line" ;;
    esac
  done < "$f"
done
assert_eq "build/dependency noise is never in the deny tier" "" "$noise"

# ============================================================================
echo -e "\n${CYAN}=== Fresh deploy: .claudeignore + deny rules ===${NC}\n"
# ============================================================================

p=$(make_project nuxt)
deploy "$p"

assert_true ".claudeignore created" test -f "$p/.claudeignore"
assert_true ".claudeignore says it is advisory, not enforcement" \
  grep -qi "not read by claude code\|advisory" "$p/.claudeignore"
assert_true ".claudeignore points at the real enforcement" \
  grep -q "settings.local.json" "$p/.claudeignore"
assert_true ".claudeignore carries common baseline patterns" grep -qxF '.env' "$p/.claudeignore"
assert_true ".claudeignore carries stack ignore patterns (nuxt)" grep -qxF '.nuxt/' "$p/.claudeignore"
assert_true ".claudeignore carries the noise tier" grep -qxF 'node_modules/' "$p/.claudeignore"

assert_eq "deny rule generated for a bare-name pattern" "true" \
  "$(jqs "$p" '.permissions.deny | index("Read(**/.git/**)") != null')"
assert_eq "deny rule generated for a credentials glob" "true" \
  "$(jqs "$p" '.permissions.deny | index("Read(**/credentials*)") != null')"
assert_eq "deny rule generated for a dump extension" "true" \
  "$(jqs "$p" '.permissions.deny | index("Read(**/*.sqlite)") != null')"
assert_eq "noise is never turned into a deny rule" "false" \
  "$(jqs "$p" '[.permissions.deny[] | select(test("node_modules"))] | length > 0')"

assert_true "hook conf deployed" test -f "$p/.claude/hooks/protected-paths.conf"
assert_true "hook conf holds deny patterns" grep -qxF '*.sqlite' "$p/.claude/hooks/protected-paths.conf"
assert_false "hook conf holds no ignore-tier patterns" \
  grep -qxF 'node_modules/' "$p/.claude/hooks/protected-paths.conf"

# ============================================================================
echo -e "\n${CYAN}=== Enforcement: safety-guard honours the deployed conf ===${NC}\n"
# ============================================================================

assert_eq "database dump is denied" "deny" "$(guard_decision "$p" Read "backups/site.sqlite")"
assert_eq ".db file is denied" "deny" "$(guard_decision "$p" Read "data/app.db")"
assert_eq ".git internals are denied" "deny" "$(guard_decision "$p" Read ".git/config")"
assert_eq "nested .git internals are denied" "deny" "$(guard_decision "$p" Read "sub/.git/config")"
assert_eq "credentials-prefixed file is denied" "deny" "$(guard_decision "$p" Read "credentials.yml")"
assert_eq "secrets-prefixed file is denied" "deny" "$(guard_decision "$p" Read "config/secrets.enc")"
assert_eq ".env is still denied (hardcoded fallback)" "deny" "$(guard_decision "$p" Read ".env")"

assert_eq "node_modules stays readable" "allow" "$(guard_decision "$p" Read "node_modules/vue/index.js")"
assert_eq ".github workflows stay readable" "allow" "$(guard_decision "$p" Read ".github/workflows/ci.yml")"
assert_eq ".github workflows stay editable" "allow" "$(guard_decision "$p" Edit ".github/workflows/ci.yml")"
assert_eq "ordinary source stays readable" "allow" "$(guard_decision "$p" Read "components/Nav.vue")"
assert_eq "a config.js is not blanket-denied" "allow" "$(guard_decision "$p" Read "app/config.js")"

# The hook must still work standalone, with no conf beside it (legacy deployments).
out=$(printf '{"tool_name":"Read","tool_input":{"file_path":".env"}}' | bash "$GUARD" 2>/dev/null)
assert_true "hook without a conf still denies .env" grep -q '"permissionDecision":"deny"' <<< "$out"
out=$(printf '{"tool_name":"Read","tool_input":{"file_path":"app/main.ts"}}' | bash "$GUARD" 2>/dev/null)
assert_eq "hook without a conf allows ordinary source" "" "$out"

# ============================================================================
echo -e "\n${CYAN}=== Stack awareness ===${NC}\n"
# ============================================================================

wp=$(make_project wordpress)
deploy "$wp"
assert_true "wordpress: uploads in the ignore tier" grep -qF 'wp-content/uploads/' "$wp/.claudeignore"
assert_eq "wordpress: .sql denied (dumps, not migrations)" "deny" "$(guard_decision "$wp" Read "db-backup.sql")"
assert_eq "wordpress: deny rule for wp-content backups" "true" \
  "$(jqs "$wp" '[.permissions.deny[] | select(test("wp-content"))] | length > 0')"
assert_false "wordpress: no nuxt patterns leaked in" grep -qxF '.nuxt/' "$wp/.claudeignore"

t3=$(make_project t3-stack)
deploy "$t3"
assert_eq "t3: prisma migrations stay readable" "allow" \
  "$(guard_decision "$t3" Read "prisma/migrations/20240101_init/migration.sql")"
assert_eq "t3: a sqlite dev database is still denied" "deny" "$(guard_decision "$t3" Read "prisma/dev.db")"
assert_true "t3: .next in the ignore tier" grep -qxF '.next/' "$t3/.claudeignore"

assert_false "nuxt: no wordpress patterns leaked in" grep -qF 'wp-content' "$p/.claudeignore"

# ============================================================================
echo -e "\n${CYAN}=== Additivity across redeploy and refresh ===${NC}\n"
# ============================================================================

before=$(cat "$p/.claudeignore")
deny_before=$(jqs "$p" '.permissions.deny | length')
deploy "$p"
deploy "$p" --refresh
assert_eq ".claudeignore unchanged by redeploy + refresh" "$before" "$(cat "$p/.claudeignore")"
assert_eq "deny count stable across redeploy + refresh" "$deny_before" "$(jqs "$p" '.permissions.deny | length')"

printf '\n# my own rule\nprivate-notes/\n' >> "$p/.claudeignore"
edited=$(cat "$p/.claudeignore")
deploy "$p" --refresh
assert_eq "edited .claudeignore is kept" "$edited" "$(cat "$p/.claudeignore")"
assert_true "new version staged in pending/" test -f "$p/.claude/ai-config/pending/.claudeignore"

# ============================================================================
echo -e "\n${CYAN}=== Flags ===${NC}\n"
# ============================================================================

p2=$(make_project nuxt)
deploy "$p2" --no-claudeignore
assert_false "--no-claudeignore writes no file" test -e "$p2/.claudeignore"
assert_eq "--no-claudeignore still applies deny rules" "true" \
  "$(jqs "$p2" '.permissions.deny | index("Read(**/.git/**)") != null')"
assert_true "--no-claudeignore still deploys the hook conf" test -f "$p2/.claude/hooks/protected-paths.conf"

p3=$(make_project nuxt)
deploy "$p3" --dry-run
assert_false "--dry-run writes no .claudeignore" test -e "$p3/.claudeignore"
assert_false "--dry-run writes no hook conf" test -e "$p3/.claude/hooks/protected-paths.conf"

# ============================================================================
echo -e "\n${CYAN}=== Shared policy (teammates) ===${NC}\n"
# ============================================================================

# The hook enforces nothing without the conf it reads, so --shared-policy has to
# un-ignore both, not just safety-guard.sh.
if command -v git >/dev/null 2>&1; then
  sp=$(make_project nuxt)
  git -C "$sp" init -q >/dev/null 2>&1
  # A real project already ignores .claude/; that line is what --shared-policy rewrites,
  # and without it update_gitignore has nothing to act on and the checks below are vacuous.
  printf '.claude/\nnode_modules/\n' > "$sp/.gitignore"
  deploy "$sp" --shared-policy
  assert_true "shared policy: .gitignore was rewritten for sharing" \
    grep -qxF '.claude/*' "$sp/.gitignore"
  assert_false "shared policy: hook conf is not gitignored" \
    git -C "$sp" check-ignore -q .claude/hooks/protected-paths.conf
  assert_false "shared policy: safety-guard.sh is not gitignored" \
    git -C "$sp" check-ignore -q .claude/hooks/safety-guard.sh
  assert_eq "shared policy: deny rules in committed settings.json" "true" \
    "$(jq -r '.permissions.deny | index("Read(**/.git/**)") != null' "$sp/.claude/settings.json" 2>/dev/null)"
fi

# ============================================================================
echo -e "\n${CYAN}=== Doctor ===${NC}\n"
# ============================================================================

assert_true "--doctor passes on a fresh deploy" \
  "$SETUP_SCRIPT" --doctor --project="$p2"

rm -f "$p2/.claude/hooks/protected-paths.conf"
out=$("$SETUP_SCRIPT" --doctor --project="$p2" 2>&1)
assert_true "--doctor reports a missing hook conf" grep -qi "protected-paths" <<< "$out"

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
