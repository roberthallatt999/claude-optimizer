#!/usr/bin/env bash
# test-leak-guards.sh — the guard's leak checks added on 2026-11-11: recursive searches,
# commands that print secrets, local personal-data queries, MCP content and reads, commits
# (and the --pre-commit mode), PHP/JSON-array passwords, .gitignore creation, the git
# pre-commit hook, and the global guard installer.
#
# Usage: ./test-leak-guards.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/projects/common/hooks/safety-guard.sh"
SETUP="$SCRIPT_DIR/setup-project.sh"
GLOBAL="$SCRIPT_DIR/scripts/install-global-guard.sh"
export AI_CONFIG_SKIP_GLOBAL_SKILLS=1 AI_CONFIG_USER_SETTINGS=/nonexistent
PASS=0
FAIL=0
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TMPS=()
tmp_dir() { local d; d="$(mktemp -d)"; TMPS+=("$d"); echo "$d"; }
cleanup_all() { local d; for d in "${TMPS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

check() {   # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then echo -e "${GREEN}PASS${NC} $1"; PASS=$((PASS + 1))
  else echo -e "${RED}FAIL${NC} $1 (expected $2, got $3)"; FAIL=$((FAIL + 1)); fi
}

# A project with fake secrets. Values are assembled so this file holds no credential shapes.
P=$(tmp_dir)
git -C "$P" init -q
mkdir -p "$P/app" "$P/storage/logs" "$P/config" "$P/.claude/hooks"
printf 'DB_%s=%s\n' PASSWORD 'Tr0ub4dor-real-pass-99' > "$P/.env"
printf '[2026-11-11] mysql://cps:%s@db.internal/live failed\n' 'S3cretPassw0rd42' > "$P/storage/logs/laravel.log"
printf "<?php return ['%s' => '%s'];\n" password 'hunter2-longer-secret-77' > "$P/config/database.php"
printf 'INSERT INTO members VALUES (1,"Jane Doe","jane@example.org");\n' > "$P/backup-2026.sql"
printf 'function hello() { return 1; }\n// TODO later\n' > "$P/app/clean.php"
printf '*.sql\n' > "$P/.claude/hooks/protected-paths.conf"
printf '.env\n.env.*\ncredentials*\n' >> "$P/.claude/hooks/protected-paths.conf"

decision() {   # <tool> <tool_input json> → deny | ask | allow
  local out
  out="$(jq -n --arg t "$1" --argjson i "$2" --arg w "$P" '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$w,tool_input:$i}' \
        | (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$GUARD") 2>/dev/null)"
  printf '%s' "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<< "$out" 2>/dev/null)" | grep . || echo allow
}
bash_d() { decision Bash "$(jq -n --arg c "$1" '{command:$c}')"; }

