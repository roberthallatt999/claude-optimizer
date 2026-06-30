# Libraries Reference Index

Framework, CSS, and tooling references for local Claude library context.

## Frontend Frameworks
- [react.md](react.md)
- [vue.md](vue.md)
- [angular.md](angular.md)
- [svelte.md](svelte.md) — covers Svelte 4 + Svelte 5 Runes + SvelteKit patterns
- [nextjs.md](nextjs.md)
- [nuxt.md](nuxt.md)

## Language / Type System
- [typescript.md](typescript.md) — strict mode, utility types, generics, branded types

## Styling
- [tailwind.md](tailwind.md)
- [bootstrap.md](bootstrap.md)
- [bulma.md](bulma.md)
- [foundation.md](foundation.md)
- [scss.md](scss.md)
- [html5.md](html5.md)

## Component Libraries
- [shadcn-ui.md](shadcn-ui.md) — shadcn/ui (Radix-based, copy-into-project)
- [material-ui.md](material-ui.md)
- [alpinejs.md](alpinejs.md)

## Animation
- [framer-motion.md](framer-motion.md) — Framer Motion / Motion (v11+)

## State Management
- [zustand.md](zustand.md) — React global state
- [pinia.md](pinia.md) — Vue/Nuxt global state
- [vanilla-js.md](vanilla-js.md)

## Data Fetching & Validation
- [tanstack-query.md](tanstack-query.md) — React Query v5
- [zod.md](zod.md) — schema validation, TypeScript type inference

## API Layer
- [trpc.md](trpc.md) — tRPC v10/v11 (end-to-end typesafe APIs)

## CMS
- [tinacms.md](tinacms.md) — Tina CMS (Git-based, MDX, live editing, Astro/Next.js)

## Database & Backend
- [prisma.md](prisma.md) — Prisma ORM
- [supabase.md](supabase.md) — Supabase JS client, Auth, Storage, Realtime

## Testing
- [vitest.md](vitest.md) — unit testing (Jest-compatible, Vite-native)
- [playwright.md](playwright.md) — E2E testing

## Legacy
- [jquery.md](jquery.md) — use only for legacy codebases

---

## Notes

- The setup script copies files from `libraries/` into each project's `.claude/libraries/`,
  making them available to Claude via `@.claude/libraries/<name>.md` imports in CLAUDE.md.
- Add a new library reference by creating `libraries/<name>.md` following existing format:
  - Opening version-check note
  - Core patterns with code examples
  - Common gotchas under "Avoid" section
- Update this README when adding new files.
