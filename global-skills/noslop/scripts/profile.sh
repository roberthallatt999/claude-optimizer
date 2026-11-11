#!/usr/bin/env bash
# profile.sh — print the active ai-config profile: who the author is in this context (work,
# volunteer, side work), as key=value lines. The noslop skill reads it before writing a page,
# and cloudflare.sh takes its default share domain from it.
#
# Profiles live outside this public repo, in a private one cloned to $AI_CONFIG_HOME
# (default ~/.config/ai-config):
#   $AI_CONFIG_HOME/profiles/<name>.conf   key = value lines (see profiles/example.conf here)
#   $AI_CONFIG_HOME/folders                 "<folder> = <profile>" lines: everything under a
#                                           folder uses that profile (longest match wins)
#   $AI_CONFIG_HOME/profile                 this machine's default profile name, one line
#
# The active profile is the first of:
#   1. $AI_CONFIG_PROFILE
#   2. "profile = <name>" under [options] in an ai-config.conf, the nearest that names one,
#      from $PWD upward
#   3. the folders map
#   4. $AI_CONFIG_HOME/profile
# With none, or a name with no file, it prints profile=none and exits 0: the caller asks.
#
# Usage: profile.sh [key]     # all lines, or just the value of one key

set -uo pipefail

HOME_DIR="${AI_CONFIG_HOME:-$HOME/.config/ai-config}"

# nearest_policy_profile — the profile named in the nearest ai-config.conf that names one.
# A project's ai-config.conf often holds only [remote]: keep looking upward past it.
nearest_policy_profile() {
  local dir="$PWD" found
  while [[ -n "$dir" ]]; do
    if [[ -f "$dir/ai-config.conf" ]]; then
      found="$(awk '/^[[:space:]]*\[/ { in_opts = ($0 ~ /^[[:space:]]*\[options\]/) ; next }
           in_opts && /^[[:space:]]*profile[[:space:]]*=/ {
             sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, ""); print; exit }' "$dir/ai-config.conf")"
      [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
    fi
    [[ "$dir" == / ]] && return 0
    dir="$(dirname "$dir")"
  done
}

# folder_profile — the folders map entry whose folder is the longest prefix of $PWD.
folder_profile() {
  [[ -f "$HOME_DIR/folders" ]] || return 0
  local here line dir prof best="" best_len=0
  here="$(pwd -P 2>/dev/null || pwd)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ "$line" == *=* ]] || continue
    dir="${line%%=*}"; prof="${line#*=}"
    dir="${dir#"${dir%%[![:space:]]*}"}"; dir="${dir%"${dir##*[![:space:]]}"}"
    prof="${prof//[[:space:]]/}"
    case "$dir" in "~"*) dir="$HOME${dir#\~}" ;; esac
    dir="${dir%/}"
    [[ -d "$dir" ]] && dir="$(cd "$dir" && pwd -P)"
    if [[ "$here" == "$dir" || "$here" == "$dir"/* ]] && [[ ${#dir} -gt $best_len ]]; then
      best="$prof"; best_len=${#dir}
    fi
  done < "$HOME_DIR/folders"
  printf '%s' "$best"
}

name="${AI_CONFIG_PROFILE:-}"
source_of="AI_CONFIG_PROFILE"
if [[ -z "$name" ]]; then
  name="$(nearest_policy_profile)"
  source_of="ai-config.conf"
fi
if [[ -z "$name" ]]; then
  name="$(folder_profile)"
  source_of="$HOME_DIR/folders"
fi
if [[ -z "$name" && -f "$HOME_DIR/profile" ]]; then
  name="$(head -1 "$HOME_DIR/profile" | tr -d '[:space:]')"
  source_of="$HOME_DIR/profile"
fi

file="$HOME_DIR/profiles/$name.conf"
if [[ -z "$name" || ! "$name" =~ ^[A-Za-z0-9._-]+$ || ! -f "$file" ]]; then
  if [[ -n "${1:-}" ]]; then exit 0; fi
  echo "profile=none"
  [[ -n "$name" ]] && echo "missing=$file"
  exit 0
fi

values() {
  awk '!/^[[:space:]]*(#|$)/ && /=/ {
         key = $0; sub(/[[:space:]]*=.*/, "", key); gsub(/^[[:space:]]+/, "", key)
         val = $0; sub(/^[^=]*=[[:space:]]*/, "", val); sub(/[[:space:]]+#.*$/, "", val); sub(/[[:space:]]+$/, "", val)
         print key "=" val }' "$file"
}

if [[ -n "${1:-}" ]]; then
  values | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
else
  echo "profile=$name"
  echo "from=$source_of"
  values
fi
