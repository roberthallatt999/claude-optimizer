#!/usr/bin/env bash
#
# safety-guard.sh — Claude Code PreToolUse hook (deployed by ai-config)
#
# Enforces the Operational Safety Guardrails from CLAUDE.md at the harness level,
# so they hold even when an allow rule would auto-approve a command:
#   - Secrets     → deny reading .env / keys / credentials (Bash and file tools);
#                   ask before writing credential-shaped strings into files or commands
#   - Publishing  → ask before git push, PR/release changes, package publishing
#   - Production  → ask before deploys, remote shells, cloud/infra CLIs, DB drops;
#                   deny remote commands that change a production target declared in
#                   ai-config.conf [remote]; let read-only remote checks through
#   - Destructive → deny catastrophic deletes; ask before irreversible git/DB ops
#   - Harness     → ask before edits to .claude/settings*.json or .claude/hooks/
#   - MCP         → ask before MCP tools that push, deploy, send, buy, delete or
#                   write (incl. SQL writes); read-only and browser tools pass
#
# Contract: reads the PreToolUse JSON payload on stdin. Prints a
# hookSpecificOutput JSON with permissionDecision "deny" or "ask", or prints
# nothing to defer to the normal permission rules. Always exits 0 so a guard
# bug can never wedge a session (the settings deny-list remains the backstop).
#
# Source of truth: claude-optimizer/projects/common/hooks/safety-guard.sh
# Tests:           claude-optimizer/test-safety-guard.sh

set -uo pipefail

# --pre-commit: run as a git pre-commit hook (no JSON on stdin); see staged_leaks below.
GUARD_MODE=hook
if [[ "${1:-}" == --pre-commit ]]; then
  GUARD_MODE="pre-commit"
  input=""
else
  input="$(cat)"
fi

# Two copies can be registered: the global one (~/.claude/hooks, put in ~/.claude/settings.json
# by scripts/install-global-guard.sh) and a project's own. The global copy ALWAYS evaluates:
# project files (a cloned repo's settings and hook) must never be able to switch it off. To
# avoid checking a call twice, the PROJECT copy stands aside instead, and only when the
# user-owned settings register the global guard and the global copy is byte-identical to this
# one, so the same checks run anyway. Otherwise both run.
# Only for a real Claude Code call (it always sends session_id): --doctor's live test and the
# test suites run a project copy directly, and must see it decide.
if [[ "${AI_CONFIG_GUARD_SCOPE:-}" != global && "$GUARD_MODE" == hook && "$input" == *'"session_id"'* ]] \
   && cmp -s "$HOME/.claude/hooks/safety-guard.sh" "${BASH_SOURCE[0]}" \
   && command -v jq >/dev/null 2>&1 \
   && jq -e '[.hooks.PreToolUse[]? | select((.matcher // "") as $m | $m == "" or $m == "*" or ($m | test("Bash") and test("Read") and test("mcp")))
              | .hooks[]?.command | strings | test("^AI_CONFIG_GUARD_SCOPE=global ")] | any' \
        "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  exit 0
fi

# $1 is a dotted path; a `name[]` segment iterates an array (one value per line).
json_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
vals = [d]
for k in sys.argv[1].lstrip(".").split("."):
    each = k.endswith("[]")
    k = k[:-2] if each else k
    vals = [v.get(k) for v in vals if isinstance(v, dict)]
    if each:
        vals = [x for v in vals if isinstance(v, list) for x in v]
sys.stdout.write("\n".join(v for v in vals if isinstance(v, str)))
' "$1" 2>/dev/null
  fi
}

# Every deny ends with the hand-off: the developer runs the step, outside the chat.
HANDOFF=" If this step is still needed, don't route around the block with another command or tool: give the developer the exact command to run in their own terminal (a separate window; a ! command in this chat sends its output back here), or the numbered steps in the service's web dashboard, and ask only for a non-secret result (done, an exit status, a count). Never ask them to paste a secret into the chat."

decide() {
  local reason="$2"
  [[ "$1" == deny && "$reason" != *"own terminal"* ]] && reason="$reason$HANDOFF"
  reason="${reason//\\/\\\\}"
  reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
  exit 0
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- Deployed protected paths -----------------------------------------------
# ai-config writes the [deny] tier of projects/common/protected-paths.conf plus the
# detected stack's own file to .claude/hooks/protected-paths.conf. Absent (a legacy
# deployment, or the hook run standalone) → only the hardcoded list below applies.
PROTECTED_PATTERNS=()
for _conf in "${BASH_SOURCE[0]%/*}/protected-paths.conf" "${CLAUDE_PROJECT_DIR:-}/.claude/hooks/protected-paths.conf"; do
  [[ "$_conf" == /* || "$_conf" == */* ]] && [[ -f "$_conf" ]] || continue
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line%$'\r'}"
    case "$_line" in ''|'#'*|'['*) continue ;; esac
    PROTECTED_PATTERNS+=("$(lower "$_line")")
  done < "$_conf"
  # The global copy also takes the project's list (a CMS stack's *.sql, say): patterns only
  # ever add protection, so reading a project's file here can't weaken anything.
  [[ "${AI_CONFIG_GUARD_SCOPE:-}" == global ]] || break
done

# --- Test fixtures the project vouches for ------------------------------------
# A test suite for credential handling needs realistic fake credentials. ai-config.conf:
#   [scan]
#   allow = test-*.sh, tests/fixtures/**
# Content scanning (reads, searches, commits) skips those project-relative globs. Path
# rules still apply, so .env or a key file can't be allowed. Editing ai-config.conf asks.
SCAN_ALLOW=()
if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "$CLAUDE_PROJECT_DIR/ai-config.conf" ]]; then
  _sec=""
  while IFS= read -r _l || [[ -n "$_l" ]]; do
    _l="${_l%$'\r'}"; _l="${_l%%#*}"
    _l="${_l#"${_l%%[![:space:]]*}"}"; _l="${_l%"${_l##*[![:space:]]}"}"
    [[ "$_l" == '['* ]] && { _sec="$_l"; continue; }
    [[ "$_sec" == "[scan]" && "$_l" == allow*=* ]] || continue
    IFS=, read -ra _parts <<< "${_l#*=}"
    for _g in "${_parts[@]}"; do
      _g="${_g#"${_g%%[![:space:]]*}"}"; _g="${_g%"${_g##*[![:space:]]}"}"
      # The literal part before the first wildcard must be a whole folder ("tests/fixtures/…")
      # or a file-name prefix of 4+ characters ending in - _ or . ("test-*.sh"). "*", "**",
      # "*.php" or "t*" would switch the scan off far beyond a fixture folder: ignored.
      [[ -n "$_g" && "$_g" != /* && "$_g" != *..* ]] || continue
      _lit="${_g%%[*?[]*}"
      # Every folder segment needs a letter or digit: "./**" or ".../**" must not pass as a folder.
      # (An empty literal is no prefix at all, and an empty array under set -u kills bash 3.2.)
      [[ -n "${_lit%/}" ]] || continue
      _seg_ok=1
      IFS=/ read -ra _segs <<< "${_lit%/}"
      for _s in "${_segs[@]}"; do [[ "$_s" =~ [A-Za-z0-9] ]] || _seg_ok=0; done
      if [[ $_seg_ok == 1 ]] && [[ "$_lit" == "$_g" || "$_lit" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/$ \
            || "$_lit" =~ ^([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.]{3,}[-_.]$ ]]; then
        SCAN_ALLOW+=("$_g")
      fi
    done
  done < "$CLAUDE_PROJECT_DIR/ai-config.conf"
fi

# glob_to_re <glob> — a path-aware regex: "**" crosses "/", "*" and "?" don't.
glob_to_re() {
  local g="$1" out="" c i=0
  while [[ $i -lt ${#g} ]]; do
    c="${g:$i:1}"
    if [[ "$c" == "*" && "${g:$((i + 1)):1}" == "*" ]]; then
      out+=".*"; i=$((i + 2))
      [[ "${g:$i:1}" == "/" ]] && { out+="/?"; i=$((i + 1)); }
      continue
    fi
    case "$c" in
      "*") out+="[^/]*" ;;
      "?") out+="[^/]" ;;
      '.'|'+'|'^'|'$'|'('|')'|'{'|'}'|'|'|'\'|'['|']') out+="\\$c" ;;
      *) out+="$c" ;;
    esac
    i=$((i + 1))
  done
  printf '^%s$' "$out"
}

# scan_allowed <path> — true when [scan] allow covers it (path relative to the project).
scan_allowed() {
  local rel="$1" g re
  [[ ${#SCAN_ALLOW[@]} -gt 0 ]] || return 1
  rel="${rel#"${CLAUDE_PROJECT_DIR:-}"/}"
  # Normalise before matching: no "./" or "//" segments, and a ".." anywhere is refused.
  while [[ "$rel" == ./* ]]; do rel="${rel#./}"; done
  while [[ "$rel" == *//* ]]; do rel="${rel//\/\//\/}"; done
  while [[ "$rel" == */./* ]]; do rel="${rel//\/.\//\/}"; done
  [[ "$rel" == /* || "/$rel/" == */../* ]] && return 1
  for g in "${SCAN_ALLOW[@]}"; do
    re="$(glob_to_re "$g")"
    [[ "$rel" =~ $re ]] && return 0
  done
  return 1
}

# matches_protected <lowercased path> — true when a deployed [deny] pattern matches.
# Pattern syntax mirrors projects/common/protected-paths.conf:
#   foo/      that directory and everything under it, at any depth
#   /foo/bar  anchored to the project root
#   foo/bar   that path fragment, at any depth
#   *.sql     matched against the basename
# SC2254: $pat must glob here — these are patterns, not literals.
# shellcheck disable=SC2254
matches_protected() {
  local p="${1#./}" base="${1##*/}" pat
  for pat in ${PROTECTED_PATTERNS[@]+"${PROTECTED_PATTERNS[@]}"}; do
    case "$pat" in
      */)
        pat="${pat%/}"; pat="${pat#/}"
        case "$p" in $pat|$pat/*|*/$pat|*/$pat/*) return 0 ;; esac
        ;;
      /*)
        pat="${pat#/}"
        case "$p" in $pat) return 0 ;; esac
        ;;
      */*)
        case "$p" in $pat|*/$pat) return 0 ;; esac
        ;;
      *)
        case "$base" in $pat) return 0 ;; esac
        ;;
    esac
  done
  return 1
}

