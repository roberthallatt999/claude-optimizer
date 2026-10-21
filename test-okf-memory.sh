#!/usr/bin/env bash
# test-okf-memory.sh — --okf-memory bundle, okf-check.sh conformance checks, and the
# detect-and-register codegraph integration (using fake codegraph/claude binaries).
#
# Usage: ./test-okf-memory.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
CHECKER="$SCRIPT_DIR/projects/common/okf/okf-check.sh"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }
export AI_CONFIG_USER_SETTINGS="/nonexistent/settings.json"

TMPS=()
tmp_dir() { local d; d="$(mktemp -d)"; TMPS+=("$d"); echo "$d"; }
cleanup_all() { local d; for d in "${TMPS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"; FAIL=$((FAIL + 1)); fi
}
assert_true() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1)); fi
}
assert_false() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo -e "${RED}FAIL${NC} $name"; FAIL=$((FAIL + 1))
  else echo -e "${GREEN}PASS${NC} $name"; PASS=$((PASS + 1)); fi
}

concept() {  # concept <file> <type-line-or-empty> [extra frontmatter...]
  local file="$1" type_line="$2"
  shift 2
  mkdir -p "$(dirname "$file")"
  { echo "---"; [[ -n "$type_line" ]] && echo "$type_line"; printf '%s\n' "$@"; echo "---"; echo; echo "Body."; } > "$file"
}
check_output() { bash "$CHECKER" "$1" 2>&1; }

# ============================================================================
echo -e "\n${CYAN}=== okf-check.sh ===${NC}\n"
# ============================================================================

b=$(tmp_dir)
printf -- '---\nokf_version: "0.2"\n---\n\n# Index\n\n- [Auth](/decisions/auth.md) — auth choice\n' > "$b/index.md"
printf '# Log\n\n## 2026-09-13\n\n- Initial.\n' > "$b/log.md"
concept "$b/decisions/auth.md" "type: Decision" "title: Auth"
assert_true "conformant bundle passes" bash "$CHECKER" "$b"

concept "$b/decisions/no-type.md" ""
assert_false "concept without type fails" bash "$CHECKER" "$b"
rm "$b/decisions/no-type.md"

printf 'No frontmatter here\n' > "$b/architecture.md"
assert_true "missing frontmatter reported" grep -q "missing YAML frontmatter" <<< "$(check_output "$b")"
rm "$b/architecture.md"

printf '# Log\n\n## September 13\n' > "$b/log.md"
assert_false "non-ISO log heading fails" bash "$CHECKER" "$b"
printf '# Log\n\n## 2026-09-13\n' > "$b/log.md"

concept "$b/issues/old.md" "type: Known Issue" "stale_after: 2020-01-01T00:00:00Z"
out=$(check_output "$b"); status=$?
assert_eq "stale concept is a warning, not an error" "0" "$status"
assert_true "stale concept reported" grep -q "stale since 2020-01-01" <<< "$out"

printf -- '- [Missing](/decisions/missing.md)\n' >> "$b/index.md"
assert_true "broken link reported" grep -q "broken link → /decisions/missing.md" <<< "$(check_output "$b")"

fake_token="gh""p_$(printf 'a%.0s' $(seq 1 36))"
concept "$b/integrations/github.md" "type: Integration" "title: GitHub"
echo "token: $fake_token" >> "$b/integrations/github.md"
assert_true "credential-looking text reported" grep -q "looks like a real credential" <<< "$(check_output "$b")"

mkdir -p "$b/decisions" && printf -- '---\ntype: x\n---\n' > "$b/decisions/index.md"
assert_true "frontmatter on nested index.md warned" grep -q "only the bundle-root index.md" <<< "$(check_output "$b")"

# ============================================================================
echo -e "\n${CYAN}=== --okf-memory deploy & refresh ===${NC}\n"
# ============================================================================

make_nuxt() {
  local d; d=$(tmp_dir)
  touch "$d/nuxt.config.ts"
  echo '{"name":"t","dependencies":{"nuxt":"3.11.0"}}' > "$d/package.json"
  printf 'node_modules\n' > "$d/.gitignore"
  echo "$d"
}
run() { local d="$1"; shift; "$SETUP_SCRIPT" --project="$d" --skip-vscode --no-superpowers "$@" >/dev/null 2>&1; }

