# Documentation

Complete documentation for Claude Optimizer.

## Overview

This repository provides automated Claude Code configuration deployment across **19 technology stacks** with:

- Automatic stack detection (frameworks, front-end tooling, template engines)
- Memory bank for persistent context, or an OKF `.okf/` bundle with `--okf-memory`
- A shared safety policy (deny/ask rules + a PreToolUse hook) merged into every project
- Stack-aware protected paths: secrets and dumps blocked, build noise kept out of context
- Content scanning: credentials are caught before a read, whatever the file is called
- Additive, non-destructive `--refresh` — edits are kept, backed up, and staged for review
- Token optimization and sensitive file protection rules
- 16 Superpowers workflow skills
- Optional code intelligence (codegraph, php-lsp) and a fleet runner for many projects

## Deployed Configuration

| Component | Files |
|-----------|-------|
| Claude Code | `CLAUDE.md`, `MEMORY.md` (or `.okf/`), `.claude/` |
| Permissions & safety | `.claude/settings.local.json` (stack permissions + shared safety policy), `.claude/hooks/safety-guard.sh`, `.claude/hooks/protected-paths.conf` |
| Update state | `.claude/ai-config/` (manifest, backups, pending, version) |
| VSCode | `.vscode/settings.json`, `launch.json`, `tasks.json` |

## Getting Started

- **[Installation](getting-started/installation.md)** - Install and set up the repository
- **[Quick Start](getting-started/quick-start.md)** - Deploy configurations in 5 minutes
- **[Configuration](getting-started/configuration.md)** - Understand the configuration structure

## Guides

- **[Setup Script](guides/setup-script.md)** - Comprehensive ai-config usage
- **[Memory System](guides/memory-system.md)** - Persistent context and token optimization
- **[Superpowers](guides/superpowers.md)** - Workflow skills for systematic development
- **[Conditional Deployment](guides/conditional-deployment.md)** - Technology detection and smart deployment
- **[Updating Projects](guides/updating-projects.md)** - Refresh and update existing configurations
- **[Project Policy](guides/project-policy.md)** - `ai-config.conf`: a project's committed say over its own config
- **[MCP Integration](guides/mcp-integration.md)** - Connecting Supabase, GitHub, Cloudflare, and other MCP servers
- **[Philter](guides/philter.md)** - Redact personal data before it reaches Claude; choose a policy set per codebase (opt-in)
- **[Sandbox](guides/sandbox.md)** - Optional dev container, Enclave or Claude Code sandbox: what it reaches, integrations, per-project VS Code extensions and settings, container reviews
- **[Profiles](guides/profiles.md)** - Who you are per context (work, volunteer, side work), from a private repo

## Reference

- **[Supported Stacks](reference/stacks.md)** - Complete stack details and features
- **[File Structure](reference/file-structure.md)** - Configuration file organization
- **[Commands](reference/commands.md)** - Available commands and skills
- **[Scripts](reference/scripts.md)** - Every command-line tool: fleet, guard installers, skill tools, the dev container kit, tests
- **[Environment Variables](reference/environment.md)** - Settings read from the environment

## Runbooks

- **[Dev container sandbox](runbooks/devcontainer.md)** - Set up, rebuild and verify a project's dev container
- **[Enclave sandbox](runbooks/enclave.md)** - Run a project in Eclipse Enclave with the same allow lists
- **[Claude Code sandbox](runbooks/claude-sandbox.md)** - Claude Code's own OS sandbox for Bash, and how the three compare
- **[Monthly safety check-up](runbooks/safety-checkup.md)** - Ten minutes to confirm the safeguards are still on

## Development

- **[Project Status](development/project-status.md)** - Current implementation status
- **[Contributing](development/contributing.md)** - How to contribute to this repository
