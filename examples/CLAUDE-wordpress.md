# Project: [Project Name]

## Stack
@~/.claude/stacks/wordpress-roots.md
@./.claude/libraries/foundation.md
@./.claude/libraries/scss.md
@./.claude/libraries/html5.md

## Local Development
- Environment: Local by Flywheel / Valet
- URL: https://projectname.test
- Theme directory: web/app/themes/theme-name

## Commands (from theme directory)
- `npm run dev` — Development build with HMR
- `npm run build` — Production build
- `composer install` — Install PHP dependencies (from project root)

## WP-CLI
- `wp cache flush` — Clear cache
- `wp acorn optimize` — Optimize Acorn/Sage
- `wp search-replace 'old.com' 'new.com'` — Update URLs

## Project-Specific Notes
- ACF Pro for custom fields (acf-json/ for version control)
- Custom Gutenberg blocks in app/Blocks
- View composers in app/View/Composers

## Content Types
- Pages (native)
- Posts (native)
- Team (CPT: team)
- Projects (CPT: project)

## Required Plugins
- Advanced Custom Fields Pro
- Gravity Forms
- WP Migrate DB Pro
- Yoast SEO
