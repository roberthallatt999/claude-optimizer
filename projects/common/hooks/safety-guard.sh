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

input="$(cat)"

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

decide() {
  local reason="$2"
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
  break
done

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
    *system/user/config/config.php|*.ddev/db_snapshots/*|*.ddev/import-db/*) return 0 ;;
  esac
  matches_protected "$p"
}

SECRET_REASON="may contain secrets (Safety Guardrail #1: never read secrets). Ask the developer for the specific non-secret value you need, or use the .env.example template."
PUBLISH="Safety Guardrail #2: publishing needs the developer's explicit approval for this specific action."
PROD="Safety Guardrail #3: this may change a production or remote environment; confirm the target and get explicit approval."
DESTRUCTIVE="This is irreversible; confirm it is intended."

# High-confidence credential shapes — keep in sync with projects/common/okf/okf-check.sh.
# Vendor token shapes. Case-sensitive: the casing IS part of the signal.
SECRET_CONTENT_RE='-----BEGIN [A-Z ]*PRIVATE KEY-----|(AKIA|ASIA)[0-9A-Z]{16}|sk-(ant|proj)-[A-Za-z0-9_-]{20,}|sk_live_[0-9A-Za-z]{16,}|rk_live_[0-9A-Za-z]{16,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|npm_[A-Za-z0-9]{36}|dop_v1_[a-f0-9]{64}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}'

# Database and service credentials, matched case-insensitively: a connection URI with an
# inline password, or a secret-ish key assigned a concrete value. This is what catches a
# server log whose stack trace prints the DSN.
SECRET_ASSIGN_RE='(mysql|mariadb|postgres|postgresql|mongodb\+srv|mongodb|redis|rediss|amqp|amqps|mssql|sqlserver|ftp|https?)://[^:/@[:space:]"]+:[^@[:space:]"]{3,}@|(db_password|db_pass|db_pwd|mysql_pwd|mysql_password|mysql_root_password|postgres_password|pgpassword|database_password|redis_password|mail_password|smtp_password|aws_secret_access_key|secret_access_key|api_key|api_secret|apikey|secret_key|access_token|auth_token|bearer_token|client_secret|encryption_key|app_key)[[:space:]]*[=:][[:space:]]*"?[^[:space:]",;&]{8,}'

# Lines the guard forgives. Without these the guard blocks .env.example, docs and any
# code that reads a value from the environment — and a guard nobody can live with gets
# switched off, which is worse than a narrower one that stays on.
# Deliberately NOT here: "xxxx", "todo", "fixme". A real vendor token can contain a run of
# x's (sk-ant-api03-xxxx…) and a line can say TODO next to a live key; template files are
# already skipped by extension in secret_scan, so those markers bought nothing and cost a hole.
SECRET_PLACEHOLDER_RE='example|sample|placeholder|dummy|changeme|change[-_]me|your[-_]|redacted|replace_|\*\*\*|\.\.\.|<[^>]*>|\$\{|%[A-Za-z_]+%|process\.env|getenv|os\.environ|env\(|:(pass|password|passwd|pwd|secret|user|username|admin|root|test|demo|foo|bar)@|test[-_]?(key|token|secret|password)|fake[-_]?(key|token|secret)'

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
SECRET_ANCHORS_RE='akia|asia|sk-ant-|sk-proj-|sk_live_|rk_live_|gh[pousr]_|github_pat_|glpat-|xox|aiza|sg\.|npm_|dop_v1_|eyj|-----begin|mysql://|mariadb://|postgres|mongodb|rediss?://|amqp|mssql://|sqlserver://|ftp://|https?://|password|passwd|_pwd|secret|token|api_?key|app_key|access_key|encryption_key'

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
      decide ask "MCP tool ${tool} performs an outward or destructive action (${verb}) — ${why}"
    fi

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
G='git([[:space:]]+(-c|--git-dir|--work-tree)[[:space:]]+[^[:space:]]+|[[:space:]]+--?[a-z][a-z-]*(=[^[:space:]]+)?)*[[:space:]]+'

# --- Secrets referenced from the shell --------------------------------------
secret=""
while IFS= read -r tok; do
  [[ -n "$tok" ]] || continue
  if is_secret_path "$tok"; then
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
    secret="$tok"
    break
  fi
done <<EOF
$(printf '%s' "$lc" | tr -c 'a-z0-9._/~*@+:%-' '\n')
EOF

READ_VERBS="${S}(cat|less|more|head|tail|bat|batcat|nl|tac|strings|xxd|od|hexdump|base64|source|\.|grep|egrep|fgrep|rg|ag|ack|awk|gawk|sed|cut|sort|uniq|diff|cmp|jq|yq|cp|scp|rsync|curl|wget|nc|ncat|openssl|gpg|vi|vim|nvim|nano|emacs|code|open|pbcopy|xclip|python|python3|node|deno|php|ruby|perl|export|dotenv|tee|zip|tar|echo|printf|eval|read)([[:space:]]|$)"

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
  scanned=0
  while IFS= read -r tok; do
    [[ -n "$tok" && -f "$tok" ]] || continue
    scan_msg="$(secret_scan "$tok")"
    case $? in
      0) decide deny "Blocked by ai-config safety guard: '${tok}' contains ${scan_msg}. $SCAN_TAIL" ;;
      2) decide deny "Blocked by ai-config safety guard: '${tok}' ${scan_msg}. $SCAN_BIG_TAIL" ;;
    esac
    scanned=$((scanned + 1))
    [[ $scanned -ge 5 ]] && break
  done <<EOF
$(printf '%s' "$cmd" | tr -c 'A-Za-z0-9._/~*@+:%-' '\n')
EOF
fi

# --- Catastrophic / irreversible: deny ---------------------------------------
RM_TARGET='["'"'"']?(/|/\*|~|~/|~/\*|\$home|\$\{home\}|\$home/|\$home/\*|\*|\.|\./|\.\.|\.\./)["'"'"']?([[:space:]]|$|[;&|])'
if m "${S}rm([[:space:]]+-[a-z-]+)*[[:space:]]+-[a-z-]*r[a-z-]*([[:space:]]+-[a-z-]+)*[[:space:]]+${RM_TARGET}"; then
  decide deny "Blocked by ai-config safety guard: recursive delete of a root, home, or whole-project path. Ask the developer to run it themselves if truly intended."
fi
if m "${S}(mkfs(\.[a-z0-9]+)?|fdisk|diskutil[[:space:]]+(erase|zero|partition))([[:space:]]|$)" || m "${S}dd[[:space:]].*of=/dev/" || m ':\(\)[[:space:]]*\{[[:space:]]*:\|:&'; then
  decide deny "Blocked by ai-config safety guard: disk-level destructive command."
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
  "${S}gh[[:space:]]+(pr[[:space:]]+(create|merge|close|reopen|edit|comment|review|ready)|release[[:space:]]+(create|upload|delete|edit)|repo[[:space:]]+(create|delete|edit|rename|archive|fork)|issue[[:space:]]+(create|close|comment|edit|delete)|workflow[[:space:]]+run|run[[:space:]]+(rerun|cancel)|secret|variable)([[:space:]]|$)	GitHub write via gh — ${PUBLISH}"
  "${S}gh[[:space:]]+api[[:space:]].*(-x|--method)[[:space:]]*(post|put|patch|delete)	GitHub API write — ${PUBLISH}"
  "${S}(npm|pnpm|yarn|bun)[[:space:]]+publish|${S}(twine[[:space:]]+upload|gem[[:space:]]+push|cargo[[:space:]]+publish|docker[[:space:]]+push)	package/image publish — ${PUBLISH}"
  "${S}vercel([[:space:]].*)?[[:space:]](--prod|--production|deploy|promote|rollback|redeploy|alias|domains|dns|remove|rm)([[:space:]]|$)|${S}vercel[[:space:]]*($|[;&|])|${S}vercel[[:space:]]+env[[:space:]]+(add|rm|remove)	Vercel deploy/config — ${PROD}"
  "${S}netlify[[:space:]]+(deploy|env:set|env:unset|env:import|sites:delete|link)	Netlify deploy/config — ${PROD}"
  "${S}(wrangler|npx[[:space:]]+wrangler)[[:space:]]+(deploy|publish|delete|rollback|secret|versions[[:space:]]+deploy|d1[[:space:]]+.*--remote|kv[[:space:]].*(put|delete)|r2[[:space:]].*(put|delete))	Cloudflare deploy/data — ${PROD}"
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
