#!/usr/bin/env bash
# Cloudflare helper for the noslop skill's web version: runs wrangler with the CPS API token, and
# scaffolds a passcode-gated Worker for a page on a temporary workers.dev address.
#
# On the Mac the API token lives only in the macOS Keychain. The dev containers have no Keychain,
# so there it's in TOKEN_FILE (mode 600) on the cps-cloudflare-config volume every CPS container
# shares. Either way it's read at call time and passed to wrangler in its environment only, never
# in argv, stdout or shell history. Nothing in this script prints it.
#
# Usage:
#   cloudflare.sh setup                 # interactive: account ID and token (Robert runs it himself)
#   cloudflare.sh config                # account, workers.dev subdomain, whether a token is stored
#   cloudflare.sh check                 # verify the token, look up and save the workers.dev subdomain
#   cloudflare.sh new <dir> <name>      # copy the passcode-gate Worker into <dir> (never overwrites)
#   cloudflare.sh url <name>            # the page's https://<name>.<subdomain>.workers.dev address
#   cloudflare.sh wrangler <args...>    # run wrangler with the token (deploy, secret put, delete …)
#
# Deploying, setting a secret and deleting are outward-facing: the safety hook asks before each one.

set -euo pipefail

KEYCHAIN_SERVICE="${CLOUDFLARE_KEYCHAIN_SERVICE:-cloudflare-api}"
CONFIG_FILE="${CLOUDFLARE_CONFIG:-$HOME/.config/cps-cloudflare/config}"
TOKEN_FILE="${CLOUDFLARE_TOKEN_FILE:-$(dirname "$CONFIG_FILE")/api-token}"
API="https://api.cloudflare.com/client/v4"
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
  CLOUDFLARE_ACCOUNT_ID='' CLOUDFLARE_WORKERS_SUBDOMAIN=''
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
  fi
}

save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  umask 077
  {
    printf '# Cloudflare config for the noslop skill - non-secret. The API token is in the macOS\n'
    printf '# Keychain on the Mac, and in the api-token file beside this one in the dev containers.\n'
    printf 'CLOUDFLARE_ACCOUNT_ID=%q\n' "$CLOUDFLARE_ACCOUNT_ID"
    printf 'CLOUDFLARE_WORKERS_SUBDOMAIN=%q\n' "$CLOUDFLARE_WORKERS_SUBDOMAIN"
  } >"$CONFIG_FILE"
}

# GET an API path with the token, sent through a curl config on stdin (never argv).
api_get() {
  local token
  token=$(read_token) && [ -n "$token" ] || die "no API token in $(token_store) - run: $0 setup"
  printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS -K - "$API$1"
  token=''
}

valid_name() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$ ]]; }

cmd_setup() {
  load_config
  local id
  read -r -p "Cloudflare account ID (dashboard: Account home > ... > Copy account ID) [${CLOUDFLARE_ACCOUNT_ID}]: " id
  CLOUDFLARE_ACCOUNT_ID=${id:-$CLOUDFLARE_ACCOUNT_ID}
  [ -n "$CLOUDFLARE_ACCOUNT_ID" ] || die 'an account ID is required'
  save_config
  printf 'Saved %s\n\n' "$CONFIG_FILE"
  printf 'Create an account API token (Manage account > API tokens) from the "Edit Cloudflare\n'
  printf 'Workers" template, limited to this account. If creating a new Worker is refused, raise\n'
  printf 'the Workers permission to Admin.\n\n'
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
  printf 'subdomain: %s\n' "${CLOUDFLARE_WORKERS_SUBDOMAIN:-(unknown - run check)}"
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
  body=$(api_get "/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain")
  local sub
  sub=$(jq -r '.result.subdomain // empty' <<<"$body")
  [ -n "$sub" ] || die "no workers.dev subdomain on this account yet: open Workers & Pages in the dashboard once to create it"
  if [ "$sub" != "$CLOUDFLARE_WORKERS_SUBDOMAIN" ]; then
    CLOUDFLARE_WORKERS_SUBDOMAIN=$sub
    save_config
  fi
  printf 'pages go to: https://<name>.%s.workers.dev\n' "$sub"
}

cmd_new() {
  local dir=${1:-} name=${2:-}
  [ -n "$dir" ] && [ -n "$name" ] || die "usage: $0 new <dir> <name>"
  valid_name "$name" || die "name must be lowercase letters, digits and hyphens (max 54): $name"
  mkdir -p "$dir"
  local f
  for f in worker.js wrangler.jsonc; do
    if [ -e "$dir/$f" ]; then
      printf 'kept existing %s\n' "$dir/$f"
    else
      sed "s/{{WORKER_NAME}}/$name/g" "$TEMPLATE_DIR/$f" >"$dir/$f"
      printf 'wrote %s\n' "$dir/$f"
    fi
  done
  printf 'Build the page into %s/dist, then deploy and set PASSCODE (see SKILL.md).\n' "$dir"
}

cmd_url() {
  local name=${1:-}
  valid_name "$name" || die "usage: $0 url <name>"
  load_config
  [ -n "$CLOUDFLARE_WORKERS_SUBDOMAIN" ] || die "subdomain unknown - run: $0 check"
  printf 'https://%s.%s.workers.dev\n' "$name" "$CLOUDFLARE_WORKERS_SUBDOMAIN"
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
  new) shift; cmd_new "$@" ;;
  url) shift; cmd_url "$@" ;;
  wrangler) shift; cmd_wrangler "$@" ;;
  *) sed -n '/^# Usage:/,/^# Deploying/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
