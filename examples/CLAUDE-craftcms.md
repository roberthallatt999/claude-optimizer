# Project: [Project Name]

## Stack
@~/.claude/stacks/craftcms.md
@./.claude/libraries/tailwind.md
@./.claude/libraries/alpinejs.md
@./.claude/libraries/html5.md

## Local Development
- Environment: DDEV
- URL: https://projectname.ddev.site
- `ddev start` — Start containers
- `ddev ssh` — Shell into container
- `npm run dev` — Vite dev server with HMR
- `npm run build` — Production build

## Deployment
- `./craft migrate/all` — Run migrations
- `./craft project-config/apply` — Apply config changes
- `./craft clear-caches/all` — Clear caches

## Project-Specific Notes
- Image transforms defined in config/image-transforms.php
- Custom module in modules/sitemodule
- Forms handled by Freeform plugin
- SEO managed by SEOmatic

## Content Structure
- Homepage: Single (homepage)
- Pages: Structure (pages)
- News: Channel (news)
- Team: Channel (team)

## Third-Party Services
- Imgix for image CDN
- Sendgrid for transactional email