# --- Recursive searches: denied only when a secret line would print ---------
check "grep -r DB_PASSWORD . (matches .env)"            deny  "$(bash_d 'grep -r DB_PASSWORD .')"
check "grep -rn with --include='*.php'"                 allow "$(bash_d "grep -rn DB_PASS --include='*.php' .")"
check "grep -r --exclude='.env*'"                       allow "$(bash_d "grep -r --exclude='.env*' DB_PASSWORD .")"
check "grep -rn TODO . (no secret line matches)"        allow "$(bash_d 'grep -rn TODO .')"
check "cd app && grep -r DB_PASSWORD .."                deny  "$(bash_d 'cd app && grep -r DB_PASSWORD ..')"
check "grep -R -i db_password (case-insensitive)"       deny  "$(bash_d 'grep -R -i db_password .')"
check "grep -rF with -e pattern"                        deny  "$(bash_d 'grep -rF -e Tr0ub4dor .')"
check "rg DB_PASSWORD (rg skips hidden files)"          allow "$(bash_d 'rg DB_PASSWORD')"
check "rg -uu DB_PASSWORD"                              deny  "$(bash_d 'rg -uu DB_PASSWORD')"
check "rg -i 'jane doe' (matches the dump)"             deny  "$(bash_d "rg -i 'jane doe'")"
check "rg -g '!*.sql' -i 'jane doe'"                    allow "$(bash_d "rg -g '!*.sql' -i 'jane doe'")"
check "--exclude-dir naming a folder ABOVE the root"    deny  "$(bash_d "grep -r --exclude-dir=$(basename "$(dirname "$P")") DB_PASSWORD .")"
mkdir -p "$P/vault"; printf 'DB_%s=%s\n' PASSWORD 'in-a-folder-4321' > "$P/vault/.env.local"
check "--exclude=<folder name> doesn't skip that folder" deny "$(bash_d "grep -r --exclude=vault --exclude='.env' in-a-folder .")"
check "--exclude-dir=<folder> does skip it"             allow "$(bash_d "grep -r --exclude-dir=vault --exclude='.env' in-a-folder .")"
check "exclude flag on a non-search command"            deny  "$(bash_d "tar --exclude=.env -cf - .env")"
check "exclude after -- is a file name, not a flag"     deny  "$(bash_d "grep x -- --exclude=.env .env")"
rm -rf "$P/vault"
mkdir -p "$P/decoys"; for i in $(seq 1 60); do touch "$P/decoys/credentials-$i.json"; done
check "more than 50 secret files fails closed"          deny  "$(bash_d 'grep -r zzzz-no-such-text .')"
rm -rf "$P/decoys"
check "git grep (tracked files only)"                   allow "$(bash_d 'git grep DB_PASSWORD')"
check "Grep tool over the project"                      deny  "$(decision Grep '{"pattern":"DB_PASSWORD"}')"
check "Grep tool glob *.php"                            allow "$(decision Grep '{"pattern":"DB_PASSWORD","glob":"*.php"}')"
if command -v rg >/dev/null 2>&1; then
  check "Grep tool type php (rg's own type list)"       allow "$(decision Grep '{"pattern":"DB_PASSWORD","type":"php"}')"
else
  check "Grep tool type, no rg: every file checked"     deny  "$(decision Grep '{"pattern":"DB_PASSWORD","type":"php"}')"
fi
check "Grep tool unknown type: every file checked"      deny  "$(decision Grep '{"pattern":"DB_PASSWORD","type":"nosuchtype"}')"
check "Grep tool rg-only syntax (\\d) still caught"     deny  "$(decision Grep '{"pattern":"Tr0ub\\dor"}')"
check "rg with \\w pattern still caught"                deny  "$(bash_d 'rg -uu "DB_\w+"')"
check "Grep tool, pattern in no secret file"            allow "$(decision Grep '{"pattern":"function"}')"
check "Grep tool -i"                                    deny  "$(decision Grep '{"pattern":"db_password","-i":true}')"

# --- Commands that print a credential ------------------------------------------
check "gh auth token"                                   deny  "$(bash_d 'gh auth token')"
check "token passed to another command"                 allow "$(bash_d 'GH_TOKEN=$(gh auth token) gh api user')"
check "echo \$(gh auth token)"                          deny  "$(bash_d 'echo $(gh auth token)')"
check "Keychain lookup with -w"                         deny  "$(bash_d 'security find-generic-password -s x -w')"
check "Keychain lookup without -w"                      allow "$(bash_d 'security find-generic-password -s x')"
check "op read"                                         deny  "$(bash_d 'op read op://vault/item/password')"
check "gcloud print-access-token"                       deny  "$(bash_d 'gcloud auth print-access-token')"
check "bw get password (Bitwarden vault)"               deny  "$(bash_d 'bw get password github.com')"
check "bw list items"                                   deny  "$(bash_d 'bw list items --search acme')"
check "bws secret get (Secrets Manager)"                deny  "$(bash_d 'bws secret get 1234-abcd')"
check "bws secret list"                                 deny  "$(bash_d 'bws secret list')"
check "bws run injecting into a dev server"             allow "$(bash_d 'bws run --project-id 1234 -- npm run dev')"
check "bw status (no secret)"                           allow "$(bash_d 'bw status')"
gt="gh auth ""token"
check "commit message naming the command (heredoc)"     allow "$(bash_d "git commit -q -F - <<'EOF'
fix: deny commands that print a secret (${gt}, op read)
EOF")"
check "commit message naming the command (-m)"          allow "$(bash_d "git commit -m \"stop ${gt} printing\"")"
check "a real call chained after a commit"              deny  "$(bash_d "git commit -m wip; ${gt}")"
check "<< inside a -m string hides nothing"             deny  "$(bash_d "git commit -m \"note <<X\"
${gt}
X")"
check "another command's heredoc isn't stripped"        deny  "$(bash_d "git commit -m wip && bash <<EOF
${gt}
EOF")"
check "unterminated commit heredoc fails closed"        deny  "$(bash_d "git commit -F - <<'EOF'
${gt}")"
check "commit heredoc not the line's first command"     deny  "$(bash_d "echo x; git commit -F - <<'EOF'
${gt}
EOF")"
check "<<- heredoc gets no exemption (tab terminator)"  deny  "$(bash_d "git commit -F - <<-EOF
msg
	EOF
