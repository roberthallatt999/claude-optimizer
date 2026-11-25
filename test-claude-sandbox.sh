#!/usr/bin/env bash
# Tests for --sandbox=claude (devcontainer-kit/claude-sandbox-policy.py) and the machine-wide
# managed settings (scripts/install-managed-settings.sh). No sandbox is started and nothing is
# installed: HOME, AI_CONFIG_HOME and the managed folder are throwaway; sudo is never run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POL="$HERE/devcontainer-kit/claude-sandbox-policy.py"
MANAGED="$HERE/scripts/install-managed-settings.sh"
SETUP="$HERE/setup-project.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" AI_CONFIG_HOME="$work/ai-config"
export AI_CONFIG_SKIP_GLOBAL_SKILLS=1 AI_CONFIG_USER_SETTINGS=/nonexistent
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = test\n\temail = test@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
mkdir -p "$HOME" "$AI_CONFIG_HOME/profiles"
unset AI_CONFIG_PROFILE
printf 'plausible_host = stats.acme.example\ndevcontainer_integrations = plausible\ndevcontainer_domains = .acme.example\n' \
  > "$AI_CONFIG_HOME/profiles/acme.conf"

P="$work/site"; mkdir -p "$P/.claude"; git -C "$P" init -q
echo '{"dependencies":{"astro":"4.0.0"}}' > "$P/package.json"
printf '[options]\nprofile = acme\n\n[sandbox]\nhosts = api.client.example\nblock = ads.acme.example\n' > "$P/ai-config.conf"
SET="$P/.claude/settings.local.json"
printf '{"permissions":{"allow":["Bash(npm test:*)"]},"sandbox":{"excludedCommands":["docker"],"network":{"allowedDomains":["mine.example"]}}}\n' > "$SET"

out=$(python3 "$POL" --project "$P" 2>&1)
check "dry run writes nothing" '[[ "$out" == *"Dry run"* ]] && ! grep -q '"'"'"enabled"'"'"' "$SET"'
python3 "$POL" --project "$P" --write </dev/null >"$work/w1.out" 2>&1
check "sandbox enabled, fails closed, no unsandboxed retry" \
  'jq -e ".sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false" "$SET" >/dev/null'
check "a leading-dot domain becomes *.domain plus the bare name" \
  'jq -e "(.sandbox.network.allowedDomains | index(\"*.acme.example\")) and (.sandbox.network.allowedDomains | index(\"acme.example\"))" "$SET" >/dev/null'
check "project and integration hosts allowed" \
  'jq -e "(.sandbox.network.allowedDomains | index(\"api.client.example\")) and (.sandbox.network.allowedDomains | index(\"stats.acme.example\"))" "$SET" >/dev/null'
check "blocks become deniedDomains" 'jq -e ".sandbox.network.deniedDomains | index(\"ads.acme.example\")" "$SET" >/dev/null'
check "your own sandbox keys and other settings are kept" \
  'jq -e "(.sandbox.excludedCommands == [\"docker\"]) and (.sandbox.network.allowedDomains | index(\"mine.example\")) and (.permissions.allow == [\"Bash(npm test:*)\"])" "$SET" >/dev/null'
check "no token injection is reported" 'grep -q "No token injection" "$work/w1.out"'
check "the record is outside the project" '[[ -n "$(ls "$HOME/.cache/ai-devcontainer/claude-sandbox/"*.json 2>/dev/null)" ]] && ! grep -q allowedDomains "$P/.claude/ai-config/claude-sandbox.json"'
# A new host from the project file is listed and, without a terminal, left out.
printf 'hosts = api.client.example, sneaky.example\n' >> "$P/ai-config.conf"
python3 "$POL" --project "$P" --write </dev/null >"$work/w2.out" 2>&1
check "new hosts are listed and not applied unasked" \
  'grep -q "+ sneaky.example" "$work/w2.out" && ! jq -e ".sandbox.network.allowedDomains | index(\"sneaky.example\")" "$SET" >/dev/null'
