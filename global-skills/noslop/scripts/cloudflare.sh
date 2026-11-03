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
#   cloudflare.sh new <dir> <topic> [days]  # name a page <topic>-<hash> that expires in [days]
#                                       # (default 30), copy the gate into <dir>; a <dir> that
#                                       # already has a page keeps its name
#   cloudflare.sh url <name>            # the page's https://<share domain>/<name>/ address
#   cloudflare.sh passcode <name>       # make a passcode, set it on the page, record it here
#   cloudflare.sh describe <name>       # a page's address, title, dates, folder and passcode
#   cloudflare.sh list                  # every page on the share domain: created, expires, status
#   cloudflare.sh prune                 # the expired pages; --delete removes them
#   cloudflare.sh delete <name>         # remove one page: its routes, custom domain and Worker
#   cloudflare.sh wrangler <args...>    # run wrangler with the token (deploy, secret put …)
#
# Deploying, setting a secret and deleting are outward-facing: the safety hook asks before each one.
# list, prune and delete only ever touch Workers served from the share domain.
#
# Cloudflare never returns a secret, so each page's passcode is recorded when this script sets
# it, with the page's address, topic and folder, in PAGES_DIR/<name>.json (mode 600). Records
# live on the machine that made them: the Mac, or the volume all CPS containers share.

set -euo pipefail

KEYCHAIN_SERVICE="${CLOUDFLARE_KEYCHAIN_SERVICE:-cloudflare-api}"
CONFIG_FILE="${CLOUDFLARE_CONFIG:-$HOME/.config/cps-cloudflare/config}"
TOKEN_FILE="${CLOUDFLARE_TOKEN_FILE:-$(dirname "$CONFIG_FILE")/api-token}"
PAGES_DIR="${CLOUDFLARE_PAGES_DIR:-$(dirname "$CONFIG_FILE")/pages}"
API="https://api.cloudflare.com/client/v4"
DEFAULT_SHARE_DOMAIN="share.cps.ca"
DEFAULT_DAYS=30
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