${gt}
EOF")"
check "two heredocs on the commit line fail closed"     deny  "$(bash_d "git commit -F - <<'EOF' && bash <<'X'
msg
EOF
${gt}
X")"

# --- Local queries returning personal data ---------------------------------------
check "select * from members"                           ask   "$(bash_d "ddev mysql -e 'select * from members'")"
check "select email from exp_members"                   ask   "$(bash_d "ddev mysql -e 'SELECT email FROM exp_members LIMIT 5'")"
check "select count(*) from members"                    allow "$(bash_d "ddev mysql -e 'select count(*) from members'")"
check "select ids from members"                         allow "$(bash_d "ddev mysql -e 'select member_id, role_id from exp_members'")"
check "select * from a non-people table"                allow "$(bash_d "ddev mysql -e 'select * from exp_channels'")"
check "wp db query users"                               ask   "$(bash_d "wp db query 'SELECT user_email FROM wp_users'")"

# --- MCP ---------------------------------------------------------------------------
aws="AKIA$(printf 'IOSFODNN7EXAMPLQ')"
check "MCP read of .env"                                deny  "$(decision mcp__github__get_file_contents '{"owner":"o","repo":"r","path":".env"}')"
check "MCP read of a normal file"                       allow "$(decision mcp__github__get_file_contents '{"owner":"o","repo":"r","path":"README.md"}')"
# Payloads with a variable are built first: bash 3.2 drops the braces of an escaped-quote
# string nested in "$( … )".
mcp_payload="$(jq -n --arg c "$aws" '{path:"a.php", content:$c}')"
check "MCP write carrying a credential"                 deny  "$(decision mcp__github__create_or_update_file "$mcp_payload")"
check "MCP write, clean content"                        ask   "$(decision mcp__github__create_or_update_file '{"path":"a.php","content":"<?php echo 1;"}')"

# --- PHP/JSON-array passwords and the tightened placeholder ------------------------
check "Read config/database.php (PHP array password)"   deny  "$(decision Read "$(jq -n --arg f "$P/config/database.php" '{file_path:$f}')")"
printf "<?php return ['password' => env('DB_PASSWORD'), 'pwd' => '', 'secret' => 'short'];\n" > "$P/app/ok.php"
check "PHP config reading env() passes"                 allow "$(decision Read "$(jq -n --arg f "$P/app/ok.php" '{file_path:$f}')")"
printf 'API_KEY=<your-api-key-here>\n' > "$P/app/README.txt"
check "<placeholder> value still forgiven"              allow "$(decision Read "$(jq -n --arg f "$P/app/README.txt" '{file_path:$f}')")"
printf '{"api_key": "%s"}\n' 'q8Zr2LmX9vB4nK7w' > "$P/app/creds.json"
check "JSON \"api_key\": \"…\" caught"                   deny  "$(decision Read "$(jq -n --arg f "$P/app/creds.json" '{file_path:$f}')")"
rm -f "$P/app/creds.json"

