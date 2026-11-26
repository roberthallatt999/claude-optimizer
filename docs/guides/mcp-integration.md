# Connect outside services (MCP)

MCP lets Claude use another service directly: GitHub issues, a database, Cloudflare, your analytics. You add a
service once, and Claude gets tools for it.

ai-config doesn't add services for you. You add them with Claude Code's own `claude mcp` command, and ai-config's
safety guard watches what Claude does with them.

## Add a service

There are two kinds.

**A service on the web** (you give it an address). For example, Cloudflare:

```bash
claude mcp add --transport http cloudflare https://mcp.cloudflare.com/mcp
```

**A program that runs on your computer.** Everything after `--` is the command that starts it:

```bash
claude mcp add my-service -- npx -y <package-name>
```

Then, inside Claude Code, type `/mcp` to see it, sign in if it asks, and check it's connected.

## Who gets the service

Add `--scope` to the `claude mcp add` command:

| Scope | Who can use it | Where it's saved |
|---|---|---|
| `--scope local` (the default) | You, in this project only | Your own Claude settings |
| `--scope project` | Everyone who clones the repo | `.mcp.json` in the project, which you commit |
| `--scope user` | You, in every project | Your own Claude settings |

ai-config turns off automatic start-up for project services (`enableAllProjectMcpServers: false`). So a service
in someone's `.mcp.json` doesn't start until you approve it.

## Keep tokens out of files

Never type a token into `.mcp.json` or any file you commit. If a service needs a key, prefer one that signs you
in through the browser (`/mcp` handles this). If you must use a key, give it to the one server with `--env`,
in your own Terminal rather than through Claude:

```bash
claude mcp add --env API_KEY=<your-key> my-service -- npx -y <package-name>
```

Use read-only access while exploring, and the smallest permissions that do the job.

## Manage services

See what's added:

```bash
claude mcp list
```

Remove one:

```bash
claude mcp remove my-service
```

## What the safety guard does with services

- A tool that pushes, merges, deploys, sends, buys, deletes or writes **asks you first**.
- A tool that only reads (list, get, search, a `SELECT` query) goes ahead.
- A tool that tries to read a secret file, such as `.env`, is **blocked**.
- A write that contains a password or key is **blocked**.

## Up-to-date library documentation (Context7)

Context7 gives Claude current docs for React, Tailwind and hundreds of other libraries. Install it once, inside
Claude Code, and it works in every project:

```text
/plugin install context7@claude-plugins-official
```

## Code search for JavaScript projects (codegraph)

[codegraph](https://github.com/colbymchenry/codegraph) builds a local index so Claude can answer "where is this
used?" in one step instead of many file reads. ai-config doesn't install it, but connects it when it's there:

1. Install codegraph, then run `codegraph init` in the project.
2. Run `ai-config --refresh --project=.`

ai-config then registers it for this project and adds a short section about it to `CLAUDE.md`. It's for
JavaScript stacks only, because codegraph can't read Twig, Blade or ExpressionEngine templates.

PHP sites get the `php-lsp` plugin instead (go-to-definition and error checking for PHP), when Intelephense is
installed. To install Intelephense and turn the plugin on:

```bash
ai-config --refresh --install-deps --project=.
```
