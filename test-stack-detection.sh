#!/usr/bin/env bash
# test-stack-detection.sh — Integration tests for setup-project.sh stack detection
#
# Usage: ./test-stack-detection.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"
PASS=0
FAIL=0
SKIP=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Run setup-project.sh in dry-run mode and capture stdout.
# Returns: stdout in variable DETECTION_OUTPUT
run_detection() {
  local project_dir="$1"
  DETECTION_OUTPUT="$("$SETUP_SCRIPT" --project="$project_dir" --dry-run 2>&1 || true)"
}

assert_stack() {
  local name="$1"
  local project_dir="$2"
  local expected_stack="$3"

  run_detection "$project_dir"

  if echo "$DETECTION_OUTPUT" | grep -qE "Auto-detected stack.*(from project files|from CLAUDE\.md): $expected_stack"; then
    echo -e "${GREEN}PASS${NC} $name → detected '$expected_stack'"
    PASS=$((PASS + 1))
  elif echo "$DETECTION_OUTPUT" | grep -qE "stack.*$expected_stack|$expected_stack.*stack"; then
    echo -e "${GREEN}PASS${NC} $name → detected '$expected_stack' (label match)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected '$expected_stack', got:"
    echo "$DETECTION_OUTPUT" | grep -iE "stack|detect" | head -5 | sed 's/^/       /'
    FAIL=$((FAIL + 1))
  fi

  cleanup "$project_dir"
}

assert_library_injected() {
  local name="$1"
  local project_dir="$2"
  local library="$3"

  run_detection "$project_dir"

  if echo "$DETECTION_OUTPUT" | grep -q "Would inject @.claude/libraries/${library}"; then
    echo -e "${GREEN}PASS${NC} $name → would inject '$library'"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $name → expected library injection of '$library', got:"
    echo "$DETECTION_OUTPUT" | grep -i "inject\|library" | head -5 | sed 's/^/       /'
    FAIL=$((FAIL + 1))
  fi

  cleanup "$project_dir"
}

# ============================================================================
# Stack detection tests
# ============================================================================

echo ""
echo -e "${CYAN}=== Stack Detection Tests ===${NC}"
echo ""

# Next.js (standalone)
p=$(make_project)
touch "$p/next.config.js"
echo '{"name":"test","dependencies":{"next":"14.0.0","react":"18.0.0"}}' > "$p/package.json"
assert_stack "Next.js (next.config.js)" "$p" "nextjs"

# Next.js (from package.json)
p=$(make_project)
echo '{"name":"test","dependencies":{"next":"14.0.0"}}' > "$p/package.json"
assert_stack "Next.js (package.json)" "$p" "nextjs"

# T3 Stack (Next.js + tRPC + Prisma)
p=$(make_project)
touch "$p/next.config.js"
mkdir -p "$p/prisma"
touch "$p/prisma/schema.prisma"
echo '{"name":"t3","dependencies":{"next":"14.0.0","@trpc/server":"11.0.0","@prisma/client":"5.0.0"}}' > "$p/package.json"
assert_stack "T3 Stack" "$p" "t3-stack"

# SvelteKit (svelte.config.js)
p=$(make_project)
touch "$p/svelte.config.js"
echo '{"name":"test","dependencies":{"@sveltejs/kit":"2.0.0"}}' > "$p/package.json"
assert_stack "SvelteKit (svelte.config.js)" "$p" "sveltekit"

# SvelteKit (from package.json)
p=$(make_project)
echo '{"name":"test","dependencies":{"@sveltejs/kit":"2.0.0"}}' > "$p/package.json"
assert_stack "SvelteKit (package.json)" "$p" "sveltekit"

# Nuxt 3 standalone
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.0.0"}}' > "$p/package.json"
assert_stack "Nuxt 3 (nuxt.config.ts)" "$p" "nuxt"

# Remix (remix.config.js)
p=$(make_project)
touch "$p/remix.config.js"
echo '{"name":"test","dependencies":{"@remix-run/react":"2.0.0"}}' > "$p/package.json"
assert_stack "Remix (remix.config.js)" "$p" "remix"

# Remix (app/root.tsx + package.json)
p=$(make_project)
mkdir -p "$p/app"
touch "$p/app/root.tsx"
echo '{"name":"test","dependencies":{"@remix-run/react":"2.0.0"}}' > "$p/package.json"
assert_stack "Remix (app/root.tsx)" "$p" "remix"

# Astro standalone
p=$(make_project)
touch "$p/astro.config.mjs"
echo '{"name":"test","dependencies":{"astro":"4.0.0"}}' > "$p/package.json"
assert_stack "Astro standalone" "$p" "astro"

