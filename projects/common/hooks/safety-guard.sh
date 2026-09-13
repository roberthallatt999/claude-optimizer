#!/usr/bin/env bash
#
# safety-guard.sh — Claude Code PreToolUse hook (deployed by ai-config)
#
# Enforces the Operational Safety Guardrails from CLAUDE.md at the harness level,
# so they hold even when an allow rule would auto-approve a command:
#   - Secrets     → deny reading .env / keys / credentials (Bash and file tools);
#                   ask before writing credential-shaped strings into files or commands
#   - Publishing  → ask before git push, PR/release changes, package publishing
#   - Production  → ask before deploys, remote shells, cloud/infra CLIs, DB drops
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
    wp-config.php|wp-config-local.php|wp-salt.php|config.local.php|database.yml|database.yaml) return 0 ;;
  esac
  case "$p" in
    .ssh/*|*/.ssh/*|.aws/*|*/.aws/credentials|*/.aws/config|.azure/*|*/.azure/*) return 0 ;;
    *system/user/config/config.php|*.ddev/db_snapshots/*|*.ddev/import-db/*) return 0 ;;
  esac
  return 1
}

SECRET_REASON="may contain secrets (Safety Guardrail #1: never read secrets). Ask the developer for the specific non-secret value you need, or use the .env.example template."
PUBLISH="Safety Guardrail #2: publishing needs the developer's explicit approval for this specific action."
PROD="Safety Guardrail #3: this may change a production or remote environment; confirm the target and get explicit approval."
DESTRUCTIVE="This is irreversible; confirm it is intended."

# High-confidence credential shapes — keep in sync with projects/common/okf/okf-check.sh.
SECRET_CONTENT_RE='-----BEGIN [A-Z ]*PRIVATE KEY-----|(AKIA|ASIA)[0-9A-Z]{16}|sk-(ant|proj)-[A-Za-z0-9_-]{20,}|sk_live_[0-9A-Za-z]{16,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}'

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
        esac
      fi
    done

    # --- Credential-shaped strings in the text being written -----------------
    case "$tool" in
      Write) content_key=.tool_input.content ;;
      Edit) content_key=.tool_input.new_string ;;
      MultiEdit) content_key='.tool_input.edits[].new_string' ;;
      NotebookEdit) content_key=.tool_input.new_source ;;
      *) exit 0 ;;
    esac
    # grep -c reads all input, so json_field can never die of SIGPIPE mid-write.
    hits="$(json_field "$content_key" | LC_ALL=C grep -Ec -e "$SECRET_CONTENT_RE")"
    if [[ "${hits:-0}" != 0 ]]; then
      decide ask "The text being written to '${target##*/}' looks like a real credential (private key or API token). Safety Guardrail #1: never write secrets into code — read the value from an environment variable (e.g. process.env.NAME, getenv('NAME')) kept in the untracked .env. Approve only if this is a placeholder or test fixture."
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
    secret="$tok"
    break
  fi
done <<EOF
$(printf '%s' "$lc" | tr -c 'a-z0-9._/~*@+:%-' '\n')
EOF

if [[ -n "$secret" ]]; then
  READ_VERBS="${S}(cat|less|more|head|tail|bat|batcat|nl|tac|strings|xxd|od|hexdump|base64|source|\.|grep|egrep|fgrep|rg|ag|ack|awk|gawk|sed|cut|sort|uniq|diff|cmp|jq|yq|cp|scp|rsync|curl|wget|nc|ncat|openssl|gpg|vi|vim|nvim|nano|emacs|code|open|pbcopy|xclip|python|python3|node|deno|php|ruby|perl|export|dotenv|tee|zip|tar|echo|printf|eval|read)([[:space:]]|$)"
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

# --- Catastrophic / irreversible: deny ---------------------------------------
RM_TARGET='["'"'"']?(/|/\*|~|~/|~/\*|\$home|\$\{home\}|\$home/|\$home/\*|\*|\.|\./|\.\.|\.\./)["'"'"']?([[:space:]]|$|[;&|])'
if m "${S}rm([[:space:]]+-[a-z-]+)*[[:space:]]+-[a-z-]*r[a-z-]*([[:space:]]+-[a-z-]+)*[[:space:]]+${RM_TARGET}"; then
  decide deny "Blocked by ai-config safety guard: recursive delete of a root, home, or whole-project path. Ask the developer to run it themselves if truly intended."
fi
if m "${S}(mkfs(\.[a-z0-9]+)?|fdisk|diskutil[[:space:]]+(erase|zero|partition))([[:space:]]|$)" || m "${S}dd[[:space:]].*of=/dev/" || m ':\(\)[[:space:]]*\{[[:space:]]*:\|:&'; then
  decide deny "Blocked by ai-config safety guard: disk-level destructive command."
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
  "${S}(ssh|sftp|ftp|lftp|mosh)[[:space:]]	remote shell/transfer — ${PROD}"
  "${S}(scp|rsync)[[:space:]].*[a-z0-9_.-]+@?[a-z0-9_.-]*:[^[:space:]]*	remote copy — ${PROD}"
  "${S}ddev[[:space:]]+(push|pull|delete|import-db|import-files|snapshot[[:space:]]+restore)([[:space:]]|$)	DDEV database/hosting sync — ${PROD}"
  "(drop[[:space:]]+(database|schema|table)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_\`\"]|delete[[:space:]]+from[[:space:]]+[a-z_\`\".]+[[:space:]]*($|[;\"'])|alter[[:space:]]+table[[:space:]].*[[:space:]]drop[[:space:]])	destructive SQL — ${DESTRUCTIVE} ${PROD}"
  "${S}${G}(reset[[:space:]]+(.*[[:space:]])?--hard|clean[[:space:]]+(.*[[:space:]])?-[a-z]*f|checkout[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)|restore[[:space:]]+(.*[[:space:]])?\.([[:space:]]|$)|branch[[:space:]]+(.*[[:space:]])?(-d|--delete)|stash[[:space:]]+(drop|clear)|filter-branch|filter-repo|update-ref[[:space:]]+-d|reflog[[:space:]]+expire)	destructive git operation — ${DESTRUCTIVE}"
  "(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)	piping a remote script into a shell — confirm the source is trusted."
  "${S}(printenv|env|set|export[[:space:]]+-p|declare[[:space:]]+-x)[[:space:]]*($|[;&|>])	dumps environment variables, which may include secrets (Safety Guardrail #1)."
  "\.claude/(settings[a-z.]*\.json|hooks/)[^;&|]*|(>|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|tee|jq[^;&|]*>)[^;&|]*\.claude/(settings[a-z.]*\.json|hooks/)	HARNESS"
)

for rule in "${ask_rules[@]}"; do
  re="${rule%%	*}"
  reason="${rule#*	}"
  if m "$re"; then
    if [[ "$reason" == "HARNESS" ]]; then
      m '(>|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|(^|[[:space:];&|])(rm|mv|cp|tee|chmod|ln)[[:space:]]|jq[^;&|]*>)' || continue
      reason="This modifies Claude Code safety configuration (.claude/settings or .claude/hooks). Confirm the change is intended."
    fi
    decide ask "$reason"
  fi
done

exit 0
