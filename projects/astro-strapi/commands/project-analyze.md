---
description: Analyze project and update Claude configuration with project-specific details
---

# Project Analyzer & Configuration Sync

Comprehensive project analysis that updates Claude Code configuration for Astro + Strapi projects.

## Purpose

This command:
1. Scans the project to detect technologies, patterns, and configurations
2. Updates CLAUDE.md with accurate project details
3. Identifies missing agents, rules, or skills based on project needs

## Analysis Steps

### 1. Package Configuration

**Backend (Strapi):**
Read `backend/package.json` and extract:
- Strapi version
- Database client (SQLite, PostgreSQL)
- Installed plugins (GraphQL, i18n, etc.)
- Custom dependencies

**Frontend (Astro):**
Read `frontend/package.json` and extract:
- Astro version
- Installed integrations (React, Vue, Svelte, Tailwind, etc.)
- Build scripts
- TypeScript version

### 2. Project Structure

Detect architecture:
- **Monorepo**: Root `package.json` with workspaces
- **Separate repos**: Distinct `backend/` and `frontend/` directories
- **Content Types**: Scan `backend/src/api/` for content type directories
- **Pages**: Scan `frontend/src/pages/` for route structure
- **Islands**: Scan for `client:` directives in `.astro` files

### 3. Configuration Files & Framework Detection

**IMPORTANT: Detect what's actually in use, then remove what's not.**

Check for:
- `frontend/astro.config.mjs` — Astro integrations
- `frontend/tsconfig.json` — TypeScript config
- `backend/config/database.ts` — Database client

- **Tailwind CSS**: `frontend/tailwind.config.mjs` exists?
  - If YES: Keep `.claude/rules/tailwind-css.md`
  - If NO: Remove `.claude/rules/tailwind-css.md` (not in use)

- **React Islands**: Check `frontend/package.json` for `@astrojs/react`
  - If YES: Note React is available for islands
  - If NO: Note only Astro components are in use

- **Vue/Svelte Islands**: Check for `@astrojs/vue` or `@astrojs/svelte`
  - If found: Note available island frameworks

- **GraphQL**: Check `backend/package.json` for `@strapi/plugin-graphql`
  - If YES: Note GraphQL is available alongside REST
  - If NO: REST API only

### 4. Strapi Content Type Inventory

Scan `backend/src/api/` and list:
- All collection types with their fields
- All single types
- All components in `backend/src/components/`
- Custom controllers and services
- Custom routes

### 5. Clean Up Unused Files

**After detection, remove files for technologies NOT in use:**
- Delete `.claude/rules/*.md` for undetected frameworks
- Delete `.claude/agents/*.md` for irrelevant specialists
- Report what was removed to keep configuration clean

### 6. Detect Missing Components

Recommend:
- Complex island components detected → suggest appropriate framework agent
- No security review done → suggest security-expert audit
- No performance audit → suggest performance-auditor review
- Missing TypeScript types for Strapi responses → suggest type generation

## Sync Actions

### Update CLAUDE.md
- Replace `{{PROJECT_NAME}}` and placeholders with detected values
- Update directory structure based on actual project layout
- Update development commands from package.json scripts
- Document detected Strapi content types
- Document Astro integrations in use
- Update Strapi version and Astro version