# $1 must already be lowercase.
is_secret_path() {
  local p="$1" base="${1##*/}"
  case "$base" in
    *.example|*.sample|*.template|*.dist|*.defaults|*.tpl) return 1 ;;
    process.env|*meta.env) return 1 ;;   # JS identifiers, not files
    .env*|*.env) return 0 ;;
    id_rsa|id_rsa.pub|id_dsa|id_ecdsa|id_ed25519|id_ed25519.pub) return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.priv|*.cer|*.crt|*.der|*.csr) return 0 ;;
    *.secret|*.secrets|*.token|*.password) return 0 ;;
    credentials.json|*-credentials.json|*service-account*.json|application_default_credentials.json) return 0 ;;
    secrets.json|secrets.yml|secrets.yaml|vault.yml|vault.yaml|auth.json) return 0 ;;
    .git-credentials|.netrc|.npmrc|.yarnrc|.pypirc|.pgpass|.my.cnf|.htpasswd) return 0 ;;
    .mysql*.cnf|.my*.cnf|mysql*-prod*.cnf|mysql*-stag*.cnf) return 0 ;;   # e.g. ~/.mysql-site-prod.cnf
    wp-config.php|wp-config-local.php|wp-salt.php|config.local.php|database.yml|database.yaml) return 0 ;;
  esac
  case "$p" in
    .ssh/*|*/.ssh/*|.aws/*|*/.aws/credentials|*/.aws/config|.azure/*|*/.azure/*) return 0 ;;
    user/config/config.php|*/user/config/config.php|*.ddev/db_snapshots/*|*.ddev/import-db/*) return 0 ;;
  esac
  matches_protected "$p"
}

# EE's <system folder>/user/config/config.php (system/, or renamed: plbmin/, lcmin/…) is a
# secret path but tracked (see git_stage_only).
TRACKED_CONFIG_RE='(^|/)user/config/config\.php$'

SECRET_REASON="may contain secrets (Safety Guardrail #1: never read secrets). Ask the developer for the specific non-secret value you need, or use the .env.example template."
PUBLISH="Safety Guardrail #2: publishing needs the developer's explicit approval for this specific action."
PROD="Safety Guardrail #3: this may change a production or remote environment; confirm the target and get explicit approval."
DESTRUCTIVE="This is irreversible; confirm it is intended."

# High-confidence credential shapes — keep in sync with projects/common/okf/okf-check.sh.
# Vendor token shapes. Case-sensitive: the casing IS part of the signal.
SECRET_CONTENT_RE='-----BEGIN [A-Z ]*PRIVATE KEY-----|(AKIA|ASIA)[0-9A-Z]{16}|sk-(ant|proj)-[A-Za-z0-9_-]{20,}|sk_live_[0-9A-Za-z]{16,}|rk_live_[0-9A-Za-z]{16,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|npm_[A-Za-z0-9]{36}|dop_v1_[a-f0-9]{64}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}'

# Database and service credentials, matched case-insensitively: a connection URI with an
# inline password, a secret-ish key assigned a concrete value, or the same key quoted in a
# PHP array or JSON object ('password' => 'value', "api_key": "value"). This is what catches a
# server log whose stack trace prints the DSN.
SECRET_ASSIGN_RE='(mysql|mariadb|postgres|postgresql|mongodb\+srv|mongodb|redis|rediss|amqp|amqps|mssql|sqlserver|ftp|https?)://[^:/@[:space:]"]+:[^@[:space:]"]{3,}@|(db_password|db_pass|db_pwd|mysql_pwd|mysql_password|mysql_root_password|postgres_password|pgpassword|database_password|redis_password|mail_password|smtp_password|aws_secret_access_key|secret_access_key|api_key|api_secret|apikey|secret_key|access_token|auth_token|bearer_token|client_secret|encryption_key|app_key)[[:space:]]*[=:][[:space:]]*"?[^[:space:]",;&]{8,}|['"'"'"](password|passwd|pwd|db_password|secret|client_secret|api_?key|auth_?key|private_key|access_token|token)['"'"'"][[:space:]]*(=>|:)[[:space:]]*['"'"'"]([^'"'"'"[:space:]|:,]{6,}[0-9][^'"'"'"[:space:]|:,]*|[^'"'"'"[:space:]|:,]*[0-9][^'"'"'"[:space:]|:,]{6,})['"'"'"]'

# Lines the guard forgives. Without these the guard blocks .env.example, docs and any
# code that reads a value from the environment — and a guard nobody can live with gets
# switched off, which is worse than a narrower one that stays on.
# Deliberately NOT here: "xxxx", "todo", "fixme". A real vendor token can contain a run of
# x's (sk-ant-api03-xxxx…) and a line can say TODO next to a live key; template files are
# already skipped by extension in secret_scan, so those markers bought nothing and cost a hole.
# The last alternative is a value made only of snake_case words ending in a credential word
# (a setup README setting DB_PASSWORD to database_password); a value with a digit is never one.
SECRET_PLACEHOLDER_RE='example|sample|placeholder|dummy|changeme|change[-_]me|your[-_]|redacted|replace_|\*\*\*|\.\.\.|<[A-Za-z][A-Za-z0-9_ .-]*>|\$\{|%[A-Za-z_]+%|process\.env|import\.meta\.env|deno\.env|getenv|os\.environ|env\(|:(pass|password|passwd|pwd|secret|user|username|admin|root|test|demo|foo|bar)@|test[-_]?(key|token|secret|password)|fake[-_]?(key|token|secret)|[=:][[:space:]]*"?([a-z]+_)+(password|passwd|pwd|secret|token|key)"?[[:space:],;]*$'

# Largest file the guard will scan. Past this it denies rather than waving the file
# through unchecked — an unscanned file is an unknown file.
SCAN_MAX_BYTES="${AI_CONFIG_SCAN_MAX_BYTES:-20971520}"

SCAN_TAIL="Reading it would put the credential into the transcript. Redact the file, or quote only the lines you need after checking them yourself."
SCAN_BIG_TAIL="Read a bounded, checked excerpt instead (for a log: the specific timestamp range you need)."

# Cheap first-pass alternation, matched against a lowercased line. Every pattern in
# SECRET_CONTENT_RE and SECRET_ASSIGN_RE must be reachable through one of these branches,
# or it becomes dead code — test-secret-scanning.sh has a case per class to catch that.
# One compiled regex, not a loop of index() calls: on BSD awk the loop costs 929ms on a
# 4MB log where this costs 126ms, which is awk's floor for reading the file at all.
SECRET_ANCHORS_RE='akia|asia|sk-ant-|sk-proj-|sk_live_|rk_live_|gh[pousr]_|github_pat_|glpat-|xox|aiza|sg\.|npm_|dop_v1_|eyj|-----begin|mysql://|mariadb://|postgres|mongodb|rediss?://|amqp|mssql://|sqlserver://|ftp://|https?://|password|passwd|_pwd|secret|token|api_?key|app_key|access_key|encryption_key|auth_?key|private_key'

# secret_scan <path> — echo a finding; 0 = credential found, 1 = clean/not applicable,
# 2 = could not be scanned. Fail closed: callers deny on both 0 and 2.
#
# Two stages, because this runs on every read.
#
# Stage 1 is awk doing literal index() checks against the anchor list. It emits the
# ORIGINAL line with its real line number, so stage 2 still sees real casing. awk is used
# rather than grep because BSD grep (every macOS box, and the macOS CI runner) takes
# ~3.3s on `-F -i` with this many patterns against a 4MB log; awk does the same work in
# ~30ms. Do not "simplify" this back to grep -Fi.
#
# Stage 2 runs the precise regexes over only those candidate lines.
secret_scan() {
  local f="$1" base size head_bytes text_bytes scan_target candidates lines
  [[ -f "$f" && -r "$f" ]] || return 1
  scan_allowed "$f" && return 1
  base="$(lower "${f##*/}")"
  case "$base" in
    # Templates exist to show the shape of a secret; that is not a leak.
    *.example|*.sample|*.template|*.dist|*.defaults|*.tpl) return 1 ;;
    *.example.*|*.sample.*|*.template.*|*.dist.*) return 1 ;;
  esac
  size=$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')
  [[ "$size" =~ ^[0-9]+$ ]] || return 2
  if [[ "$size" -gt "$SCAN_MAX_BYTES" ]]; then
    printf 'is too large to scan for credentials (%s bytes)' "$size"
    return 2
  fi

  # Binary check, standing in for grep -I: a NUL in the first 4KB means not text.
  head_bytes=$(LC_ALL=C head -c 4096 -- "$f" 2>/dev/null | wc -c | tr -d '[:space:]')
  text_bytes=$(LC_ALL=C head -c 4096 -- "$f" 2>/dev/null | LC_ALL=C tr -d '\000' | wc -c | tr -d '[:space:]')
  [[ "$head_bytes" == "$text_bytes" ]] || return 1

  # The pattern reaches awk through the environment rather than -v, which avoids every
  # quoting question about a regex on a command line. awk has no "--", so a path that
  # could begin with "-" is prefixed with "./".
  case "$f" in /*|./*) scan_target="$f" ;; *) scan_target="./$f" ;; esac
  candidates="$(SECRET_ANCHORS_RE="$SECRET_ANCHORS_RE" LC_ALL=C awk '
    BEGIN { re = ENVIRON["SECRET_ANCHORS_RE"] }
    {
      if (tolower($0) ~ re) { print FNR ":" $0; hits++ }
      if (hits >= 2000) exit
    }' "$scan_target" 2>/dev/null)"
  [[ -n "$candidates" ]] || return 1

  # Stage 2, over candidate lines only. Each already carries its "NN:" prefix.
  lines=$( { LC_ALL=C grep -E -e "$SECRET_CONTENT_RE" <<< "$candidates" 2>/dev/null
             LC_ALL=C grep -iE -e "$SECRET_ASSIGN_RE" <<< "$candidates" 2>/dev/null
           } | LC_ALL=C grep -viE -e "$SECRET_PLACEHOLDER_RE" \
             | cut -d: -f1 | sort -n -u | head -5 | paste -sd, - )
  [[ -n "$lines" ]] || return 1
  printf 'credential-shaped content (line %s)' "$lines"
  return 0
}

# content_secret_hits — count credential-shaped lines in text on stdin.
content_secret_hits() {
  local text
  text="$(cat)"
  { LC_ALL=C grep -E -e "$SECRET_CONTENT_RE" <<< "$text" 2>/dev/null
    LC_ALL=C grep -iE -e "$SECRET_ASSIGN_RE" <<< "$text" 2>/dev/null
  } | LC_ALL=C grep -vcE -e "$SECRET_PLACEHOLDER_RE"
}

# --- Recursive searches -----------------------------------------------------
# A path rule blocks `grep x .env`, but `grep -r DB_PASSWORD .` opens .env without naming
# it. These find the secret files a search would open and check whether the search pattern
# actually matches a line in one: only then is it denied, so everyday searches never prompt.

# secret_files_under <dir|file> — secret files a recursive search would open (max 50).
secret_files_under() {
  local root="$1" f rel
  if [[ -f "$root" ]]; then
    is_secret_path "$(lower "$root")" && printf '%s\n' "$root"
    return 0
  fi
  [[ -d "$root" ]] || return 0
  find "$root" -maxdepth 8 \( -type d \( -name node_modules -o -name vendor -o -name .git \
      -o -name dist -o -name build -o -name .next -o -name .nuxt -o -name .cache -o -name .npm \
      -o -name Library -o -name .Trash -o -name bower_components -o -name .venv -o -name __pycache__ \) -prune \) \
    -o -type f \( -name '.env*' -o -name '*.env' -o -name '*.pem' -o -name '*.key' -o -name 'id_[rde]*' \
      -o -name '*.p12' -o -name '*.pfx' -o -name '*credentials*' -o -name 'secrets.*' -o -name 'auth.json' \
      -o -name 'wp-config*.php' -o -name 'wp-salt.php' -o -name '.npmrc' -o -name '.netrc' -o -name '.pgpass' \
      -o -name '.my*.cnf' -o -name '.mysql*.cnf' -o -name '*.sql' -o -name 'database.y*ml' -o -name 'config.php' \
      -o -name '*.secret*' -o -name '*.token' -o -name '.git-credentials' -o -name '.htpasswd' -o -name 'vault.y*ml' \) \
    -print 2>/dev/null | while IFS= read -r f; do
      rel="${f#"$root"/}"
      is_secret_path "$(lower "$rel")" && printf '%s\n' "$f"
    done | head -51
  # Filtered first, capped after: decoy names can't push a real secret past the cap. A 51st
  # secret file means "too many to check" — search_leak fails closed on it.
  return 0
}

# glob_hit <basename> <glob> — the glob as rg/grep apply it to a file name; {a,b} expanded.
# shellcheck disable=SC2254
glob_hit() {
  local base="$1" g="${2#!}" pre alts post alt
  g="${g##*/}"
  if [[ "$g" =~ ^([^{]*)\{([^}]*)\}(.*)$ ]]; then
    pre="${BASH_REMATCH[1]}" alts="${BASH_REMATCH[2]}" post="${BASH_REMATCH[3]}"
    local IFS=,
    for alt in $alts; do
      case "$base" in $pre$alt$post) return 0 ;; esac
    done
    return 1
  fi
  case "$base" in $g) return 0 ;; esac
  return 1
}

