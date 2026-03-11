# Project Analyze

Analyze this project's codebase and customize the Claude configuration.

## Instructions

Scan the following and report findings:

### Backend (Craft CMS)
1. Craft CMS version from `composer.json`
2. Installed plugins from `composer.json`
3. GraphQL schema configuration
4. Custom modules in `modules/`
5. Content types and sections (from project config YAML)
6. Asset volumes and transforms

### Frontend (Nuxt)
1. Nuxt version and modules from `package.json` / `nuxt.config.ts`
2. Component structure and naming conventions
3. Composables and their patterns
4. Tailwind configuration and custom theme
5. Available npm scripts
6. TypeScript configuration

### Integration
1. GraphQL queries and their locations
2. Environment variable usage
3. Server routes (API proxy patterns)
4. Rendering mode (SSR/SSG/ISR configuration)

Report findings and suggest updates to CLAUDE.md and rules.
