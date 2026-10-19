#!/bin/bash
# Default-deny egress firewall for the Claude Code dev container.
# Adapted from Anthropic's reference: github.com/anthropics/claude-code/.devcontainer
set -euo pipefail
IFS=$'\n\t'

ALLOWLIST=/etc/claude-firewall/allowed-domains.txt

# 1. Save Docker's internal DNS rules (127.0.0.11) before flushing.
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Reset default policies first: on a re-run they are still DROP from last time,
# which would block the GitHub lookup below.
iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT
iptables -F; iptables -X
iptables -t nat -F; iptables -t nat -X
iptables -t mangle -F; iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
  iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
  iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
  echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

# 2. Always allow DNS and loopback. (SSH is allowed only to GitHub, via the allowlist.)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT  -p tcp --sport 53 -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

# 3. GitHub IP ranges (web, api, git).
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --connect-timeout 10 https://api.github.com/meta || true)
if echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
  while read -r cidr; do
    [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || continue
    ipset add allowed-domains "$cidr" -exist
  done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -v ':' | aggregate -q)
else
  echo "WARNING: could not fetch GitHub ranges; GitHub will be blocked."
fi

# 4. Domains from the allowlist file.
while read -r domain; do
  domain="${domain%%#*}"; domain="$(echo "$domain" | xargs)"
  [ -z "$domain" ] && continue
  ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}' || true)
  if [ -z "$ips" ]; then
    echo "WARNING: could not resolve $domain (skipped)"
    continue
  fi
  while read -r ip; do
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || continue
    ipset add allowed-domains "$ip" -exist
  done <<< "$ips"
  echo "Allowed $domain"
done < "$ALLOWLIST"

# 5. Allow the container's own network: DDEV's (its databases, add-ons, router)
#    when the project uses DDEV, otherwise the compose default network.
#    Allowing the subnet, not single IPs, survives DB containers restarting.
DDEV_SUBNET=$(ip -o -f inet addr show eth0 | awk '{print $4}' | head -n1)
if [ -n "$DDEV_SUBNET" ]; then
  iptables -A INPUT  -s "$DDEV_SUBNET" -j ACCEPT
  iptables -A OUTPUT -d "$DDEV_SUBNET" -j ACCEPT
  echo "Allowed DDEV network $DDEV_SUBNET"
fi

# 6. Default deny, then allow established traffic and the allowlist.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# Block IPv6 egress entirely (if the kernel supports it).
ip6tables -F OUTPUT 2>/dev/null || true
ip6tables -P OUTPUT DROP 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

# 7. Verify.
if curl -s -o /dev/null --connect-timeout 5 https://example.com; then
  echo "ERROR: firewall check failed, example.com is reachable"; exit 1
fi
if ! curl -s -o /dev/null --connect-timeout 5 https://api.anthropic.com; then
  echo "ERROR: firewall check failed, api.anthropic.com is unreachable"; exit 1
fi
echo "Firewall active: example.com blocked, api.anthropic.com reachable."
