#!/bin/sh
# Egress proxy for the Claude Code dev container (the egress-proxy compose service).
#
# The firewall allows hosts by the addresses they had when the container started, and CDN
# hosts (repo.packagist.org, the VS Code gallery) move between addresses within minutes.
# Squid matches the host name instead and resolves it per request, so a move doesn't matter.
# Only CONNECT to port 443 and plain HTTP to port 80 are let through, and only to the names
# in allowed-domains.txt; nothing is cached. The allowlist is re-read every 15 s.
set -eu

SRC=/etc/sandbox/allowed-domains.txt
LIST=/etc/squid/sandbox-allowed.txt

build_list() {
  # One host per line, comments and blanks dropped. An empty list would make squid refuse
  # to start, so it always holds one name that never resolves.
  { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$SRC" 2>/dev/null | grep -v '^$' || true
    echo 'allowlist-missing.invalid'; } | sort -u > "$LIST.new"
  mv "$LIST.new" "$LIST"
}

build_list
cat > /etc/squid/squid.conf <<EOF
http_port 3128
acl allowed dstdomain "$LIST"
acl SSL_ports port 443
acl Safe_ports port 80 443
acl CONNECT method CONNECT
# Names on the list that resolve to a private address (the Mac, other containers) stay blocked.
acl private_dst dst 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16 100.64.0.0/10
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny private_dst
http_access allow allowed
http_access deny all
cache deny all
# Squid writes these as user proxy, which can't open the container's stdout; tail -F
# below forwards them, so refusals (TCP_DENIED) show in docker logs.
access_log stdio:/var/log/squid/access.log
cache_log /var/log/squid/cache.log
logfile_rotate 0
pid_filename /run/squid.pid
shutdown_lifetime 1 seconds
forwarded_for delete
via off
EOF

mkdir -p /var/log/squid
touch /var/log/squid/access.log /var/log/squid/cache.log
chown -R proxy:proxy /var/log/squid
tail -n 0 -F /var/log/squid/access.log /var/log/squid/cache.log &
tail_pid=$!
# A restart keeps the container's filesystem, so the last run's PID file is still there and
# squid refuses to start ("already running") whenever another process now has that PID.
rm -f /run/squid.pid
squid -N -f /etc/squid/squid.conf &
squid_pid=$!
trap 'kill "$squid_pid" "$tail_pid" 2>/dev/null; wait "$squid_pid" 2>/dev/null; exit 0' TERM INT

last=$(cksum < "$SRC" 2>/dev/null || true)
while kill -0 "$squid_pid" 2>/dev/null; do
  sleep 15 &
  wait $! || true
  now=$(cksum < "$SRC" 2>/dev/null || true)
  if [ "$now" != "$last" ]; then
    last=$now
    build_list
    squid -k reconfigure -f /etc/squid/squid.conf && echo "egress-proxy: allowlist reloaded"
  fi
done
echo "egress-proxy: squid exited" >&2
exit 1
