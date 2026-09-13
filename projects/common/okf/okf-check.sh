#!/usr/bin/env bash
#
# okf-check.sh — conformance and hygiene check for an Open Knowledge Format (OKF v0.2) bundle.
#
# Usage:  bash .claude/scripts/okf-check.sh [bundle-dir]     (default: .okf)
# Exit:   0 = conformant (warnings allowed), 1 = conformance errors
#
# Errors (spec conformance):
#   - a concept file (any .md except index.md / log.md) without YAML frontmatter
#   - frontmatter without a non-empty `type`
#   - log.md date headings not in `## YYYY-MM-DD` form
# Warnings (hygiene, never fail):
#   - frontmatter on a non-root index.md
#   - concepts past their `stale_after`
#   - links to bundle .md files that don't exist
#   - text that looks like a real credential (private keys, cloud/API tokens)
#
# Source of truth: claude-optimizer/projects/common/okf/okf-check.sh

set -uo pipefail

bundle="${1:-.okf}"
bundle="${bundle%/}"
if [[ ! -d "$bundle" ]]; then
  echo "No OKF bundle at $bundle"
  exit 0
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
errors=0
warnings=0
concepts=0

err()  { echo "✗ $1"; errors=$((errors + 1)); }
warn() { echo "⚠ $1"; warnings=$((warnings + 1)); }

has_frontmatter() {
  [[ "$(head -n 1 "$1")" == "---" ]] && awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$1"
}
frontmatter() { awk 'NR == 1 { next } $0 == "---" { exit } { print }' "$1"; }

while IFS= read -r file; do
  rel="${file#"$bundle"/}"

  while IFS= read -r target; do
    target="${target%%#*}"
    [[ -n "$target" ]] || continue
    case "$target" in
      http://*|https://*|mailto:*) continue ;;
      /*) resolved="$bundle$target" ;;
      *)  resolved="$(dirname "$file")/$target" ;;
    esac
    [[ -e "$resolved" ]] || warn "$rel: broken link → $target"
  done < <(grep -oE '\]\([^)[:space:]]+\.md(#[^)[:space:]]*)?\)' "$file" | sed -E 's/^\]\(//; s/\)$//')

  case "${file##*/}" in
    index.md)
      if [[ "$rel" != "index.md" && "$(head -n 1 "$file")" == "---" ]]; then
        warn "$rel: only the bundle-root index.md may carry frontmatter"
      fi
      ;;
    log.md)
      while IFS= read -r heading; do
        err "$rel:${heading%%:*}: log date headings must be '## YYYY-MM-DD'"
      done < <(grep -nE '^## ' "$file" | grep -vE '^[0-9]+:## [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$')
      ;;
    *)
      concepts=$((concepts + 1))
      if ! has_frontmatter "$file"; then
        err "$rel: missing YAML frontmatter (--- … ---)"
        continue
      fi
      fm=$(frontmatter "$file")
      if ! grep -qE '^type:[[:space:]]*[^[:space:]#]' <<< "$fm"; then
        err "$rel: frontmatter needs a non-empty 'type'"
      fi
      stale_after=$(sed -nE 's/^stale_after:[[:space:]]*["'\'']?([0-9][0-9TZ:+.-]*).*/\1/p' <<< "$fm" | head -n 1)
      if [[ -n "$stale_after" && ! "$stale_after" > "$now" ]]; then
        warn "$rel: stale since $stale_after — re-verify it or move stale_after forward"
      fi
      ;;
  esac
done < <(find "$bundle" -type f -name '*.md' | LC_ALL=C sort)

secret_pattern='-----BEGIN [A-Z ]*PRIVATE KEY-----|(AKIA|ASIA)[0-9A-Z]{16}|sk-(ant|proj)-[A-Za-z0-9_-]{20,}|sk_live_[0-9A-Za-z]{16,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}'
while IFS= read -r hit; do
  warn "${hit#"$bundle"/}: looks like a real credential — remove it and record only the variable name"
done < <(grep -rlE -e "$secret_pattern" "$bundle" 2>/dev/null)

echo "OKF bundle $bundle: $concepts concept(s), $errors error(s), $warnings warning(s)"
[[ $errors -eq 0 ]]