python3 "$POL" --project "$P" --write --yes </dev/null >/dev/null 2>&1
check "--yes applies them" 'jq -e ".sandbox.network.allowedDomains | index(\"sneaky.example\")" "$SET" >/dev/null'
check "rerunning adds no duplicates" '[[ $(jq "[.sandbox.network.allowedDomains[]] | length - (unique | length)" "$SET") -eq 0 ]]'
# A settings file replaced with a link is never written through.
mv "$SET" "$work/real.json"; ln -s "$work/real.json" "$SET"
python3 "$POL" --project "$P" --write --yes </dev/null >"$work/w3.out" 2>&1
check "a linked settings file is refused" 'grep -q "link" "$work/w3.out"'
rm "$SET"; mv "$work/real.json" "$SET"

# --- ai-config --sandbox=claude --------------------------------------------------------------
Q="$work/via-setup"; mkdir -p "$Q"; git -C "$Q" init -q; echo '{"dependencies":{"astro":"4.0.0"}}' > "$Q/package.json"
"$SETUP" --project="$Q" --sandbox=claude --force --no-superpowers --skip-vscode </dev/null >"$work/s.out" 2>&1
check "ai-config --sandbox=claude writes the sandbox block" 'jq -e ".sandbox.enabled == true" "$Q/.claude/settings.local.json" >/dev/null'
check "the safety policy is still there" 'jq -e ".permissions.deny | length > 0" "$Q/.claude/settings.local.json" >/dev/null'
"$SETUP" --project="$Q" --refresh --no-superpowers --skip-vscode </dev/null >"$work/r.out" 2>&1
check "the choice is sticky on --refresh" 'grep -q "Claude Code sandbox" "$work/r.out"'

# --- ai-config never writes through a link out of the project -------------------------------
L="$work/linked"; mkdir -p "$L/.claude/ai-config"; git -C "$L" init -q; echo '{"dependencies":{"astro":"4.0.0"}}' > "$L/package.json"
echo "keep me" > "$work/victim.txt"
ln -s "$work/victim.txt" "$L/.claude/ai-config/manifest.tsv"
"$SETUP" --project="$L" --force --no-superpowers --skip-vscode </dev/null >"$work/l.out" 2>&1; rc=$?
check "a link out of the project stops the run" '[[ $rc -ne 0 ]] && grep -q "links that lead outside the project" "$work/l.out"'
check "the linked file is untouched" '[[ "$(cat "$work/victim.txt")" == "keep me" ]]'
rm "$L/.claude/ai-config/manifest.tsv"
echo "# agents" > "$L/AGENTS.md"; ln -s AGENTS.md "$L/CLAUDE.md"
"$SETUP" --project="$L" --force --no-superpowers --skip-vscode </dev/null >"$work/l2.out" 2>&1
check "a link inside the project (CLAUDE.md -> AGENTS.md) is fine" '! grep -q "links that lead outside" "$work/l2.out"'

# --- managed settings ------------------------------------------------------------------------
export AI_CONFIG_MANAGED_STAGE="$work/stage" AI_CONFIG_MANAGED_DIR="$work/managed.d"
out=$(bash "$MANAGED" 2>&1)
F="$work/stage/50-ai-config.json"
check "managed: the file holds the shared deny rules" \
  '[[ $(jq ".permissions.deny | length" "$F") -eq $(jq ".permissions.deny | length" "$HERE/projects/common/security.settings.local.json") ]]'
check "managed: bypass mode is disabled" 'jq -e ".permissions.disableBypassPermissionsMode == \"disable\"" "$F" >/dev/null'
check "managed: the global guard is a PreToolUse hook" 'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"safety-guard.sh\")" "$F" >/dev/null'
check "managed: no managed-only switches without --strict" 'jq -e "(.allowManagedHooksOnly // false) == false" "$F" >/dev/null'
check "managed: it prints the sudo command and runs none" '[[ "$out" == *"sudo sh -c"* && ! -e "$work/managed.d/50-ai-config.json" ]]'
check "managed: the hook runs a copy next to the managed settings, not ~/.claude" \
  'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"/ai-config/safety-guard.sh\") and (test(\"[.]claude/hooks\") | not)" "$F" >/dev/null'