# Values the tightened array pattern must leave alone (Laravel rules, labels, doc examples).
printf "<?php return ['password' => 'required', 'label' => ['password' => 'Password'], 'pwd' => 'db_password'];\n" > "$P/app/rules.php"
check "PHP validation rules and labels pass"            allow "$(decision Read "$(jq -n --arg f "$P/app/rules.php" '{file_path:$f}')")"
printf 'const apiKey = import.meta.env.STRAPI_TOKEN;\n' > "$P/app/env.ts"
check "import.meta.env read passes"                     allow "$(decision Read "$(jq -n --arg f "$P/app/env.ts" '{file_path:$f}')")"

# --- [scan] allow: test fixtures a project vouches for ------------------------------
mkdir -p "$P/tests/fixtures"
printf 'DB_%s=%s\n' PASSWORD 'fixture-pass-12345' > "$P/tests/fixtures/sample.txt"
check "fixture flagged without an allow-list"           deny  "$(decision Read "$(jq -n --arg f "$P/tests/fixtures/sample.txt" '{file_path:$f}')")"
printf '[scan]\nallow = tests/fixtures/**\n' > "$P/ai-config.conf"
check "[scan] allow skips the content scan"             allow "$(decision Read "$(jq -n --arg f "$P/tests/fixtures/sample.txt" '{file_path:$f}')")"
printf '[scan]\nallow = .env*, tests/fixtures/**\n' > "$P/ai-config.conf"
check "[scan] allow can't open a secret path"           deny  "$(decision Read "$(jq -n --arg f "$P/.env" '{file_path:$f}')")"
printf '[scan]\nallow = tests/fixtures/**\n' > "$P/ai-config.conf"
printf 'DB_%s=%s\n' PASSWORD 'outside-fixture-9876' > "$P/app/outside.txt"
check "[scan] allow: '..' can't climb out of the folder" deny "$(decision Read "$(jq -n --arg f "$P/tests/fixtures/../../app/outside.txt" '{file_path:$f}')")"
rm -f "$P/app/outside.txt"
for g in '**' '*' '*/**' '*.txt' 't*' 'tests*' 'te-*' './**' '.../**' 'tests/./**'; do
  printf '[scan]\nallow = %s\n' "$g" > "$P/ai-config.conf"
  check "[scan] allow = $g is ignored (no literal prefix)" deny "$(decision Read "$(jq -n --arg f "$P/tests/fixtures/sample.txt" '{file_path:$f}')")"
done
printf '[scan]\nallow = tests/fixtures/**\n' > "$P/ai-config.conf"
git -C "$P" add tests/fixtures/sample.txt
check "commit: a [scan] fixture asks, never skips"      ask   "$(bash_d 'git commit -m wip')"
git -C "$P" rm -q --cached tests/fixtures/sample.txt
rm -f "$P/ai-config.conf"; rm -rf "$P/tests"

# --- Prose that names a secret-ish word isn't a file read ---------------------------
check "echo about credentials (no such file)"           allow "$(bash_d 'echo update the credentials docs')"
touch "$P/credentials"
check "cat credentials (the file exists)"               deny  "$(bash_d 'cat credentials')"
rm -f "$P/credentials"
mkdir -p "$P/sub"; touch "$P/sub/credentials"
check "cd sub && cat credentials (found via cd)"        deny  "$(bash_d 'cd sub && cat credentials')"
rm -rf "$P/sub"

