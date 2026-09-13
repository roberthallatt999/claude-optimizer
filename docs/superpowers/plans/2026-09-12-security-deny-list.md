# Shared Sensitive-File Deny-List Implementation Plan

> **Status (2026-09-13): implemented and superseded.** The deny-list work landed as part of the broader
> `apply_security_policy()` (deny + ask rules, `safety-guard.sh` PreToolUse hook, allow-rule revocation),
> covered by `test-security-policy.sh` and `test-safety-guard.sh`. `apply_security_denies()` no longer exists.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `projects/common/security.settings.local.json` the single, always-applied source of truth for sensitive-file `Read()` deny rules, so every stack — including `nuxt`, `remix`, `sveltekit`, and `t3-stack`, which currently ship **zero** deny rules — gets full secret-read protection on both deploy and `--refresh`.

**Architecture:** `apply_security_denies()` already exists in `setup-project.sh` (added in the working tree, lines 853–867) but is **never called** — it is dead code today. This plan hardens that function, wires it into the fresh-deploy and `--refresh` paths immediately after the per-stack `settings.local.json` merge, adds a bash integration test suite in the repo's existing `test-*.sh` style, then removes the duplicated `permissions.deny` arrays from the 15 stack templates that carry them so the common file is the only place deny rules are maintained.

**Tech Stack:** Bash 3.2+ (macOS default), `jq` for JSON merging, `mktemp`-based integration tests (pattern: `test-stack-detection.sh`).

**Spec:** This document — see "Spec" below. (No separate brainstorm doc exists; the spec was reverse-engineered from the in-flight working-tree changes and verified against the repo.)

---

## Spec

### Problem

1. `apply_security_denies()` is defined but never invoked. The new `projects/common/security.settings.local.json` (58 deny rules) is deployed nowhere.
2. `projects/nuxt`, `projects/remix`, `projects/sveltekit`, and `projects/t3-stack` have **no `permissions.deny` key at all**. Projects on those stacks can read `.env`, `id_rsa`, `credentials.json`, etc. with no permission-layer block.
3. The other 15 stack templates each duplicate a 48–53-entry deny list. Adding a new pattern means editing 15 files; drift is inevitable (e.g. `Read(**/.pgpass)` and `Read(**/config.php)` exist in the common file but in no stack template).

### Requirements

- **R1** — Every fresh deploy applies the full common deny-list, for all stacks, with no flag.
- **R2** — Every `--refresh` applies it too (so already-deployed projects get new rules).
- **R3** — Project-added `allow` and `deny` entries are never dropped (union merge, existing wins for scalars — `merge_settings_json` already guarantees this).
- **R4** — Idempotent: a second run adds 0 rules and prints "already up to date".
- **R5** — `--dry-run` writes nothing and reports what would change.
- **R6** — The common file must never be copied to the project under its own basename (`.claude/security.settings.local.json` would be dead weight Claude Code never reads).
- **R7** — After the cleanup, `projects/common/security.settings.local.json` is the only file in the repo containing generic secret-read deny rules.
- **R8** — If `jq` is missing, the script must fail *loudly* on the security merge (after R7, a silent skip means zero protection).

### Verified facts (checked against the repo before writing this plan)

- The common file's 58 deny rules are a **strict superset** of every stack template's deny list. Verified for all 19 stacks:
  `jq -s '((.[0].permissions.deny // []) - (.[1].permissions.deny // [])) | length' <stack> projects/common/security.settings.local.json` returns `0` for every stack. **Nothing is lost by deleting the per-stack arrays.**
- 15 templates have a `permissions.deny` key and are already jq-canonical (`jq . file` is byte-identical to `file`), so `del(.permissions.deny)` produces a clean, deny-only diff.
- 4 templates (`nuxt`, `remix`, `sveltekit`, `t3-stack`) have no `deny` key and must not be touched.
- `merge_settings_json` (line 762) copies the *template file under its own name* when the target does not exist — the R6 hazard.

## Global Constraints

