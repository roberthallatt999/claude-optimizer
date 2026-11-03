#!/usr/bin/env bash
# Cloudflare helper for the noslop skill's web version: runs wrangler with the CPS API token, and
# scaffolds a passcode-gated Worker for a page at its own path of the share domain, e.g.
# https://share.cps.ca/q3-traffic-7f3a9c2e/. The random hash keeps every page's route unique.
#
# On the Mac the API token lives only in the macOS Keychain. The dev containers have no Keychain,
# so there it's in TOKEN_FILE (mode 600) on the cps-cloudflare-config volume every CPS container
# shares. Either way it's read at call time and passed to wrangler in its environment only, never
# in argv, stdout or shell history. Nothing in this script prints it.
#
# Usage:
#   cloudflare.sh setup                 # interactive: account, share domain, token (Robert runs it)
#   cloudflare.sh config                # account, share domain, whether a token is stored
#   cloudflare.sh check                 # verify the token
#   cloudflare.sh domain <host>         # set the share domain (default share.cps.ca)
#   cloudflare.sh new <dir> <topic>     # name a page <topic>-<hash>, copy the gate into <dir>;
#                                       # a <dir> that already has a page keeps its name
#   cloudflare.sh url <name>            # the page's https://<share domain>/<name>/ address
#   cloudflare.sh wrangler <args...>    # run wrangler with the token (deploy, secret put, delete …)
#
# Deploying, setting a secret and deleting are outward-facing: the safety hook asks before each one.

set -euo pipefail

KEYCHAIN_SERVICE="${CLOUDFLARE_KEYCHAIN_SERVICE:-cloudflare-api}"
CONFIG_FILE="${CLOUDFLARE_CONFIG:-$HOME/.config/cps-cloudflare/config}"
TOKEN_FILE="${CLOUDFLARE_TOKEN_FILE:-$(dirname "$CONFIG_FILE")/api-token}"
API="https://api.cloudflare.com/client/v4"
DEFAULT_SHARE_DOMAIN="share.cps.ca"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates/cloudflare" && pwd)"

die() {
  printf 'cloudflare: %s\n' "$*" >&2
  exit 1
}

has_keychain() { command -v security >/dev/null 2>&1; }

token_store() {
  if has_keychain; then printf 'Keychain (service %s)' "$KEYCHAIN_SERVICE"; else printf '%s' "$TOKEN_FILE"; fi
}

# Prints the token; only ever called inside a command substitution.
read_token() {
  if has_keychain; then
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null
  else
    [ -s "$TOKEN_FILE" ] && tr -d '\n' <"$TOKEN_FILE"
  fi
}

token_present() {
  if has_keychain; then
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" >/dev/null 2>&1
  else
    [ -s "$TOKEN_FILE" ]
  fi
}

load_config() {
  CLOUDFLARE_ACCOUNT_ID='' CLOUDFLARE_SHARE_DOMAIN='' CLOUDFLARE_SHARE_ZONE=''
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
  fi
  CLOUDFLARE_SHARE_DOMAIN=${CLOUDFLARE_SHARE_DOMAIN:-$DEFAULT_SHARE_DOMAIN}
  # The Cloudflare zone the routes live in: the last two labels unless the config says otherwise.
  CLOUDFLARE_SHARE_ZONE=${CLOUDFLARE_SHARE_ZONE:-$(printf '%s' "$CLOUDFLARE_SHARE_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')}
}

save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  umask 077
  {
    printf '# Cloudflare config for the noslop skill - non-secret. The API token is in the macOS\n'
    printf '# Keychain on the Mac, and in the api-token file beside this one in the dev containers.\n'
    printf 'CLOUDFLARE_ACCOUNT_ID=%q\n' "$CLOUDFLARE_ACCOUNT_ID"
    printf 'CLOUDFLARE_SHARE_DOMAIN=%q\n' "$CLOUDFLARE_SHARE_DOMAIN"
  } >"$CONFIG_FILE"
}

# GET an API path with the token, sent through a curl config on stdin (never argv).
api_get() {
  local token
  token=$(read_token) && [ -n "$token" ] || die "no API token in $(token_store) - run: $0 setup"
  printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS -K - "$API$1"
  token=''
}

# HTTP status of a GET, or 000 when there is no token or no answer.
api_status() {
  local token
  token=$(read_token 2>/dev/null) && [ -n "$token" ] || { printf '000'; return; }
  printf 'header = "Authorization: Bearer %s"\n' "$token" \
    | curl -sS -K - -o /dev/null -w '%{http_code}' "$API$1" 2>/dev/null || printf '000'
  token=''
}

random_hash() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 4
  else od -An -N4 -tx1 /dev/urandom | tr -d ' \n'; fi
}

