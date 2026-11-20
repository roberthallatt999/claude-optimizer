#!/bin/sh
# Egress proxy for the Claude Code dev container (the egress-proxy compose service).
#
# The firewall allows hosts by the addresses they had when the container started, and CDN
# hosts (repo.packagist.org, the VS Code gallery) move between addresses within minutes.
# Squid matches the host name instead and resolves it per request, so a move doesn't matter.
# Only CONNECT to port 443 and plain HTTP to port 80 are let through, and only to the names
# in allowed-domains.txt; nothing is cached. The allowlist is re-read every 15 s.
#
# Tokens (kit 1.16.0): the Claude container holds placeholders only. For the hosts in CRED_HOSTS
# squid intercepts TLS with this Mac's CA (egress-credentials.sh creates it; the container trusts
# its certificate, the key is mounted here only), drops whatever Authorization header the client
# sent and adds the real one from /etc/sandbox-egress/credentials.env. HTTPS requests only, so a
# token never travels in clear text. Every other host is spliced: tunnelled untouched, as before.
# Without the CA or the credentials file the proxy runs exactly as before.
set -eu

EGRESS=/etc/sandbox-egress
CRED_HOSTS="github.com api.github.com uploads.github.com plausible.cps.ca api.cloudflare.com"
TLS_CONF=/etc/squid/egress-tls.conf

SRC=/etc/sandbox/allowed-domains.txt
LIST=/etc/squid/sandbox-allowed.txt

drop_covered() {
  # In squid, ".example.org" already matches example.org and every subdomain, and squid 5
  # refuses to start when a dstdomain list also names one of those ("is a subdomain of").
  # The firewall needs the apex listed on its own, so allowed-domains.txt keeps both forms;
  # drop the covered names here instead. Squid allows exactly the same hosts either way.
  awk '
    { names[NR] = $0; if (substr($0, 1, 1) == ".") wild[$0] = 1 }
    END {
      for (i = 1; i <= NR; i++) {
        n = names[i]; rest = (substr(n, 1, 1) == ".") ? substr(n, 2) : n; covered = 0
        if (substr(n, 1, 1) != "." && (("." n) in wild)) covered = 1
        while (!covered && (p = index(rest, ".")) > 0) {
          rest = substr(rest, p + 1)
          if (("." rest) in wild) covered = 1
        }
        if (!covered) print n
      }
    }'
}

build_list() {
  # One host per line, comments and blanks dropped. An empty list would make squid refuse
  # to start, so it always holds one name that never resolves.
  { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$SRC" 2>/dev/null | grep -v '^$' || true
    echo 'allowlist-missing.invalid'; } | sort -u | drop_covered > "$LIST.new"
  mv "$LIST.new" "$LIST"
}

cred() { # $1 variable name: its value from credentials.env, or nothing
  [ -r "$EGRESS/credentials.env" ] || return 0
  value=$(sed -n "s/^$1=//p" "$EGRESS/credentials.env" | head -n 1)
  # Same check as on the Mac: the value goes inside double quotes in squid.conf.
  case "$value" in *[!A-Za-z0-9._~+/=-]*) value='' ;; esac
  printf '%s' "$value"
}

header_rule() { # $1 acl name, $2 header value; nothing when the token is missing
  [ -n "$2" ] || return 0
  printf 'request_header_add Authorization "%s" %s cred_https\n' "$2" "$1"
}