- Bash must stay macOS-`/bin/bash` (3.2) compatible: no `declare -A`, no `${var,,}`, no `mapfile`.
- Script uses `set -e`-style discipline and the existing helpers: `do_copy`, `do_mkdir`, `do_template`, `merge_settings_json`. Reuse them; do not hand-roll new copy logic except where R6 requires it.
- All user-facing output uses the existing colour vars: `${GREEN}`, `${YELLOW}`, `${RED}`, `${CYAN}`, `${NC}`, with the established glyphs `✓` / `○` / `⚠` / `✗`.
- Every code path must honour `DRY_RUN` (`[[ "$DRY_RUN" == true ]]`).
- Never hardcode the number 58 in tests — derive it from `projects/common/security.settings.local.json` so the tests survive future additions.
- Test invocations must be non-interactive: `setup-project.sh` prompts at line 1672 (existing config) and line 1900 (VSCode). Always pass `--force --skip-vscode --no-superpowers`.
- Commit messages: Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`), matching `git log`.

---

### Task 1: Harden `apply_security_denies()` and wire it into fresh deploy

**Files:**
- Create: `test-security-denies.sh` (repo root, executable)
- Modify: `setup-project.sh:853-867` (the `apply_security_denies` function)
- Modify: `setup-project.sh:1874-1877` (the `# 3. Copy/merge settings.local.json` block)

**Interfaces:**
- Consumes: `merge_settings_json <template> <target>`, `do_mkdir <dir>`, globals `$SCRIPT_DIR`, `$PROJECT_DIR`, `$DRY_RUN`.
- Produces: `apply_security_denies()` — no arguments, no return value used; reads `$SCRIPT_DIR/projects/common/security.settings.local.json` and merges into `$PROJECT_DIR/.claude/settings.local.json`. Later tasks call it verbatim as `apply_security_denies`.
- Produces (test harness): `test-security-denies.sh` with helpers `make_project`, `deploy`, `deny_count <file>`, `expected_deny_count`, `assert_eq <name> <expected> <actual>`, `assert_file_absent <name> <path>`, and the `PASS`/`FAIL` counters. Tasks 2–4 add tests to this file using those helpers.

- [ ] **Step 1: Write the failing test harness + first test**

Create `test-security-denies.sh`:

```bash
#!/usr/bin/env bash
# test-security-denies.sh — Integration tests for the shared sensitive-file deny-list
#
# Usage: ./test-security-denies.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
SECURITY_FILE="$SCRIPT_DIR/projects/common/security.settings.local.json"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Helpers
# ============================================================================

make_project() {
  local dir
  dir="$(mktemp -d)"
  echo "$dir"
}

cleanup() {
  local dir="$1"
  [[ -d "$dir" ]] && rm -rf "$dir"
}

# Run setup-project.sh non-interactively. Extra args are passed through.
# Prompts live at setup-project.sh:1672 (existing config) and :1900 (VSCode),
# so --force and --skip-vscode are mandatory here.
deploy() {
  local project_dir="$1"
  shift
  "$SETUP_SCRIPT" --project="$project_dir" --force --skip-vscode --no-superpowers "$@" >/dev/null 2>&1 || true
}

deny_count() {
  local file="$1"
  [[ -f "$file" ]] || { echo "0"; return; }
  jq '(.permissions.deny // []) | length' "$file"
}

allow_contains() {
  local file="$1" rule="$2"
  jq -e --arg r "$rule" '((.permissions.allow // []) | index($r)) != null' "$file" >/dev/null 2>&1
}

expected_deny_count() {
  jq '.permissions.deny | length' "$SECURITY_FILE"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}PASS${NC} $name (= $actual)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local name="$1"
  shift
  if "$@"; then
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_absent() {
  local name="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo -e "${GREEN}PASS${NC} $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → unexpected file: $path"
    FAIL=$((FAIL + 1))
  fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

EXPECTED=$(expected_deny_count)

# ============================================================================
# Fresh deploy
# ============================================================================

echo ""
echo -e "${CYAN}=== Fresh Deploy ===${NC}"
echo ""

# A stack whose template ships ZERO deny rules — the gap this feature closes.
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$p/package.json"
deploy "$p"
assert_eq "nuxt deploy applies full deny-list" "$EXPECTED" "$(deny_count "$p/.claude/settings.local.json")"
assert_file_absent "no stray security.settings.local.json (R6)" "$p/.claude/security.settings.local.json"
cleanup "$p"

# A stack whose template already had a deny list — must not regress.
p=$(make_project)
touch "$p/next.config.js"
echo '{"name":"test","dependencies":{"next":"14.0.0","react":"18.0.0"}}' > "$p/package.json"
deploy "$p"
assert_eq "nextjs deploy applies full deny-list" "$EXPECTED" "$(deny_count "$p/.claude/settings.local.json")"
cleanup "$p"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${CYAN}================================${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS"
if [[ $FAIL -gt 0 ]]; then
  echo -e "  ${RED}FAIL${NC}: $FAIL"
else
  echo -e "  FAIL: $FAIL"
fi
echo -e "${CYAN}================================${NC}"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}✗ $FAIL test(s) failed${NC}"
  exit 1
else
  echo -e "${GREEN}✓ All $PASS tests passed${NC}"
  exit 0
fi
```

