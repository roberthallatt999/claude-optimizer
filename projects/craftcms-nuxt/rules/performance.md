# Performance Rules

## Backend (Craft CMS)
- Use `{% cache %}` tags for expensive Twig sections (if any templates exist)
- Configure GraphQL query caching in production
- Use asset transforms — never serve original images
- Enable Redis/Memcached for object caching in production

## Frontend (Nuxt)
- Use `<NuxtImg>` or `<NuxtPicture>` for optimized images
- Use `useFetch` with caching options for API calls
- Lazy-load components below the fold with `<LazyComponent />`
- Use `defineAsyncComponent` for heavy components
- Leverage Nuxt's built-in code splitting (automatic per-page)
- Use `useNuxtData` to share cached data between components

## GraphQL
- Request only the fields you need
- Use pagination (limit/offset) for large datasets
- Batch related queries where possible
- Use ISR (Incremental Static Regeneration) for content pages

## General
- Minimize third-party scripts
- Use `loading="lazy"` for images below the fold
- Preload critical resources with `useHead({ link: [...] })`
- Use Web Vitals (LCP, FID, CLS) as performance targets