# search_leak <patterns> <fixed> <icase> <includes> <excludes> <hidden> <noignore> <root>...
# Lists are \x1f-separated. Prints the first secret file whose lines the search would return.
# An empty pattern list (e.g. grep -f) counts as matching when the file holds a credential.
# SEARCH_ENGINE=rg (ripgrep, the Grep tool, ag, ack) tests the pattern with rg itself, so a
# regex dialect difference (\d, \w, lookarounds) can't make a match look like a miss. Without
# rg, a pattern with a backslash counts as matching (fail closed).
search_leak() {
  local pats="$1" fixed="$2" icase="$3" incs="$4" excs="$5" hidden="$6" noignore="$7" root f base g ok rc
  shift 7
  local -a gargs=() rargs=(-q --no-config -uuu)
  local npats=0 engine="${SEARCH_ENGINE:-grep}"
  if [[ "$fixed" == 1 ]]; then gargs+=(-F); rargs+=(-F); else gargs+=(-E); fi
  [[ "$icase" == 1 ]] && { gargs+=(-i); rargs+=(-i); }
  while IFS= read -r -d $'\x1f' g; do
    [[ -n "$g" ]] && { gargs+=(-e "$g"); rargs+=(-e "$g"); npats=$((npats + 1)); }
  done <<< "$pats"$'\x1f'
  if [[ "$engine" == rg ]] && ! command -v rg >/dev/null 2>&1; then
    [[ "$pats" == *\\* ]] && npats=0   # rg syntax grep may read differently: fail closed below
    engine="grep"
  fi
  local nfiles rel_dir comp
  for root in "$@"; do
    nfiles=0
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      nfiles=$((nfiles + 1))
      if [[ $nfiles -gt 50 ]]; then printf '%s' "${root}/ (more than 50 secret files)"; return 0; fi
      base="${f##*/}"
      if [[ "$hidden" == 0 && "$base" == .* ]]; then continue; fi
      if [[ "$noignore" == 0 ]] && git -C "$(dirname "$f")" check-ignore -q "$f" 2>/dev/null; then continue; fi
      if [[ -n "$incs" ]]; then
        ok=0
        while IFS= read -r -d $'\x1f' g; do glob_hit "$base" "$g" && ok=1; done <<< "$incs"$'\x1f'
        [[ $ok == 1 ]] || continue
      fi
      ok=1
      # Excludes match the file name, or a folder BELOW the search root (as grep's
      # --exclude-dir and rg's globs do), never a folder above it in the absolute path.
      rel_dir="${f#"$root"/}"; rel_dir="${rel_dir%/*}"; [[ "$rel_dir" == "${f#"$root"/}" ]] && rel_dir=""
      while IFS= read -r -d $'\x1f' g; do
        [[ -n "$g" ]] || continue
        glob_hit "$base" "$g" && ok=0
        if [[ -n "$rel_dir" && "${g%/}" != */* ]]; then
          local IFS=/
          for comp in $rel_dir; do glob_hit "$comp" "${g%/}" && ok=0; done
          unset IFS
        fi
      done <<< "$excs"$'\x1f'
      [[ $ok == 1 ]] || continue
      if [[ $npats -gt 0 && "$engine" == rg ]]; then
        LC_ALL=C rg "${rargs[@]}" -- "$f" >/dev/null 2>&1; rc=$?
      elif [[ $npats -gt 0 ]]; then
        LC_ALL=C grep -q "${gargs[@]}" -- "$f" 2>/dev/null; rc=$?
      else
        rc=2
      fi
      if [[ $rc == 0 ]]; then printf '%s' "$f"; return 0; fi
      if [[ $rc == 2 ]]; then
        secret_scan "$f" >/dev/null; case $? in 0|2) printf '%s' "$f"; return 0 ;; esac
      fi
    done < <(secret_files_under "$root")
  done
  return 1
}

SEARCH_TAIL="Search a narrower path, or exclude secret files (grep -r --exclude='.env*' …, rg -g '!.env*' …)."

# --- Commits ------------------------------------------------------------------
# staged_leaks <dir> <all> — what a commit would put into the repository's history: a staged
# secret file, or an added line with a credential. With all=1 (git commit -a) unstaged
# changes to tracked files count too. Prints "file<TAB>path" or "content<TAB>path:line", or
# "gitleaks<TAB>path (rule)" for a finding only gitleaks makes. Never prints the value.
staged_leaks() {
  local dir="$1" all="$2" names f lf hit out
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 1
  names="$(git -C "$dir" diff --cached --name-only --diff-filter=ACMR 2>/dev/null
           [[ "$all" == 1 ]] && git -C "$dir" diff --name-only --diff-filter=ACMR 2>/dev/null)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    lf="$(lower "$f")"
    [[ "$lf" =~ $TRACKED_CONFIG_RE ]] && continue
    if is_secret_path "$lf"; then printf 'file\t%s' "$f"; return 0; fi
  done <<< "$names"
  hit="$( { git -C "$dir" diff --cached -U0 --no-color --no-ext-diff --diff-filter=ACMR 2>/dev/null
            [[ "$all" == 1 ]] && git -C "$dir" diff -U0 --no-color --no-ext-diff --diff-filter=ACMR 2>/dev/null
          } | head -c 8000000 | SECRET_ANCHORS_RE="$SECRET_ANCHORS_RE" LC_ALL=C awk '
      BEGIN { re = ENVIRON["SECRET_ANCHORS_RE"] }
      # Templates and the tracked EE config are skipped here, in one pass: a shell loop per
      # added line costs a process per line and takes minutes on a large first commit.
      /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); lf = tolower(f)
                    skip = (lf ~ /\.(example|sample|template|dist|defaults|tpl)(\.[^\/]*)?$/ || lf ~ /(^|\/)user\/config\/config\.php$/)
                    next }
      /^@@/ { split($3, a, ","); n = substr(a[1], 2) - 1; next }
      /^\+/ { n++; if (!skip && tolower($0) ~ re) print f ":" n ":" substr($0, 2) }')"
  # Both patterns over the same added lines (a here-string each: one stdin can't feed two greps).
  hit="$( { LC_ALL=C grep -E -e "$SECRET_CONTENT_RE" <<< "$hit"; LC_ALL=C grep -iE -e "$SECRET_ASSIGN_RE" <<< "$hit"; } 2>/dev/null \
    | head -500)"
  # A hit in a [scan] allow fixture isn't waved through at commit time, where the content
  # reaches git history: it asks. Any other hit denies. The placeholder test looks at the
  # line's CONTENT only: a path like examples/ or sample.txt must not excuse a real secret.
  local _h _line _fixture=""
  while IFS= read -r _line; do
    [[ -n "$_line" ]] || continue
    LC_ALL=C grep -qiE -e "$SECRET_PLACEHOLDER_RE" <<< "${_line#*:*:}" && continue
    _h="$(cut -d: -f1,2 <<< "$_line")"
    if scan_allowed "${_h%%:*}"; then [[ -n "$_fixture" ]] || _fixture="$_h"
    else printf 'content\t%s' "$_h"; return 0; fi
  done <<< "$hit"
  if [[ -n "$_fixture" ]]; then printf 'fixture\t%s' "$_fixture"; return 0; fi
  if command -v gitleaks >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    out="$(cd "$dir" && { gitleaks git --staged --pre-commit --no-banner --redact --exit-code 0 -f json -r - . 2>/dev/null
                          [[ "$all" == 1 ]] && gitleaks git --pre-commit --no-banner --redact --exit-code 0 -f json -r - . 2>/dev/null; } \
           | jq -rs 'add // [] | .[0] // empty | "\(.File):\(.StartLine) (\(.RuleID))"' 2>/dev/null)"
    if [[ -n "$out" ]]; then printf 'gitleaks\t%s' "$out"; return 0; fi
  fi
  return 1
}

# commit_verdict <dir> <all> — deny for our own patterns, ask for gitleaks-only findings.
commit_verdict() {
  local r kind what
  r="$(staged_leaks "$1" "$2")" || return 0
  kind="${r%%$'\t'*}" what="${r#*$'\t'}"
  case "$kind" in
    file) COMMIT_DECISION=deny
          COMMIT_REASON="Blocked by ai-config safety guard: the commit would add '${what}', a secret file, to the repository's history (and to GitHub on the next push). Unstage it with: git rm --cached '${what}' (the file stays on disk), and make sure .gitignore covers it." ;;
    content) COMMIT_DECISION=deny
          COMMIT_REASON="Blocked by ai-config safety guard: the commit adds credential-shaped content at ${what}. Move the value to the untracked .env and read it from the environment, then re-stage. Once a secret is in git history (and pushed), it has to be rotated." ;;
    fixture) COMMIT_DECISION=ask
          COMMIT_REASON="The commit adds credential-shaped content at ${what}, in a file ai-config.conf [scan] lists as a test fixture. Confirm it is a fake value before committing." ;;
    gitleaks) COMMIT_DECISION=ask
          COMMIT_REASON="gitleaks flags a possible secret in the staged changes at ${what}. Check that line before committing; approve only if it is a false positive (mark it with a gitleaks:allow comment to silence it)." ;;
  esac
  return 0
}

if [[ "$GUARD_MODE" == pre-commit ]]; then
  COMMIT_DECISION=""
  commit_verdict "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" 0
  if [[ "$COMMIT_DECISION" == deny ]]; then
    printf 'ai-config pre-commit: %s\n' "$COMMIT_REASON" >&2
    exit 1
  elif [[ "$COMMIT_DECISION" == ask ]]; then
    printf 'ai-config pre-commit: %s\nCommit again with --no-verify only if you have checked it.\n' "$COMMIT_REASON" >&2
    exit 1
  fi
  exit 0
fi

# Without jq or python3 nothing can be read and every call defers. The shared policy allows
# ssh because this hook inspects it, so an ssh command must not pass unread.
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  case "$input" in
    *'"Bash"'*ssh*) decide ask "The ai-config safety guard cannot inspect this remote command: neither jq nor python3 is on PATH. ${PROD:-Confirm the target before approving.}" ;;
  esac
fi

tool="$(json_field .tool_name)"

# ---------------------------------------------------------------------------
# MCP tools: mcp__<server>__<tool>  (plugins: mcp__plugin_<plugin>_<server>__<tool>)
# ---------------------------------------------------------------------------
# The tool part is split into words (snake_case, kebab-case, camelCase) and
# matched against action verbs. A read-led name (get_pull_request,
# list_agent_run_projects) asks only for a MCP_STRONG verb or a joined action
# (get_or_create, list_and_delete): pull/run/release/purchase are nouns there.
MCP_ASK='push|merge|pull|fork|commit|release|publish|unpublish|deploy|promote|rollback|redeploy|delete|remove|drop|truncate|destroy|trash|purge|erase|send|post|reply|comment|share|invite|schedule|submit|buy|purchase|pay|execute|run|invoke|trigger|write|create|update|edit|modify|upload|insert|upsert|put|patch|replace|overwrite|save|move|rename|set|add|enable|disable|pause|unpause|cancel|close|reopen|archive|restore|reset|restart|revoke|grant|approve|assign|transfer|install|uninstall|provision|rotate|change|import|sync|apply'
MCP_STRONG='delete|remove|drop|truncate|destroy|trash|purge|erase|create|write|upload|insert|upsert|overwrite|rename'
MCP_READ='get|list|search|read|fetch|find|describe|inspect|check|resolve|view|show|count|lookup|retrieve|discover|download|query|whoami|help|status'
# Lowercased SQL. `replace` only as REPLACE INTO, so SELECT replace(col, …) passes.
SQL_WRITE='(^|[^a-z0-9_])(insert|update|delete|drop|alter|truncate|create|grant|revoke|merge|replace[[:space:]]+into)([^a-z0-9_]|$)'
# A free-text `query` field (e.g. context7 query-docs) counts as SQL only if it reads like a statement.
SQL_SHAPE='^[[:space:]]*\(?[[:space:]]*(select|with|insert|update|delete|drop|alter|truncate|create|grant|revoke|replace|merge|pragma|explain|begin)([[:space:]].*)?[^a-z0-9_](from|into|table|set|values|where|index|view|database|schema|returning)([^a-z0-9_]|$)'

case "$tool" in
  mcp__*)
    mcp_rest="${tool#mcp__}"
    mcp_name="${mcp_rest##*__}"
    while [[ "$mcp_name" =~ [[:lower:][:digit:]][[:upper:]] ]]; do   # createCollection → create_Collection
      hump="${BASH_REMATCH[0]}"
      mcp_name="${mcp_name/$hump/${hump:0:1}_${hump:1}}"
    done
    mcp_lower="$(lower "${mcp_rest%__*}__${mcp_name}")"
    mcp_server="${mcp_lower%__*}"
    case "$mcp_server" in
      *playwright*|*chrome*|*devtools*|*browser*) exit 0 ;;   # local browser automation
    esac
    mcp_words="${mcp_lower##*__}"
    mcp_words=" ${mcp_words//[_-]/ } "

    read_led=""
    lead_re='^ +([^ ]+) +([^ ]*)'
    if [[ "$mcp_words" =~ $lead_re ]]; then
      w1="${BASH_REMATCH[1]}"
      w2="${BASH_REMATCH[2]}"
      # Allow one vendor-prefix word that repeats the server name (slack_read_channel).
      if [[ "$w1" =~ ^($MCP_READ)$ ]] || [[ "$mcp_server" == *"$w1"* && "$w2" =~ ^($MCP_READ)$ ]]; then
        read_led=1
      fi
    fi
    if [[ -n "$read_led" ]]; then
      ask_re=" ($MCP_STRONG) | (and|or) ($MCP_ASK) "
    else
      ask_re=" ($MCP_ASK) "
    fi
    if [[ "$mcp_words" =~ $ask_re ]]; then
      verb="${BASH_REMATCH[1]}${BASH_REMATCH[3]:-}"
      case "$verb" in
        push|merge|pull|fork|commit|release|publish|unpublish) why="$PUBLISH" ;;
        delete|remove|drop|truncate|destroy|trash|purge|erase) why="$DESTRUCTIVE $PROD" ;;
        *) why="$PROD" ;;
      esac
      # Content sent out (a file pushed to GitHub, a message, a Worker script) is checked
      # for credentials first: a secret in it is not a judgement call.
      if [[ "$(printf '%s' "$input" | content_secret_hits)" != 0 ]]; then
        decide deny "Blocked by ai-config safety guard: the content MCP tool ${tool} would send contains credential-shaped text (private key, API token or password). Remove it and reference an environment variable or the service's secret store instead."
      fi
      decide ask "MCP tool ${tool} performs an outward or destructive action (${verb}) — ${why}"
    fi
    # A read-led tool naming a secret file (get_file_contents path=.env) returns its contents.
    for key in .tool_input.path .tool_input.file_path .tool_input.filename .tool_input.filePath; do
      val="$(json_field "$key")"
      [[ -n "$val" ]] || continue
      if is_secret_path "$(lower "$val")"; then
        decide deny "Blocked by ai-config safety guard: MCP tool ${tool} would return '${val##*/}', which $SECRET_REASON"
      fi
    done

    sql_re=' (query|execute|sql) '
    if [[ "$mcp_words" =~ $sql_re ]]; then
      sql="$(json_field .tool_input.sql)"
      if [[ -n "$sql" ]]; then
        sql="$(lower "$sql")"
      else
        sql="$(lower "$(json_field .tool_input.query)")"
        [[ "$sql" =~ $SQL_SHAPE ]] || exit 0
      fi
      if [[ "$sql" =~ $SQL_WRITE ]]; then
        decide ask "MCP tool ${tool} runs SQL that writes data or changes the schema — ${PROD}"
      fi
    fi
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# File tools
# ---------------------------------------------------------------------------
case "$tool" in
  Read|Edit|MultiEdit|Write|NotebookEdit|Grep)
    target=""
    for key in .tool_input.file_path .tool_input.notebook_path .tool_input.path .tool_input.glob; do
      val="$(json_field "$key")"
      [[ -n "$val" ]] || continue
      [[ -n "$target" ]] || target="$val"
      lval="$(lower "$val")"
      if is_secret_path "$lval"; then
        decide deny "Blocked by ai-config safety guard: '${val##*/}' $SECRET_REASON"
      fi
      if [[ "$tool" != "Read" && "$tool" != "Grep" ]]; then
        case "$lval" in
          .claude/settings*.json|*/.claude/settings*.json|.claude/hooks/*|*/.claude/hooks/*)
            decide ask "This modifies Claude Code safety configuration (${val}). Confirm the change is intended." ;;
          ai-config.conf|*/ai-config.conf)
            decide ask "This modifies ai-config.conf, the project's committed policy — including the production targets under [remote] that the safety guard blocks. Confirm the change is intended." ;;
        esac
      fi
    done

    # A path rule can only block what we can name. Reading is the leak, so check the
    # content itself before it reaches the transcript — this is what catches a server
    # log, a docker-compose.yml or a seeder nobody knew held a credential.
    # Grep over a directory (or the whole project) opens every file under it.
    if [[ "$tool" == "Grep" ]]; then
      g_root="$(json_field .tool_input.path)"
      g_cwd="$(json_field .cwd)"; g_cwd="${g_cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"
      [[ -n "$g_root" ]] || g_root="$g_cwd"
      [[ "$g_root" == /* ]] || g_root="$g_cwd/$g_root"
      if [[ -d "$g_root" ]]; then
        g_inc="$(json_field .tool_input.glob)"
        g_type="$(json_field .tool_input.type)"
        # A type is ripgrep's own glob set (rg --type-list). Unknown, or no rg to ask: no
        # include filter, so every secret file under the root is still checked.
        if [[ -n "$g_type" && -z "$g_inc" ]] && command -v rg >/dev/null 2>&1; then
          g_inc="$(rg --no-config --type-list 2>/dev/null | awk -F': ' -v t="$g_type" '$1 == t { gsub(/, /, "\037", $2); print $2; exit }')"
        fi
        g_ci=0; [[ "$(json_field '.tool_input["-i"]')" == true ]] && g_ci=1
        if g_hit="$(SEARCH_ENGINE=rg search_leak "$(json_field .tool_input.pattern)" 0 "$g_ci" "$g_inc" "" 1 1 "$g_root")"; then
          decide deny "Blocked by ai-config safety guard: this search would return lines from '${g_hit#"$g_root"/}', which $SECRET_REASON $SEARCH_TAIL"
        fi
      fi
    fi
    if [[ "$tool" == "Read" || "$tool" == "Grep" ]] && [[ -n "$target" ]]; then
      scan_msg="$(secret_scan "$target")"
      case $? in
        0) decide deny "Blocked by ai-config safety guard: '${target##*/}' contains ${scan_msg}. $SCAN_TAIL" ;;
        2) decide deny "Blocked by ai-config safety guard: '${target##*/}' ${scan_msg}. $SCAN_BIG_TAIL" ;;
      esac
    fi

    # --- Credential-shaped strings in the text being written -----------------
    case "$tool" in
      Write) content_key=.tool_input.content ;;
      Edit) content_key=.tool_input.new_string ;;
      MultiEdit) content_key='.tool_input.edits[].new_string' ;;
      NotebookEdit) content_key=.tool_input.new_source ;;
      *) exit 0 ;;
    esac
    # grep -c reads all input, so json_field can never die of SIGPIPE mid-write.
    hits="$(json_field "$content_key" | content_secret_hits)"
    if [[ "${hits:-0}" != 0 ]]; then
      # Project memory and the OKF bundle reload into context every session, so a
      # credential recorded there leaks repeatedly and silently. No prompt for those.
      case "$(lower "$target")" in
        memory.md|*/memory.md|memory-archive.md|*/memory-archive.md|.okf/*|*/.okf/*)
          decide deny "Blocked by ai-config safety guard: this would record a credential in '${target##*/}', which reloads into context every session. Record the variable NAME only, never its value." ;;
      esac
      decide ask "The text being written to '${target##*/}' looks like a real credential (private key, API token, or database password). Safety Guardrail #1: never write secrets into code — read the value from an environment variable (e.g. process.env.NAME, getenv('NAME')) kept in the untracked .env. Approve only if this is a placeholder or test fixture."
    fi
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Bash
# ---------------------------------------------------------------------------
cmd="$(json_field .tool_input.command)"
[[ -n "$cmd" ]] || exit 0
lc="$(lower "$cmd")"
lc="${lc//$'\n'/;}"

m() { [[ "$lc" =~ $1 ]]; }

# Start of a command segment (including inside quotes, e.g. bash -c "git push"),
# allowing env assignments and wrappers (sudo, xargs…).
S='(^|[;&|({`"'"'"']|\$\()[[:space:]]*(([a-z_][a-z0-9_]*=("[^"]*"|'"'[^']*'"'|[^[:space:]]*)|sudo|command|exec|time|nohup|xargs)[[:space:]]+)*'
# `git` plus any global options before the subcommand (git -C dir push).
# Package runners that fetch and run a CLI (npx -y wrangler@4 …), and the noslop skill's Cloudflare
# helper, which hands wrangler its token: a deploy through either must still be seen as a deploy.
R='((npx|bunx|pnpm[[:space:]]+(dlx|exec)|yarn[[:space:]]+dlx)([[:space:]]+-[^[:space:]]*)*[[:space:]]+)?'
CF_HELPER='[^[:space:]]*cloudflare\.sh[[:space:]]+wrangler'
G='git([[:space:]]+(-c|--git-dir|--work-tree)[[:space:]]+[^[:space:]]+|[[:space:]]+--?[a-z][a-z-]*(=[^[:space:]]+)?)*[[:space:]]+'

# --- Tracked config files that must stay committable ------------------------
# EE's system/user/config/config.php is a secret path, but unlike .env it is tracked:
# every EE upgrade rewrites it and the upgrade is not shipped until it is committed.
# These git subcommands only move a file between working tree, index and remote, and
# never print it, so a path named only as their argument is exempt. Anything that shows
# content (cat, git diff/show/log -p, add -p, status -v) still hits the checks below.
GIT_STAGE_RE="${S}${G}(add|commit|status|restore|reset|rm|push)([[:space:]]+[^;&|<>\`\$]*)?"
GIT_SHOWS_CONTENT_RE='[[:space:]](-[a-z]*[piv][a-z]*|--patch|--interactive|--verbose|--edit)([[:space:]]|$)'

# git_stage_only <lowercased token> — true when every mention of the token is an
# argument to a GIT_STAGE_RE subcommand that cannot print it.
git_stage_only() {
  local tok="$1" rest="$lc" seg
  [[ "$tok" =~ $TRACKED_CONFIG_RE ]] || return 1
  while [[ "$rest" =~ $GIT_STAGE_RE ]]; do
    seg="${BASH_REMATCH[0]}"
    [[ "$seg" =~ $GIT_SHOWS_CONTENT_RE ]] && return 1
    rest="${rest/"$seg"/ }"
  done
  [[ "$rest" != *"$tok"* ]]
}
STAGE_ONLY_TOKS=" "