p=$(make_nuxt)
run "$p" --force --okf-memory
for f in index.md log.md handoff.md; do assert_true "seeded .okf/$f" test -f "$p/.okf/$f"; done
assert_true "seeded bundle is conformant" bash "$CHECKER" "$p/.okf"
assert_true "index declares okf_version" grep -q '^okf_version: "0.2"' "$p/.okf/index.md"
assert_false "no {{placeholders}} left in seed files" grep -rq '{{' "$p/.okf"
assert_false "MEMORY.md not created in OKF mode" test -f "$p/MEMORY.md"
assert_eq "OKF memory block present once" "1" "$(grep -c '<!-- BEGIN OKF MEMORY PROTOCOL' "$p/CLAUDE.md")"
assert_eq "MEMORY.md protocol block absent" "0" "$(grep -c '<!-- BEGIN MEMORY PROTOCOL' "$p/CLAUDE.md")"
assert_true "scoped okf-memory rule deployed" grep -q '".okf/\*\*"' "$p/.claude/rules/okf-memory.md"
assert_true "checker deployed and executable" test -x "$p/.claude/scripts/okf-check.sh"
assert_true ".okf/ gitignored" grep -qxF ".okf/" "$p/.gitignore"
assert_eq "checker allowed without prompt" "true" \
  "$(jq '.permissions.allow | index("Bash(bash .claude/scripts/okf-check.sh)") != null' "$p/.claude/settings.local.json")"

echo "- KEEP-LOG-ENTRY" >> "$p/.okf/log.md"
echo "KEEP-HANDOFF" >> "$p/.okf/handoff.md"
concept "$p/.okf/decisions/db.md" "type: Decision" "title: DB"
run "$p" --refresh
assert_true "refresh without the flag keeps OKF mode (sticky)" grep -q '<!-- BEGIN OKF MEMORY PROTOCOL' "$p/CLAUDE.md"
assert_true "log.md history never overwritten" grep -q KEEP-LOG-ENTRY "$p/.okf/log.md"
assert_true "handoff.md never overwritten" grep -q KEEP-HANDOFF "$p/.okf/handoff.md"
assert_true "agent-written concept untouched" test -f "$p/.okf/decisions/db.md"
assert_false "still no MEMORY.md after refresh" test -f "$p/MEMORY.md"

p=$(make_nuxt)
run "$p" --force
echo "| 2026-01-01 | KEEP-LEGACY-MEMORY | x |" >> "$p/MEMORY.md"
memory_sha=$(shasum -a 256 "$p/MEMORY.md" | cut -d' ' -f1)
run "$p" --refresh --okf-memory
assert_eq "adopting OKF leaves MEMORY.md byte-identical" "$memory_sha" "$(shasum -a 256 "$p/MEMORY.md" | cut -d' ' -f1)"
assert_eq "MEMORY.md protocol block swapped for the OKF block" "0|1" \
  "$(grep -c '<!-- BEGIN MEMORY PROTOCOL' "$p/CLAUDE.md")|$(grep -c '<!-- BEGIN OKF MEMORY PROTOCOL' "$p/CLAUDE.md")"

p=$(make_nuxt)
run "$p" --dry-run --okf-memory
assert_false "--dry-run creates no bundle" test -d "$p/.okf"

# ============================================================================
echo -e "\n${CYAN}=== codegraph: detect & register only ===${NC}\n"
# ============================================================================

bin=$(tmp_dir)
export FAKE_CLAUDE_LOG="$bin/claude.log" FAKE_CLAUDE_STATE="$bin/registered"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/codegraph"
cat > "$bin/claude" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CLAUDE_LOG"
case "$1 $2" in
  "mcp get") [[ -f "$FAKE_CLAUDE_STATE" ]]; exit $? ;;
  "mcp add") touch "$FAKE_CLAUDE_STATE" ;;
esac
exit 0
SH
chmod +x "$bin/codegraph" "$bin/claude"
add_count() { if [[ -f "$FAKE_CLAUDE_LOG" ]]; then grep -c '^mcp add' "$FAKE_CLAUDE_LOG"; else echo 0; fi; }

p=$(make_nuxt)
PATH="$bin:$PATH" run "$p" --force
assert_eq "no index → nothing registered" "0" "$(add_count)"
assert_eq "no index → no Code Index block" "0" "$(grep -c '<!-- BEGIN CODE INDEX' "$p/CLAUDE.md")"