bash "$MANAGED" --check >/dev/null 2>&1; rc=$?
check "managed: --check fails while not installed" '[[ $rc -ne 0 ]]'
mkdir -p "$work/managed.d" "$work/ai-config" && cp "$F" "$work/managed.d/" \
  && cp "$work/stage/safety-guard.sh" "$work/stage/protected-paths.conf" "$work/ai-config/"
bash "$MANAGED" --check >/dev/null 2>&1; rc=$?
check "managed: --check passes once installed" '[[ $rc -eq 0 ]]'
bash "$MANAGED" --strict >/dev/null 2>&1
check "managed: --strict adds both managed-only switches" \
  'jq -e ".allowManagedHooksOnly == true and .permissions.allowManagedPermissionRulesOnly == true" "$F" >/dev/null'
check "managed: --remove only prints the command" '[[ "$(bash "$MANAGED" --remove)" == *"sudo rm"* && -e "$work/managed.d/50-ai-config.json" ]]'
# Run the printed command without root (AI_CONFIG_MANAGED_SUDO empty): a staged file changed
# after the build is refused and nothing moves into place; an untouched build installs.
rm -rf "$work/managed.d" "$work/ai-config"
inst() { AI_CONFIG_MANAGED_SUDO= bash "$MANAGED" | sed -n 's/^  \(sh -c .*\)$/\1/p'; }
cmd=$(inst); echo "# changed" >> "$work/stage/safety-guard.sh"
( eval "$cmd" ) >/dev/null 2>&1; rc=$?
check "managed: a staged file changed after the build is refused" \
  '[[ $rc -ne 0 && ! -e "$work/managed.d/50-ai-config.json" && ! -e "$work/ai-config/safety-guard.sh" ]]'
cmd=$(inst); ( eval "$cmd" ) >/dev/null 2>&1; rc=$?
check "managed: an untouched build installs settings and the guard copy" \
  '[[ $rc -eq 0 && -f "$work/managed.d/50-ai-config.json" ]] && cmp -s "$work/ai-config/safety-guard.sh" "$HERE/projects/common/hooks/safety-guard.sh"'
AI_CONFIG_MANAGED_SUDO= bash "$MANAGED" --check >/dev/null 2>&1; rc=$?
check "managed: --check passes after the printed command ran" '[[ $rc -eq 0 ]]'

# --- scan-transcripts.sh (fake transcripts; a fake key assembled here) -------------------------
T="$work/transcripts/-p-site"; mkdir -p "$T"
fake_key="AKIA$(printf '%s' ABCDEFGHIJKLMNOP)"
printf '{"type":"user","text":"hello"}\n' > "$T/clean.jsonl"
printf '{"type":"tool","text":"aws_key=%s"}\n{"type":"user","text":"ok"}\n' "$fake_key" > "$T/leaky.jsonl"
out=$(bash "$HERE/scripts/scan-transcripts.sh" "$work/transcripts" 2>&1); rc=$?
check "transcripts: a leaked key is reported by file and count" '[[ $rc -eq 1 && "$out" == *"1 line(s)"*"leaky.jsonl"* ]]'
check "transcripts: the value is never printed" '[[ "$out" != *"$fake_key"* ]]'
check "transcripts: clean files are not listed" '[[ "$out" != *"clean.jsonl"* ]]'
rm "$T/leaky.jsonl"
bash "$HERE/scripts/scan-transcripts.sh" "$work/transcripts" >/dev/null 2>&1; rc=$?
check "transcripts: exit 0 when clean" '[[ $rc -eq 0 ]]'

echo ""
echo "claude-sandbox: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
