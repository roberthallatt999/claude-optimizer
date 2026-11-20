#!/bin/bash
# Runs on the Mac (the dev container's initializeCommand, before ensure-ddev.sh).
#
# Keeps API tokens out of the Claude container. The real tokens stay in the Mac's Keychain;
# this script copies them into a file only the egress-proxy service mounts. The proxy
# intercepts TLS for a handful of hosts and sets the Authorization header itself, so the
# container holds nothing but placeholders.
#
#   ~/.cache/cps-devcontainer/egress/
#     ca.crt, ca.key        this Mac's interception CA (key: proxy only; cert: trusted inside)
#     credentials.env       real tokens, mode 600, mounted into egress-proxy only
#     plausible/            the Mac's Plausible config + a placeholder key (mounted read-only)
#     cloudflare/           the Mac's Cloudflare config + a placeholder token (mounted read-only)
#
# Keychain items read (service, account = your macOS user):
#   cps-devcontainer-github   fine-grained GitHub token for the dev containers
#   plausible-api             the plausible skill's key (already there if you set it up)
#   cloudflare-api            noslop's Cloudflare token (already there if you set it up)
#
# Never prints a token. bash 3.2 compatible: macOS runs this with /bin/bash.
set -euo pipefail

DIR="$HOME/.cache/cps-devcontainer/egress"
PLACEHOLDER="cps-egress-placeholder"
CA_DAYS=3650

umask 077
mkdir -p "$DIR" "$DIR/plausible" "$DIR/cloudflare"
chmod 700 "$DIR"

# --- this Mac's interception CA ---------------------------------------------------------
# Created once; its key never enters the Claude container. The certificate is named .crt
# because update-ca-certificates only picks those up (an early test build wrote .pem).
if [ -s "$DIR/ca.pem" ] && [ ! -e "$DIR/ca.crt" ]; then
  mv "$DIR/ca.pem" "$DIR/ca.crt"
fi
if [ ! -s "$DIR/ca.crt" ] || [ ! -s "$DIR/ca.key" ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days "$CA_DAYS" \
    -subj "/CN=cps-devcontainer egress proxy ($(hostname -s))" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "$DIR/ca.key.new" -out "$DIR/ca.crt.new" >/dev/null 2>&1
  mv "$DIR/ca.key.new" "$DIR/ca.key"
  mv "$DIR/ca.crt.new" "$DIR/ca.crt"
  echo "Egress proxy: created this Mac's interception CA ($DIR/ca.crt)."
fi
chmod 600 "$DIR/ca.key"
chmod 644 "$DIR/ca.crt"

# --- tokens from the Keychain -----------------------------------------------------------
keychain() {
  security find-generic-password -s "$1" -a "$USER" -w 2>/dev/null || true
}
valid() {
  # A token goes into squid.conf inside double quotes; refuse anything that could break out.
  case "$1" in
    *[!A-Za-z0-9._~+/=-]*) return 1 ;;
  esac
  [ -n "$1" ]
}

found=''
missing=''
{
  echo '# Written by egress-credentials.sh on the Mac. Mounted into egress-proxy only.'
  for pair in GITHUB_TOKEN:cps-devcontainer-github PLAUSIBLE_API_KEY:plausible-api CLOUDFLARE_API_TOKEN:cloudflare-api; do
    var="${pair%%:*}"
    service="${pair#*:}"
    value="$(keychain "$service")"
    if valid "$value"; then
      printf '%s=%s\n' "$var" "$value"
      found="$found $service"
    else
      missing="$missing $service"
    fi
  done
} > "$DIR/credentials.env.new"
unset value
chmod 600 "$DIR/credentials.env.new"
mv "$DIR/credentials.env.new" "$DIR/credentials.env"

# --- skill config the container can read (nothing secret) -------------------------------
copy_config() { # $1 Mac config file, $2 destination
  if [ -f "$1" ]; then
    cp "$1" "$2"
  else
    : > "$2"
  fi
  chmod 644 "$2"
}
copy_config "$HOME/.config/plausible/config" "$DIR/plausible/config"
copy_config "$HOME/.config/cps-cloudflare/config" "$DIR/cloudflare/config"
printf '%s\n' "$PLACEHOLDER" > "$DIR/plausible/api-key"
printf '%s\n' "$PLACEHOLDER" > "$DIR/cloudflare/api-token"
chmod 644 "$DIR/plausible/api-key" "$DIR/cloudflare/api-token"
chmod 755 "$DIR/plausible" "$DIR/cloudflare"

echo "Egress proxy: tokens injected for:${found:- none}."
if [ -n "$missing" ]; then
  echo "Egress proxy: not in the Keychain (those services stay signed out inside):$missing."
  case "$missing" in
    *cps-devcontainer-github*)
      echo "  GitHub: store a fine-grained token in a Mac terminal with"
      echo "    security add-generic-password -U -s cps-devcontainer-github -a \"\$USER\" -w"
      echo "  then reopen the container." ;;
  esac
fi
