#!/usr/bin/env bash
#
# link-global-skills.sh
# Link every global-skills/<name>/ in this repo, and every skill in the private profiles repo
# ($AI_CONFIG_HOME/skills/<name>/, default ~/.config/ai-config), into ~/.claude/skills/<name>.
# The links are symlinks, so a git pull updates the skills. Sourced by install.sh and setup-project.sh, so
# every ai-config run links a skill added to the repo since the last install.
#
# Functions (bash 3.2 safe, no `set -e` traps):
#   link_global_skills <repo_dir> <claude_dir> [dry_run] [repoint]
#     Links missing skills (and replaces broken links). With repoint=true (install.sh), a link
#     to another checkout is moved to this one; setup-project.sh leaves it, so a test run from
#     a temporary worktree can't steal the links. A real directory with the same name is left
#     alone and reported. Prints one line per change; silent when current.
#   global_skills_unlinked <repo_dir> <claude_dir>
#     Prints the name of each repo skill that ~/.claude/skills/<name> doesn't link to.
#
# Standalone: scripts/link-global-skills.sh [--dry-run]

_gs_green=$'\033[0;32m'; _gs_yellow=$'\033[1;33m'; _gs_nc=$'\033[0m'

# True when $1 is a symlink that resolves to directory $2.
_gs_links_to() {
  [[ -L "$1" ]] || return 1
  [[ "$(cd "$1" 2>/dev/null && pwd -P)" == "$(cd "$2" 2>/dev/null && pwd -P)" ]]
}

# _gs_sources <repo> — one skill folder per line: the repo's global skills, then private ones.
# A private skill with the same name as a repo skill is skipped (the pinned copy wins).
_gs_sources() {
  local root d seen=" "
  for root in "$1/global-skills" "${AI_CONFIG_HOME:-$HOME/.config/ai-config}/skills"; do
    [[ -d "$root" ]] || continue
    for d in "$root"/*/; do
      [[ -f "${d}SKILL.md" ]] || continue
      case "$seen" in *" $(basename "$d") "*) continue ;; esac
      seen+="$(basename "$d") "
      echo "${d%/}"
    done
  done
}

link_global_skills() {
  local repo="$1" claude_dir="$2" dry="${3:-false}" repoint="${4:-false}" skill_dir name link srcs
  srcs="$(_gs_sources "$repo")"
  [[ -n "$srcs" ]] || return 0
  [[ "$dry" == true ]] || mkdir -p "$claude_dir/skills"
  while IFS= read -r skill_dir; do
    name="$(basename "$skill_dir")"
    link="$claude_dir/skills/$name"
    if _gs_links_to "$link" "$skill_dir"; then
      continue
    elif [[ ! -e "$link" ]] || [[ -L "$link" && "$repoint" == true ]]; then
      if [[ "$dry" == true ]]; then
        echo -e "  ${_gs_yellow}[DRY-RUN]${_gs_nc} Link global skill $name → ~/.claude/skills/$name"
      else
        ln -sfn "$skill_dir" "$link"
        echo -e "  ${_gs_green}✓${_gs_nc} Linked global skill $name (~/.claude/skills/$name)"
      fi
    elif [[ -L "$link" ]]; then
      echo -e "  ${_gs_yellow}○${_gs_nc} ~/.claude/skills/$name links to another checkout; run install.sh to point it here"
    else
      echo -e "  ${_gs_yellow}○${_gs_nc} Left ~/.claude/skills/$name alone: it isn't a link to this repo." \
        "Move it aside and rerun to use the copy in ${skill_dir%/*}/$name/"
    fi
  done <<< "$srcs"
  return 0
}

global_skills_unlinked() {
  local repo="$1" claude_dir="$2" skill_dir
  while IFS= read -r skill_dir; do
    [[ -n "$skill_dir" ]] || continue
    _gs_links_to "$claude_dir/skills/$(basename "$skill_dir")" "$skill_dir" || basename "$skill_dir"
  done <<< "$(_gs_sources "$repo")"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _gs_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  _gs_dry=false
  [[ "${1:-}" == "--dry-run" ]] && _gs_dry=true
  link_global_skills "$_gs_repo" "${AI_CONFIG_CLAUDE_DIR:-$HOME/.claude}" "$_gs_dry" true
fi