- [ ] **Step 2: Make it executable and run it to verify it fails**

```bash
chmod +x test-security-denies.sh
./test-security-denies.sh
```

Expected: FAIL on "nuxt deploy applies full deny-list" — expected `58`, got `0` (the nuxt template has no deny key and `apply_security_denies` is never called). The nextjs case may pass already (its template ships 48 of the 58) — it will still be short of `58`, so expect it to fail too with `expected '58', got '48'`.

- [ ] **Step 3: Harden `apply_security_denies()`**

Replace the whole function at `setup-project.sh:853-867` with:

```bash
# Merge the shared, stack-agnostic sensitive-file deny-list into the project's
# settings.local.json. Runs for EVERY stack — including templates that ship no
# deny list at all — so no project is ever left without read-protection on
# secrets (.env, keys, credentials, config.php, wp-config.php, DB dumps, etc.).
# Single source of truth: projects/common/security.settings.local.json.
apply_security_denies() {
  local security_file="$SCRIPT_DIR/projects/common/security.settings.local.json"
  local target_file="$PROJECT_DIR/.claude/settings.local.json"

  if [[ ! -f "$security_file" ]]; then
    echo ""
    echo -e "  ${RED}✗${NC}  Missing $security_file"
    echo -e "      Sensitive-file deny rules were NOT applied."
    return 0
  fi

  echo ""
  echo -e "${CYAN}Applying shared sensitive-file safeguards...${NC}"

  # Do NOT fall through to merge_settings_json's "target missing → copy template"
  # branch: it copies under the template's own basename, which would create
  # .claude/security.settings.local.json — a file Claude Code never reads.
  if [[ ! -f "$target_file" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Create settings.local.json from the shared deny-list"
    else
      do_mkdir "$(dirname "$target_file")"
      cp "$security_file" "$target_file"
      echo -e "  ${GREEN}✓${NC} Created settings.local.json with sensitive-file deny rules"
    fi
    return 0
  fi

  merge_settings_json "$security_file" "$target_file"
}
```

- [ ] **Step 4: Call it from the fresh-deploy path**

At `setup-project.sh:1874-1877`, the block currently reads:

```bash
# 3. Copy/merge settings.local.json
if [[ -f "$STACK_DIR/settings.local.json" ]]; then
  merge_settings_json "$STACK_DIR/settings.local.json" "$PROJECT_DIR/.claude/settings.local.json"
fi
```

Change it to:

```bash
# 3. Copy/merge settings.local.json
if [[ -f "$STACK_DIR/settings.local.json" ]]; then
  merge_settings_json "$STACK_DIR/settings.local.json" "$PROJECT_DIR/.claude/settings.local.json"
fi

# 3b. Apply the shared sensitive-file deny-list (all stacks, no flag required)
apply_security_denies
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
./test-security-denies.sh
```

Expected: `✓ All 3 tests passed`