# Any method; prints the response body. Used for the DELETEs in cmd_delete.
api_call() {
  local method=$1 token
  token=$(read_token) && [ -n "$token" ] || die "no API token in $(token_store) - run: $0 setup"
  printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS -K - -X "$method" "$API$2"
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

today() { date -u +%F; }

# Plain words for passcodes: short, unambiguous when read aloud or typed on a phone.
WORDS=(amber anchor apple arrow aspen badge basin beacon birch bison blaze bloom brook cabin
  cactus camel canoe canyon cedar cherry cliff clover cobalt comet copper coral crane crater
  daisy delta desert dune eagle ember falcon fern fjord flint forest fossil garnet geyser
  glacier granite harbor hazel heron hollow iris island ivory jasper juniper kayak kettle
  lagoon lantern larch lemon lilac linden lotus maple marble meadow mesa meteor mint moose
  nectar oasis ocean olive onyx orbit otter owl panda pebble pepper pine planet plum prairie
  quartz quill raven reef ridge river robin saffron sage salmon shore sierra spruce summit
  sunset thistle thunder tide timber topaz tulip tundra valley velvet violet walnut willow
  wren yarrow zephyr acorn alpine aurora bamboo bramble breeze cascade cinder dawn drift)

# Three words and two digits, from /dev/urandom: about 1 in 200 million to guess.
make_passcode() {
  local n=${#WORDS[@]} out='' r
  for _ in 1 2 3; do
    r=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
    out+="${WORDS[r % n]}-"
  done
  r=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
  printf '%s%02d' "$out" $((r % 100))
}

record_file() { printf '%s/%s.json' "$PAGES_DIR" "$1"; }

# Merge fields into a page's record (JSON object args), creating it with mode 600.
record_set() {
  local name=$1 file tmp
  shift
  file=$(record_file "$name")
  mkdir -p "$PAGES_DIR" && chmod 700 "$PAGES_DIR"
  tmp=$(umask 077; mktemp "$PAGES_DIR/.tmp.XXXXXX")
  jq -s 'add' <( [ -f "$file" ] && cat "$file" || echo '{}' ) <(jq -n "$@") >"$tmp"
  chmod 600 "$tmp" && mv "$tmp" "$file"
}

# The date <days> from today, on BSD (macOS) or GNU date.
days_from_today() {
  date -u -v+"$1"d +%F 2>/dev/null || date -u -d "+$1 days" +%F
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
  local dir=${1:-} topic=${2:-} days=${3:-$DEFAULT_DAYS} name slug status f expires
  [ -n "$dir" ] && [ -n "$topic" ] || die "usage: $0 new <dir> <topic> [days]"
  [[ "$days" =~ ^[1-9][0-9]{0,2}$ ]] || die "days must be 1 to 999: $days"
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
  expires=$(days_from_today "$days")
  mkdir -p "$dir"
  for f in worker.js wrangler.jsonc; do
    sed -e "s/{{WORKER_NAME}}/$name/g" -e "s/{{SHARE_DOMAIN}}/$CLOUDFLARE_SHARE_DOMAIN/g" \
      -e "s/{{SHARE_ZONE}}/$CLOUDFLARE_SHARE_ZONE/g" -e "s/{{EXPIRES}}/$expires/g" \
      "$TEMPLATE_DIR/$f" >"$dir/$f"
  done
  record_set "$name" --arg name "$name" --arg address "$(cmd_url "$name")" --arg topic "$topic" \
    --arg folder "$(cd "$dir" && pwd)" --arg created "$(today)" --arg expires "$expires" \
    '{name: $name, address: $address, topic: $topic, folder: $folder, created: $created, expires: $expires}'
  printf 'page %s, expires %s\n%s\n' "$name" "$expires" "$(cmd_url "$name")"
  printf 'Build the page into %s/dist with relative asset links, then deploy and set PASSCODE.\n' "$dir"
}

cmd_url() {
  local name=${1:-}
  valid_name "$name" || die "usage: $0 url <name>"
  load_config
  printf 'https://%s/%s/\n' "$CLOUDFLARE_SHARE_DOMAIN" "$name"
}

zone_id() {
  api_get "/zones?name=$CLOUDFLARE_SHARE_ZONE" | jq -r '.result[0].id // empty'
}

# One line per page on the share domain: name<TAB>address<TAB>created<TAB>expires.
# A page is a Worker with a route under the share domain, or a custom domain on it.
share_pages() {
  local zone acct=$CLOUDFLARE_ACCOUNT_ID share=$CLOUDFLARE_SHARE_DOMAIN routes domains scripts name
  [ -n "$acct" ] || die "no account ID - run: $0 setup"
  zone=$(zone_id)
  [ -n "$zone" ] || die "can't read zone $CLOUDFLARE_SHARE_ZONE: give the token Zone > Workers Routes for it"
  routes=$(api_get "/zones/$zone/workers/routes")
  domains=$(api_get "/accounts/$acct/workers/domains")
  scripts=$(api_get "/accounts/$acct/workers/scripts")
  {
    jq -r --arg s "$share/" '.result[]? | select(.script and (.pattern | startswith($s))) | .script' <<<"$routes"
    jq -r --arg s "$share" '.result[]? | select(.hostname == $s or (.hostname | endswith("." + $s))) | .service' <<<"$domains"
  } | sort -u | while read -r name; do
    [ -n "$name" ] || continue
    local address created expires
    address=$(jq -r --arg n "$name" --arg s "$share" '
      ([.result[]? | select(.service == $n) | "https://\(.hostname)/"] | first) // empty' <<<"$domains")
    [ -n "$address" ] || address=$(cmd_url "$name")
    created=$(jq -r --arg n "$name" '.result[]? | select(.id == $n) | .created_on[0:10]' <<<"$scripts")
    expires=$(api_get "/accounts/$acct/workers/scripts/$name/settings" \
      | jq -r '[.result.bindings[]? | select(.type == "plain_text" and .name == "EXPIRES") | .text] | first // empty')
    printf '%s\t%s\t%s\t%s\n' "$name" "$address" "${created:-?}" "$expires"
  done
}

# Expired: its EXPIRES date has passed, or it has none and was created over DEFAULT_DAYS ago.
is_expired() {
  local created=$1 expires=$2 now
  now=$(today)
  if [ -n "$expires" ]; then [[ "$expires" < "$now" ]]; return; fi
  [[ "$created" != "?" && "$(date -u -j -f %F "$created" +%s 2>/dev/null || date -u -d "$created" +%s)" -lt \
     "$(( $(date -u +%s) - DEFAULT_DAYS * 86400 ))" ]]
}

# Sets a new passcode on a deployed page and records it. The passcode reaches Cloudflare in the
# request body on stdin, never in argv.
cmd_passcode() {
  local name=${1:-} code token body
  valid_name "$name" || die "usage: $0 passcode <name>"
  load_config
  cut -f1 <<<"$(share_pages)" | grep -qx -- "$name" \
    || die "$name is not a deployed page on $CLOUDFLARE_SHARE_DOMAIN - deploy it first"
  code=$(make_passcode)
  token=$(read_token) && [ -n "$token" ] || die "no API token in $(token_store) - run: $0 setup"
  body=$(jq -n --arg t "$code" '{name: "PASSCODE", text: $t, type: "secret_text"}' \
    | curl -sS -K <(printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$token") \
        -X PUT --data-binary @- "$API/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$name/secrets")
  token=''
  jq -e '.success' >/dev/null <<<"$body" || die "could not set the passcode: $(jq -c '.errors' <<<"$body")"
  record_set "$name" --arg name "$name" --arg code "$code" --arg at "$(date -u +%FT%TZ)" \
    '{name: $name, passcode: $code, passcode_set: $at}'
  printf 'passcode for %s: %s\n' "$name" "$code"
}

# Everything known about one page: Cloudflare's view plus this machine's record.
cmd_describe() {
  local name=${1:-} file pages line address created expires state title modified
  valid_name "$name" || die "usage: $0 describe <name>"
  load_config
  file=$(record_file "$name")
  if ! pages=$(share_pages 2>/dev/null); then
    state="unknown (can't reach Cloudflare)"
  fi
  line=$(awk -F'\t' -v n="$name" '$1 == n' <<<"$pages")
  if [ -n "$state" ]; then
    :
  elif [ -n "$line" ]; then
    IFS=$'\t' read -r _ address created expires <<<"$line"
    state=live
    is_expired "$created" "$expires" && state=expired
    local settings
    settings=$(api_get "/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$name/settings")
    title=$(jq -r '[.result.bindings[]? | select(.type == "plain_text" and .name == "PAGE_TITLE") | .text] | first // empty' <<<"$settings")
    modified=$(api_get "/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts" \
      | jq -r --arg n "$name" '.result[]? | select(.id == $n) | .modified_on[0:10]')
  else
    state="not deployed"
  fi
  printf 'page:      %s\n' "$name"
  printf 'state:     %s\n' "$state"
  printf 'address:   %s\n' "${address:-$(jq -r '.address // empty' "$file" 2>/dev/null)}"
  printf 'title:     %s\n' "${title:-?}"
  printf 'created:   %s\n' "${created:-$(jq -r '.created // "?"' "$file" 2>/dev/null)}"
  printf 'updated:   %s\n' "${modified:-?}"
  printf 'expires:   %s\n' "${expires:-$(jq -r '.expires // "none"' "$file" 2>/dev/null || echo none)}"
  if [ -f "$file" ]; then
    printf 'topic:     %s\n' "$(jq -r '.topic // "?"' "$file")"
    printf 'folder:    %s\n' "$(jq -r '.folder // "?"' "$file")"
    printf 'passcode:  %s\n' "$(jq -r 'if .passcode then "\(.passcode) (set \(.passcode_set[0:10]))" else "not recorded" end' "$file")"
  else
    printf 'passcode:  not recorded on this machine. %s passcode %s sets a new one.\n' "$0" "$name"
  fi
}

cmd_list() {
  load_config
  local pages name address created expires state
  pages=$(share_pages)
  [ -n "$pages" ] || { printf 'No pages on %s.\n' "$CLOUDFLARE_SHARE_DOMAIN"; return; }
  printf '%-36s %-10s %-10s %-8s %s\n' PAGE CREATED EXPIRES STATE ADDRESS
  while IFS=$'\t' read -r name address created expires; do
    state=live
    is_expired "$created" "$expires" && state=expired
    printf '%-36s %-10s %-10s %-8s %s\n' "$name" "$created" "${expires:-none}" "$state" "$address"
  done <<<"$pages"
}

cmd_prune() {
  load_config
  local pages name address created expires found=0
  pages=$(share_pages)
  while IFS=$'\t' read -r name address created expires; do
    [ -n "$name" ] || continue
    is_expired "$created" "$expires" || continue
    found=1
    printf 'expired: %s (created %s, expires %s) %s\n' "$name" "$created" "${expires:-none}" "$address"
    [ "${1:-}" = "--delete" ] && cmd_delete "$name"
  done <<<"$pages"
  [ "$found" = 1 ] || printf 'Nothing has expired on %s.\n' "$CLOUDFLARE_SHARE_DOMAIN"
  if [ "$found" = 1 ] && [ "${1:-}" != "--delete" ]; then printf 'Run %s prune --delete to remove them.\n' "$0"; fi
}

# Removes one page: its routes, any custom domain, then the Worker. Refuses anything that isn't
# served from the share domain, so other Workers in the account are never touched.
cmd_delete() {
  local name=${1:-} zone acct id body
  valid_name "$name" || die "usage: $0 delete <name>"
  load_config
  acct=$CLOUDFLARE_ACCOUNT_ID
  cut -f1 <<<"$(share_pages)" | grep -qx -- "$name" \
    || die "$name is not a page on $CLOUDFLARE_SHARE_DOMAIN - nothing deleted"
  zone=$(zone_id)
  for id in $(api_get "/zones/$zone/workers/routes" | jq -r --arg n "$name" '.result[]? | select(.script == $n) | .id'); do
    api_call DELETE "/zones/$zone/workers/routes/$id" | jq -e '.success' >/dev/null || die "could not remove a route of $name"
  done
  for id in $(api_get "/accounts/$acct/workers/domains" | jq -r --arg n "$name" '.result[]? | select(.service == $n) | .id'); do
    api_call DELETE "/accounts/$acct/workers/domains/$id" >/dev/null || die "could not detach the custom domain of $name"
  done
  body=$(api_call DELETE "/accounts/$acct/workers/scripts/$name?force=true")
  jq -e '.success' >/dev/null <<<"$body" || die "could not delete $name: $(jq -c '.errors' <<<"$body")"
  rm -f "$(record_file "$name")"
  printf 'deleted %s\n' "$name"
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
  list) cmd_list ;;
  prune) shift; cmd_prune "$@" ;;
  delete) shift; cmd_delete "$@" ;;
  passcode) shift; cmd_passcode "$@" ;;
  describe) shift; cmd_describe "$@" ;;
  wrangler) shift; cmd_wrangler "$@" ;;
  *) sed -n '/^# Usage:/,/^# Deploying/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