# --- Secrets referenced from the shell --------------------------------------
# bare_word_exists <name> — a file by that name in the session's folder, the hook's own
# folder, or any folder the command cds into (relative to the session folder).
_bw_cwd="$(json_field .cwd)"
_bw_dirs=("$PWD" "${_bw_cwd:-$PWD}")
_bw_rest="$cmd"
_bw_re='(^|[;&|(])[[:space:]]*cd[[:space:]]+([^;&|()[:space:]]+)'
while [[ "$_bw_rest" =~ $_bw_re ]]; do
  _d="${BASH_REMATCH[2]//[\"\']/}"
  case "$_d" in "~"*) _d="$HOME${_d#\~}" ;; esac
  case "$_d" in /*) _bw_dirs+=("$_d") ;; *) _bw_dirs+=("${_bw_cwd:-$PWD}/$_d") ;; esac
  _bw_rest="${_bw_rest#*"${BASH_REMATCH[0]}"}"
done
bare_word_exists() {
  local d
  for d in "${_bw_dirs[@]}"; do [[ -e "$d/$1" ]] && return 0; done
  # Case-insensitive filesystems: tokens are lowercased, the file may not be.
  local f found=1
  shopt -s nocasematch
  for d in "${_bw_dirs[@]}"; do
    for f in "$d"/*; do [[ "${f##*/}" == "$1" ]] && { found=0; break 2; }; done
  done
  shopt -u nocasematch
  return $found
}

secret=""
while IFS= read -r tok; do
  [[ -n "$tok" ]] || continue
  if is_secret_path "$tok"; then
    # A bare word ("credentials", "secrets") is prose in an echo or a commit message far more
    # often than a file name: only an existing file by that name counts. Key names still do.
    if [[ "$tok" != */* && "$tok" != *.* ]] && ! bare_word_exists "$tok" \
       && [[ ! "$tok" =~ ^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$ ]]; then
      continue
    fi
    if git_stage_only "$tok"; then
      STAGE_ONLY_TOKS+="$tok "
      continue
    fi
    # A search that EXCLUDES the file (grep --exclude='.env*', rg -g '!*.sql') never opens it.
    _rest="$lc"
    for _flag in "--exclude=" "--exclude " "--exclude-dir=" "--exclude-dir " "-g !" "--glob=!" "--glob !" "--iglob=!" "--iglob !"; do
      for _q in "" "'" '"'; do _rest="${_rest//"$_flag$_q$tok"/ }"; done
      _rest="${_rest//"$_flag'!$tok"/ }"; _rest="${_rest//"$_flag\"!$tok"/ }"
    done
    for _q in "'" '"'; do _rest="${_rest//"-g $_q!$tok"/ }"; _rest="${_rest//"--glob=$_q!$tok"/ }"; _rest="${_rest//"--glob $_q!$tok"/ }"; done
    [[ "$_rest" != *"$tok"* ]] && continue
    # `ssh -i ~/.ssh/key` and `mysql --defaults-extra-file=~/.mysql-site.cnf` use a credential
    # file without printing it; only that exact argument is exempt.
    if [[ "$lc" =~ ${S}(ssh|scp|sftp)[[:space:]] && "$lc" == *"-i $tok"* ]]; then
      _rest="${lc/"-i $tok"/}"
      [[ "$_rest" != *"$tok"* ]] && continue
    fi
    for _flag in "--defaults-extra-file=" "--defaults-file="; do
      if [[ "$lc" == *"$_flag$tok"* ]]; then
        _rest="${lc/"$_flag$tok"/}"
        [[ "$_rest" != *"$tok"* ]] && continue 2
      fi
    done
    # `ddev export-db --file=backups/x.sql.gz` writes a new dump and never prints it (the
    # DDEV relay refuses an existing file), so the --file argument is exempt the same way.
    if [[ "$lc" =~ ${S}ddev[[:space:]]+export-db([[:space:]]|$) ]]; then
      for _flag in "--file=" "--file " "-f "; do
        if [[ "$lc" == *"$_flag$tok"* ]]; then
          _rest="${lc//"$_flag$tok"/}"
          [[ "$_rest" != *"$tok"* ]] && continue 2
        fi
      done
    fi
    secret="$tok"
    break
  fi
done <<EOF
$(printf '%s' "$lc" | tr -c 'a-z0-9._/~*@+:%-' '\n')
EOF

READ_VERBS="${S}(cat|zcat|gzcat|bzcat|xzcat|zless|zmore|zgrep|gunzip|unzip|less|more|head|tail|bat|batcat|nl|tac|strings|xxd|od|hexdump|base64|source|\.|grep|egrep|fgrep|rg|ag|ack|awk|gawk|sed|cut|sort|uniq|diff|cmp|jq|yq|cp|scp|rsync|curl|wget|nc|ncat|openssl|gpg|vi|vim|nvim|nano|emacs|code|open|pbcopy|xclip|python|python3|node|deno|php|ruby|perl|export|dotenv|tee|zip|tar|echo|printf|eval|read)([[:space:]]|$)"

if [[ -n "$secret" ]]; then
  IGNORE_FILE='(^|[[:space:]/;&|])\.(git|docker|prettier|eslint|npm|stylelint)?ignore([[:space:];&|]|$)|\.gitattributes'
  TEMPLATE_COPY="${S}cp[[:space:]]+(-[a-z]+[[:space:]]+)*[^[:space:]]*\.(example|sample|template|dist)[[:space:]]+[^[:space:]]*\.env[^[:space:];&|]*[[:space:]]*($|[;&|])"
  EXISTENCE_ONLY="${S}(ls|test|\[|stat|file|touch|chmod|chown)([[:space:]]|$)"

  if m "$IGNORE_FILE"; then
    m "$READ_VERBS" && ! m "${S}(echo|printf|grep|cat)([[:space:]]|$)" \
      && decide ask "This command touches an ignore file and references '${secret}'. Confirm it does not expose secret values."
  elif m "$TEMPLATE_COPY"; then
    decide ask "This copies a template over '${secret}' and would overwrite existing secrets. Confirm it is intended."
  elif m "$READ_VERBS"; then
    decide deny "Blocked by ai-config safety guard: '${secret}' $SECRET_REASON"
  elif m "$EXISTENCE_ONLY" && ! m '[|>]|\$\(|`'; then
    :
  else
    decide ask "This command references '${secret}', which may contain secrets. Confirm it will not read or expose secret values."
  fi
fi

# --- Secrets inside files the command would read ----------------------------
# The checks above match on the path. This one opens the file. Tokens come from the
# original command, not the lowercased copy, so paths survive on a case-sensitive
# filesystem. Capped at a handful of files to keep the hook well inside its timeout.
if m "$READ_VERBS"; then
  # `cd dir; cat x` reads dir/x. A relative name is scanned as written and under every
  # directory the command cds into (fail closed: which one applies depends on order).
  CD_DIRS=()
  _rest="$cmd" _cur=""
  _cd_re='(^|[;&|(])[[:space:]]*cd[[:space:]]+([^;&|()[:space:]]+)'
  while [[ "$_rest" =~ $_cd_re ]]; do
    _d="${BASH_REMATCH[2]//[\"\']/}"
    case "$_d" in "~"*) _d="$HOME${_d#\~}" ;; esac
    case "$_d" in /*) _cur="$_d" ;; *) _cur="${_cur:+$_cur/}$_d" ;; esac
    CD_DIRS+=("$_cur")
    _rest="${_rest#*"${BASH_REMATCH[0]}"}"
  done
  scanned=0
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    [[ "$STAGE_ONLY_TOKS" == *" $(lower "$tok") "* ]] && continue
    _cands=("$tok")
    if [[ "$tok" != /* ]]; then
      for _d in ${CD_DIRS[@]+"${CD_DIRS[@]}"}; do _cands+=("$_d/$tok"); done
    fi
    for _f in "${_cands[@]}"; do
      [[ -f "$_f" ]] || continue
      scan_msg="$(secret_scan "$_f")"
      case $? in
        0) decide deny "Blocked by ai-config safety guard: '${_f}' contains ${scan_msg}. $SCAN_TAIL" ;;
        2) decide deny "Blocked by ai-config safety guard: '${_f}' ${scan_msg}. $SCAN_BIG_TAIL" ;;
      esac
      scanned=$((scanned + 1))
    done
    [[ $scanned -ge 5 ]] && break
  done <<EOF
$(printf '%s' "$cmd" | tr -c 'A-Za-z0-9._/~*@+:%-' '\n')
EOF
fi

# --- Commands that print a credential ----------------------------------------
# gh auth token, a Keychain lookup with -w, op read … put the secret itself on stdout.
# Inside $( ) the value usually flows into another command (GH_TOKEN=$(gh auth token) gh api),
# which is fine, unless that command echoes it.
PRINTS_SECRET_RE="${S}(gh[[:space:]]+auth[[:space:]]+token|security[[:space:]]+find-(generic|internet)-password([[:space:]][^;&|]*)?[[:space:]]-[a-z]*[wg]([[:space:]]|$)|op[[:space:]]+read[[:space:]]|op[[:space:]]+item[[:space:]]+get[^;&|]*--reveal|aws[[:space:]]+configure[[:space:]]+(get|export-credentials)|gcloud[[:space:]]+auth[[:space:]]+(application-default[[:space:]]+)?print-(access|identity)-token|heroku[[:space:]]+auth:token|doppler[[:space:]]+secrets|vault[[:space:]]+(kv[[:space:]]+get|read)[[:space:]]|${G}credential[[:space:]]+fill|npm[[:space:]]+token[[:space:]]+create|bw[[:space:]]+(get[[:space:]]+(password|item|notes|totp|attachment)|list[[:space:]]+items|export)|bws[[:space:]]+(secret|secrets)[[:space:]]+(get|list))"
if m "$PRINTS_SECRET_RE"; then
  _top="$lc"
  # A commit message describing such a command is prose, not a call. Its -m strings are
  # removed first; then a heredoc is dropped only when it directly follows -F - / --file=- on
  # the git commit line, outside quotes, and its terminator line is found. Otherwise every line
  # is kept (fail closed). Anything chained after the commit still counts.
  if m "${S}${G}commit([[:space:]]|$)"; then
    _top="$(lower "$cmd" | sed -E "s/(-m|--message)[[:space:]]*(\"[^\"]*\"|'[^']*')/ /g" | awk '
      function quotes_balanced(s,   d, q) { d = gsub(/"/, "&", s); q = gsub(/\047/, "&", s); return (d % 2 == 0 && q % 2 == 0) }
      hd { body = body $0 "\n"; if ($0 == term) { hd = 0; body = "" } ; next }
      {
        print
        # Only when git commit -F - is the line'"'"'s first command (optionally after cd … &&),
        # the heredoc marker ends the line, and it is the line'"'"'s only "<<". A "<<-" heredoc
        # (tab-indented terminator) gets no exemption: its end can differ from ours.
        tmp = $0
        if (gsub(/<</, "&", tmp) == 1 && match($0, /^[ \t]*(cd[ \t]+[^;&|<]*&&[ \t]*)?git([ \t]+-c[ \t]+[^ \t;&|<]+)*[ \t]+commit[ \t][^;&|<]*(-f|--file)[ \t]*=?[ \t]*-[ \t]*<<[ \t]*["\047]?[a-z_][a-z0-9_]*["\047]?[ \t]*$/)) {
          pre = $0
          sub(/<<.*/, "", pre)
          if (quotes_balanced(pre)) {
            term = substr($0, RSTART, RLENGTH); sub(/.*<<-?[ \t]*["\047]?/, "", term); sub(/["\047]$/, "", term)
            hd = 1; body = ""
          }
        }
      }
      END { if (hd) printf "%s", body }' | tr '\n' ';')"
  fi
  while [[ "$_top" =~ \$\([^()]*\) ]]; do _top="${_top/"${BASH_REMATCH[0]}"/ }"; done
  _top="$(printf '%s' "$_top" | sed 's/`[^`]*`/ /g')"
  if [[ "$_top" =~ $PRINTS_SECRET_RE ]] || [[ "$_top" =~ ${S}(echo|printf|print|cat|tee)([[:space:]]|$) ]]; then
    decide deny "Blocked by ai-config safety guard: this command prints a credential (token, password or key) into the transcript (Safety Guardrail #1). Pass it straight to the command that needs it instead, e.g. GH_TOKEN=\$(gh auth token) gh api …, or ask the developer to run it themselves."
  fi
fi

# --- Recursive searches that would return lines from secret files -----------
# The command is split with Python's shlex (quotes, -e, --include, rg -g '!x'): one line per
# recursive search, fields as search_leak takes them.
IFS= read -r -d '' SEARCH_PY <<'PY' || true
import os, shlex, sys
cmd, cwd = sys.argv[1], sys.argv[2]
try:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=';&|()')
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    sys.exit(0)
segs, cur = [], []
for t in toks:
    if t and set(t) <= set(';&|()'):
        segs.append(cur); cur = []
    else:
        cur.append(t)
segs.append(cur)
US = '\x1f'
d = cwd
# options that take a value, per tool family
GREP_SHORT, GREP_LONG = set('efmABCdD'), {'--regexp', '--file', '--max-count', '--after-context',
    '--before-context', '--context', '--include', '--exclude', '--exclude-dir', '--exclude-from',
    '--label', '--directories', '--devices', '--binary-files', '--group-separator'}
RG_SHORT, RG_LONG = set('efgtTmABCMjErd'), {'--regexp', '--file', '--glob', '--iglob', '--type',
    '--type-not', '--max-count', '--after-context', '--before-context', '--context', '--max-columns',
    '--threads', '--encoding', '--replace', '--max-depth', '--type-add', '--sort', '--sortr',
    '--colors', '--pre', '--pre-glob', '--ignore-file', '--path-separator', '--engine'}
for s in segs:
    while s and (s[0] in ('sudo', 'command', 'exec', 'time', 'nohup', 'xargs', 'env')
                 or ('=' in s[0] and s[0].split('=', 1)[0].replace('_', 'a').isalnum())):
        s = s[1:]
    if not s:
        continue
    c = os.path.basename(s[0])
    if c == 'cd':
        if len(s) > 1:
            d = os.path.normpath(os.path.join(d, os.path.expanduser(s[1])))
        continue
    if c not in ('grep', 'egrep', 'fgrep', 'zgrep', 'rg', 'ag', 'ack'):
        continue
    grepish = c in ('grep', 'egrep', 'fgrep', 'zgrep')
    short, long_ = (GREP_SHORT, GREP_LONG) if grepish else (RG_SHORT, RG_LONG)
    rec = not grepish
    fixed = c == 'fgrep'
    icase = False
    hidden = c == 'ack' or grepish
    noignore = c == 'ack' or grepish
    pats, pos, inc, exc, patfile, u = [], [], [], [], False, 0
    args, i = s[1:], 0
    endopts = False
    while i < len(args):
        a = args[i]; i += 1
        if endopts or not a.startswith('-') or a == '-':
            pos.append(a); continue
        if a == '--':
            endopts = True; continue
        if a.startswith('--'):
            name, eq, val = a.partition('=')
            if name in long_ and not eq:
                val = args[i] if i < len(args) else ''; i += 1
            if name == '--recursive' or name == '--dereference-recursive': rec = True
            elif name in ('--fixed-strings',): fixed = True
            elif name in ('--ignore-case',): icase = True
            elif name == '--regexp': pats.append(val)
            elif name == '--file': patfile = True
            elif name == '--include': inc.append(val)
            elif name in ('--exclude', '--exclude-dir'): exc.append(val)
            elif name in ('--glob', '--iglob'):
                (exc if val.startswith('!') else inc).append(val.lstrip('!'))
            elif name in ('--hidden',): hidden = True
            elif name in ('--no-ignore', '--no-ignore-vcs', '--skip-vcs-ignores'): noignore = True
            elif name in ('--unrestricted',): hidden = noignore = True
            elif name == '--directories' and val == 'recurse': rec = True
            continue
        j = 1
        while j < len(a):
            ch = a[j]; j += 1
            if ch in short:
                val = a[j:] if j < len(a) else (args[i] if i < len(args) else '')
                if j >= len(a): i += 1
                j = len(a)
                if ch == 'e': pats.append(val)
                elif ch == 'f': patfile = True
                elif ch == 'g' and not grepish: (exc if val.startswith('!') else inc).append(val.lstrip('!'))
                elif ch == 'd' and grepish and val == 'recurse': rec = True
                continue
            if grepish and ch in 'rR': rec = True
            elif ch == 'F': fixed = True
            elif ch == 'i': icase = True
            elif ch == 'u' and not grepish: u += 1
            elif ch == '.' and not grepish: hidden = True
    if not rec:
        continue
    if u >= 1: noignore = True
    if u >= 2: hidden = True
    if not pats and not patfile:
        if not pos:
            continue
        pats.append(pos.pop(0))
    if patfile:
        pats = []
    roots = [os.path.normpath(os.path.join(d, os.path.expanduser(p))) for p in pos] or [d]
    print('\x1e'.join([US.join(pats), '1' if fixed else '0', '1' if icase else '0', US.join(inc),
                     US.join(exc), '1' if hidden else '0', '1' if noignore else '0',
                     'grep' if grepish else 'rg', US.join(roots)]))