- [ ] **Step 6: Verify the existing suite still passes**

```bash
./test-stack-detection.sh
```

Expected: `✓ All N tests passed` (same N as before the change; the new output line is additive and detection assertions do not match on it).

- [ ] **Step 7: Commit**

```bash
git add setup-project.sh projects/common/security.settings.local.json test-security-denies.sh
git commit -m "feat(security): apply shared sensitive-file deny-list on every deploy"
```

---

### Task 2: Apply the deny-list on `--refresh`

**Files:**
- Modify: `setup-project.sh:1612-1615` (refresh-mode settings merge)
- Modify: `setup-project.sh:1650` (the "Preserved & merged" summary block)
- Modify: `test-security-denies.sh` (add a `=== Refresh ===` section before the Summary section)

**Interfaces:**
- Consumes: `apply_security_denies` from Task 1; test helpers `make_project`, `deploy`, `deny_count`, `allow_contains`, `assert_eq`, `assert_true`, `$EXPECTED` from Task 1.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Insert into `test-security-denies.sh`, immediately before the `# === Summary ===` banner block:

```bash
# ============================================================================
# Refresh
# ============================================================================

echo ""
echo -e "${CYAN}=== Refresh ===${NC}"
echo ""

# An already-configured project with a hand-written allow rule and no denies —
# --refresh must add the deny-list and keep the custom allow rule (R2, R3).
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$p/package.json"
mkdir -p "$p/.claude"
cat > "$p/.claude/settings.local.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(my-custom-command:*)"
    ]
  }
}
JSON
deploy "$p" --refresh --stack=nuxt
assert_eq "refresh applies full deny-list" "$EXPECTED" "$(deny_count "$p/.claude/settings.local.json")"
assert_true "refresh preserves project-specific allow rule" \
  allow_contains "$p/.claude/settings.local.json" "Bash(my-custom-command:*)"
cleanup "$p"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./test-security-denies.sh
```

Expected: FAIL on "refresh applies full deny-list" — `expected '58', got '0'` (the nuxt template contributes no denies and refresh never calls `apply_security_denies`).

- [ ] **Step 3: Call `apply_security_denies` in the refresh path**

At `setup-project.sh:1612-1615`, the block currently reads:

```bash
  # Merge settings.local.json (adds missing global rules, preserves project customizations)
  if [[ -f "$STACK_DIR/settings.local.json" ]]; then
    merge_settings_json "$STACK_DIR/settings.local.json" "$PROJECT_DIR/.claude/settings.local.json"
  fi
```

Change it to:

```bash
  # Merge settings.local.json (adds missing global rules, preserves project customizations)
  if [[ -f "$STACK_DIR/settings.local.json" ]]; then
    merge_settings_json "$STACK_DIR/settings.local.json" "$PROJECT_DIR/.claude/settings.local.json"
  fi

  # Re-apply the shared sensitive-file deny-list so existing projects pick up new rules
  apply_security_denies
```

- [ ] **Step 4: Update the refresh summary output**

At `setup-project.sh:1650`, the line currently reads:

```bash
  echo -e "  settings.local.json (allow)  (project-specific rules kept)"
```

Change it to:

```bash
  echo -e "  settings.local.json (allow)  (project-specific rules kept)"
  echo -e "  settings.local.json (deny)   (shared sensitive-file rules re-applied)"
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
./test-security-denies.sh
```

Expected: `✓ All 5 tests passed`

- [ ] **Step 6: Commit**

```bash
git add setup-project.sh test-security-denies.sh
git commit -m "feat(security): re-apply sensitive-file deny-list on --refresh"
```

---

### Task 3: Lock in idempotency and dry-run safety

These are regression tests for behaviour Tasks 1–2 introduced (R4, R5). They are expected to **pass on the first run** — their value is catching a future change that breaks the union-merge or starts writing during `--dry-run`. If one fails, that is a real bug in Task 1/2 and must be fixed before committing.

**Files:**
- Modify: `test-security-denies.sh` (add an `=== Idempotency & Dry-Run ===` section before the Summary section)