mkdir -p "$p/.codegraph"
PATH="$bin:$PATH" run "$p" --refresh
PATH="$bin:$PATH" run "$p" --refresh
assert_eq "existing index → registered exactly once" "1" "$(add_count)"
assert_true "registered at local scope with serve --mcp" grep -qx 'mcp add --scope local codegraph -- codegraph serve --mcp' "$FAKE_CLAUDE_LOG"
assert_eq "Code Index block present once" "1" "$(grep -c '<!-- BEGIN CODE INDEX' "$p/CLAUDE.md")"
assert_true ".codegraph/ gitignored" grep -qxF ".codegraph/" "$p/.gitignore"

rm -f "$FAKE_CLAUDE_LOG" "$FAKE_CLAUDE_STATE"
c=$(tmp_dir)
touch "$c/craft"; echo '{"require":{"craftcms/cms":"^5.0"}}' > "$c/composer.json"; mkdir -p "$c/.codegraph"
PATH="$bin:$PATH" run "$c" --force
assert_eq "PHP CMS stack (craftcms) never registered" "0" "$(add_count)"

# ============================================================================
echo -e "\n${CYAN}=== MEMORY.md → OKF migration (automatic with --okf-memory) ===${NC}\n"
# ============================================================================

make_memory_project() {
  local d
  d=$(tmp_dir)
  touch "$d/nuxt.config.ts"
  echo '{"name":"m","dependencies":{"nuxt":"3.11.0"}}' > "$d/package.json"
  cat > "$d/MEMORY.md" <<'MEM'
# m - Project Memory

## Project Identity

### Overview
A members site for a regional club.

### Repository
git@example.com:club/site.git

## Architecture

### Tech Stack
Nuxt 3 with a Craft GraphQL backend.

### Directory Map
- `pages/` — routes

## Design System

### Design Tokens
Brand green is #2E7D32.

## Third-Party Integrations

### Environment Variables
CRAFT_API_URL, STRIPE_KEY

## Decision Log

### DEC-001: Use Craft GraphQL rather than REST
Typed schema, one round trip.

### DEC-002: No front-end build step
The theme ships plain CSS.

## Active Context

### Current Focus
Rebuilding the members area.

## Session Handoff

### Next Steps
Finish the login flow.

## Empty Section

_None recorded._

## Memory Maintenance

Boilerplate that should never be migrated.
MEM
  echo "$d"
}

m=$(make_memory_project)
# MEMORY.md is history, never rewritten — baseline taken before the first migration.
before_sha=$(shasum "$m/MEMORY.md" | cut -d' ' -f1)
run "$m" --okf-memory --force

assert_true "migration: architecture concept created" test -f "$m/.okf/concepts/architecture.md"
assert_true "migration: design system concept created" test -f "$m/.okf/concepts/design-system.md"
assert_true "migration: integrations concept created" test -f "$m/.okf/concepts/integrations.md"
assert_true "migration: project identity concept created" test -f "$m/.okf/concepts/project-identity.md"
assert_true "migration: decision split per DEC entry (DEC-001)" test -f "$m/.okf/decisions/dec-001.md"
assert_true "migration: decision split per DEC entry (DEC-002)" test -f "$m/.okf/decisions/dec-002.md"

assert_eq "migration: architecture carries its type" "architecture" \
  "$(sed -nE 's/^type:[[:space:]]*//p' "$m/.okf/concepts/architecture.md" | head -1)"
assert_eq "migration: decisions carry their type" "decision" \
  "$(sed -nE 's/^type:[[:space:]]*//p' "$m/.okf/decisions/dec-001.md" | head -1)"
assert_true "migration: frontmatter records the source" \
  grep -qE '^source:[[:space:]]*MEMORY\.md' "$m/.okf/concepts/architecture.md"

assert_true "migration: body content carried over" \
  grep -qF "Craft GraphQL backend" "$m/.okf/concepts/architecture.md"
assert_true "migration: decision body carried over" \
  grep -qF "one round trip" "$m/.okf/decisions/dec-001.md"

assert_true "migration: session sections went to handoff.md" \
  grep -qF "Rebuilding the members area" "$m/.okf/handoff.md"
assert_true "migration: next steps went to handoff.md" \
  grep -qF "Finish the login flow" "$m/.okf/handoff.md"

