# MCP Integration Guide

Connect Claude Code to third-party services and databases via MCP (Model Context Protocol) servers. MCP gives Claude direct tool access to external systems without copy-pasting data.

## What MCP Enables

With MCP, Claude can:
- Query your Supabase/PostgreSQL database directly
- Read/write GitHub issues and PRs
- Search Linear tickets
- Read Slack messages
- Browse Figma designs
- Run Cloudflare D1 queries
- And much more (9,000+ integrations via Zapier MCP)

---

## Setting Up MCP in a Project

MCP servers are configured per-user (global) or per-project in `settings.json`.

### Global (All Projects)
Located at `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@mcp-package/server"],
      "env": {
        "API_KEY": "${MCP_SERVER_API_KEY}"
      }
    }
  }
}
```

### Project-Specific
Located at `<project>/.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase@latest", "--read-only"],
      "env": {
        "SUPABASE_URL": "${SUPABASE_URL}",
        "SUPABASE_SERVICE_ROLE_KEY": "${SUPABASE_SERVICE_ROLE_KEY}"
      }
    }
  },
  "enableAllProjectMcpServers": true
}
```

---

## Common MCP Servers

### Supabase

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase@latest"],
      "env": {
        "SUPABASE_URL": "${SUPABASE_URL}",
        "SUPABASE_SERVICE_ROLE_KEY": "${SUPABASE_SERVICE_ROLE_KEY}"
      }
    }
  }
}
```

**Enables:** `list_tables`, `execute_sql`, `get_schema`, `create_migration`

**Security:** Add `--read-only` flag to prevent writes during exploration.

---

### GitHub

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

**Enables:** `search_issues`, `create_issue`, `get_pull_request`, `list_commits`, `create_review`

---

### Cloudflare

```json
{
  "mcpServers": {
    "cloudflare": {
      "command": "npx",
      "args": ["-y", "@cloudflare/mcp-server-cloudflare"],
      "env": {
        "CLOUDFLARE_API_TOKEN": "${CLOUDFLARE_API_TOKEN}",
        "CLOUDFLARE_ACCOUNT_ID": "${CLOUDFLARE_ACCOUNT_ID}"
      }
    }
  }
}
```

**Enables:** D1 queries, KV operations, R2 bucket management, Workers deployment

---

### PostgreSQL / MySQL

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}"
      }
    }
  }
}
```

---

### Context7 (Documentation)

Already configured in this template system. Context7 gives Claude current library docs (React, Next.js, Tailwind, etc.):

```json
{
  "enabledMcpjsonServers": ["context7"]
}
```

Usage: Claude will automatically fetch current docs when working with supported libraries.

---

### Filesystem

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/path/to/allowed/directory"
      ]
    }
  }
}
```

---

## Environment Variable Best Practices

**Never hardcode secrets in `settings.json`.**

Use `${ENV_VAR}` syntax in MCP server configs — Claude Code reads from the shell environment.

Set environment variables in your shell profile or `.env` file (sourced before launching Claude):

```bash
# ~/.zshrc or ~/.bashrc
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
export GITHUB_TOKEN="ghp_your_token"
```

Or use a `.env` file with `direnv` or `dotenv` to auto-load per project.

---

## Adding MCP to This Config Template

When adding a new MCP server to a project template:

1. Add the server config to `projects/<stack>/settings.local.json`
2. Document it in `MEMORY.md` under **MCP Servers** table
3. Add the required env variables to `MEMORY.md` under **Environment Variables**
4. Note any read-only vs. read-write access requirements

### Template for settings.local.json with MCP

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(git:*)"
    ]
  },
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase@latest", "--read-only"],
      "env": {
        "SUPABASE_URL": "${SUPABASE_URL}",
        "SUPABASE_SERVICE_ROLE_KEY": "${SUPABASE_SERVICE_ROLE_KEY}"
      }
    }
  },
  "enableAllProjectMcpServers": true,
  "enabledMcpjsonServers": ["context7"]
}
```

---

## Zapier MCP (9,000+ Integrations)

For services without a dedicated MCP server, Zapier MCP provides broad coverage:

```json
{
  "mcpServers": {
    "zapier": {
      "command": "npx",
      "args": ["-y", "zapier-mcp"],
      "env": {
        "ZAPIER_MCP_API_KEY": "${ZAPIER_MCP_API_KEY}"
      }
    }
  }
}
```

Enables connection to Slack, Notion, Airtable, Google Sheets, Salesforce, HubSpot, and 9,000+ more.

---

## Discovering Available MCP Tools

Once an MCP server is connected, Claude can use `ToolSearch` to discover its capabilities. You can also tell Claude: "What tools are available from the [server-name] MCP server?"

---

## Security Checklist

Before deploying MCP in a project:

- [ ] All secrets use `${ENV_VAR}` syntax, not hardcoded values
- [ ] `settings.local.json` is in `.gitignore`
- [ ] Database MCP uses `--read-only` during exploration/dev; write access requires approval
- [ ] Service role keys are never committed
- [ ] Each service uses the minimum required permissions/scopes