# Astro + Tina CMS (tina/config.ts file)
p=$(make_project)
touch "$p/astro.config.mjs"
mkdir -p "$p/tina"
touch "$p/tina/config.ts"
echo '{"name":"test","dependencies":{"astro":"4.0.0","tinacms":"2.0.0"}}' > "$p/package.json"
assert_stack "Astro + Tina CMS (tina/config.ts)" "$p" "astro-tina"

# Astro + Tina CMS (package.json only)
p=$(make_project)
touch "$p/astro.config.mjs"
echo '{"name":"test","dependencies":{"astro":"4.0.0","tinacms":"2.0.0","@tinacms/cli":"1.5.0"}}' > "$p/package.json"
assert_stack "Astro + Tina CMS (package.json)" "$p" "astro-tina"

# Docusaurus
p=$(make_project)
touch "$p/docusaurus.config.js"
echo '{"name":"test","dependencies":{"@docusaurus/core":"3.0.0"}}' > "$p/package.json"
assert_stack "Docusaurus" "$p" "docusaurus"

# WordPress standard
p=$(make_project)
touch "$p/wp-config.php"
mkdir -p "$p/wp-content"
assert_stack "WordPress (wp-config.php)" "$p" "wordpress"

# ============================================================================
# Library injection tests
# ============================================================================

echo ""
echo -e "${CYAN}=== Library Injection Tests ===${NC}"
echo ""

# TypeScript detection from tsconfig.json
p=$(make_project)
touch "$p/next.config.js"
touch "$p/tsconfig.json"
echo '{"name":"test","dependencies":{"next":"14.0.0"}}' > "$p/package.json"
assert_library_injected "TypeScript injection (tsconfig.json)" "$p" "typescript.md"

# Zod detection
p=$(make_project)
touch "$p/next.config.js"
echo '{"name":"test","dependencies":{"next":"14.0.0","zod":"3.0.0"}}' > "$p/package.json"
assert_library_injected "Zod injection" "$p" "zod.md"

# Zustand detection
p=$(make_project)
touch "$p/next.config.js"
echo '{"name":"test","dependencies":{"next":"14.0.0","zustand":"4.0.0"}}' > "$p/package.json"
assert_library_injected "Zustand injection" "$p" "zustand.md"

# TanStack Query detection
p=$(make_project)
touch "$p/next.config.js"
echo '{"name":"test","dependencies":{"next":"14.0.0","@tanstack/react-query":"5.0.0"}}' > "$p/package.json"
assert_library_injected "TanStack Query injection" "$p" "tanstack-query.md"

# Prisma detection (schema file)
p=$(make_project)
touch "$p/next.config.js"
mkdir -p "$p/prisma"
touch "$p/prisma/schema.prisma"
echo '{"name":"test","dependencies":{"next":"14.0.0","@prisma/client":"5.0.0"}}' > "$p/package.json"
assert_library_injected "Prisma injection (schema file)" "$p" "prisma.md"

# Playwright detection (config file)
p=$(make_project)
touch "$p/next.config.js"
touch "$p/playwright.config.ts"
echo '{"name":"test","devDependencies":{"next":"14.0.0","@playwright/test":"1.0.0"}}' > "$p/package.json"
assert_library_injected "Playwright injection (config file)" "$p" "playwright.md"

# shadcn/ui detection (components/ui dir)
p=$(make_project)
touch "$p/next.config.js"
mkdir -p "$p/components/ui"
echo '{"name":"test","dependencies":{"next":"14.0.0"}}' > "$p/package.json"
assert_library_injected "shadcn/ui injection (components/ui)" "$p" "shadcn-ui.md"

# Pinia detection
p=$(make_project)
touch "$p/nuxt.config.ts"
echo '{"name":"test","dependencies":{"nuxt":"3.0.0","pinia":"2.0.0"}}' > "$p/package.json"
assert_library_injected "Pinia injection" "$p" "pinia.md"

# Supabase detection
p=$(make_project)
touch "$p/next.config.js"
echo '{"name":"test","dependencies":{"next":"14.0.0","@supabase/supabase-js":"2.0.0"}}' > "$p/package.json"
assert_library_injected "Supabase injection" "$p" "supabase.md"

# Tina CMS detection (tina/config.ts file)
p=$(make_project)
touch "$p/astro.config.mjs"
mkdir -p "$p/tina"
touch "$p/tina/config.ts"
echo '{"name":"test","dependencies":{"astro":"4.0.0","tinacms":"2.0.0","@tinacms/cli":"1.5.0"}}' > "$p/package.json"
assert_library_injected "Tina CMS injection (tina/config.ts)" "$p" "tinacms.md"

# Tina CMS detection (package.json only)
p=$(make_project)
touch "$p/astro.config.mjs"
echo '{"name":"test","dependencies":{"astro":"4.0.0","tinacms":"2.0.0"}}' > "$p/package.json"
assert_library_injected "Tina CMS injection (package.json)" "$p" "tinacms.md"

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
