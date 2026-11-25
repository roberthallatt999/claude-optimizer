#!/usr/bin/env bash
# Tests for devcontainer-kit/files/ddev-relay.pl: a relay on a spare port with its own HOME,
# talked to over TCP the way ddev-relay-client.sh does. The project's ee-migrate.sh is a fake
# that prints what it was given, so nothing reaches a server or DDEV.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY="$HERE/devcontainer-kit/files/ddev-relay.pl"
PORT=20199
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1 [rc=$RC out=${OUT:0:300}]"; fi; }

work=$(mktemp -d)
relay_pid=""
cleanup() { [ -n "$relay_pid" ] && kill "$relay_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

export HOME="$work/home"
STATE="$HOME/.cache/ai-devcontainer/relay"
mkdir -p "$STATE/tokens"
site="$work/site"
mkdir -p "$site/.admin-scripts/.ee-migrate" "$site/.ddev" "$site/.devcontainer"
echo "name: site" > "$site/.ddev/config.yaml"
site="$(cd "$site" && pwd -P)"
TOKEN=$(printf '%064d' 7)
echo "$TOKEN" > "$STATE/tokens/site.token"
echo "$site" > "$STATE/tokens/site.root"
cat > "$site/.admin-scripts/ee-migrate.sh" <<'EOS'
#!/usr/bin/env bash
echo "ARGS:$*"
echo "PWD:$PWD"
echo "ROOT:${EE_MIGRATE_REPO_ROOT:-}"
echo "STAMPS:${EE_MIGRATE_STAMP_DIR:-}"
echo "VIA:${EE_MIGRATE_VIA_RELAY:-}"
echo "FUNCS:${EE_MIGRATE_FUNCTIONS:-unset}"
EOS
APPROVED="$STATE/approved/site/ee-migrate.sh"
approve() { mkdir -p "$(dirname "$APPROVED")" && cp "$site/.admin-scripts/ee-migrate.sh" "$APPROVED"; }

start_relay() { # start_relay <allow|deny>
  [ -n "$relay_pid" ] && kill "$relay_pid" 2>/dev/null && wait "$relay_pid" 2>/dev/null
  EE_MIGRATE_FUNCTIONS=/should/be/removed CPS_DDEV_RELAY_PORT=$PORT CPS_DDEV_RELAY_ASSUME="$1" \
    perl "$RELAY" --serve >>"$work/relay.out" 2>&1 &
  relay_pid=$!
  for _ in $(seq 1 50); do
    CPS_DDEV_RELAY_PORT=$PORT perl "$RELAY" --ping >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "relay did not start"; cat "$work/relay.out"; exit 1
}

# req ARGS… → OUT (relay output) and RC (the relay's exit code)
req() {
  local line
  OUT="" RC=99
  exec 3<>"/dev/tcp/127.0.0.1/$PORT" || return
  { printf 'CPSRELAY1\n%s\n%s\n%s\n' "$TOKEN" /workspace "$#"; printf '%s\n' "$@"; } >&3
  while IFS= read -r line <&3; do
    if [[ "$line" == $'\x1e'EXIT\ * ]]; then RC=${line#$'\x1e'EXIT }; break; fi
    OUT+="$line"$'\n'
  done
  exec 3<&-
}

start_relay deny

req ee-migrate staging status
check 'not approved -> refused with the approve command' '[[ $RC -eq 2 && "$OUT" == *"isn'"'"'t approved yet"*"--approve-ee-migrate site"* ]]'

approve
req ee-migrate staging status
check 'status runs the approved copy, no dialog' '[[ $RC -eq 0 && "$OUT" == *"ARGS:staging status"* ]]'
check 'runs in the project root' '[[ "$OUT" == *"PWD:$site"$'"'"'\n'"'"'* && "$OUT" == *"ROOT:$site"$'"'"'\n'"'"'* ]]'
check 'stamps in the relay state folder' '[[ "$OUT" == *"STAMPS:$STATE/ee-migrate-stamps/site"* && -d "$STATE/ee-migrate-stamps/site" ]]'
check 'stamp folder is private' '[[ "$(ls -ld "$STATE/ee-migrate-stamps/site" | cut -c1-10)" == drwx------ ]]'
check 'EE_MIGRATE_VIA_RELAY set, EE_MIGRATE_FUNCTIONS cleared' '[[ "$OUT" == *"VIA:1"* && "$OUT" == *"FUNCS:unset"* ]]'

echo 'echo PLANTED' >> "$site/.admin-scripts/ee-migrate.sh"
req ee-migrate staging status
check 'repo script edited -> refused, edited code not run' '[[ $RC -eq 2 && "$OUT" == *"changed since it was approved"* && "$OUT" != *PLANTED* ]]'
approve

req ee-migrate local test a
check 'local test -> refused, points inside the container' '[[ $RC -eq 2 && "$OUT" == *"runs inside the container"* ]]'
req ee-migrate prod apply '--expect=a;rm'
check 'unsafe --expect -> refused' '[[ $RC -eq 2 && "$OUT" != *ARGS:* ]]'
req ee-migrate prod apply
check 'apply without --expect -> refused' '[[ $RC -eq 2 ]]'
req ee-migrate staging status --extra
check 'status with extra arguments -> refused' '[[ $RC -eq 2 ]]'
req ee-migrate dev status
check 'unknown target -> refused' '[[ $RC -eq 2 ]]'

ln -s /etc/hosts "$site/.admin-scripts/.ee-migrate/dump.sql.gz"
req ee-migrate staging status
check 'symlink in .admin-scripts/.ee-migrate -> refused' '[[ $RC -eq 2 && "$OUT" == *"is a symlink"* ]]'
rm "$site/.admin-scripts/.ee-migrate/dump.sql.gz"

req ee-migrate staging rehearse
check 'rehearse, dialog denied -> exit 3, not run' '[[ $RC -eq 3 && "$OUT" != *ARGS:* ]]'
req ee-migrate prod apply --expect=a,b
check 'apply, dialog denied -> exit 3, not run' '[[ $RC -eq 3 && "$OUT" != *ARGS:* ]]'
req snapshot restore x
check 'existing verbs: snapshot restore still asks' '[[ $RC -eq 3 ]]'
req logs -f
check 'existing verbs: logs -f still refused' '[[ $RC -eq 2 && "$OUT" == *"not allowed here"* ]]'

start_relay allow
req ee-migrate prod apply --expect=a,b
check 'apply, dialog allowed -> runs with --expect, no DDEV snapshot' \
  '[[ $RC -eq 0 && "$OUT" == *"ARGS:prod apply --expect=a,b"* && "$OUT" != *"taking snapshot"* ]]'
req ee-migrate staging rehearse
check 'rehearse, dialog allowed -> runs' '[[ $RC -eq 0 && "$OUT" == *"ARGS:staging rehearse"* ]]'

mkdir -p "$STATE/locks/site.ee-migrate"
echo $$ > "$STATE/locks/site.ee-migrate/pid"
req ee-migrate staging status
check 'another run in progress -> refused' '[[ $RC -eq 1 && "$OUT" == *"still running"* && "$OUT" != *ARGS:* ]]'
echo 999999 > "$STATE/locks/site.ee-migrate/pid"
req ee-migrate staging status
check 'stale lock is taken over' '[[ $RC -eq 0 && "$OUT" == *ARGS:* && ! -d "$STATE/locks/site.ee-migrate" ]]'

check 'audit log records the runs' 'grep -q "site RUN     ddev ee-migrate prod apply --expect=a,b" "$STATE/relay.log"'

# --- sandbox-domains (ai-devcontainer 2.x) -------------------------------------------------
DC="$site/.devcontainer/domains.conf"
printf '# mine\n[allow]\n\n[block]\n' > "$DC"
# The kit 2.x client's protocol line; CPSRELAY1 (above) stays accepted for 1.x containers.
req2() {
  local line
  OUT="" RC=99
  exec 3<>"/dev/tcp/127.0.0.1/$PORT" || return
  { printf 'AIRELAY1\n%s\n%s\n%s\n' "$TOKEN" /workspace "$#"; printf '%s\n' "$@"; } >&3
  while IFS= read -r line <&3; do
    if [[ "$line" == $'\x1e'EXIT\ * ]]; then RC=${line#$'\x1e'EXIT }; break; fi
    OUT+="$line"$'\n'
  done
  exec 3<&-
}
start_relay deny
req2 sandbox-domains allow api.example.com 'webhook test'
check 'allow, dialog denied -> exit 3, file unchanged' '[[ $RC -eq 3 ]] && ! grep -q api.example.com "$DC"'
req2 sandbox-domains block ads.example.com ''
check 'block needs no dialog' '[[ $RC -eq 0 ]] && sed -n "/^\[block\]/,\$p" "$DC" | grep -q "^ads.example.com"'
req2 sandbox-domains block claude.ai ''
check 'Claude Code hosts cannot be blocked' '[[ $RC -eq 2 && "$OUT" == *"can'"'"'t be blocked"* ]]'
for bad in 1.2.3.4 '*.example.com' 'https://x.example.com' com 'a b.example.com' 'x.example.com/path'; do
  req2 sandbox-domains allow "$bad" ''
  check "invalid name refused: $bad" '[[ $RC -eq 2 ]]'
done
start_relay allow
req2 sandbox-domains allow API.Example.com 'webhook test'
check 'allow, dialog allowed -> saved in [allow], lower-case, with the reason' \
  '[[ $RC -eq 0 ]] && sed -n "/^\[allow\]/,/^\[block\]/p" "$DC" | grep -q "^api.example.com .*webhook test"'
req2 sandbox-domains allow api.example.com ''
check 'allowing twice changes nothing' '[[ $RC -eq 0 && "$OUT" == *"nothing to change"* ]] && [[ $(grep -c "^api.example.com" "$DC") -eq 1 ]]'
req2 sandbox-domains allow ads.example.com ''
check 'a blocked name must be unblocked first' '[[ $RC -eq 2 && "$OUT" == *unblock* ]]'
req2 sandbox-domains unblock ads.example.com ''
check 'unblock (dialog allowed) removes it from [block]' '[[ $RC -eq 0 ]] && ! grep -q "^ads.example.com" "$DC"'
req2 sandbox-domains block api.example.com ''
check 'block moves a name out of [allow]' \
  '[[ $RC -eq 0 ]] && ! sed -n "/^\[allow\]/,/^\[block\]/p" "$DC" | grep -q "^api.example.com" && sed -n "/^\[block\]/,\$p" "$DC" | grep -q "^api.example.com"'
check 'comments in domains.conf are kept' 'grep -q "^# mine" "$DC"'
req2 sandbox-domains list
check 'list prints domains.conf' '[[ $RC -eq 0 && "$OUT" == *"[block]"* ]]'
check 'domain requests are logged' 'grep -q "site BLOCKED sandbox-domains block ads.example.com" "$STATE/relay.log"'
mv "$DC" "$DC.real"; ln -s "$DC.real" "$DC"
req2 sandbox-domains block x.example.com ''
check 'a symlinked domains.conf is refused' '[[ $RC -eq 1 && "$OUT" == *link* ]]'
rm "$DC"; mv "$DC.real" "$DC"
# A project without DDEV still gets domain requests, but no ddev commands.
rm "$site/.ddev/config.yaml"
req2 logs
check 'ddev commands refused for a project without DDEV' '[[ $RC -eq 2 && "$OUT" == *"no DDEV config"* ]]'
req2 sandbox-domains block y.example.com ''
check 'domain requests still work without DDEV' '[[ $RC -eq 0 ]]'

[[ $fail -eq 0 ]] && echo "All $pass tests passed" || echo "ddev-relay: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
