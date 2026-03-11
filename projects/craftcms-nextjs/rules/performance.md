# Performance Rules

## Backend (Craft CMS)
- Configure GraphQL query caching in production
- Use asset transforms — never serve original images
- Enable Redis/Memcached for object caching in production
- Set up webhook notifications for content changes (for ISR/cache invalidation)

## Frontend (Next.js)
- Use `next/image` for all images — never use raw `<img>` tags
- Use Server Components by default for zero client-side JS
- Lazy-load client components below the fold with `dynamic()`
- Leverage Next.js automatic code splitting per route
- Use Suspense boundaries for streaming SSR
- Optimize fonts with `next/font`

## GraphQL
- Request only the fields you need
- Use pagination (limit/offset) for large datasets
- Batch related queries where possible
- Use ISR (`next: { revalidate: N }`) for content pages

## Data Fetching
- Use `{ cache: 'force-cache' }` for static content (default)
- Use `{ next: { revalidate: 3600 } }` for ISR pages
- Use `{ cache: 'no-store' }` only for truly dynamic data
- Leverage automatic request deduplication in Server Components

## General
- Minimize third-party scripts
- Preload critical resources
- Use Web Vitals (LCP, INP, CLS) as performance targets
- Configure `next.config.js` image domains for Craft CMS asset URLs