# Lowercase letters, digits and single hyphens, at most 40 characters.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-40 | sed 's/-$//'
}

valid_name() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$ ]]; }
valid_domain() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; }

cmd_setup() {
  load_config
  local id
  read -r -p "Cloudflare account ID (dashboard: Account home > ... > Copy account ID) [${CLOUDFLARE_ACCOUNT_ID}]: " id
  CLOUDFLARE_ACCOUNT_ID=${id:-$CLOUDFLARE_ACCOUNT_ID}
  [ -n "$CLOUDFLARE_ACCOUNT_ID" ] || die 'an account ID is required'
  local domain
  read -r -p "Share domain: each page becomes <name>.<this> [${CLOUDFLARE_SHARE_DOMAIN}]: " domain
  CLOUDFLARE_SHARE_DOMAIN=${domain:-$CLOUDFLARE_SHARE_DOMAIN}
  valid_domain "$CLOUDFLARE_SHARE_DOMAIN" || die "not a host name: $CLOUDFLARE_SHARE_DOMAIN"
  save_config
  printf 'Saved %s\n\n' "$CONFIG_FILE"
  printf 'Create an account API token (Manage account > API tokens) from the "Edit Cloudflare\n'
  printf 'Workers" template, limited to this account, and add Zone > Workers Routes > Edit for the\n'
  printf 'zone that holds the share domain. If creating a Worker is refused, raise Workers to\n'
  printf 'Admin.\n\n'
  if has_keychain; then
    printf 'Paste the token when prompted (input is hidden, asked twice).\n'
    security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -l 'Cloudflare API token (noslop)' -w
  else
    local token
    read -r -s -p 'Cloudflare API token (input is hidden): ' token
    printf '\n'
    [ -n "$token" ] || die 'no token entered'
    printf '%s\n' "$token" >"$TOKEN_FILE"
    token=''
  fi
  printf 'Token stored in %s. Now run: %s check\n' "$(token_store)" "$0"
}

cmd_config() {
  load_config
  printf 'account:   %s\n' "${CLOUDFLARE_ACCOUNT_ID:-(not set - run setup)}"
  printf 'pages:     https://%s/<name>/ (zone %s)\n' "$CLOUDFLARE_SHARE_DOMAIN" "$CLOUDFLARE_SHARE_ZONE"
  if token_present; then printf 'token:     stored in %s\n' "$(token_store)"
  else printf 'token:     missing - Robert runs: %s setup\n' "$0"; fi
  printf 'wrangler:  %s\n' "$(command -v wrangler || echo 'not installed - runs through npx')"
}

cmd_check() {
  load_config
  [ -n "$CLOUDFLARE_ACCOUNT_ID" ] || die "no account ID - run: $0 setup"
  local body
  body=$(api_get "/accounts/$CLOUDFLARE_ACCOUNT_ID/tokens/verify")
  if ! jq -e '.success' >/dev/null <<<"$body"; then
    body=$(api_get "/user/tokens/verify")
  fi
  jq -e '.success and .result.status == "active"' >/dev/null <<<"$body" \
    || die "token rejected: $(jq -c '.errors' <<<"$body" 2>/dev/null)"
  printf 'token: active\n'
  printf 'pages go to: https://%s/<name>/\n' "$CLOUDFLARE_SHARE_DOMAIN"
}

