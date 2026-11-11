#!/usr/bin/env bash
#
# vendor-skills.sh
# Fetch the third-party skills listed in vendor/skills.conf at their pinned commits, apply
# vendor/patches/<name>.patch, and record the source in <skill>/upstream/SOURCE.
#
# Usage:
#   scripts/vendor-skills.sh --list                 # name, tier, repo, commit for every skill
#   scripts/vendor-skills.sh --fetch [NAME...]      # rebuild the named skills (default: all)
#   scripts/vendor-skills.sh --bump NAME [REF]      # pin NAME's repo(s) to REF (default: the
#                                                   # default branch), then rebuild NAME
#
# Neither --fetch nor --bump commits. Review `git diff` (and the upstream changelog) first.
# A patch that no longer applies stops the run and leaves the old copy in place.
#
# Exit codes:
#   0  done
#   1  fetch failed, unknown skill, or a patch didn't apply
#   2  usage error

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${VENDOR_SKILLS_CONF:-$ROOT/vendor/skills.conf}"
PATCHES="${VENDOR_SKILLS_PATCHES:-$ROOT/vendor/patches}"
OUT_ROOT="${VENDOR_SKILLS_OUT:-$ROOT}"

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# rows — the config's data lines, comments and blanks dropped, columns normalised to one space.
rows() { awk '!/^[[:space:]]*(#|$)/ { $1 = $1; print }' "$CONF"; }

skill_names() { rows | awk '{ print $1 }' | awk '!seen[$0]++'; }

skill_dir_for_tier() {
  case "$1" in
    global)  echo "$OUT_ROOT/global-skills" ;;
    design*) echo "$OUT_ROOT/design-skills" ;;
    *) echo "Unknown tier '$1' in $CONF" >&2; exit 1 ;;
  esac
}

# fetch_commit <repo> <commit> <dir> — a shallow checkout of exactly that commit.
fetch_commit() {
  git -C "$3" init --quiet
  git -C "$3" fetch --quiet --depth 1 "$1" "$2" \
    || { echo "Could not fetch $1 at $2" >&2; return 1; }
  git -C "$3" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
}

build_skill() {
  local name="$1" work stage tier dir row repo commit src dest checkout n=0 lic
  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN
  stage="$work/out/$name"
  mkdir -p "$stage/upstream"
  : > "$stage/upstream/SOURCE"
  tier=""
  while IFS= read -r row; do
    # shellcheck disable=SC2086
    set -- $row
    [[ "$1" == "$name" ]] || continue
    tier="$2" repo="$3" commit="$4" src="$5" dest="${6:-}"
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "$name: commit must be a full SHA" >&2; return 1; }
    n=$((n + 1))
    checkout="$work/src$n"
    mkdir -p "$checkout"
    fetch_commit "$repo" "$commit" "$checkout"
    if [[ -d "$checkout/$src" ]]; then
      mkdir -p "$stage/${dest:-.}"
      (cd "$checkout/$src" && find . -type f ! -name '.DS_Store' ! -path './bin/*' ! -path './scripts/bin/*' -print0 \
        | while IFS= read -r -d '' f; do mkdir -p "$stage/${dest:-.}/$(dirname "$f")"; cp "$f" "$stage/${dest:-.}/$f"; done)
    elif [[ -f "$checkout/$src" ]]; then
      dest="${dest:-SKILL.md}"
      mkdir -p "$(dirname "$stage/$dest")"
      cp "$checkout/$src" "$stage/$dest"
    else
      echo "$name: $repo has no $src at $commit" >&2; return 1
    fi
    lic=""
    for f in LICENSE LICENSE.md LICENSE.txt COPYING; do
      if [[ -f "$checkout/$f" ]]; then lic="$f"; break; fi
    done
    if [[ -n "$lic" ]]; then
      if [[ $n -eq 1 ]]; then cp "$checkout/$lic" "$stage/upstream/LICENSE"
      else cp "$checkout/$lic" "$stage/upstream/LICENSE.$(basename "$repo")"; fi
    fi
    {
      [[ $n -gt 1 ]] && echo ""
      echo "repo=$repo"
      echo "commit=$commit"
      echo "path=$src${dest:+ → $dest}"
      echo "license=${lic:-none (no licence file in the repo; check its README)}"
    } >> "$stage/upstream/SOURCE"
  done < <(rows)
  [[ $n -gt 0 ]] || { echo "Unknown skill: $name" >&2; return 1; }

  # Claude Code would load a nested SKILL.md as a second skill.
  if find "$stage" -mindepth 2 -name SKILL.md | grep -q .; then
    echo "$name: upstream nests another SKILL.md; check its layout by hand" >&2; return 1
  fi
  if [[ -f "$PATCHES/$name.patch" ]]; then
    patch --quiet --forward -p1 -d "$stage" < "$PATCHES/$name.patch" \
      || { echo "$name: $PATCHES/$name.patch no longer applies; refresh it by hand" >&2; return 1; }
    find "$stage" \( -name '*.orig' -o -name '*.rej' \) -delete
    echo "patch=vendor/patches/$name.patch" >> "$stage/upstream/SOURCE"
  fi
  head -1 "$stage/SKILL.md" | grep -qx -- '---' || { echo "$name: SKILL.md has no frontmatter" >&2; return 1; }

  dir="$(skill_dir_for_tier "$tier")/$name"
  mkdir -p "$(dirname "$dir")"
  rm -rf "$dir"
  mv "$stage" "$dir"
  echo "Built $name (${tier}) → ${dir#"$OUT_ROOT"/}"
}

bump() {
  local name="$1" ref="${2:-HEAD}" repos repo sha tmp
  repos=$(rows | awk -v n="$name" '$1 == n { print $3 }' | awk '!seen[$0]++')
  [[ -n "$repos" ]] || { echo "Unknown skill: $name" >&2; exit 1; }
  tmp="$(mktemp)"
  cp "$CONF" "$tmp"
  while IFS= read -r repo; do
    sha=$(git ls-remote "$repo" "$ref" | awk 'NR == 1 { print $1 }')
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { rm -f "$tmp"; echo "Could not resolve $ref in $repo" >&2; exit 1; }
    awk -v n="$name" -v r="$repo" -v s="$sha" '
      !/^[[:space:]]*(#|$)/ { split($0, f, /[[:space:]]+/); if (f[1] == n && f[3] == r) { sub(/[0-9a-f]{40}/, s) } }
      { print }' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"
    echo "$name: $repo → $sha"
  done <<< "$repos"
  mv "$tmp" "$CONF"
  build_skill "$name"
}

case "${1:-}" in
  --list)  rows | awk '{ printf "%-24s %-24s %s %s\n", $1, $2, $3, substr($4, 1, 7) }' ;;
  --fetch)
    shift
    if [[ $# -eq 0 ]]; then
      names=()
      while IFS= read -r n; do names+=("$n"); done < <(skill_names)
      set -- "${names[@]}"
    fi
    for n in "$@"; do build_skill "$n"; done ;;
  --bump)  [[ -n "${2:-}" ]] || usage; bump "$2" "${3:-}" ;;
  *) usage ;;
esac
