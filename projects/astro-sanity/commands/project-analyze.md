---
description: Analyze project and update Claude configuration with project-specific details
---

# Project Analyzer & Configuration Sync

Comprehensive project analysis that updates Claude Code configuration.

## Purpose

This command:
1. Scans the project to detect technologies, patterns, and configurations
2. Updates CLAUDE.md with accurate project details
3. Identifies missing agents, rules, or skills based on project needs

## Analysis Steps

### 1. Package Configuration

Read `package.json` and extract:
- Astro version
- Sanity Studio version (`sanity`, `@sanity/client`, `@sanity/image-url`)
- Dependencies (Tailwind, React, Vue, Svelte, etc.)
- Build scripts and dev commands

### 2. Sanity Configuration

Check for:
- `sanity.config.ts` — Studio configuration, plugins, schema types
- `sanity.cli.ts` — CLI configuration, project ID, dataset
- `src/sanity/schemas/` — Content type schemas
- Embedded Studio route (`src/pages/studio/`)

### 3. Project Structure

Detect project layout:
- Single repo: `src/` contains both Astro and Sanity
- Monorepo: separate `frontend/` and `studio/` directories
- Components: `src/components/` or `components/`
- Sanity schemas: `src/sanity/schemas/` or `schemas/`

### 4. Configuration Files & Framework Detection

**IMPORTANT: Detect what's actually in use, then remove what's not.**

Check for:
- `astro.config.mjs` — Astro config, integrations
- `sanity.config.ts` — Sanity Studio config
- `tsconfig.json` — TypeScript config

- **Tailwind CSS**: `tailwind.config.mjs` or `tailwind.config.js` exists?
  - If YES: Keep `.claude/rules/tailwind-css.md`
  - If NO: Remove `.claude/rules/tailwind-css.md` (not in use)

- **React**: Check `package.json` for `@astrojs/react` or `react`
  - If YES: Note React islands are available
  - If NO: Note only Astro components used

- **Portable Text**: Check for `@portabletext/react` or `@portabletext/astro`
  - If YES: Note Portable Text rendering is configured
  - If NO: Recommend adding Portable Text renderer

### 5. Clean Up Unused Files

**After detection, remove files for technologies NOT in use:**
- Delete `.claude/rules/*.md` for undetected frameworks
- Delete `.claude/agents/*.md` for irrelevant specializations
- Report what was removed to keep configuration clean

### 6. Detect Missing Components

Recommend:
- No Portable Text component found -> suggest creating one
- No `urlFor()` helper found -> suggest creating image helper
- No typegen configured -> suggest `npx sanity typegen generate`
- Missing alt text fields on image schemas -> flag accessibility issue
- No preview configuration -> suggest draft mode setup

## Sync Actions

### Update CLAUDE.md
- Replace `{{PROJECT_NAME}}` and placeholders with detected values
- Update directory structure based on actual project layout
- Update development commands from package.json
- Update detected technologies (Tailwind, React, etc.)
- Document Astro and Sanity versions
- List all Sanity content types found in schemas

### Update Sanity-Specific Details
- List all document types from `src/sanity/schemas/`
- Document GROQ query patterns found in `src/lib/sanity.ts`
- Note Studio URL (embedded vs standalone)
- Document dataset name and project ID location
