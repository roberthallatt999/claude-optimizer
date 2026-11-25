#!/bin/bash
# Runs on the Mac (the dev container's initializeCommand, first).
#
#   egress-credentials.sh <workspace> <key>
#
# Keeps API tokens out of the Claude container. The real tokens stay in the Mac's Keychain;
# this script copies the ones the project's integrations name (.devcontainer/token-hosts.conf)
# into a file only the egress-proxy service mounts. The proxy intercepts TLS for those hosts
# and sets the Authorization header itself, so the container holds nothing but placeholders.
#
#   ~/.cache/ai-devcontainer/egress/
#     ca.crt, ca.key              this Mac's interception CA (key: proxy only; cert: trusted inside)
#     projects/<key>/
#       credentials.env           this project's real tokens, mode 600, egress-proxy only
#       mounts/<integration>/     the Mac's config for a skill, with its key file replaced by
#                                 the placeholder (.devcontainer/mounts.conf), mounted read-only
#
# Each project gets its own folder, so two profiles' tokens never meet in one file.
# Never prints a token. bash 3.2 compatible: macOS runs this with /bin/bash.
set -euo pipefail

workspace="${1:?usage: egress-credentials.sh <workspace> <key>}"
key="${2:?usage: egress-credentials.sh <workspace> <key>}"
case "$key" in
  *[!A-Za-z0-9_.-]*|'') echo "egress-credentials.sh: bad project key '$key'" >&2; exit 2 ;;
esac

STATE_DIR="$HOME/.cache/ai-devcontainer"
OLD_STATE="$HOME/.cache/cps-devcontainer"
if [ ! -e "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ -d "$OLD_STATE" ] && [ ! -L "$OLD_STATE" ]; then
  ln -s "$OLD_STATE" "$STATE_DIR"
fi
DIR="$STATE_DIR/egress"
OUT="$DIR/projects/$key"
CONF="$workspace/.devcontainer/token-hosts.conf"
MOUNTS="$workspace/.devcontainer/mounts.conf"
PLACEHOLDER="ai-egress-placeholder"
CA_DAYS=3650

umask 077
mkdir -p "$DIR" "$OUT/mounts"
# One folder per project: never hand this project's tokens to a folder another workspace owns.
if [ -s "$OUT/workspace" ] && [ "$(cat "$OUT/workspace")" != "$workspace" ] && [ -d "$(cat "$OUT/workspace")" ]; then
  echo "Egress proxy: key '$key' already belongs to $(cat "$OUT/workspace"); no tokens written for $workspace." >&2
  echo "Regenerate this project's .devcontainer (ai-config --refresh) so it gets its own key." >&2
  exit 0
fi
printf '%s\n' "$workspace" > "$OUT/workspace"
chmod 700 "$DIR" "$DIR/projects" "$OUT"
chmod 755 "$OUT/mounts"

# --- this Mac's interception CA ---------------------------------------------------------
# Created once; its key never enters the Claude container. Named .crt because
# update-ca-certificates only picks those up.
if [ ! -s "$DIR/ca.crt" ] || [ ! -s "$DIR/ca.key" ]; then
  # openssl's progress dots are noise; its error is shown only when it fails (set -e would
  # otherwise stop the script with no reason given).
  # A common name may hold 64 characters at most; OpenSSL refuses a longer one, and some
  # hostnames (GitHub's macOS runners) are long. 31 for the text, at most 32 for the host.
  ca_host=$(hostname -s 2>/dev/null | cut -c1-32)
  if ! ca_err=$(openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days "$CA_DAYS" \
    -subj "/CN=ai-devcontainer egress proxy (${ca_host:-unknown host})" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "$DIR/ca.key.new" -out "$DIR/ca.crt.new" 2>&1 >/dev/null); then
    echo "Egress proxy: could not create the interception CA with $(command -v openssl) ($(openssl version 2>&1)):" >&2
    printf '%s\n' "$ca_err" | tail -n 5 >&2
    exit 1
  fi
  mv "$DIR/ca.key.new" "$DIR/ca.key"
  mv "$DIR/ca.crt.new" "$DIR/ca.crt"
  echo "Egress proxy: created this Mac's interception CA ($DIR/ca.crt)."
fi
chmod 600 "$DIR/ca.key"
chmod 644 "$DIR/ca.crt"

# --- tokens from the Keychain -----------------------------------------------------------
keychain() {
  if [ -n "${AI_DEVCONTAINER_FAKE_KEYCHAIN:-}" ]; then
    # Tests only: "service=value" lines in a file instead of the Keychain.
    sed -n "s/^$1=//p" "$AI_DEVCONTAINER_FAKE_KEYCHAIN" | head -n 1
    return 0
  fi
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
github_item=''
{
  echo '# Written by egress-credentials.sh on the Mac. Mounted into egress-proxy only.'
  if [ -f "$CONF" ]; then
    while IFS="$(printf '\t')" read -r var service scheme _hosts; do
      case "$var" in ''|\#*) continue ;; esac
      case "$var" in *[!A-Z0-9_]*) continue ;; esac
      case "$service" in *[!A-Za-z0-9._-]*|'') continue ;; esac
      [ "$scheme" = github ] && github_item="$service"
      value="$(keychain "$service")"
      if valid "$value"; then
        printf '%s=%s\n' "$var" "$value"
        found="$found $service"
      else
        missing="$missing $service"
      fi
    done < "$CONF"
  fi
} > "$OUT/credentials.env.new"
unset value
chmod 600 "$OUT/credentials.env.new"
mv "$OUT/credentials.env.new" "$OUT/credentials.env"

# --- skill config the container can read (nothing secret) -------------------------------
if [ -f "$MOUNTS" ]; then
  while IFS="$(printf '\t')" read -r name source copy placeholder; do
    case "$name" in ''|\#*) continue ;; esac
    case "$name" in *[!A-Za-z0-9._-]*) continue ;; esac
    case "$source" in \~/*) source="$HOME/${source#\~/}" ;; *) continue ;; esac
    dest="$OUT/mounts/$name"
    mkdir -p "$dest"
    chmod 755 "$dest"
    if [ "$copy" != - ]; then
      for f in $(printf '%s' "$copy" | tr ',' ' '); do
        case "$f" in *[!A-Za-z0-9._-]*|'') continue ;; esac
        if [ -f "$source/$f" ]; then cp "$source/$f" "$dest/$f"; else : > "$dest/$f"; fi
        chmod 644 "$dest/$f"
      done
    fi
    if [ "$placeholder" != - ]; then
      case "$placeholder" in *[!A-Za-z0-9._-]*|'') continue ;; esac
      printf '%s\n' "$PLACEHOLDER" > "$dest/$placeholder"
      chmod 644 "$dest/$placeholder"
    fi
  done < "$MOUNTS"
fi

echo "Egress proxy: tokens injected for:${found:- none}."
if [ -n "$missing" ]; then
  echo "Egress proxy: not in the Keychain (those services stay signed out inside):$missing."
  if [ -n "$github_item" ]; then
    case "$missing" in
      *" $github_item"*)
        echo "  GitHub: store a fine-grained token in a Mac terminal with"
        echo "    security add-generic-password -U -s $github_item -a \"\$USER\" -w"
        echo "  then reopen the container." ;;
    esac
  fi
fi