assert_false "migration: boilerplate section skipped" test -f "$m/.okf/concepts/memory-maintenance.md"
assert_false "migration: placeholder-only section skipped" test -f "$m/.okf/concepts/empty-section.md"

assert_true "migration: index links the architecture concept" \
  grep -qF "(/concepts/architecture.md)" "$m/.okf/index.md"
assert_true "migration: index links decisions under Decisions" \
  awk '/^## Decisions/{f=1;next} /^## /{f=0} f && /dec-001\.md/{found=1} END{exit !found}' "$m/.okf/index.md"
assert_true "migration: index links integrations under Integrations" \
  awk '/^## Integrations/{f=1;next} /^## /{f=0} f && /integrations\.md/{found=1} END{exit !found}' "$m/.okf/index.md"

assert_true "migration: recorded in log.md" grep -qF "MEMORY.md" "$m/.okf/log.md"
assert_true "migration: bundle is still conformant" bash "$CHECKER" "$m/.okf"
assert_eq "migration: no conformance errors" "0" \
  "$(check_output "$m/.okf" | sed -nE 's/.*, ([0-9]+) error\(s\).*/\1/p' | head -1)"


# Idempotence: a second run must not duplicate, and must not clobber an edit.
printf '\nHand-edited note.\n' >> "$m/.okf/concepts/architecture.md"
edited_sha=$(shasum "$m/.okf/concepts/architecture.md" | cut -d' ' -f1)
links_before=$(grep -c "(/concepts/\|(/decisions/" "$m/.okf/index.md")
run "$m" --okf-memory --force
assert_eq "migration: MEMORY.md never modified" "$before_sha" "$(shasum "$m/MEMORY.md" | cut -d' ' -f1)"
assert_eq "migration: an edited concept is not clobbered" "$edited_sha" \
  "$(shasum "$m/.okf/concepts/architecture.md" | cut -d' ' -f1)"
assert_eq "migration: index links not duplicated" "$links_before" \
  "$(grep -c "(/concepts/\|(/decisions/" "$m/.okf/index.md")"
assert_eq "migration: handoff not duplicated" "1" \
  "$(grep -c "Rebuilding the members area" "$m/.okf/handoff.md")"

# A project with no MEMORY.md must be unaffected.
n=$(tmp_dir)
touch "$n/nuxt.config.ts"; echo '{"name":"n","dependencies":{"nuxt":"3.11.0"}}' > "$n/package.json"
run "$n" --okf-memory --force
assert_true "no MEMORY.md: bundle still created" test -f "$n/.okf/index.md"
assert_false "no MEMORY.md: no concepts invented" test -d "$n/.okf/concepts"
assert_true "no MEMORY.md: bundle conformant" bash "$CHECKER" "$n/.okf"

# Without --okf-memory nothing is migrated.
q=$(make_memory_project)
run "$q" --force
assert_false "without --okf-memory: no bundle" test -d "$q/.okf"
assert_true "without --okf-memory: MEMORY.md still in use" test -f "$q/MEMORY.md"

# Never follow a symlink planted in a cloned repo: writes would land outside the project.
outside=$(tmp_dir)
s=$(make_memory_project)
mkdir -p "$s/.okf"
ln -s "$outside" "$s/.okf/concepts"
run "$s" --okf-memory --force
assert_eq "symlinked concepts dir: nothing written outside the project" "" "$(ls -A "$outside")"

s=$(make_memory_project)
mkdir -p "$s/.okf/concepts"
ln -s "$outside/planted.md" "$s/.okf/concepts/architecture.md"
run "$s" --okf-memory --force
assert_false "dangling symlinked concept: its target is never created" test -e "$outside/planted.md"
assert_true "dangling symlinked concept: other sections still migrate" test -f "$s/.okf/concepts/design-system.md"

secret_dir=$(tmp_dir)
printf '## Architecture\n\nOUTSIDE-SECRET\n' > "$secret_dir/notes.md"
s=$(make_memory_project)
rm "$s/MEMORY.md"
ln -s "$secret_dir/notes.md" "$s/MEMORY.md"
run "$s" --okf-memory --force
assert_false "symlinked MEMORY.md: outside content never copied in" grep -rqF "OUTSIDE-SECRET" "$s/.okf"

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