PY
if m "${S}(grep|egrep|fgrep|zgrep|rg|ag|ack)([[:space:]]|$)" && command -v python3 >/dev/null 2>&1; then
  _cwd="$(json_field .cwd)"; _cwd="${_cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  # \x1e, not a tab: bash collapses runs of whitespace IFS, which would drop empty fields.
  while IFS=$'\x1e' read -r _pats _fx _ci _inc _exc _hid _noign _eng _roots; do
    [[ -n "$_roots" ]] || continue
    _rootv=()
    while IFS= read -r -d $'\x1f' _r; do [[ -n "$_r" ]] && _rootv+=("$_r"); done <<< "$_roots"$'\x1f'
    if _hit="$(SEARCH_ENGINE="$_eng" search_leak "$_pats" "$_fx" "$_ci" "$_inc" "$_exc" "$_hid" "$_noign" "${_rootv[@]}")"; then
      decide deny "Blocked by ai-config safety guard: this search would print lines from '${_hit}', which $SECRET_REASON $SEARCH_TAIL"
    fi
  done < <(python3 -I -c "$SEARCH_PY" "$cmd" "$_cwd" 2>/dev/null)
fi

# --- Commits: nothing secret goes into git history ---------------------------
if m "${S}${G}commit([[:space:]]|$)"; then
  _dir="$(json_field .cwd)"; _dir="${_dir:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  _cdre='(^|[;&|(])[[:space:]]*cd[[:space:]]+([^;&|()[:space:]]+)'
  if [[ "$cmd" =~ $_cdre ]]; then
    _d="${BASH_REMATCH[2]//[\"\']/}"; case "$_d" in "~"*) _d="$HOME${_d#\~}" ;; esac
    case "$_d" in /*) _dir="$_d" ;; *) _dir="$_dir/$_d" ;; esac
  fi
  if [[ "$cmd" =~ git[[:space:]]+-C[[:space:]]+([^[:space:];&|]+) ]]; then
    _d="${BASH_REMATCH[1]//[\"\']/}"; case "$_d" in /*) _dir="$_d" ;; *) _dir="$_dir/$_d" ;; esac
  fi
  _all=0
  m "commit([[:space:]]+[^;&|]*)?[[:space:]](-[b-z]*a[a-z]*|--all)([[:space:]]|$)" && _all=1
  COMMIT_DECISION=""
  commit_verdict "$_dir" "$_all"
  [[ -n "$COMMIT_DECISION" ]] && decide "$COMMIT_DECISION" "$COMMIT_REASON"
fi

# --- Local database queries that return personal data ------------------------
# Local CMS databases are often copies of production. A query that returns names, emails or
# whole rows from a members/users table puts that personal data into the transcript. Counts,
# ids and other columns pass; remote queries are handled (and asked about) below.
LOCAL_DB_RE="${S}(ddev[[:space:]]+(mysql|psql|wp[[:space:]]+db[[:space:]]+query|craft[[:space:]]+db)|mysql|mariadb|psql|sqlite3|wp([[:space:]]+[^;&|]*)?[[:space:]]+db[[:space:]]+query|php[[:space:]]+craft[[:space:]]+db)([[:space:]]|$)"
PII_TABLE_RE="select[[:space:]]+(.+)[[:space:]]from[[:space:]]+[\`\"]?[a-z0-9_.]*(member|user|customer|patient|donor|subscriber|contact|account|people|person|registrant|applicant|volunteer|famil|guardian|submission|form_entr|usermeta|order)"
if m "$LOCAL_DB_RE" && [[ "$lc" =~ $PII_TABLE_RE ]]; then
  _sel="${BASH_REMATCH[1]}"
  _sel="$(printf '%s' "$_sel" | sed -E 's/count\([^)]*\)//g; s/[[:space:]]from[[:space:]].*//')"
  if [[ "$_sel" =~ (\*|mail|name|phone|address|street|city|postal|zip|birth|dob|ssn|health|ip_address|password|meta_value|first|last|contact|note) ]]; then
    decide ask "This query returns personal data (${BASH_REMATCH[1]} from a people table). Local databases are often copies of production, so the rows would go into the transcript. Select only the columns you need (ids, counts, statuses), or approve if this data is safe to see."
  fi
fi

# --- Catastrophic / irreversible: deny ---------------------------------------
RM_TARGET='["'"'"']?(/|/\*|~|~/|~/\*|\$home|\$\{home\}|\$home/|\$home/\*|\*|\.|\./|\.\.|\.\./)["'"'"']?([[:space:]]|$|[;&|])'
if m "${S}rm([[:space:]]+-[a-z-]+)*[[:space:]]+-[a-z-]*r[a-z-]*([[:space:]]+-[a-z-]+)*[[:space:]]+${RM_TARGET}"; then
  decide deny "Blocked by ai-config safety guard: recursive delete of a root, home, or whole-project path. Ask the developer to run it themselves if truly intended."
fi
if m "${S}(mkfs(\.[a-z0-9]+)?|fdisk|diskutil[[:space:]]+(erase|zero|partition))([[:space:]]|$)" || m "${S}dd[[:space:]].*of=/dev/" || m ':\(\)[[:space:]]*\{[[:space:]]*:\|:&'; then
  decide deny "Blocked by ai-config safety guard: disk-level destructive command."
fi

# --- EE migration runner -----------------------------------------------------
# .admin-scripts/ee-migrate.sh is the only sanctioned path for EE migrations to reach a
# server (EE Migrate spec §8). Its own checks gate staging; production apply always asks.
# Only a plain, canonical invocation is recognised — anything wrapped or chained asks.
if [[ "$lc" == *ee-migrate.sh* ]]; then
  EEM_CANON='^([[:space:]]*cd[[:space:]]+[^;&|`$()]+[[:space:]]*&&[[:space:]]*)?(bash[[:space:]]+)?\.admin-scripts/ee-migrate\.sh[[:space:]]+(local[[:space:]]+test[[:space:]]+[a-z0-9_]+|(staging|prod)[[:space:]]+(status|rehearse)|(staging|prod)[[:space:]]+apply[[:space:]]+--expect=[a-z0-9_,]+)[[:space:]]*$'
  if [[ ! "$lc" =~ $EEM_CANON ]]; then
    decide ask "ee-migrate.sh was called in a form the safety guard does not recognise (wrapped, chained, absolute path or unknown mode). Run it plainly from the repo root, or confirm this exact command."
  elif [[ "$lc" =~ (^|[[:space:]])prod[[:space:]]+apply([[:space:]]|$) ]]; then
    decide ask "Production migration: ee-migrate.sh will back up the production database and run the listed migrations. Approve only for this exact set."
  fi
fi

# --- Remote servers and databases -------------------------------------------
# An SSH alias is not a safety boundary: staging and production often share a host, a
# login and a database server, so the only thing separating them is the path or database
# the command names. The project declares those in ai-config.conf:
#
#   [remote]
#   production = /var/www/example.com        # paths, host aliases, database names, @aliases
#   staging    = /var/www/stg.example.com
#   assert-database = true    # optional: a staging write must run SELECT DATABASE() first
#
# Every remote invocation — ssh, scp/rsync, wp @alias / --ssh, a database client with a
# non-local host or connection URI — is parsed (quotes, heredocs, bash -c, VAR=…; $VAR)
# and its commands classified:
#   safe    read-only and output-safe (versions, status, listings, counts, hashes) → defer
#   content returns file contents, config, logs or rows; unscanned, may hold secrets or PII → ask
#   write   changes something, or is not recognised                                → ask; deny on production
#   opaque  cannot be inspected: interactive, a script file, a tunnel               → ask; deny on production
# Markers match longest first, so a staging path that contains the production one
# (stg.example.com vs example.com) is not mistaken for it. Any production marker wins.
REMOTE_MARKERS=""
REMOTE_POLICY=false
REMOTE_ASSERT_DB=false
for _pol in ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR/ai-config.conf"} "${BASH_SOURCE[0]%/*}/../../ai-config.conf"; do
  [[ -f "$_pol" ]] || continue
  _section=""
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line%$'\r'}"
    _line="${_line%%[[:space:]]#*}"
    _line="${_line#"${_line%%[![:space:]]*}"}"
    _line="${_line%"${_line##*[![:space:]]}"}"
    case "$_line" in ''|'#'*|';'*) continue ;; '['*) _section="$_line"; continue ;; esac
    [[ "$_section" == "[remote]" && "$_line" == *=* ]] || continue
    _key="$(lower "${_line%%=*}")"; _key="${_key//[[:space:]]/}"
    if [[ "$_key" == assert-database ]]; then
      case "$(lower "${_line#*=}")" in *true*|*yes*|*on*|*1*) REMOTE_ASSERT_DB=true ;; esac
      continue
    fi
    [[ "$_key" == production || "$_key" == staging ]] || continue
    IFS=',' read -r -a _vals <<< "${_line#*=}"
    for _v in ${_vals[@]+"${_vals[@]}"}; do
      _v="$(lower "$_v")"; _v="${_v#"${_v%%[![:space:]]*}"}"; _v="${_v%"${_v##*[![:space:]]}"}"
      while [[ "$_v" == */ && "$_v" != / ]]; do _v="${_v%/}"; done
      [[ -n "$_v" ]] || continue
      REMOTE_MARKERS+="${_key}"$'\t'"${_v}"$'\n'
      [[ "$_key" == production ]] && REMOTE_POLICY=true
    done
  done < "$_pol"
  break
done