# --- Commits ------------------------------------------------------------------------
commit_d() { bash_d 'git commit -m wip'; }
git -C "$P" add app/clean.php
check "commit: clean file"                              allow "$(commit_d)"
git -C "$P" add .env
check "commit: staged .env"                             deny  "$(commit_d)"
check "commit: git -C <dir> commit"                     deny  "$(bash_d "git -C $P commit -m x")"
git -C "$P" rm -q --cached .env
git -C "$P" add storage/logs/laravel.log
check "commit: DB URI with password in a staged log"    deny  "$(commit_d)"
git -C "$P" rm -q --cached storage/logs/laravel.log
git -C "$P" add config/database.php
check "commit: PHP-array password"                      deny  "$(commit_d)"
git -C "$P" rm -q --cached config/database.php
printf 'DB_%s=%s\n' PASSWORD 'not-real-but-long-1' > "$P/app/.env.example"
git -C "$P" add -f app/.env.example
check "commit: .env.example template"                   allow "$(commit_d)"
git -C "$P" rm -q --cached app/.env.example
mkdir -p "$P/system/user/config" "$P/other/user/config"
printf "<?php \$config['%s'] = '%s';\n" db_password 'tracked-ee-config-77' > "$P/system/user/config/config.php"
cp "$P/system/user/config/config.php" "$P/other/user/config/config.php"
git -C "$P" add -f system/user/config/config.php
check "commit: the tracked EE config is exempt"         allow "$(commit_d)"
git -C "$P" rm -q --cached system/user/config/config.php
git -C "$P" add -f other/user/config/config.php
check "commit: any other user/config/config.php is not" deny  "$(commit_d)"
git -C "$P" rm -q --cached other/user/config/config.php
rm -rf "$P/system" "$P/other"
git -C "$P" -c user.name=t -c user.email=t@t commit -qm base
printf 'k = "%s"\n' "$aws" >> "$P/app/clean.php"
check "commit -a: unstaged credential counts"           deny  "$(bash_d 'git commit -am wip')"
check "commit (no -a): unstaged credential ignored"     allow "$(commit_d)"
git -C "$P" checkout -q -- app/clean.php
if command -v gitleaks >/dev/null 2>&1; then
  # Assembled at run time: a literal webhook URL in this file trips GitHub push protection.
  printf 'hook = "https://%s/services/%s/%s/%s"\n' "hooks.slack"".com" "T01ABCDEF" "B01ABCDEF" "abcdefghijklmnopqrstuvwx" > "$P/app/hook.txt"
  git -C "$P" add app/hook.txt
  check "commit: gitleaks-only finding asks"            ask   "$(commit_d)"
  git -C "$P" rm -q --cached app/hook.txt; rm -f "$P/app/hook.txt"
fi
git -C "$P" add .env
(cd "$P" && bash "$GUARD" --pre-commit >/dev/null 2>&1); check "--pre-commit: staged .env exits 1" 1 "$?"
git -C "$P" rm -q --cached .env
(cd "$P" && bash "$GUARD" --pre-commit >/dev/null 2>&1); check "--pre-commit: clean exits 0" 0 "$?"

# --- setup-project: .gitignore created, pre-commit hook installed ------------------
N=$(tmp_dir)
git -C "$N" init -q
echo '{"require":{"laravel/framework":"^11"}}' > "$N/composer.json"; touch "$N/artisan" "$N/.env" "$N/backup.sql"
"$SETUP" --stack=coilpack --project="$N" --force --no-superpowers --skip-vscode >/dev/null 2>&1
check "setup: creates .gitignore when missing"          yes "$([[ -f "$N/.gitignore" ]] && echo yes || echo no)"
check "setup: .env ignored"                             yes "$(git -C "$N" check-ignore -q .env && echo yes || echo no)"
check "setup: CMS dump *.sql ignored"                   yes "$(git -C "$N" check-ignore -q backup.sql && echo yes || echo no)"
check "setup: pre-commit hook installed"                yes "$(grep -qs 'ai-config pre-commit' "$N/.git/hooks/pre-commit" && echo yes || echo no)"
git -C "$N" add -f .env
(cd "$N" && .git/hooks/pre-commit >/dev/null 2>&1); check "pre-commit hook stops a staged .env" 1 "$?"
printf '#!/bin/sh\nexit 0\n' > "$N/.claude/hooks/safety-guard.sh"
(cd "$N" && .git/hooks/pre-commit >/dev/null 2>&1); check "pre-commit hook ignores the repo's own guard copy" 1 "$?"
check "pre-commit hook names no working-tree guard"     no  "$(grep -q 'show-toplevel)/.claude/hooks' "$N/.git/hooks/pre-commit" && echo yes || echo no)"
git -C "$N" rm -q --cached .env
H=$(tmp_dir); git -C "$H" init -q; touch "$H/artisan"; echo '{"require":{"laravel/framework":"^11"}}' > "$H/composer.json"
printf '#!/bin/sh\necho mine\n' > "$H/.git/hooks/pre-commit"
"$SETUP" --stack=coilpack --project="$H" --force --no-superpowers --skip-vscode >/dev/null 2>&1
check "setup: an existing pre-commit hook is left alone" yes "$(grep -q mine "$H/.git/hooks/pre-commit" && echo yes || echo no)"
"$SETUP" --stack=coilpack --project="$N" --uninstall --force >/dev/null 2>&1
check "uninstall: removes our pre-commit hook"          no  "$([[ -f "$N/.git/hooks/pre-commit" ]] && echo yes || echo no)"

