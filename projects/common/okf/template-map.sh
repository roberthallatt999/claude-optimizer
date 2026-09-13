#!/usr/bin/env bash
#
# template-map.sh — deterministic template relationship map for CMS projects, written as an
# OKF concept. No LLM calls: plain pattern matching over template source.
#
# Usage:  bash template-map.sh <project-dir>    → markdown on stdout (nothing if no templates)
#
# Covers:
#   ExpressionEngine  {embed="…"}, {layout="…"}, template partials/variables, add-on tags,
#                     {exp:channel:… channel="a|b"}           (system/user/templates)
#   Craft / Twig      {% extends|include|embed|import|from "…" %}, include("…"),
#                     .section('…') / section: '…', section → entry-template routes from
#                     config/project/sections/*.yaml            (templates/ beside ./craft)
#   Sage / Blade      @extends/@include*/@each/@component('…'), <x-component>
#                                                               (resources/views)
# Tags spanning several lines are handled (files are flattened before matching). Dynamic
# includes built from variables can't be resolved statically and are not listed.
#
# Source of truth: claude-optimizer/projects/common/okf/template-map.sh

set -uo pipefail

project="${1:?usage: template-map.sh <project-dir>}"
project="${project%/}"
TAB=$'\t'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
edges="$work/edges.tsv"   # template \t relation \t target
ids="$work/ids.txt"       # every template id found
routes="$work/routes.tsv" # section \t entry templates
: > "$edges"; : > "$ids"; : > "$routes"

emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$edges"; }

