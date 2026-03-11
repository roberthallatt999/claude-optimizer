---
description: Analyze project and update Claude configuration with project-specific details
---

# Project Analyzer & Configuration Sync

Comprehensive project analysis that updates Claude Code configuration for a headless EE Coilpack + Next.js project.

## Purpose

This command:
1. Scans both backend and frontend to detect technologies, patterns, and configurations
2. Updates CLAUDE.md with accurate project details
3. Identifies missing agents, rules, or skills based on project needs

## Analysis Steps

### 1. DDEV/Environment Configuration (Backend)

Read `backend/.ddev/config.yaml` and extract:
- **name**: Project name for URLs
- **docroot**: Document root path
- **php_version**: PHP version
- **database.type/version**: Database engine
- **nodejs_version**: Node.js version (if configured in DDEV)

### 2. Backend Structure (Coilpack)

Scan for:
- ExpressionEngine: `backend/system/user/templates/` or `backend/ee/system/user/templates/`
- Laravel controllers: `backend/app/Http/Controllers/Api/`
- Laravel routes: `backend/routes/api.php`
- Coilpack config: `backend/config/coilpack.php`
- Composer packages: `backend/composer.json`

### 3. Frontend Structure (Next.js)

Scan for:
- App Router: `frontend/app/` directory
- Pages Router: `frontend/pages/` directory (should not exist)
- Components: `frontend/components/`
- API client: `frontend/lib/api.ts`
- Package configuration: `frontend/package.json`

### 4. Framework & Tool Detection

**IMPORTANT: Detect what's actually in use, then remove what's not.**

Check for:
- **Tailwind CSS**: `frontend/tailwind.config.ts` or `frontend/tailwind.config.js` exists?
  - If YES: Keep `.claude/rules/tailwind-css.md`
  - If NO: Remove `.claude/rules/tailwind-css.md` (not in use)

- **GraphQL**: Check `backend/config/coilpack.php` for GraphQL enabled, or check `frontend/package.json` for graphql packages
  - If YES: Keep GraphQL-related configuration
  - If NO: Confirm REST-only API pattern

- **SCSS/Sass**: Check `frontend/package.json` for "sass"/"node-sass" OR find `.scss`/`.sass` files
  - If YES: Keep SCSS-related files
  - If NO: Remove SCSS files (not in use)

- **Sanctum**: Check `backend/composer.json` for "laravel/sanctum"
  - If YES: Confirm auth patterns in rules
  - If NO: Remove Sanctum references

### 5. Clean Up Unused Files

**After detection, remove files for technologies NOT in use:**
- Delete `.claude/rules/*.md` for undetected frameworks
- Delete `.claude/commands/*.md` for undetected technologies
- Report what was removed to keep configuration clean

### 6. Detect Missing Components

Based on analysis, recommend:
- API controllers detected but no API resource classes -> suggest creating them
- No error handling middleware -> suggest adding
- Forms detected -> confirm form handling setup
- i18n detected -> confirm bilingual configuration

## Sync Actions

### Update CLAUDE.md
- Replace `{{PROJECT_NAME}}`, `{{DDEV_NAME}}` with detected values
- Update directory structure based on actual project layout
- Update development commands from package.json scripts
- Document detected API endpoints from `routes/api.php`
- Document Next.js version and React version from `package.json`
- Update detected technologies (Tailwind, TypeScript strict mode, etc.)

### Verify API Integration
- Check that `COILPACK_API_URL` is documented
- Verify CORS configuration in `config/cors.php`
- Confirm API client pattern in `frontend/lib/api.ts`
- Check for consistent response format across endpoints

### Create Missing Files
If needed, offer to create:
- Missing agents based on detected patterns
- Missing rules for detected frameworks
- API client types based on actual API responses