# --- Stack detection that refresh relies on ---------------------------------------
E=$(tmp_dir); git -C "$E" init -q
mkdir -p "$E/plbmin/ee" "$E/plbmin/user/config"
printf "<?php\n\t\$system_path = './plbmin';\n" > "$E/admin.php"
"$SETUP" --project="$E" --force --no-superpowers --skip-vscode >/dev/null 2>&1
check "EE with a renamed system folder is detected"     expressionengine "$(sed -n 's/^stack=//p' "$E/.claude/ai-config/version" 2>/dev/null)"
check "renamed EE config is a protected path"           deny "$(jq -n --arg f "$E/plbmin/user/config/config.php" '{tool_name:"Read",tool_input:{file_path:$f}}' \
  | CLAUDE_PROJECT_DIR="$E" bash "$GUARD" | jq -r .hookSpecificOutput.permissionDecision)"
printf '# Rewritten by hand\nNo stack marker here.\n' > "$E/CLAUDE.md"
rm -f "$E/admin.php"
out="$("$SETUP" --project="$E" --refresh --no-superpowers --skip-vscode 2>&1)"
check "refresh falls back to the recorded stack"        yes "$(grep -q 'from the last ai-config run: .*expressionengine' <<< "$out" && echo yes || echo no)"
out="$("$SETUP" --project="$E" --doctor 2>&1)"
check "doctor: shipped rules mentioning ssh aren't 'remote use'" no "$(grep -q 'Remote servers are used here' <<< "$out" && echo yes || echo no)"

# --- Global guard installer --------------------------------------------------------
C=$(tmp_dir)
cat > "$C/settings.json" <<'EOF'
{"model":"opus","permissions":{"allow":["Read(//Users/someone/**)","Bash(gh auth:*)","Bash(gh run view 1)","Bash(npm test:*)"],"deny":["Read(./mine)"]},
 "hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo stop"}]}]}}
EOF
AI_CONFIG_CLAUDE_DIR="$C" "$GLOBAL" >/dev/null 2>&1
check "global: hook registered"                         true "$(jq '[.hooks.PreToolUse[].hooks[].command | contains("AI_CONFIG_GUARD_SCOPE=global")] | any' "$C/settings.json")"
check "global: other hooks kept"                        '"echo stop"' "$(jq -c '.hooks.Stop[0].hooks[0].command' "$C/settings.json")"
check "global: secret deny rules added, own kept"       true "$(jq '.permissions.deny | (index("Read(**/.env)") != null) and (index("Read(./mine)") != null)' "$C/settings.json")"
check "global: broad allows removed"                    '["Bash(gh run view 1)","Bash(npm test:*)"]' "$(jq -c '.permissions.allow' "$C/settings.json")"
check "global: other settings kept"                     '"opus"' "$(jq -c .model "$C/settings.json")"
check "global: settings backed up"                      yes "$(ls "$C/backups"/settings-*.json >/dev/null 2>&1 && echo yes || echo no)"
before="$(cat "$C/settings.json")"; AI_CONFIG_CLAUDE_DIR="$C" "$GLOBAL" >/dev/null 2>&1
check "global: second run changes nothing"              same "$([[ "$before" == "$(cat "$C/settings.json")" ]] && echo same || echo changed)"
AI_CONFIG_CLAUDE_DIR="$C" "$GLOBAL" --check >/dev/null 2>&1; check "global: --check passes when installed" 0 "$?"
out_dir=$(tmp_dir)
check "global guard denies outside a project"           deny "$(printf '{"tool_name":"Bash","tool_input":{"command":"gh auth token"}}' \
  | (cd "$out_dir" && AI_CONFIG_GUARD_SCOPE=global CLAUDE_PROJECT_DIR="$out_dir" bash "$C/hooks/safety-guard.sh") | jq -r .hookSpecificOutput.permissionDecision)"