# Template id as the CMS references it: path under the root, without extensions or ".group".
template_id() {
  local rel="${2#"$1"/}" dir base
  base="${rel##*/}"
  base="${base%%.*}"
  if [[ "$rel" == */* ]]; then
    dir="${rel%/*}"
    printf '%s/%s\n' "${dir//.group/}" "$base"
  else
    printf '%s\n' "$base"
  fi
}

quoted_values() { grep -oE "[\"'][^\"']+[\"']" | tr -d "\"'"; }

scan_file() {  # <root> <file> <partials-alternation> <variables-alternation>
  local root="$1" file="$2" partials="$3" variables="$4" id flat rel target
  id=$(template_id "$root" "$file")
  echo "$id" >> "$ids"
  flat=$(tr '\r\n' '  ' < "$file")

  # Twig
  while IFS="$TAB" read -r rel target; do
    [[ -n "$target" ]] || continue
    case "$rel" in import|from) rel="import" ;; esac
    target="${target#/}"; target="${target%.twig}"; target="${target%.html}"
    emit "$id" "$rel" "$target"
  done < <(grep -oE "\{%-?[[:space:]]*(extends|include|embed|import|from)[[:space:]]+[\"'][^\"']+[\"']|\{\{-?[[:space:]]*include\([[:space:]]*[\"'][^\"']+[\"']" <<< "$flat" \
    | sed -E "s/^\{%-?[[:space:]]*([a-z]+)[[:space:]]+[\"']([^\"']+)[\"']$/\1${TAB}\2/; s/^\{\{-?[[:space:]]*include\([[:space:]]*[\"']([^\"']+)[\"']$/include${TAB}\1/")

  # Blade directives and components (dot notation → path)
  while IFS="$TAB" read -r rel target; do
    [[ -n "$target" ]] || continue
    case "$rel" in include*) rel="include" ;; esac
    emit "$id" "$rel" "${target//.//}"
  done < <(grep -oE "@(extends|include|includeIf|includeFirst|includeWhen|includeUnless|each|component)\([^'\"]*['\"][^'\"]+['\"]" <<< "$flat" \
    | sed -E "s/^@([A-Za-z]+)\([^'\"]*['\"]([^'\"]+)['\"]$/\1${TAB}\2/")
  while IFS= read -r target; do
    case "$target" in slot|slot:*|dynamic-component) continue ;; esac
    emit "$id" "component" "components/${target//.//}"
  done < <(grep -oE '<x-[a-z0-9.:-]+' <<< "$flat" | sed 's/^<x-//')

  # ExpressionEngine embeds, layouts, partials, variables, channels, add-on tags
  while IFS="$TAB" read -r rel target; do
    [[ -n "$target" ]] && emit "$id" "$rel" "${target#/}"
  done < <(grep -oE "\{(embed|layout)[[:space:]]*=[[:space:]]*[\"'][^\"']+[\"']" <<< "$flat" \
    | sed -E "s/^\{([a-z]+)[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"']$/\1${TAB}\2/")
  if [[ -n "$partials" ]]; then
    while IFS= read -r target; do emit "$id" "partial" "_partials/$target"; done \
      < <(grep -oE "\{($partials)\}" <<< "$flat" | tr -d '{}')
  fi
  if [[ -n "$variables" ]]; then
    while IFS= read -r target; do emit "$id" "variable" "_variables/$target"; done \
      < <(grep -oE "\{($variables)\}" <<< "$flat" | tr -d '{}')
  fi
  while IFS= read -r target; do
    target="${target#not }"
    [[ -n "$target" ]] && emit "$id" "channel" "$target"
  done < <(grep -oE "\{exp:channel:[a-z_]+[^}]*[[:space:]]channel[[:space:]]*=[[:space:]]*[\"'][^\"']+[\"']" <<< "$flat" \
    | sed -E "s/.*[[:space:]]channel[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"']$/\1/" | tr '|' '\n')
  while IFS= read -r target; do
    [[ "$target" == "channel" ]] || emit "$id" "addon" "$target"
  done < <(grep -oE '\{exp:[a-z0-9_]+:' <<< "$flat" | sed -E 's/^\{exp:([a-z0-9_]+):$/\1/')

  # Craft section queries
  while IFS= read -r target; do
    emit "$id" "section" "$target"
  done < <(grep -oE "\.section\([[:space:]]*(\[[^]]*\]|[\"'][^\"']+[\"'])|[{,][[:space:]]*section[[:space:]]*:[[:space:]]*(\[[^]]*\]|[\"'][^\"']+[\"'])" <<< "$flat" | quoted_values)
}

names_in() {  # alternation of template names in a directory (EE partials/variables)
  [[ -d "$1" ]] || return 0
  find "$1" -maxdepth 1 -type f | sed -E 's|.*/||; s|\..*$||' | grep -E '^[A-Za-z0-9_-]+$' | sort -u | paste -sd'|' -
}

# Template roots (vendor code and dependencies are never scanned)
{
  find "$project" -maxdepth 6 \( -name node_modules -o -name vendor -o -name .git -o -name .ddev \) -prune \
    -o -type d \( -path '*/system/user/templates' -o -path '*/resources/views' \) -print
  find "$project" -maxdepth 4 \( -name node_modules -o -name vendor -o -name .git \) -prune -o -type f -name craft -print \
    | while IFS= read -r craft; do
        [[ -d "$(dirname "$craft")/templates" ]] && echo "$(dirname "$craft")/templates"
      done
} | LC_ALL=C sort -u > "$work/roots"

while IFS= read -r root; do
  partials=$(names_in "$root/_partials")
  variables=$(names_in "$root/_variables")
  while IFS= read -r file; do
    scan_file "$root" "$file" "$partials" "$variables"
  done < <(find "$root" -type f \( -name '*.html' -o -name '*.twig' -o -name '*.blade.php' -o -name '*.xml' -o -name '*.rss' -o -name '*.atom' \) | LC_ALL=C sort)

  # Craft: section → entry template, from project config
  sections_dir="$(dirname "$root")/config/project/sections"
  if [[ -d "$sections_dir" ]]; then
    for yaml in "$sections_dir"/*.yaml; do
      [[ -f "$yaml" ]] || continue
      handle=$(sed -nE 's/^handle:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "$yaml" | head -n 1)
      templates=$(sed -nE 's/^[[:space:]]+template:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' "$yaml" | grep -v '^null$' | LC_ALL=C sort -u | paste -sd',' - | sed 's/,/, /g')
      [[ -n "$handle" && -n "$templates" ]] && printf '%s\t%s\n' "$handle" "$templates" >> "$routes"
    done
  fi
done < "$work/roots"

LC_ALL=C sort -u "$edges" | awk -F'\t' '$1 != $3' > "$work/edges.sorted"
LC_ALL=C sort -u "$ids" > "$work/ids.sorted"

if [[ ! -s "$work/edges.sorted" && ! -s "$routes" ]]; then
  exit 0
fi

template_count=$(wc -l < "$work/ids.sorted" | tr -d ' ')
linked_count=$(cut -f1 "$work/edges.sorted" | LC_ALL=C sort -u | wc -l | tr -d ' ')

cat <<EOF
---
type: Template Map
title: Template map
description: Generated map of which templates extend, include, or embed which, and the data (channels, sections, add-ons) each uses.
tags: [templates, generated]
generated: { by: "process:ai-config/template-map", at: "__GENERATED_AT__" }
---

# About

Generated by ai-config from template source on every \`--refresh\` — pattern matching, no LLM.
Check it before grepping template folders for "what renders X" or "what includes Y". It misses
includes built from variables and can lag behind edits made since the last refresh. \`?\` marks
a target with no matching template file (plugin-provided, dynamic, or broken). Don't edit this
file; a refresh regenerates it.

Scanned ${template_count} template(s); ${linked_count} have relationships or data.

# Templates

| Template | Uses | Data |
|---|---|---|
EOF

awk -F'\t' -v idsfile="$work/ids.sorted" '
  BEGIN { while ((getline line < idsfile) > 0) known[line] = 1 }
  function flush() {
    if (cur == "") return
    printf "| `%s` | %s | %s |\n", cur, (uses == "" ? "—" : uses), (data == "" ? "—" : data)
  }
  {
    if ($1 != cur) { flush(); cur = $1; uses = ""; data = ""; drel = "" }
    if ($2 == "channel" || $2 == "section" || $2 == "addon") {
      label = ($2 == "addon" ? "add-ons" : $2 "s")
      if ($2 != drel) { data = data (data == "" ? "" : " · ") label ": " $3; drel = $2 }
      else data = data ", " $3
    } else {
      uses = uses (uses == "" ? "" : "; ") $2 " `" $3 "`" (($3 in known) ? "" : " ?")
    }
  }
  END { flush() }
' "$work/edges.sorted"

if awk -F'\t' '$2 != "channel" && $2 != "section" && $2 != "addon"' "$work/edges.sorted" | grep -q .; then
  printf '\n# Included by\n\n'
  awk -F'\t' '$2 != "channel" && $2 != "section" && $2 != "addon" { print $3 "\t" $1 }' "$work/edges.sorted" \
    | LC_ALL=C sort -u \
    | awk -F'\t' -v idsfile="$work/ids.sorted" '
        BEGIN { while ((getline line < idsfile) > 0) known[line] = 1 }
        function out() {
          if (cur == "") return
          printf "- `%s`%s ← %s%s\n", cur, ((cur in known) ? "" : " ?"), list, (n > 15 ? " (+" (n - 15) " more)" : "")
        }
        {
          if ($1 != cur) { out(); cur = $1; n = 0; list = "" }
          if (n < 15) list = list (n ? ", " : "") "`" $2 "`"
          n++
        }
        END { out() }
      '
fi

if [[ -s "$routes" ]]; then
  printf '\n# Section routes\n\n| Section | Entry template |\n|---|---|\n'
  LC_ALL=C sort -u "$routes" | awk -F'\t' '{ printf "| `%s` | `%s` |\n", $1, $2 }'
fi