**Interfaces:**
- Consumes: all helpers from Task 1 (`make_project`, `deploy`, `deny_count`, `assert_eq`, `assert_true`, `assert_file_absent`, `$EXPECTED`).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the tests**

Insert into `test-security-denies.sh`, immediately before the `# === Summary ===` banner block:

```bash
# ============================================================================
# Idempotency & Dry-Run
# ============================================================================

echo ""
echo -e "${CYAN}=== Idempotency & Dry-Run ===${NC}"
echo ""

# Running twice must not duplicate rules (merge does `unique`) — R4.
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$p/package.json"
deploy "$p"
first=$(deny_count "$p/.claude/settings.local.json")
deploy "$p"
second=$(deny_count "$p/.claude/settings.local.json")
assert_eq "second deploy adds no duplicate deny rules" "$first" "$second"
assert_eq "deny count still matches source of truth" "$EXPECTED" "$second"
cleanup "$p"

# A project-added deny rule survives the merge — R3.
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$p/package.json"
mkdir -p "$p/.claude"
cat > "$p/.claude/settings.local.json" <<'JSON'
{
  "permissions": {
    "deny": [
      "Read(**/super-secret-project-file.txt)"
    ]
  }
}
JSON
deploy "$p" --refresh --stack=nuxt
assert_eq "project deny rule kept alongside shared rules" "$((EXPECTED + 1))" \
  "$(deny_count "$p/.claude/settings.local.json")"
cleanup "$p"

# --dry-run must not write anything — R5.
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.11.0"}}' > "$p/package.json"
deploy "$p" --dry-run
assert_file_absent "dry-run writes no settings.local.json" "$p/.claude/settings.local.json"
assert_file_absent "dry-run writes no security.settings.local.json" "$p/.claude/security.settings.local.json"
cleanup "$p"
```

- [ ] **Step 2: Run the tests**

```bash
./test-security-denies.sh
```

Expected: `✓ All 10 tests passed`. If "second deploy adds no duplicate deny rules" fails, the `unique` in `merge_settings_json` (line ~823) has regressed. If a dry-run assertion fails, a write path in `apply_security_denies` is ignoring `$DRY_RUN` — fix it in `setup-project.sh` before committing.

- [ ] **Step 3: Commit**

```bash
git add test-security-denies.sh
git commit -m "test(security): cover deny-list idempotency, merge preservation, dry-run"
```

---

### Task 4: Make the common file the single source of truth

Deletes the duplicated `permissions.deny` arrays from the 15 stack templates that carry them. Safe because the common file is a verified strict superset of all of them (see "Verified facts"). Because the templates then contribute no denies, a missing `jq` becomes a total loss of protection — so this task also makes that case loud (R8).

**Files:**
- Modify: `projects/{astro,astro-sanity,astro-strapi,astro-tina,coilpack,craftcms,craftcms-nextjs,craftcms-nuxt,custom,docusaurus,ee-nextjs,expressionengine,nextjs,wordpress,wordpress-roots}/settings.local.json` (15 files — remove `permissions.deny`)
- Do **not** touch: `projects/{nuxt,remix,sveltekit,t3-stack}/settings.local.json` (no `deny` key; they are not jq-canonical and rewriting them would produce noisy formatting-only diffs)
- Modify: `setup-project.sh` — `apply_security_denies()` (add the jq guard)
- Modify: `test-security-denies.sh` (add a `=== Single Source of Truth ===` section before the Summary section)

**Interfaces:**
- Consumes: all helpers from Task 1.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Insert into `test-security-denies.sh`, immediately before the `# === Summary ===` banner block:

```bash
# ============================================================================
# Single Source of Truth
# ============================================================================

echo ""
echo -e "${CYAN}=== Single Source of Truth ===${NC}"
echo ""

# No stack template may carry its own generic deny list — R7.
stray=""
for f in "$SCRIPT_DIR"/projects/*/settings.local.json; do
  count=$(jq '(.permissions.deny // []) | length' "$f")
  if [[ "$count" != "0" ]]; then
    stray="$stray $(basename "$(dirname "$f")")"
  fi
done
assert_eq "no stack template carries its own deny list" "" "$stray"

# ...and the deny rules still arrive at the project anyway.
for stack in wordpress craftcms expressionengine; do
  p=$(make_project)
  deploy "$p" --stack="$stack"
  assert_eq "$stack deploy still gets full deny-list" "$EXPECTED" \
    "$(deny_count "$p/.claude/settings.local.json")"
  cleanup "$p"
done
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./test-security-denies.sh
```