# The global copy always evaluates, whatever the project ships: a cloned repo's own
# settings and hook (even a do-nothing one) can't switch it off.
tok='{"tool_name":"Bash","tool_input":{"command":"gh auth token"}}'
echo '{"hooks":{"PreToolUse":[{"matcher":"Nothing","hooks":[{"command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/safety-guard.sh"}]}]}}' > "$P/.claude/settings.local.json"
printf '#!/bin/sh\nexit 0\n' > "$P/.claude/hooks/safety-guard.sh"
check "global guard evaluates despite project files"    deny "$(printf '%s' "$tok" \
  | AI_CONFIG_GUARD_SCOPE=global CLAUDE_PROJECT_DIR="$P" bash "$C/hooks/safety-guard.sh" | jq -r .hookSpecificOutput.permissionDecision)"
rm -f "$P/.claude/settings.local.json"
check "global guard applies the project's protected paths" deny "$(jq -n --arg f "$P/backup-2026.sql" '{tool_name:"Read",tool_input:{file_path:$f}}' \
  | AI_CONFIG_GUARD_SCOPE=global CLAUDE_PROJECT_DIR="$P" bash "$C/hooks/safety-guard.sh" | jq -r .hookSpecificOutput.permissionDecision)"
# Instead the PROJECT copy stands aside, when the user-owned settings register an identical
# global copy (so the same checks still run once).
FH=$(tmp_dir); mkdir -p "$FH/.claude/hooks"
cp "$C/settings.json" "$FH/.claude/settings.json"
cp "$GUARD" "$FH/.claude/hooks/safety-guard.sh"
cp "$GUARD" "$P/.claude/hooks/safety-guard.sh"
stok='{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"gh auth token"}}'
check "project copy stands aside for an identical global" "" "$(printf '%s' "$stok" \
  | HOME="$FH" CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/safety-guard.sh")"
printf '\n# local edit\n' >> "$FH/.claude/hooks/safety-guard.sh"
check "project copy runs when the global copy differs"   deny "$(printf '%s' "$stok" \
  | HOME="$FH" CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/safety-guard.sh" | jq -r .hookSpecificOutput.permissionDecision)"
cp "$GUARD" "$FH/.claude/hooks/safety-guard.sh"
echo '{}' > "$FH/.claude/settings.json"
check "project copy decides for a direct call (doctor, tests)" deny "$(printf '%s' "$tok" \
  | HOME="$FH" CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/safety-guard.sh" | jq -r .hookSpecificOutput.permissionDecision)"
check "project copy runs when no global guard is registered" deny "$(printf '%s' "$stok" \
  | HOME="$FH" CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/safety-guard.sh" | jq -r .hookSpecificOutput.permissionDecision)"
AI_CONFIG_CLAUDE_DIR="$C" "$GLOBAL" --remove >/dev/null 2>&1
check "global: --remove unregisters, keeps own deny"    '["Read(./mine)"]' "$(jq -c '.permissions.deny' "$C/settings.json")"
check "global: --remove keeps other hooks"              '["Stop"]' "$(jq -c '.hooks | keys' "$C/settings.json")"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
