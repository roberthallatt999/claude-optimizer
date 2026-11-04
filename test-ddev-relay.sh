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
STATE="$HOME/.cache/cps-devcontainer/relay"
mkdir -p "$STATE/tokens"
site="$work/site"
mkdir -p "$site/.admin-scripts/.ee-migrate"
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

[[ $fail -eq 0 ]] && echo "All $pass tests passed" || echo "ddev-relay: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