cmd_domain() {
  local host=${1:-}
  valid_domain "$host" || die "usage: $0 domain <host>, e.g. $DEFAULT_SHARE_DOMAIN"
  load_config
  CLOUDFLARE_SHARE_DOMAIN=$host
  save_config
  printf 'pages go to: https://%s/<name>/\n' "$host"
}

cmd_new() {
  local dir=${1:-} topic=${2:-} name slug status f
  [ -n "$dir" ] && [ -n "$topic" ] || die "usage: $0 new <dir> <topic>"
  load_config
  # A folder that already holds a page keeps its name: redeploying updates the same address.
  if [ -f "$dir/wrangler.jsonc" ]; then
    name=$(sed -n 's/^  "name": "\([^"]*\)".*/\1/p' "$dir/wrangler.jsonc" | head -1)
    [ -n "$name" ] || die "$dir/wrangler.jsonc has no name"
    printf 'kept existing page %s\n%s\n' "$name" "$(cmd_url "$name")"
    return
  fi
  slug=$(slugify "$topic")
  [ -n "$slug" ] || die "the topic needs at least one letter or digit: $topic"
  for _ in 1 2 3 4 5; do
    name="$slug-$(random_hash)"
    status=$(api_status "/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$name")
    case "$status" in
      404) break ;;
      200) name=''; continue ;;
      *) printf 'Could not confirm %s is unused (HTTP %s); its random hash makes a clash very unlikely.\n' \
           "$name" "$status" >&2
         break ;;
    esac
  done
  [ -n "$name" ] || die "five random names were all taken - try another topic"
  valid_name "$name" || die "bad page name: $name"
  mkdir -p "$dir"
  for f in worker.js wrangler.jsonc; do
    sed -e "s/{{WORKER_NAME}}/$name/g" -e "s/{{SHARE_DOMAIN}}/$CLOUDFLARE_SHARE_DOMAIN/g" \
      -e "s/{{SHARE_ZONE}}/$CLOUDFLARE_SHARE_ZONE/g" "$TEMPLATE_DIR/$f" >"$dir/$f"
  done
  printf 'page %s\n%s\n' "$name" "$(cmd_url "$name")"
  printf 'Build the page into %s/dist with relative asset links, then deploy and set PASSCODE.\n' "$dir"
}

cmd_url() {
  local name=${1:-}
  valid_name "$name" || die "usage: $0 url <name>"
  load_config
  printf 'https://%s/%s/\n' "$CLOUDFLARE_SHARE_DOMAIN" "$name"
}

cmd_wrangler() {
  load_config
  local runner=(npx --yes wrangler@4)
  command -v wrangler >/dev/null 2>&1 && runner=(wrangler)
  export WRANGLER_SEND_METRICS=false
  if token_present; then
    [ -n "$CLOUDFLARE_ACCOUNT_ID" ] || die "no account ID - run: $0 setup"
    CLOUDFLARE_API_TOKEN="$(read_token)" CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" "${runner[@]}" "$@"
  elif has_keychain; then
    # No stored token on the Mac: fall back to wrangler's own browser login.
    "${runner[@]}" "$@"
  else
    die "no API token in $(token_store) - Robert runs: $0 setup"
  fi
}

case "${1:-}" in
  setup) cmd_setup ;;
  config) cmd_config ;;
  check) cmd_check ;;
  domain) shift; cmd_domain "$@" ;;
  new) shift; cmd_new "$@" ;;
  url) shift; cmd_url "$@" ;;
  wrangler) shift; cmd_wrangler "$@" ;;
  *) sed -n '/^# Usage:/,/^# Deploying/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