read -r -d '' REMOTE_AWK <<'AWK'
function lc(s) { return tolower(s) }
function bname(p,   n, P) { n = split(p, P, "/"); return n ? P[n] : p }
function joinw(W, a, b,   s, k) { s = ""; for (k = a; k <= b; k++) s = s (k > a ? " " : "") W[k]; return s }
function clip(s) { gsub(/[\t\n\r"\\\001\037]/, " ", s); gsub(/  +/, " ", s); return length(s) > 80 ? substr(s, 1, 77) "..." : s }
function res(c, W, i, m,   e) { e = i + 3; if (e > m) e = m; CD = clip(joinw(W, i, e)); return c }
function res_d(c, d) { CD = clip(d); return c }
function isin(w, list) { return index(" " list " ", " " w " ") > 0 }

# ---- tokenizer: words (quotes removed), control operators, redirections, heredoc bodies
function emit(T, K, n, w, x) {
  n++; T[n] = w; K[n] = x ? "x" : "w"
  if (EXPECT_DELIM) { HDN++; HDI[HDN] = EXPECT_DELIM; HDD[HDN] = w; HDS[HDN] = EXPECT_STRIP; EXPECT_DELIM = 0 }
  return n
}
function subst_end(s, i, len,   j, d, c) {
  if (substr(s, i, 1) == "`") { j = index(substr(s, i + 1), "`"); return j ? i + j : len }
  d = 0
  for (j = i + 1; j <= len; j++) { c = substr(s, j, 1); if (c == "(") d++; else if (c == ")") { d--; if (d == 0) return j } }
  return len
}
function subst_inner(s, i, e) { return substr(s, i, 1) == "`" ? substr(s, i + 1, e - i - 1) : substr(s, i + 2, e - i - 2) }
function tokenize(s, T, K, B,    n, i, len, c, c2, c3, w, inw, x, j, e, k, line, test, body, op) {
  n = 0; len = length(s); w = ""; inw = 0; x = 0; HDN = 0; EXPECT_DELIM = 0
  i = 1
  while (i <= len) {
    c = substr(s, i, 1)
    if (c == Q1) {
      j = index(substr(s, i + 1), Q1)
      if (j == 0) { w = w substr(s, i + 1); inw = 1; break }
      w = w substr(s, i + 1, j - 1); i += j + 1; inw = 1; continue
    }
    if (c == "\"") {
      inw = 1; i++
      while (i <= len) {
        c = substr(s, i, 1)
        if (c == "\\") {
          c2 = substr(s, i + 1, 1)
          if (c2 == "\n") { i += 2; continue }
          if (index("\"\\$`", c2)) { w = w c2; i += 2; continue }
          w = w c; i++; continue
        }
        if (c == "\"") { i++; break }
        if (c == "`" || (c == "$" && substr(s, i + 1, 1) == "(")) {
          e = subst_end(s, i, len); SUBS[++NSUBS] = subst_inner(s, i, e)
          w = w substr(s, i, e - i + 1); x = 1; i = e + 1; continue
        }
        w = w c; i++
      }
      continue
    }
    if (c == "\\") { c2 = substr(s, i + 1, 1); if (c2 != "\n") { w = w c2; inw = 1 }; i += 2; continue }
    if (c == "`" || (c == "$" && substr(s, i + 1, 1) == "(")) {
      e = subst_end(s, i, len); SUBS[++NSUBS] = subst_inner(s, i, e)
      w = w substr(s, i, e - i + 1); x = 1; inw = 1; i = e + 1; continue
    }
    if (c == "$" && substr(s, i + 1, 1) == "{") {
      j = index(substr(s, i), "}"); if (j == 0) j = len - i + 1
      w = w substr(s, i, j); inw = 1; i += j; continue
    }
    if (c == "#" && !inw) { j = index(substr(s, i), "\n"); if (j == 0) break; i += j - 1; continue }
    if (c == " " || c == "\t") { if (inw) { n = emit(T, K, n, w, x); w = ""; inw = 0; x = 0 }; i++; continue }
    if (index("\n;&|()<>", c)) {
      if (inw && (c == "<" || c == ">") && w ~ /^[0-9]+$/ && !x) { w = ""; inw = 0 }
      if (inw) { n = emit(T, K, n, w, x); w = ""; inw = 0; x = 0 }
      c2 = substr(s, i + 1, 1); c3 = substr(s, i + 2, 1)
      if (c == "\n") {
        n++; T[n] = ";"; K[n] = "o"; i++
        for (k = 1; k <= HDN; k++) {
          body = ""
          while (i <= len) {
            j = index(substr(s, i), "\n")
            line = j ? substr(s, i, j - 1) : substr(s, i)
            i = j ? i + j : len + 1
            test = line; if (HDS[k]) sub(/^\t+/, "", test)
            if (test == HDD[k]) break
            body = body line "\n"
          }
          B[HDI[k]] = body
        }
        HDN = 0
        continue
      }
      if (c == "<") {
        if (c2 == "<" && c3 == "<") op = "<<<"
        else if (c2 == "<" && c3 == "-") op = "<<-"
        else if (c2 == "<") op = "<<"
        else if (c2 == ">") op = "<>"
        else if (c2 == "&") op = "<&"
        else op = "<"
        n++; T[n] = op; K[n] = "r"; B[n] = ""; i += length(op)
        if (op == "<<" || op == "<<-") { EXPECT_DELIM = n; EXPECT_STRIP = (op == "<<-") }
        continue
      }
      if (c == ">") {
        if (c2 == ">") op = ">>"; else if (c2 == "&") op = ">&"; else if (c2 == "|") op = ">|"; else op = ">"
        n++; T[n] = op; K[n] = "r"; i += length(op); continue
      }
      if (c == "&" && c2 == ">") { op = (c3 == ">") ? "&>>" : "&>"; n++; T[n] = op; K[n] = "r"; i += length(op); continue }
      if (c == "&") op = (c2 == "&") ? "&&" : "&"
      else if (c == "|") { op = (c2 == "|") ? "||" : "|"; if (c2 == "&") i++ }
      else op = c
      n++; T[n] = op; K[n] = "o"; i += length(op)
      continue
    }
    w = w c; inw = 1; i++
  }
  if (inw) n = emit(T, K, n, w, x)
  return n
}

# ---- variables: VAR=value earlier in the command, so `$W option update` is still seen
function repl(s, a, b,   p, out) { out = ""; while ((p = index(s, a)) > 0) { out = out substr(s, 1, p - 1) b; s = substr(s, p + length(a)) }; return out s }
function repl_var(s, a, b,   p, out, nx) {
  out = ""
  while ((p = index(s, a)) > 0) {
    nx = substr(s, p + length(a), 1)
    if (nx ~ /[A-Za-z0-9_]/) { out = out substr(s, 1, p + length(a) - 1); s = substr(s, p + length(a)); continue }
    out = out substr(s, 1, p - 1) b; s = substr(s, p + length(a))
  }
  return out s
}
function expand(w,   k) {
  if (index(w, "$") == 0) return w
  for (k in VARS) { w = repl(w, "${" k "}", VARS[k]); w = repl_var(w, "$" k, VARS[k]) }
  return w
}
function seg_expand(W, WK, m,   N, NK, nm, i, j, k, v, P, np) {
  split("", N); split("", NK); nm = 0
  for (i = 1; i <= m; i++) {
    v = W[i]
    if (v ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) {
      k = v; gsub(/[${}]/, "", k)
      if (k in VARS) { np = split(VARS[k], P, /[ \t]+/); for (j = 1; j <= np; j++) if (P[j] != "") { N[++nm] = P[j]; NK[nm] = "w" }; continue }
    }
    N[++nm] = expand(v); NK[nm] = WK[i]
  }
  i = (nm > 0 && isin(N[1], "export local readonly declare typeset")) ? 2 : 1
  for (; i <= nm; i++) {
    if (N[i] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) break
    k = index(N[i], "="); VARS[substr(N[i], 1, k - 1)] = substr(N[i], k + 1)
  }
  for (i = 1; i <= nm; i++) { W[i] = N[i]; WK[i] = NK[i] }
  for (i = nm + 1; i <= m; i++) { delete W[i]; delete WK[i] }
  return nm
}

# ---- walk: split into simple commands; "local" finds remote invocations, "remote" classifies
function walk(s, level, sinp, skind, depth,    T, K, B, n, t, W, WK, m, prev, hb, hk, out, cls, worst, wd, s0, s1, k, op, opi, tg) {
  if (depth > 6) return res_d("opaque", "nested too deeply to inspect")
  split("", T); split("", K); split("", B); split("", W); split("", WK)
  s0 = NSUBS; n = tokenize(s, T, K, B); s1 = NSUBS
  worst = "safe"; wd = ""; prev = ""; m = 0; hb = ""; hk = ""; out = 0
  for (t = 1; t <= n + 1; t++) {
    if (t <= n && K[t] == "r") {
      op = T[t]; opi = t; tg = ""
      if (t < n && K[t + 1] != "o" && K[t + 1] != "r") { tg = T[t + 1]; t++ }
      if (op == "<<" || op == "<<-") { hb = B[opi]; hk = "heredoc" }
      else if (op == "<<<") { hb = tg; hk = "herestring" }
      else if (op == "<" || op == "<>") hk = "file"
      else if (op == ">&" || op == "<&") { if (tg !~ /^[0-9-]*$/ && tg != "/dev/null") out = 1 }
      else if (tg != "/dev/null") out = 1
      continue
    }
    if (t <= n && K[t] != "o") { m++; W[m] = T[t]; WK[m] = K[t]; continue }
    if (m > 0) {
      if (hk == "" && prev != "|" && skind != "") { hb = sinp; hk = skind }
      m = seg_expand(W, WK, m)
      if (m > 0) {
        if (level == "local") local_seg(W, WK, m, hb, hk, depth)
        else { cls = remote_seg(W, WK, m, prev, hb, hk, out, depth); if (RANK[cls] > RANK[worst]) { worst = cls; wd = CD } }
      }
    }
    if (t <= n) prev = T[t]
    m = 0; hb = ""; hk = ""; out = 0; split("", W); split("", WK)
  }
  if (level == "local") for (k = s0 + 1; k <= s1; k++) walk(SUBS[k], "local", "", "", depth + 1)
  CD = wd
  return worst
}

# Wrappers that run the next word as the command. Sets WRAP_SHELL for sudo -i / -s.
function skip_wrappers(W, m, i,   b) {
  while (i <= m) {
    if (W[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
    b = lc(bname(W[i]))
    if (b == "sudo" || b == "doas") {
      i++
      while (i <= m && W[i] ~ /^-/) { if (W[i] ~ /^-[a-zA-Z]*[is]$/ && W[i] !~ /^--/) WRAP_SHELL = 1; if (W[i] ~ /^-[ugChpDrtU]$/) i++; i++ }
      continue
    }
    if (b == "env") { i++; while (i <= m && (W[i] ~ /^-/ || W[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) { if (W[i] ~ /^-[uSC]$/) i++; i++ }; continue }
    if (b == "command" && W[i + 1] ~ /^-[vV]$/) return m + 1
    if (isin(b, "nohup time command exec builtin nice ionice stdbuf chronic")) { i++; while (i <= m && W[i] ~ /^-/) { if (W[i] == "-n" || W[i] == "-c") i++; i++ }; continue }
    if (b == "timeout") { i++; while (i <= m && W[i] ~ /^-/) { if (W[i] ~ /^-[sk]$/) i++; i++ }; i++; continue }
    if (b == "xargs") { i++; while (i <= m && W[i] ~ /^-/) { if (W[i] ~ /^-[InLPEsd]$/) i++; i++ }; continue }
    break
  }
  return i
}
function shell_string(W, i, m, anywhere,   j, a) {
  SHS_FOUND = 0; SHS_SCRIPT = 0
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (a ~ /^-[A-Za-z]*c[A-Za-z]*$/) { SHS_FOUND = 1; return (j < m) ? W[j + 1] : "" }
    if (a !~ /^-/ && !anywhere) { SHS_SCRIPT = 1; return "" }
  }
  return ""
}
function db_host(W, i, m,   j, a, u) {
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (a == "-h" || a == "--host" || a == "--hostname") return lc(W[j + 1])
    if (a ~ /^--host(name)?=/) return lc(substr(a, index(a, "=") + 1))
    if (a ~ /^-h./ && a !~ /^-help/) return lc(substr(a, 3))
    if (a ~ /^[a-z+]+:\/\/[^\/]*@/) { u = a; sub(/^[a-z+]+:\/\/[^\/]*@/, "", u); sub(/[:\/?].*$/, "", u); return lc(u) }
    if (a ~ /^(mongodb(\+srv)?|redis|rediss|postgres(ql)?|mysql|mariadb):\/\//) { u = a; sub(/^[a-z+]+:\/\//, "", u); sub(/[:\/?].*$/, "", u); return lc(u) }
  }
  return ""
}
function is_local_host(h) { return h == "" || isin(h, "localhost 127.0.0.1 ::1 db 0.0.0.0 host.docker.internal") || h ~ /\.ddev\.site$/ || h ~ /^\// }

# ---- local level: find remote invocations
function local_seg(W, WK, m, hb, hk, depth,    i, c, j, str, h, u) {
  WRAP_SHELL = 0
  i = skip_wrappers(W, m, 1)
  if (i > m) return
  c = lc(bname(W[i]))
  if (c == "ssh") { ssh_inv(W, m, i, hb, hk, depth); return }
  if (c == "scp" || c == "rsync") { copy_inv(W, m, i, c); return }
  if (c == "wp") {
    for (j = i + 1; j <= m; j++) if (W[j] ~ /^@./ || W[j] ~ /^--ssh=/) { invocation("wp-cli", joinw(W, i, m), classify_wp(W, i + 1, m, hb, hk, i)); return }
    return
  }
  if (isin(c, "mysql mariadb psql mongosh mongo redis-cli")) {
    h = db_host(W, i, m)
    if (!is_local_host(h)) invocation(c, joinw(W, i, m), classify_dbcli(W, i, m, "", hb, hk))
    return
  }
  if (isin(c, "bash sh zsh dash ksh su")) {
    str = shell_string(W, i, m, c == "su")
    if (SHS_FOUND) walk(str, "local", "", "", depth + 1)
    else if (!SHS_SCRIPT && (hk == "heredoc" || hk == "herestring")) walk(hb, "local", "", "", depth + 1)
    return
  }
  if (c == "eval") { walk(joinw(W, i + 1, m), "local", "", "", depth + 1); return }
  # Any other tool handed a remote database URI (Prisma, Drizzle, Knex, a script, …).
  for (j = 1; j <= m; j++) {
    u = W[j]; sub(/^[A-Za-z_][A-Za-z0-9_]*=/, "", u)
    if (u ~ /^(mongodb(\+srv)?|redis|rediss|postgres(ql)?|mysql|mariadb|mssql|sqlserver):\/\//) {
      split("", DBW); DBW[1] = "x"; DBW[2] = u; h = db_host(DBW, 1, 2)
      if (!is_local_host(h)) { invocation("database", joinw(W, 1, m), res_d("opaque", "runs " joinw(W, i, i + 2) " against a remote database")); return }
    }
  }
}
function ssh_inv(W, m, i, hb, hk, depth,    j, a, p, ch, host, rt, cls, tunnel) {
  NSSH++
  j = i + 1; tunnel = 0
  while (j <= m) {
    a = W[j]
    if (a == "--") { j++; break }
    if (a !~ /^-./) break
    for (p = 2; p <= length(a); p++) {
      ch = substr(a, p, 1)
      if (index("LRDWN", ch)) tunnel = 1
      if (index("BbcDEeFIiJLlmOoPpQRSWw", ch)) { if (p == length(a)) j++; break }
    }
    j++
  }
  host = (j <= m) ? W[j] : ""
  if (host == "") { CD = ""; invocation("ssh", "", "safe"); return }
  rt = (j < m) ? joinw(W, j + 1, m) : ""
  if (tunnel) cls = res_d("opaque", "ssh tunnel / port forward to " host)
  else if (rt == "" && (hk == "heredoc" || hk == "herestring")) cls = walk(hb, "remote", "", "", depth + 1)
  else if (rt == "") cls = res_d("opaque", (hk == "file" ? "ssh " host " < script file" : "interactive ssh session on " host))
  else cls = walk(rt, "remote", hb, hk, depth + 1)
  invocation("ssh", host " " expand(rt) " " hb, cls)
}
function is_remote_spec(a) { return a ~ /^[^\/]*:/ && a !~ /^[a-z]+:\/\// }
function copy_inv(W, m, i, c,    j, a, no, O, k, remote) {
  no = 0; split("", O)
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (a ~ /^-/) {
      if (c == "scp" && a ~ /^-[cDFiJloPSX]$/) j++
      if (c == "rsync" && (a ~ /^-[eBfTM]$/ || a ~ /^--(exclude|include|rsh|filter|files-from|exclude-from|include-from|temp-dir|partial-dir|backup-dir|log-file|password-file|chmod|chown|rsync-path)$/)) j++
      continue
    }
    O[++no] = a
  }
  if (no == 0) return
  remote = 0
  for (k = 1; k <= no; k++) if (is_remote_spec(O[k])) remote = 1
  if (!remote) return
  if (is_remote_spec(O[no])) invocation(c, joinw(W, i, m), res_d("write", c " upload to " O[no]))
  else invocation(c, joinw(W, i, m), res_d("content", c " download from " O[1]))
}
function invocation(what, text, cls,    t, k, p, mk, prod, stg, pm, sm, tgt, d) {
  t = lc(text); prod = 0; stg = 0; pm = ""; sm = ""
  for (k = 1; k <= NM; k++) {
    mk = MV[k]
    while ((p = index(t, mk)) > 0) {
      if (MC[k] == "production") { prod = 1; if (pm == "") pm = mk } else { stg = 1; if (sm == "") sm = mk }
      t = substr(t, 1, p - 1) "\001" substr(t, p + length(mk))
    }
  }
  tgt = prod ? "production" : (stg ? "staging" : "unknown")
  if (cls == "safe") d = "none"
  else if (tgt == "production" && (cls == "write" || cls == "opaque")) d = "deny"
  else d = "ask"
  if (DRANK[d] > DRANK[BEST]) { BEST = d; B_WHAT = what; B_TGT = tgt; B_MK = prod ? pm : sm; B_CLS = cls; B_DET = CD }
}

# ---- remote level: classify one simple command
function remote_seg(W, WK, m, prev, hb, hk, out, depth,    i, j, c, c1) {
  WRAP_SHELL = 0
  c1 = lc(bname(W[1]))
  if (c1 == "printenv" || (c1 == "env" && skip_wrappers(W, m, 1) > m)) return res("content", W, 1, m)
  if ((isin(c1, "export declare typeset") && (m == 1 || W[2] ~ /^-[a-z]*[px]/)) || (c1 == "set" && m == 1)) return res("content", W, 1, m)
  i = skip_wrappers(W, m, 1)
  if (i > m) return WRAP_SHELL ? shell_seg(W, m, i, hb, hk, depth, 1) : res_d("safe", "")
  for (j = i; j <= m; j++) if (WK[j] == "x") return res_d("write", "command substitution in: " joinw(W, i, m))
  if (out) return res_d("write", "output redirect: " joinw(W, i, m))
  c = lc(bname(W[i]))
  if (isin(c, NEUTRAL) || c == "[" || c == "[[") return res_d("safe", "")
  if (isin(c, "bash sh zsh dash ksh su")) return shell_seg(W, m, i, hb, hk, depth, 0)
  if (c == "eval") return walk(joinw(W, i + 1, m), "remote", "", "", depth + 1)
  if (isin(c, SAFE_CMD)) return res("safe", W, i, m)
  if (c == "find") {
    for (j = i + 1; j <= m; j++) if (W[j] ~ /^-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)$/) return res("write", W, i, m)
    return res("safe", W, i, m)
  }
  if (isin(c, CONTENT_CMD)) {
    for (j = i + 1; j <= m; j++) {
      if (c == "sed" && (W[j] ~ /^-[a-zA-Z]*i/ || W[j] ~ /^--in-place/)) return res("write", W, i, m)
      if (c ~ /awk$/ && W[j] ~ /system[ \t]*\(|print[^;}]*>|\| *getline|getline *</) return res("write", W, i, m)
      if (c == "sort" && (W[j] ~ /^-o/ || W[j] ~ /^--output/)) return res("write", W, i, m)
    }
    return res(prev == "|" ? "safe" : "content", W, i, m)
  }
  if (c == "git") return classify_git(W, i, m)
  if (c == "wp" || c ~ /^wp-cli(\.phar)?$/) return classify_wp(W, i + 1, m, hb, hk, i)
  if (c ~ /^php[0-9.]*(-cli)?$/) return classify_php(W, i, m, hb, hk)
  if (c == "artisan") return classify_first(W, i + 1, m, i, ARTISAN_SAFE, ARTISAN_CONTENT)
  if (c == "craft") return classify_first(W, i + 1, m, i, CRAFT_SAFE, "")
  if (c == "eecli.php") return classify_first(W, i + 1, m, i, EE_SAFE, "")
  if (c == "drush") return classify_first(W, i + 1, m, i, DRUSH_SAFE, DRUSH_CONTENT)
  if (c == "composer" || c == "composer.phar") return classify_composer(W, i, m)
  if (isin(c, "npm pnpm yarn bun")) {
    for (j = i + 1; j <= m; j++) if (W[j] == "fix" || W[j] == "--fix") return res("write", W, i, m)
    return classify_first(W, i + 1, m, i, NPM_SAFE, "")
  }
  if (isin(c, "node deno python python3 ruby perl java go rustc cargo nginx apache2 httpd mysql_config")) {
    for (j = i + 1; j <= m; j++) if (!isin(W[j], "-v -V --version version -t -T")) return res("write", W, i, m)
    return res("safe", W, i, m)
  }
  if (c == "systemctl") return classify_first(W, i + 1, m, i, "status is-active is-enabled is-failed list-units list-timers list-unit-files show cat", "")
  if (c == "service") return res((W[i + 2] == "status" || W[i + 1] == "--status-all") ? "safe" : "write", W, i, m)
  if (isin(c, "docker podman docker-compose")) return classify_docker(W, i, m, c)
  if (c == "curl" || c == "wget") return classify_http(W, i, m, c)
  if (isin(c, "mysql mariadb psql mongosh mongo redis-cli")) return classify_dbcli(W, i, m, prev, hb, hk)
  if (isin(c, "mysqldump mariadb-dump pg_dump pg_dumpall mongodump mongoexport")) return res("content", W, i, m)
  if (c == "crontab") { for (j = i + 1; j <= m; j++) if (W[j] == "-l") return res("content", W, i, m); return res("write", W, i, m) }
  if (c == "sanity" || c == "strapi") return classify_first(W, i + 1, m, i, JSCMS_SAFE, "")
  return res("write", W, i, m)
}
function shell_seg(W, m, i, hb, hk, depth, wrapped,   str) {
  if (!wrapped) {
    str = shell_string(W, i, m, lc(bname(W[i])) == "su")
    if (SHS_FOUND) return walk(str, "remote", hb, hk, depth + 1)
    if (SHS_SCRIPT) return res_d("opaque", "runs a script file the guard cannot inspect: " joinw(W, i, m))
  }
  if (hk == "heredoc" || hk == "herestring") return walk(hb, "remote", "", "", depth + 1)
  return res_d("opaque", "shell reading commands from " (hk == "file" ? "a file" : "an interactive session"))
}
# First positional argument (after options) looked up in a safe list, then a content list.
function classify_first(W, j, m, ci, safe, content,   a) {
  for (; j <= m; j++) {
    a = W[j]
    if (isin(a, "--version -V -v --help -h help")) return res("safe", W, ci, m)
    if (a ~ /^-/) continue
    a = lc(a)
    if (isin(a, safe)) return res("safe", W, ci, m)
    if (content != "" && isin(a, content)) return res("content", W, ci, m)
    return res("write", W, ci, m)
  }
  return res("safe", W, ci, m)
}
function classify_git(W, i, m,   j, s, a, k) {
  j = i + 1
  while (j <= m && W[j] ~ /^-/) { if (W[j] == "-C" || W[j] == "-c") j++; j++ }
  if (j > m) return res("safe", W, i, m)
  s = lc(W[j])
  if (isin(s, "status log show diff rev-parse describe ls-files ls-tree shortlog blame cat-file rev-list merge-base fetch whatchanged grep count-objects version help")) return res("safe", W, i, m)
  if (s == "branch") {
    for (k = j + 1; k <= m; k++) {
      a = W[k]
      if (isin(a, "-d -D -m -M -c -C -f -u --delete --move --copy --force --set-upstream-to --unset-upstream --edit-description")) return res("write", W, i, m)
      if (isin(a, "--contains --no-contains --merged --no-merged --points-at --sort --format")) { k++; continue }
      if (a !~ /^-/) return res("write", W, i, m)
    }
    return res("safe", W, i, m)
  }
  if (s == "tag") {
    if (j == m) return res("safe", W, i, m)
    for (k = j + 1; k <= m; k++) if (isin(W[k], "-d -a -s -f -m -F -u --delete --annotate --sign --force")) return res("write", W, i, m)
    for (k = j + 1; k <= m; k++) if (isin(W[k], "-l --list")) return res("safe", W, i, m)
    return res("write", W, i, m)
  }
  if (s == "stash" || s == "worktree") return res(isin(lc(W[j + 1]), "list show") ? "safe" : "write", W, i, m)
  if (s == "reflog") { for (k = j + 1; k <= m; k++) if (isin(W[k], "expire delete")) return res("write", W, i, m); return res("safe", W, i, m) }
  if (s == "remote") { if (j == m) return res("safe", W, i, m); return res(isin(W[j + 1], "-v --verbose show get-url") ? "content" : "write", W, i, m) }
  if (s == "config") { for (k = j + 1; k <= m; k++) if (W[k] ~ /^--(get|get-all|get-regexp|get-urlmatch|list|show-origin)$/ || W[k] == "-l") return res("content", W, i, m); return res("write", W, i, m) }
  return res("write", W, i, m)
}
function classify_wp(W, j, m, hb, hk, ci,   k, a, np, P, k2, k3, sql) {
  # P[1..3] start as "" — gawk 5.2 double-frees an unset element passed to a function.
  np = 0; split("", P); P[1] = ""; P[2] = ""; P[3] = ""; sql = ""
  for (k = j; k <= m; k++) {
    a = W[k]
    if (a ~ /^--(require|exec)/) return res("write", W, ci, m)
    if (a == "--help") return res("safe", W, ci, m)
    if (a ~ /^-/ || a ~ /^@/) continue
    np++; P[np] = lc(a)
    if (np == 3) sql = a
    if (np >= 3) break
  }
  if (np == 0 || P[1] == "help") return res("safe", W, ci, m)
  if (P[1] == "db" && P[2] == "query") {
    if (sql != "") return classify_sql(sql, W, ci, m)
    if (hk == "heredoc" || hk == "herestring") return classify_sql(hb, W, ci, m)
    return res_d("opaque", "wp db query reading SQL from " (hk == "file" ? "a file" : "stdin"))
  }
  if (isin(P[1], "eval eval-file shell")) return res("write", W, ci, m)
  if (isin(P[1], WP_WRITE) || isin(P[2], WP_WRITE) || isin(P[3], WP_WRITE)) return res("write", W, ci, m)
  k2 = P[1] " " P[2]; k3 = k2 " " P[3]
  if (index(WP_SAFE, "|" k3 "|") || index(WP_SAFE, "|" k2 "|")) return res("safe", W, ci, m)
  if (index(WP_CONTENT, "|" k3 "|") || index(WP_CONTENT, "|" k2 "|") || P[1] == "wc") return res("content", W, ci, m)
  return res("write", W, ci, m)
}
function classify_php(W, i, m, hb, hk,   j, a, b) {
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (isin(a, "-v --version -m --modules --ini -l --syntax-check")) return res("safe", W, i, m)
    if (a == "-i" || a == "--info") return res("content", W, i, m)
    if (a ~ /^-(r|a|B|R|E|F|S|t)/ || a ~ /^--(run|interactive|server)/) return res("write", W, i, m)
    if (a ~ /^-[dcz]$/) { j++; continue }
    if (a == "-f") { j++; break }
    if (a ~ /^-/) continue
    break
  }
  if (j > m) return res("write", W, i, m)
  b = lc(bname(W[j]))
  if (b ~ /^wp(-cli(\.phar)?)?$/) return classify_wp(W, j + 1, m, hb, hk, i)
  if (b == "artisan") return classify_first(W, j + 1, m, i, ARTISAN_SAFE, ARTISAN_CONTENT)
  if (b == "craft") return classify_first(W, j + 1, m, i, CRAFT_SAFE, "")
  if (b == "eecli.php") return classify_first(W, j + 1, m, i, EE_SAFE, "")
  if (b == "composer" || b == "composer.phar") return classify_composer(W, j, m)
  return res("write", W, i, m)
}
function classify_composer(W, i, m,   j, a, np) {
  np = 0
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (isin(a, "-V --version")) return res("safe", W, i, m)
    if (a ~ /^-/) continue
    a = lc(a)
    if (isin(a, "show info outdated validate diagnose licenses why depends why-not prohibits audit check-platform-reqs status fund search suggests list help")) return res("safe", W, i, m)
    if (a == "config") return res("content", W, i, m)
    return res("write", W, i, m)
  }
  return res("safe", W, i, m)
}
function classify_docker(W, i, m, c,   j, a, s) {
  s = ""
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (a ~ /^-/) continue
    a = lc(a)
    if (s == "" && a == "compose" && c != "docker-compose") { s = "compose"; continue }
    if (isin(a, "ps images version info top port ls stats")) return res("safe", W, i, m)
    if (isin(a, "logs inspect config")) return res("content", W, i, m)
    return res("write", W, i, m)
  }
  return res("safe", W, i, m)
}
function classify_http(W, i, m, c,   j, a, body, nx) {
  body = 1
  for (j = i + 1; j <= m; j++) {
    a = W[j]; nx = lc(W[j + 1])
    if (a ~ /^-(d|F|T)/ || a ~ /^--(data|form|upload-file|json|post-data|post-file|body-data|body-file|method)/) return res("write", W, i, m)
    if (a == "-X" || a == "--request") { if (!isin(nx, "get head")) return res("write", W, i, m); j++; continue }
    if (a ~ /^-X./) { if (!isin(lc(substr(a, 3)), "get head")) return res("write", W, i, m); continue }
    if (a == "--head" || a == "--spider" || (c == "curl" && a ~ /^-[a-zA-Z]*I[a-zA-Z]*$/)) body = 0
    if (a == "-o" || a == "--output" || a == "-O" || a == "--output-document") {
      if (nx == "/dev/null") body = 0; else if (!(c == "wget" && nx == "-")) return res("write", W, i, m)
      j++; continue
    }
    if (c == "curl" && (a == "--remote-name" || a ~ /^-[a-zA-Z]*O/ && a !~ /^--/)) return res("write", W, i, m)
  }
  if (c == "wget" && body) {
    for (j = i + 1; j <= m; j++) if (W[j] == "-O" && W[j + 1] == "-" || W[j] == "-qO-" || W[j] == "-O-") return res("content", W, i, m)
    return res("write", W, i, m)
  }
  return res(body ? "content" : "safe", W, i, m)
}
function classify_dbcli(W, i, m, prev, hb, hk,   c, j, a, q, found) {
  c = lc(bname(W[i])); q = ""; found = 0
  for (j = i + 1; j <= m; j++) {
    a = W[j]
    if (c == "psql") {
      if (a == "-c" || a == "--command") { q = q ";" W[j + 1]; found = 1; j++; continue }
      if (a ~ /^--command=/) { q = q ";" substr(a, 11); found = 1; continue }
      if (a == "-f" || a ~ /^--file/) return res_d("opaque", "psql running a SQL file")
    } else if (c == "mongosh" || c == "mongo") {
      if (a == "--eval") { return classify_mongo(W[j + 1], W, i, m) }
      if (a ~ /\.js$/) return res_d("opaque", c " running a script file")
    } else if (c == "redis-cli") {
      if (a ~ /^-[hpanu]$/ || a ~ /^--(user|pass|tls|cacert)$/) { j++; continue }
      if (a ~ /^-/ || a ~ /^redis/) continue
      a = lc(a)
      if (isin(a, "ping info dbsize ttl pttl type exists strlen llen scard zcard hlen memory latency slowlog client time lastsave role config")) return res(a == "config" ? "content" : "safe", W, i, m)
      if (isin(a, "get mget hget hgetall hmget lrange smembers zrange keys scan hscan sscan zscan getrange monitor")) return res("content", W, i, m)
      return res("write", W, i, m)
    } else {
      if (a == "-e" || a == "--execute") { q = q ";" W[j + 1]; found = 1; j++; continue }
      if (a ~ /^--execute=/) { q = q ";" substr(a, 11); found = 1; continue }
      if (a ~ /^-e./) { q = q ";" substr(a, 3); found = 1; continue }
    }
  }
  if (found) return classify_sql(q, W, i, m)
  if (c == "mongosh" || c == "mongo") {
    if (hk == "heredoc" || hk == "herestring") return classify_mongo(hb, W, i, m)
    return res_d("opaque", "interactive " c " session")
  }
  if (c == "redis-cli") return res_d("opaque", "interactive redis-cli session")
  if (hk == "heredoc" || hk == "herestring") return classify_sql(hb, W, i, m)
  if (hk == "file" || prev == "|") return res_d("opaque", c " reading SQL from a file or pipe")
  return res_d("opaque", "interactive " c " session")
}
function classify_sql(sql, W, i, m,   t, n, S, k, st, all) {
  t = lc(sql)
  gsub(Q1 "[^" Q1 "]*" Q1, "''", t); gsub(/"[^"]*"/, "\"\"", t)
  gsub(/\/\*[^*]*\*+([^\/*][^*]*\*+)*\//, " ", t); gsub(/--[^\n]*/, " ", t); gsub(/[\n\t\r]/, " ", t)
  if (t ~ SQL_WRITE) return res_d("write", "SQL: " sql)
  n = split(t, S, ";"); all = 1
  for (k = 1; k <= n; k++) {
    st = S[k]; sub(/^ +/, "", st); sub(/ +$/, "", st)
    if (st == "") continue
    if (st !~ SQL_SAFE) all = 0
  }
  return res_d(all ? "safe" : "content", "SQL: " sql)
}
function classify_mongo(js, W, i, m,   t) {
  t = lc(js)
  if (t ~ /(insert|update|delete|remove|replace|drop|create|rename|bulkwrite|findandmodify|findoneand|save|shutdown|grant|revoke|runcommand|eval|adminc)/) return res_d("write", "mongo: " js)
  if (t ~ /^[ ;]*((db\.)?[a-z0-9_.]*(count|countdocuments|estimateddocumentcount|stats|getcollectionnames|listcollections|version|serverstatus|hostinfo)\(\)?[^;]*[ ;]*)+$/ || t ~ /^[ ;]*show (dbs|collections|databases)[ ;]*$/) return res_d("safe", "mongo: " js)
  return res_d("content", "mongo: " js)
}

{ S = S (NR > 1 ? "\n" : "") $0 }
END {
  Q1 = sprintf("%c", 39)
  RANK["safe"] = 0; RANK["content"] = 1; RANK["write"] = 2; RANK["opaque"] = 3
  DRANK["none"] = 0; DRANK["ask"] = 1; DRANK["deny"] = 2
  NEUTRAL = "cd pushd popd true false exit : sleep echo printf test umask wait shopt set export unset alias local readonly return"
  SAFE_CMD = "ls ll pwd whoami id groups hostname uptime date df du free uname which type whereis stat file wc readlink realpath basename dirname nproc lscpu lsb_release md5sum sha1sum sha224sum sha256sum sha384sum sha512sum shasum b2sum cksum tty locale getconf"
  CONTENT_CMD = "cat head tail less more grep egrep fgrep zgrep zcat bzcat xzcat rg ag ack awk gawk mawk sed cut sort uniq strings xxd od hexdump tac nl jq yq diff cmp base64 column fold fmt tr paste join comm journalctl dmesg last lastlog who w ps pgrep top htop lsof netstat ss history"
  WP_WRITE = "add update delete set create remove patch reset flush activate deactivate install uninstall toggle run import export generate regenerate clean optimize repair replace search-replace migrate push pull rename edit save enable disable dismiss destroy spam unspam trash untrash approve unapprove recount assign revoke grant upgrade update-db convert empty duplicate move scaffold truncate prune reset-password"
  WP_SAFE = "|core version|core is-installed|core verify-checksums|core check-update|plugin list|plugin status|plugin is-active|plugin is-installed|plugin path|plugin get|plugin verify-checksums|plugin search|theme list|theme status|theme is-active|theme is-installed|theme path|theme get|theme search|cli version|cli info|cli check-update|cli alias list|cli has-command|cron event list|cron schedule list|cron test|site list|rewrite list|language core list|language core is-installed|language plugin list|language plugin is-installed|language theme list|role list|role exists|cap list|sidebar list|widget list|menu list|menu location list|post-type list|post-type get|taxonomy list|taxonomy get|maintenance-mode status|maintenance-mode is-active|db size|db tables|db check|db prefix|db columns|cache type|package list|package path|super-admin list|config path|config has|config is-true|"
  WP_CONTENT = "|option get|option list|option pluck|config get|config list|user list|user get|user meta|user session list|user list-caps|post list|post get|post meta|post term list|term list|term get|term meta|comment list|comment get|comment meta|transient get|transient list|db search|site option|network meta|menu item list|cache get|user application-password list|"
  ARTISAN_SAFE = "list about help env route:list migrate:status schedule:list event:list"
  ARTISAN_CONTENT = "config:show model:show"
  CRAFT_SAFE = "help migrate/history project-config/diff queue/info plugin/list update/info"
  EE_SAFE = "list help"
  DRUSH_SAFE = "status st core:status version updatedb:status updbst pm:list pml watchdog:list"
  DRUSH_CONTENT = "config:get cget sql:query sqlq php:eval ev state:get"
  NPM_SAFE = "ls list ll outdated view info why explain doctor audit version"
  JSCMS_SAFE = "versions version help debug projects dataset documents"
  SQL_WRITE = "(^|[^a-z0-9_])(insert|update|delete|drop|alter|truncate|create|grant|revoke|merge|replace[ ]+into|rename|call|load|handler|lock|flush|kill|optimize|repair|purge|reset|shutdown|install|uninstall|prepare|execute|do|set[ ]+(global|persist|password|session)|into[ ]+(outfile|dumpfile)|copy)([^a-z0-9_]|$)"
  SQL_SAFE = "^(show|describe|desc|explain|use|select[ ]+(count[ ]*\\(|database[ ]*\\([ ]*\\)|version[ ]*\\([ ]*\\)|@@|now[ ]*\\(|current_user|user[ ]*\\(|connection_id|1$|1[ ]))"
  NM = 0
  nr = split(ENVIRON["RG_MARKERS"], R, "\n")
  for (k = 1; k <= nr; k++) { if (R[k] == "") continue; p = index(R[k], "\t"); NM++; MC[NM] = substr(R[k], 1, p - 1); MV[NM] = substr(R[k], p + 1) }
  for (a = 1; a <= NM; a++) for (b = a + 1; b <= NM; b++) if (length(MV[b]) > length(MV[a])) { t = MV[a]; MV[a] = MV[b]; MV[b] = t; t = MC[a]; MC[a] = MC[b]; MC[b] = t }
  BEST = "none"; NSSH = 0; NSUBS = 0
  gsub(/\r/, "", S)
  walk(S, "local", "", "", 0)
  printf "%s\037%s\037%s\037%s\037%s\037%s\037%d\n", BEST, B_WHAT, B_TGT, B_MK, B_CLS, clip(B_DET), NSSH
}
AWK

SSH_CLEARED=false
if m '(^|[^a-z0-9_.-])(ssh|scp|rsync|wp|mysql|mariadb|psql|mongosh|mongo|redis-cli)([[:space:]]|$)|(mongodb|redis|rediss|postgres|postgresql|mysql|mariadb|mssql|sqlserver)(\+srv)?://'; then
  IFS=$'\037' read -r r_dec r_what r_tgt r_mark r_cls r_det r_nssh <<< \
    "$(printf '%s' "$cmd" | RG_MARKERS="$REMOTE_MARKERS" LC_ALL=C awk "$REMOTE_AWK" 2>/dev/null)"
  case "${r_tgt:-}" in
    production) r_where="production (it names '${r_mark}')" ;;
    staging) r_where="staging (it names '${r_mark}')" ;;
    *) if [[ "$REMOTE_POLICY" == true ]]; then
         r_where="a remote environment that matches no staging or production target in ai-config.conf [remote]"
       else
         r_where="a remote environment"
       fi ;;
  esac
  case "${r_dec:-}" in
    deny)
      if [[ "$r_cls" == opaque ]]; then
        decide deny "Blocked by ai-config safety guard: this ${r_what} command would run commands on production that the guard cannot inspect (${r_det}); it names '${r_mark}'. Pass read-only commands inline so they can be checked. Changes to production are for the developer to run."
      fi
      decide deny "Blocked by ai-config safety guard: this ${r_what} command changes production (${r_det}); it names '${r_mark}'. Changes to production are made by the developer, not by Claude: give them the exact command and let them run it (in Claude Code they can prefix it with !). Read-only checks against production are still allowed."
      ;;
    ask)
      case "$r_cls" in
        content)
          decide ask "This ${r_what} command returns file contents, configuration, logs or database rows from ${r_where} (${r_det}). That output reaches the transcript unscanned and can hold secrets or personal data. Prefer counts and hashes (wc -l, SELECT COUNT(*), sha256sum); approve only if the full output is needed." ;;
        opaque)
          decide ask "This ${r_what} command runs commands on ${r_where} that the guard cannot inspect (${r_det}). ${PROD}" ;;
        *)
          if [[ "$r_tgt" == staging && "$REMOTE_ASSERT_DB" == true ]] \
            && ! m 'select[[:space:]]+database[[:space:]]*\([[:space:]]*\)'; then
            decide deny "Blocked by ai-config safety guard: this ${r_what} command changes ${r_where} (${r_det}) without proving the database first. This project sets assert-database in ai-config.conf [remote]: run SELECT DATABASE() in the same command, before the write, and check it names the staging database."
          fi
          if [[ "$r_tgt" == staging ]]; then
            decide ask "This ${r_what} command changes ${r_where} (${r_det}). Staging and production can share a server and database host: confirm the path, and prove the database (SELECT DATABASE()) before any write."
          elif [[ "$REMOTE_POLICY" == true ]]; then
            decide ask "This ${r_what} command may change ${r_where} (${r_det}). Confirm which environment it reaches before approving."
          fi
          decide ask "This ${r_what} command may change ${r_where} (${r_det}). ${PROD} To block production changes outright, declare this project's production paths, hosts and database names under [remote] in ai-config.conf." ;;
      esac
      ;;
    none)
      # Every ssh the parser found is read-only. Clear the blanket ssh ask only if it saw
      # every ssh in the command — anything it missed keeps the prompt.
      _nssh_seen="$(printf '%s' "$lc" | grep -oE '(^|[^a-z0-9_.-])ssh([[:space:]]|$)' | wc -l | tr -d '[:space:]')"
      [[ "${r_nssh:-0}" -ge "${_nssh_seen:-1}" ]] && SSH_CLEARED=true
      ;;
  esac