Expected: FAIL on "no stack template carries its own deny list" — got a list of 15 stack names.

- [ ] **Step 3: Re-verify the superset claim before deleting anything**

```bash
for f in projects/*/settings.local.json; do
  extra=$(jq -s '((.[0].permissions.deny // []) - (.[1].permissions.deny // [])) | length' \
    "$f" projects/common/security.settings.local.json)
  printf "%-22s extra=%s\n" "$(basename "$(dirname "$f")")" "$extra"
done
```

Expected: `extra=0` on every line. **If any line shows a non-zero count, stop** — that stack has a deny rule the common file lacks. Add those exact rules to `projects/common/security.settings.local.json` first, then re-run this step until every line reads `extra=0`.

- [ ] **Step 4: Strip the deny arrays**

```bash
for f in projects/*/settings.local.json; do
  if [[ "$(jq '(.permissions.deny // []) | length' "$f")" != "0" ]]; then
    tmp=$(mktemp)
    jq 'del(.permissions.deny)' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "stripped: $f"
  fi
done
```

- [ ] **Step 5: Confirm the diff is deny-only**

```bash
git diff --stat projects/
git diff projects/ | grep -E '^[+-]' | grep -v '^[+-][+-]' | grep -v '"Read(' | sort -u
```

Expected: 15 files changed. The second command should print only the `-    "deny": [`, `-    ],` and matching structural lines — **no `allow` or `enabledMcpjsonServers` lines**. If anything else appears, `git checkout -- projects/` and redo Step 4.

- [ ] **Step 6: Make a missing `jq` loud**

In `apply_security_denies()` (`setup-project.sh`), insert this block immediately after the `echo -e "${CYAN}Applying shared sensitive-file safeguards...${NC}"` line and before the `if [[ ! -f "$target_file" ]]` block:

```bash
  # Stack templates no longer carry deny rules, so a silent jq-less skip here
  # means the project ends up with NO secret-read protection at all.
  if [[ -f "$target_file" ]] && ! command -v jq &>/dev/null; then
    echo -e "  ${RED}✗${NC}  jq not installed — sensitive-file deny rules could NOT be merged."
    echo -e "      Install jq (brew install jq) and re-run, or copy the deny list from:"
    echo -e "      $security_file"
    return 0
  fi
```

- [ ] **Step 7: Run both suites**

```bash
./test-security-denies.sh && ./test-stack-detection.sh
```

Expected: `✓ All 14 tests passed` then `✓ All N tests passed`.

- [ ] **Step 8: Commit**

```bash
git add projects setup-project.sh test-security-denies.sh
git commit -m "refactor(security): make common deny-list the single source of truth"
```

---

### Task 5: Documentation

**Files:**
- Modify: `CLAUDE.md` (the `## Recent Changes` list — add a new first bullet)
- Modify: `docs/guides/setup-script.md:83-94` ("What Gets Deployed") and `:300-325` ("Safety Guardrails (Always Deployed)")
- Modify: `docs/guides/updating-projects.md:122-130` ("Regenerated During --refresh")
- Modify: `docs/reference/file-structure.md:51-62` (the `projects/common/` tree)

**Interfaces:**
- Consumes: the finished behaviour from Tasks 1–4.
- Produces: nothing.

- [ ] **Step 1: Add the `CLAUDE.md` Recent Changes entry**

Insert as the **first** bullet under `## Recent Changes`:

