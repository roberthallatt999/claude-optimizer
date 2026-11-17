#!/bin/bash
# Connects this container's Claude Code to Philter on the Mac (philter-guard), so the
# philter-scrub mod redacts prompts and tool output here as it does on the Mac.
# Runs at every start as the container user. Idempotent, and never fails the start: a
# problem prints a warning, and the mod (once installed) blocks rather than send unredacted.
# The MCP server and mod live in CLAUDE_CONFIG_DIR, a volume, so they survive rebuilds.

PHILTER_URL="http://host.docker.internal:27840/mcp"
MARKETPLACE_REPO="roberthallatt999/philter-guard"
PLUGIN="philter-scrub@philter-guard"

warn() { echo "WARNING (philter): $*"; }

if ! command -v claude >/dev/null 2>&1; then
  warn "claude not found; skipped."
  exit 0
fi

# 1. The MCP server the mod calls. Re-added when it points anywhere else (a copy from the Mac
#    would say 127.0.0.1, which is this container, not the Mac).
current=$(claude mcp get philter </dev/null 2>/dev/null | awk '$1 == "URL:" {print $2}')
if [ "$current" != "$PHILTER_URL" ]; then
  [ -n "$current" ] && claude mcp remove philter -s user </dev/null >/dev/null 2>&1
  if claude mcp add --transport http --scope user philter "$PHILTER_URL" </dev/null >/dev/null 2>&1; then
    echo "Philter MCP server registered: $PHILTER_URL"
  else
    warn "could not register the philter MCP server."
  fi
fi

# 2. The mod. Installed once; updates are deliberate (`claude plugin marketplace update
#    philter-guard` inside), so a push to the repo doesn't change what runs here unseen.
if ! claude plugin list --json </dev/null 2>/dev/null | grep -q "\"$PLUGIN\""; then
  claude plugin marketplace add "$MARKETPLACE_REPO" </dev/null >/dev/null 2>&1
  if claude plugin install "$PLUGIN" --scope user </dev/null >/dev/null 2>&1; then
    echo "Philter mod installed: $PLUGIN"
  else
    warn "could not install $PLUGIN (is github.com reachable?)."
  fi
fi

# 3. Report, without failing: Philter runs on the Mac and may simply be stopped.
if curl -s -o /dev/null -m 3 --noproxy '*' "${PHILTER_URL%/mcp}/health"; then
  echo "Philter reachable at ${PHILTER_URL%/mcp}."
else
  warn "Philter isn't answering at ${PHILTER_URL%/mcp}. Start it on the Mac (cd ~/docker/philter-mcp && docker compose up -d); until then the mod blocks prompts and tool output."
fi
exit 0
