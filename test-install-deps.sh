#!/usr/bin/env bash
# test-install-deps.sh — --install-deps with fake package managers (brew, apt-get + sudo, npm).
# Nothing real is installed: fakes log their arguments and drop shims onto PATH.
#
# Usage: ./test-install-deps.sh
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

REAL_JQ="$(command -v jq)" || { echo "jq is required to run these tests"; exit 1; }
export REAL_JQ
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
contains() { grep -qF -- "$2" <<< "$1"; }
logged() { grep -qxF -- "$2" "$1" 2>/dev/null; }

# System tools without jq, intelephense, npm, codegraph, or claude.
farm=$(tmp_dir)
for dir in /usr/bin /bin /usr/sbin /sbin; do
  for tool in "$dir"/*; do
    name="${tool##*/}"
    case "$name" in jq|intelephense|npm|node|codegraph|claude|brew|apt-get|sudo) continue ;; esac
    [[ -e "$farm/$name" ]] || ln -s "$tool" "$farm/$name"
  done
done

make_nuxt() { local d; d=$(tmp_dir); touch "$d/nuxt.config.ts"; echo '{"dependencies":{"nuxt":"3"}}' > "$d/package.json"; echo "$d"; }
make_wp() { local d; d=$(tmp_dir); mkdir -p "$d/wp-content/themes"; echo "$d"; }
setup() {  # setup <bin-dir> <project> [args...] — run with only fakes + system tools on PATH
  local bin="$1" project="$2"
  shift 2
  PATH="$bin:$farm" /bin/bash "$SETUP_SCRIPT" --project="$project" --skip-vscode --no-superpowers "$@" 2>&1
}

# ============================================================================
echo -e "\n${CYAN}=== Homebrew ===${NC}\n"
# ============================================================================

bin=$(tmp_dir)
export FAKE_LOG="$bin/log" SHIM_DIR="$bin"
cat > "$bin/brew" <<'SH'
#!/usr/bin/env bash
echo "brew $*" >> "$FAKE_LOG"
for pkg in "${@:2}"; do
  case "$pkg" in
    jq) ln -sf "$REAL_JQ" "$SHIM_DIR/jq" ;;
    node) printf '#!/usr/bin/env bash\necho "npm $*" >> "$FAKE_LOG"\n[[ "$1 $2 $3" == "install -g intelephense" ]] && printf "#!/usr/bin/env bash\\nexit 0\\n" > "$SHIM_DIR/intelephense" && chmod +x "$SHIM_DIR/intelephense"\nexit 0\n' > "$SHIM_DIR/npm"; chmod +x "$SHIM_DIR/npm" ;;
  esac
done
exit 0
SH
chmod +x "$bin/brew"

p=$(make_nuxt)
out=$(AI_CONFIG_PKG_MANAGER=brew setup "$bin" "$p" --force --install-deps); status=$?
assert_true "missing jq → brew install jq" logged "$FAKE_LOG" "brew install jq"
assert_eq "deploy succeeds once jq is installed" "0" "$status"
assert_true "safety policy applied with the installed jq" test -s "$p/.claude/settings.local.json"
assert_true "JS stack: codegraph named as not auto-installed" contains "$out" "Not auto-installed (optional): codegraph"

p=$(make_nuxt)
rm -f "$bin/jq" "$FAKE_LOG"
out=$(AI_CONFIG_PKG_MANAGER=brew setup "$bin" "$p" --dry-run --install-deps)
assert_true "--dry-run shows the plan" contains "$out" "Will run: brew install jq"
assert_false "--dry-run installs nothing" test -f "$FAKE_LOG"

p=$(make_wp)
rm -f "$bin/jq" "$bin/npm" "$bin/intelephense" "$FAKE_LOG"
printf '#!/usr/bin/env bash\necho "claude $*" >> "$FAKE_LOG"\nexit 0\n' > "$bin/claude"; chmod +x "$bin/claude"
out=$(AI_CONFIG_PKG_MANAGER=brew setup "$bin" "$p" --force --install-deps); status=$?
assert_true "PHP stack without npm → brew installs jq and node together" logged "$FAKE_LOG" "brew install jq node"
assert_true "PHP stack → npm install -g intelephense (no sudo)" logged "$FAKE_LOG" "npm install -g intelephense"
assert_false "npm is never run through sudo" grep -q "sudo npm" "$FAKE_LOG"
assert_true "php-lsp enabled in the same run" logged "$FAKE_LOG" "claude plugin install php-lsp@claude-plugins-official --scope local"
assert_eq "PHP deploy succeeds" "0" "$status"

# ============================================================================
echo -e "\n${CYAN}=== apt-get (sudo, update-and-retry) ===${NC}\n"
# ============================================================================

apt=$(tmp_dir)
export APT_LOG="$apt/log" APT_DIR="$apt"
cat > "$apt/sudo" <<'SH'
#!/usr/bin/env bash
echo "sudo $*" >> "$APT_LOG"
exec "$@"
SH
cat > "$apt/apt-get" <<'SH'
#!/usr/bin/env bash
echo "apt-get $*" >> "$APT_LOG"
if [[ "$1" == "update" ]]; then touch "$APT_DIR/updated"; exit 0; fi
if [[ "$1" == "install" ]]; then
  [[ -f "$APT_DIR/updated" ]] || exit 100
  ln -sf "$REAL_JQ" "$APT_DIR/jq"
fi
exit 0
SH
chmod +x "$apt/sudo" "$apt/apt-get"

p=$(make_nuxt)
AI_CONFIG_PKG_MANAGER=apt-get setup "$apt" "$p" --force --install-deps >/dev/null; status=$?
assert_eq "apt-get: install, update, install again" "apt-get install -y jq|apt-get update|apt-get install -y jq" \
  "$(grep '^apt-get' "$APT_LOG" | paste -sd'|' -)"
if [[ "$(id -u)" != "0" ]]; then
  assert_true "apt-get runs through sudo when not root" logged "$APT_LOG" "sudo apt-get install -y jq"
fi
assert_eq "deploy succeeds after apt-get retry" "0" "$status"

# ============================================================================
echo -e "\n${CYAN}=== Nothing to do / nothing available ===${NC}\n"
# ============================================================================

p=$(make_nuxt)
rm -f "$FAKE_LOG"
out=$(AI_CONFIG_PKG_MANAGER=brew PATH="$bin:$PATH" "$SETUP_SCRIPT" --project="$p" --force --skip-vscode --no-superpowers --install-deps 2>&1)
if command -v jq >/dev/null && command -v git >/dev/null; then
  assert_true "all present → nothing installed" contains "$out" "All dependencies already installed"
  assert_false "all present → package manager never called" test -f "$FAKE_LOG"
fi

p=$(make_nuxt)
empty=$(tmp_dir)
out=$(AI_CONFIG_PKG_MANAGER=none setup "$empty" "$p" --force --install-deps); status=$?
assert_true "no package manager → manual instructions" contains "$out" "No supported package manager found"
assert_eq "no package manager → preflight still stops the run" "1" "$status"
assert_false "no package manager → nothing written" test -e "$p/.claude"

p=$(make_nuxt)
out=$(setup "$empty" "$p" --force); status=$?
assert_true "without --install-deps the error suggests it" contains "$out" "Re-run with --install-deps"
assert_eq "without --install-deps missing jq still exits 1" "1" "$status"

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