```markdown
- **Sensitive-file deny-list is now shared and always applied** — `projects/common/security.settings.local.json` is the single source of truth for secret-read `deny` rules, merged into every project's `settings.local.json` on both deploy and `--refresh` via `apply_security_denies()`. The per-stack `permissions.deny` arrays were removed from all 15 stack templates that had them (the common file was a verified superset), and `nuxt`/`remix`/`sveltekit`/`t3-stack` — which previously shipped **zero** deny rules — are now covered. Adding a new pattern means editing one file. Covered by `test-security-denies.sh`.
```

- [ ] **Step 2: Update "What Gets Deployed" in `docs/guides/setup-script.md`**

Replace the line:

```markdown
- `.claude/settings.local.json` - Stack-appropriate permissions
```

with:

```markdown
- `.claude/settings.local.json` - Stack-appropriate permissions, plus the shared
  sensitive-file `deny` rules (always applied, every stack, no flag required)
```

- [ ] **Step 3: Update the Safety Guardrails enforcement bullet in `docs/guides/setup-script.md`**

Replace the bullet:

```markdown
- **Enforcement:** the `deny` list in `.claude/settings.local.json` blocks reads of
  `.env`, keys, certs, and other secret files at the permission layer.
```

with:

```markdown
- **Enforcement:** the `deny` list in `.claude/settings.local.json` blocks reads of
  `.env`, keys, certs, DB dumps, `config.php`/`wp-config.php`, and other secret
  files at the permission layer. The list is maintained in one place —
  `projects/common/security.settings.local.json` — and merged into every project
  on both deploy and `--refresh`, so adding a pattern there reaches every project
  on its next refresh. Requires `jq`; the script reports an error if it is missing.
```

- [ ] **Step 4: Update `docs/guides/updating-projects.md`**

Replace the line under "Regenerated During --refresh":

```markdown
- `settings.local.json` - Updated with permissions
```

with:

```markdown
- `settings.local.json` - Updated with permissions. The shared sensitive-file
  `deny` rules are re-applied on every refresh (union merge — your own `allow`
  and `deny` entries are kept)
```

- [ ] **Step 5: Update `docs/reference/file-structure.md`**

In the `projects/common/` tree (around line 51), add `security.settings.local.json` after the `rules/` subtree, so the block reads:

```
    ├── common/                   # Global fallback templates
    │   ├── rules/                # Common rules (deployed to all/most stacks)
    │   │   ├── memory-management.md
    │   │   ├── token-optimization.md
    │   │   ├── sensitive-files.md
    │   │   ├── deployment-safety.md
    │   │   ├── accessibility.md
    │   │   ├── performance.md
    │   │   ├── typescript-patterns.md  # Strict TS, discriminated unions
    │   │   ├── design-system.md        # Token-first design, cva variants
    │   │   └── api-design.md           # Zod validation, response envelopes
    │   ├── security.settings.local.json  # Sensitive-file deny rules (all stacks, always merged)
    │   └── MEMORY.md.template    # Memory bank template (with Design System, Integrations, API inventory)
```

- [ ] **Step 6: Verify no stale claims remain**

```bash
grep -rn "Stack-appropriate permissions" docs/ README.md CLAUDE.md
grep -rn "settings.local.json" docs/reference/file-structure.md
```

Expected: the only "Stack-appropriate permissions" hit is the line updated in Step 2. Review any other `settings.local.json` reference in `file-structure.md` for accuracy and fix it inline.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs(security): document the shared sensitive-file deny-list"
```

---

## Post-Implementation Verification

- [ ] `./test-security-denies.sh` → all pass
- [ ] `./test-stack-detection.sh` → all pass (no regressions)
- [ ] Real-project smoke test on a copy, not the original:

```bash
cp -R /path/to/a/real/project /tmp/deny-smoke && \
  ./setup-project.sh --project=/tmp/deny-smoke --refresh --skip-vscode --no-superpowers && \
  jq '.permissions.deny | length' /tmp/deny-smoke/.claude/settings.local.json
```

Expected: prints `58` (or the current `jq '.permissions.deny | length' projects/common/security.settings.local.json`), and `git -C /tmp/deny-smoke diff` shows only additive deny entries.

- [ ] `git log --oneline -6` shows the five task commits in order