fi

# --- Credential-shaped strings in the command (heredocs, echo/tee, curl) ------
# Same patterns as file writes. Runs after the secret-file and catastrophic checks, so those
# decisions keep precedence. grep -c reads all input (no SIGPIPE on long commands).
hits="$(printf '%s' "$cmd" | LC_ALL=C grep -Ec -e "$SECRET_CONTENT_RE")"
if [[ "${hits:-0}" != 0 ]]; then
  decide ask "This command contains what looks like a real credential (private key or API token). Safety Guardrail #1: never put secrets into code, files, or command lines — read the value from an environment variable kept in the untracked .env. Approve only if this is a placeholder or test fixture."
fi

# --- Ask: each rule is "regex<TAB>reason" ------------------------------------
ask_rules=(
  "${S}${G}push([[:space:]]|$)	git push — ${PUBLISH}"
  "${S}gh[[:space:]]+(pr[[:space:]]+merge|release[[:space:]]+(create|upload|delete|edit)|repo[[:space:]]+(create|delete|edit|rename|archive|fork)|issue[[:space:]]+delete|workflow[[:space:]]+run|run[[:space:]]+(rerun|cancel)|secret|variable)([[:space:]]|$)	GitHub write via gh — ${PUBLISH}"
  "${S}gh[[:space:]]+api[[:space:]].*(-x|--method)[[:space:]]*(post|put|patch|delete)	GitHub API write — ${PUBLISH}"
  "${S}(npm|pnpm|yarn|bun)[[:space:]]+publish|${S}(twine[[:space:]]+upload|gem[[:space:]]+push|cargo[[:space:]]+publish|docker[[:space:]]+push)	package/image publish — ${PUBLISH}"
  "${S}${R}vercel(@[^[:space:]]*)?([[:space:]].*)?[[:space:]](--prod|--production|deploy|promote|rollback|redeploy|alias|domains|dns|remove|rm)([[:space:]]|$)|${S}${R}vercel(@[^[:space:]]*)?[[:space:]]*($|[;&|])|${S}${R}vercel(@[^[:space:]]*)?[[:space:]]+env[[:space:]]+(add|rm|remove)	Vercel deploy/config — ${PROD}"
  "${S}${R}netlify(-cli)?(@[^[:space:]]*)?[[:space:]]+(deploy|env:set|env:unset|env:import|sites:delete|link)	Netlify deploy/config — ${PROD}"
  "${S}(${R}wrangler(@[^[:space:]]*)?|${CF_HELPER})[[:space:]]+(deploy|publish|delete|rollback|secret|versions[[:space:]]+deploy|d1[[:space:]]+.*--remote|kv[[:space:]].*(put|delete)|r2[[:space:]].*(put|delete))	Cloudflare deploy/data — ${PROD}"
  "${S}[^[:space:]]*cloudflare\.sh[[:space:]]+(delete|prune([[:space:]].*)?[[:space:]]--delete|passcode)([[:space:]]|$)	Cloudflare page delete or passcode change — ${PROD}"
  "${S}(firebase[[:space:]]+deploy|flyctl?[[:space:]]+(deploy|secrets|destroy|scale)|heroku[[:space:]]|railway[[:space:]]+(up|variables)|dep[[:space:]]+deploy|cap[[:space:]]+production|envoy[[:space:]]+run|forge[[:space:]]+deploy|ansible-playbook)	deploy — ${PROD}"
  "${S}(terraform|tofu)[[:space:]]+(apply|destroy|import|taint|state[[:space:]]+(rm|mv|push))|${S}pulumi[[:space:]]+(up|destroy|refresh)|${S}kubectl[[:space:]]+(apply|create|delete|edit|patch|replace|scale|rollout|set|drain|cordon|exec)|${S}helm[[:space:]]+(install|upgrade|uninstall|rollback|delete)	infrastructure change — ${PROD}"
  "${S}(aws|gcloud|gsutil|az|doctl|linode-cli|hcloud)[[:space:]]	cloud provider CLI — ${PROD}"
  "${S}ssh[[:space:]]	SSH"
  "${S}(sftp|ftp|lftp|mosh)[[:space:]]	remote shell/transfer — ${PROD}"
  "(^|[^a-z0-9_])(app_env|node_env|wp_env|craft_environment|craft_env|rails_env|django_settings_module|environment|env)=[\"']?prod(uction)?([^a-z]|$)|--env(ironment)?[= ][\"']?prod(uction)?([^a-z]|$)|--(prod|production)([[:space:]]|$)|\.env\.prod(uction)?([^a-z]|$)	targets a production environment — ${PROD}"
  "${S}(npx[[:space:]]+)?(sanity[[:space:]]+(dataset[[:space:]]+(import|delete|copy|alias|create|visibility)|documents[[:space:]]+(delete|create)|graphql[[:space:]]+(deploy|undeploy)|deploy|undeploy|cors[[:space:]]+(add|delete)|hook[[:space:]]+(create|delete)|migration[[:space:]]+run)|strapi[[:space:]]+(transfer|import|admin:reset-user-password|configuration:restore))	headless CMS data/deploy change — ${PROD}"
  "${S}(scp|rsync)[[:space:]].*[a-z0-9_.-]+@?[a-z0-9_.-]*:[^[:space:]]*	remote copy — ${PROD}"
  "${S}ddev[[:space:]]+(push|pull|delete|import-db|import-files|snapshot[[:space:]]+restore)([[:space:]]|$)	DDEV database/hosting sync — ${PROD}"
  "(drop[[:space:]]+(database|schema|table)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_\`\"]|delete[[:space:]]+from[[:space:]]+[a-z_\`\".]+[[:space:]]*($|[;\"'])|alter[[:space:]]+table[[:space:]].*[[:space:]]drop[[:space:]])	destructive SQL — ${DESTRUCTIVE} ${PROD}"
  "${S}${G}(reset[[:space:]]+(.*[[:space:]])?--hard|clean[[:space:]]+(.*[[:space:]])?-[a-z]*f|checkout[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)|restore[[:space:]]+(.*[[:space:]])?\.([[:space:]]|$)|branch[[:space:]]+(.*[[:space:]])?(-d|--delete)|stash[[:space:]]+(drop|clear)|filter-branch|filter-repo|update-ref[[:space:]]+-d|reflog[[:space:]]+expire)	destructive git operation — ${DESTRUCTIVE}"
  "(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)	piping a remote script into a shell — confirm the source is trusted."
  "${S}(printenv|env|set|export[[:space:]]+-p|declare[[:space:]]+-x)[[:space:]]*($|[;&|>])	dumps environment variables, which may include secrets (Safety Guardrail #1)."
  "(\.claude/(settings[a-z.]*\.json|hooks/)|ai-config\.conf)[^;&|]*|(>|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|tee|jq[^;&|]*>)[^;&|]*(\.claude/(settings[a-z.]*\.json|hooks/)|ai-config\.conf)	HARNESS"
)