build_tls_conf() {
  # Header rules for the credential hosts. Rewritten when credentials.env changes.
  gh=$(cred GITHUB_TOKEN)
  plausible=$(cred PLAUSIBLE_API_KEY)
  cloudflare=$(cred CLOUDFLARE_API_TOKEN)
  {
    echo "acl cred_https proto HTTPS"
    echo "acl cred_any dstdomain $CRED_HOSTS"
    echo "acl cred_github_api dstdomain api.github.com uploads.github.com"
    echo "acl cred_github_git dstdomain github.com"
    echo "acl cred_plausible dstdomain plausible.cps.ca"
    echo "acl cred_cloudflare dstdomain api.cloudflare.com"
    echo "# Whatever the client sent (a placeholder, or another token) never reaches these hosts."
    echo "request_header_access Authorization deny cred_any"
    header_rule cred_github_api "${gh:+Bearer $gh}"
    # git over HTTPS takes a token as the password of Basic auth.
    header_rule cred_github_git "${gh:+Basic $(printf 'x-access-token:%s' "$gh" | base64 -w 0)}"
    header_rule cred_plausible "${plausible:+Bearer $plausible}"
    header_rule cred_cloudflare "${cloudflare:+Bearer $cloudflare}"
  } > "$TLS_CONF.new"
  unset gh plausible cloudflare value
  chown root:proxy "$TLS_CONF.new"
  chmod 640 "$TLS_CONF.new"
  mv "$TLS_CONF.new" "$TLS_CONF"
}

http_port_line='http_port 3128'
tls_include=''
if [ -s "$EGRESS/ca.crt" ] && [ -s "$EGRESS/ca.key" ]; then
  # The key is copied out of the read-only mount so only squid's user can read it.
  install -o root -g proxy -m 640 "$EGRESS/ca.key" /etc/squid/egress-ca.key
  install -o root -g proxy -m 644 "$EGRESS/ca.crt" /etc/squid/egress-ca.crt
  rm -rf /var/spool/squid/ssl_db
  mkdir -p /var/spool/squid
  /usr/lib/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 4MB >/dev/null
  chown -R proxy:proxy /var/spool/squid
  build_tls_conf
  http_port_line="http_port 3128 ssl-bump tls-cert=/etc/squid/egress-ca.crt tls-key=/etc/squid/egress-ca.key generate-host-certificates=on dynamic_cert_mem_cache_size=4MB"
  tls_include=$(printf '%s\n' \
    "sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/spool/squid/ssl_db -M 4MB" \
    "sslcrtd_children 3" \
    "acl step1 at_step SslBump1" \
    "acl cred_connect dstdomain $CRED_HOSTS" \
    "acl cred_sni ssl::server_name $CRED_HOSTS" \
    "# Only CONNECTs to the credential hosts are looked at; allowed ones elsewhere are spliced." \
    "# A denied CONNECT still gets 200 and then squid's 403 inside TLS (squid's way of reporting" \
    "# errors on an ssl-bump port): nothing reaches the host, and checks must read the status." \
    "ssl_bump peek step1 cred_connect" \
    "ssl_bump splice step1" \
    "ssl_bump bump cred_sni" \
    "ssl_bump splice all" \
    "include $TLS_CONF")
  echo "egress-proxy: token injection on for $CRED_HOSTS"
else
  echo "egress-proxy: no interception CA mounted; tokens are not injected (kit < 1.16 setup?)" >&2
fi

build_list
cat > /etc/squid/squid.conf <<EOF
$http_port_line
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
$tls_include
EOF
chown root:proxy /etc/squid/squid.conf
chmod 640 /etc/squid/squid.conf

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
last_cred=$(cksum < "$EGRESS/credentials.env" 2>/dev/null || true)
while kill -0 "$squid_pid" 2>/dev/null; do
  sleep 15 &
  wait $! || true
  now=$(cksum < "$SRC" 2>/dev/null || true)
  now_cred=$(cksum < "$EGRESS/credentials.env" 2>/dev/null || true)
  if [ "$now" != "$last" ]; then
    last=$now
    build_list
    squid -k reconfigure -f /etc/squid/squid.conf && echo "egress-proxy: allowlist reloaded"
  fi
  if [ -n "$tls_include" ] && [ "$now_cred" != "$last_cred" ]; then
    last_cred=$now_cred
    build_tls_conf
    squid -k reconfigure -f /etc/squid/squid.conf && echo "egress-proxy: credentials reloaded"
  fi
done
echo "egress-proxy: squid exited" >&2
exit 1
