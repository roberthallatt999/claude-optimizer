#!/bin/bash
# sandbox-domains: see, ask for, or block the domains this sandbox can reach.
#
#   sandbox-domains list                        what's allowed and blocked, and where it came from
#   sandbox-domains allow <name> ["why"]        asks on the Mac (Deny is the default)
#   sandbox-domains block <name>                at once, no dialog
#   sandbox-domains unblock <name> ["why"]      asks on the Mac
#
# A leading dot (.example.org) means the name and every subdomain. allowed-domains.txt and
# domains.conf are read-only in here, so a change goes through the relay on the Mac, which
# writes domains.conf and logs the request. Then this reloads the firewall; the egress proxy
# picks the change up by itself within 15 s.
set -uo pipefail
DIR=/workspace/.devcontainer
CLIENT="$DIR/ddev-relay-client.sh"

usage() {
  sed -n '2,8s/^# \{0,1\}//p' "$0"
  exit 2
}

action="${1:-}"
case "$action" in
  list)
    echo "# allowed-domains.txt (generated):"
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$DIR/allowed-domains.txt" 2>/dev/null | grep -v '^$' | sort | sed 's/^/  /'
    echo "# domains.conf (yours):"
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$DIR/domains.conf" 2>/dev/null | sed 's/^/  /'
    exit 0 ;;
  allow|block|unblock) ;;
  -h|--help|'') usage ;;
  *) echo "sandbox-domains: unknown action '$action'" >&2; usage ;;
esac
[ $# -ge 2 ] || usage
name=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
shift 2
if ! printf '%s' "$name" | grep -Eq '^\.?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'; then
  echo "sandbox-domains: '$name' isn't a host name (no IPs, wildcards, schemes or paths)" >&2
  exit 2
fi
if [ ! -r /run/ddev-relay/token ]; then
  echo "sandbox-domains: no relay token in this container. On the Mac, edit .devcontainer/domains.conf instead," >&2
  echo "or rebuild the container with ai-devcontainer 2.0 or later." >&2
  exit 1
fi
[ "$action" != block ] && echo "sandbox-domains: asking on the Mac (a dialog there; it times out after 2 minutes)..."
bash "$CLIENT" sandbox-domains "$action" "$name" "$*"
code=$?
if [ "$code" -eq 0 ]; then
  # Tools that ignore HTTPS_PROXY connect by address: reload the firewall's address list too.
  sudo /usr/local/sbin/sandbox-firewall.sh >/dev/null 2>&1 \
    && echo "sandbox-domains: firewall reloaded; the proxy follows within 15 s." \
    || echo "sandbox-domains: saved, but the firewall reload failed: run sudo /usr/local/sbin/sandbox-firewall.sh" >&2
fi
exit "$code"