# PRs and issues change GitHub but deploy nothing. They ask too, unless the session's
# settings set AI_CONFIG_GH_LIGHT_WRITES=allow: the CPS dev containers do, in root-owned
# managed settings, so a command inside can't switch it on. Merges, releases and workflow
# runs (the deploying writes) always ask.
if [[ "${AI_CONFIG_GH_LIGHT_WRITES:-}" != allow ]]; then
  ask_rules+=("${S}gh[[:space:]]+(pr[[:space:]]+(create|close|reopen|edit|comment|review|ready)|issue[[:space:]]+(create|close|comment|edit))([[:space:]]|$)	GitHub write via gh — ${PUBLISH}")
fi

for rule in "${ask_rules[@]}"; do
  re="${rule%%	*}"
  reason="${rule#*	}"
  if m "$re"; then
    if [[ "$reason" == "SSH" ]]; then
      [[ "$SSH_CLEARED" == true ]] && continue
      reason="remote shell — ${PROD}"
    fi
    if [[ "$reason" == "HARNESS" ]]; then
      m '(>|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|(^|[[:space:];&|])(rm|mv|cp|tee|chmod|ln)[[:space:]]|jq[^;&|]*>)' || continue
      reason="This modifies safety configuration (.claude/settings, .claude/hooks, or ai-config.conf). Confirm the change is intended."
    fi
    decide ask "$reason"
  fi
done

exit 0
