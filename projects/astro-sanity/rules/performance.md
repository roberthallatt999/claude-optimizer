# Performance Optimization for Astro + Sanity

These rules MUST be followed for optimal performance in Astro + Sanity projects.

## Static Site Generation (SSG)

### Default to Static
- Astro generates static HTML by default — leverage this for maximum performance
- Use `getStaticPaths()` for dynamic routes at build time
- Only enable SSR (`output: 'server'` or `output: 'hybrid'`) when truly needed (previews, auth)
- NEVER use SSR for pages that can be statically generated

**Static Route (Default):**
```astro
---
// Built once at build time — zero server cost
import { getPosts } from '@/lib/sanity';
const posts = await getPosts(10);
---

{posts.map((post) => (
  <article>
    <h2>{post.title}</h2>
  </article>
))}
```

**When to Use SSR:**
- Sanity preview/draft mode
- Authenticated content
- Personalized pages
- Real-time data requirements

## Image Optimization

### Sanity CDN Image Transforms
- ALWAYS use `urlFor()` with width/height transforms — never serve raw originals
- Use Sanity's CDN for automatic format negotiation (WebP/AVIF)
- Specify dimensions to prevent layout shift (CLS)
- Use `loading="lazy"` for below-the-fold images

```astro
---
import { urlFor } from '@/lib/sanity';
---

<!-- Optimized hero image (above fold — no lazy loading) -->
<img
  src={urlFor(post.mainImage).width(1200).height(600).format('webp').quality(80).url()}
  alt={post.mainImage.alt}
  width="1200"
  height="600"
  fetchpriority="high"
  decoding="async"
/>

<!-- Below-fold image (lazy loaded) -->
<img
  src={urlFor(post.mainImage).width(800).height(450).format('webp').url()}
  alt={post.mainImage.alt}
  width="800"
  height="450"
  loading="lazy"
  decoding="async"
/>
```

### Responsive Images with Sanity CDN
```astro
<img
  src={urlFor(image).width(800).url()}
  srcset={`
    ${urlFor(image).width(400).url()} 400w,
    ${urlFor(image).width(800).url()} 800w,
    ${urlFor(image).width(1200).url()} 1200w
  `}
  sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 800px"
  alt={image.alt}
  loading="lazy"
  decoding="async"
/>
```

### Sanity CDN Configuration
```typescript
// Use CDN in production, bypass in development
export const sanityClient = createClient({
  projectId: import.meta.env.PUBLIC_SANITY_PROJECT_ID,
  dataset: import.meta.env.PUBLIC_SANITY_DATASET || 'production',
  apiVersion: '2024-01-01',
  useCdn: import.meta.env.PROD,  // CDN for production, API for dev
});
```

## Islands Architecture Performance

### Minimize Client-Side JavaScript
- Default to zero-JS Astro components
- Use `client:visible` or `client:idle` instead of `client:load` whenever possible
- NEVER hydrate components that don't need interactivity

```astro
<!-- Zero JS (preferred) -->
<StaticCard title={post.title} />

<!-- Deferred hydration (good) -->
<InteractiveWidget client:visible />

<!-- Idle hydration (acceptable) -->
<NewsletterForm client:idle />

<!-- Immediate hydration (use sparingly) -->
<SearchBar client:load />
```

### Bundle Size
- Keep interactive islands small and focused
- Use dynamic imports for heavy dependencies
- Avoid importing entire libraries when only a function is needed

```typescript
// Bad: imports entire library
import _ from 'lodash';

// Good: import only what you need
import debounce from 'lodash/debounce';
```

## GROQ Query Performance

### Efficient Queries
- Project only the fields you need (avoid `...` spread)
- Use pagination with slice operators
- Limit dereferencing depth

```groq
// Efficient: project specific fields
*[_type == "post"] | order(publishedAt desc) [0...10] {
  _id,
  title,
  slug,
  publishedAt,
  "imageUrl": mainImage.asset->url,
  "category": categories[0]->title
}

// Inefficient: fetches everything
*[_type == "post"] {
  ...
}
```

### Avoid N+1 Queries
```groq
// Good: single query with joins
*[_type == "post"] {
  title,
  "author": author->{ name, image },
  "categories": categories[]->{ title, slug }
}

// Bad: separate queries for each post's author
```

## Core Web Vitals

### Largest Contentful Paint (LCP)
- Use `fetchpriority="high"` on hero/LCP images
- Inline critical CSS
- Preload key resources

```astro
<head>
  <!-- Preload LCP image -->
  <link
    rel="preload"
    as="image"
    href={urlFor(heroImage).width(1200).format('webp').url()}
  />

  <!-- Preload critical font -->
  <link
    rel="preload"
    as="font"
    type="font/woff2"
    href="/fonts/main.woff2"
    crossorigin
  />
</head>
```

### Cumulative Layout Shift (CLS)
- ALWAYS set width and height on images
- Reserve space for dynamic content
- Use aspect ratio utilities

```astro
<!-- Prevents CLS with explicit dimensions -->
<img
  src={urlFor(image).width(800).height(450).url()}
  alt={image.alt}
  width="800"
  height="450"
/>

<!-- Or use aspect ratio -->
<div class="aspect-video">
  <img src={imageUrl} alt="" class="object-cover w-full h-full" />
</div>
```

### Interaction to Next Paint (INP)
- Minimize JavaScript execution time
- Defer non-critical scripts
- Use `client:idle` or `client:visible` for interactive islands

## Caching

### Build-Time Caching
- Sanity queries are cached at build time for SSG pages
- Rebuild triggers via Sanity webhooks on content publish

### CDN Caching
- Static assets are immutable and cacheable forever
- Use content-hash filenames (Astro does this by default)
- Configure CDN cache headers for HTML pages

### Sanity API Caching
```typescript
// Production: use CDN (cached, fast)
useCdn: import.meta.env.PROD

// Development: bypass CDN (fresh data)
useCdn: false
```

## Font Optimization

### Self-Host Fonts
```astro
<head>
  <link rel="preload" as="font" type="font/woff2" href="/fonts/inter.woff2" crossorigin />
  <style>
    @font-face {
      font-family: 'Inter';
      src: url('/fonts/inter.woff2') format('woff2');
      font-display: swap;
      font-weight: 100 900;
    }
  </style>
</head>
```

### Or Use @fontsource
```typescript
// In layout frontmatter
import '@fontsource-variable/inter';
```

## Build Optimization

### Analyze Build Output
```bash
# Check build output sizes
npm run build

# Astro outputs a summary showing:
# - Page count and sizes
# - Asset sizes
# - Build time
```

### Content Prefetching
```javascript
// astro.config.mjs
export default defineConfig({
  prefetch: {
    prefetchAll: true,        // Prefetch all links
    defaultStrategy: 'hover', // Or 'viewport', 'load'
  },
});
```

## Webhook-Triggered Rebuilds

### Sanity Webhook Configuration
- Configure a webhook in Sanity to trigger site rebuilds on content publish
- Use platform-specific deploy hooks (Vercel, Netlify, Cloudflare)
- Only rebuild when published content changes (filter drafts)

## Performance Targets

### Excellent
- LCP: < 1.0s
- CLS: < 0.05
- INP: < 100ms
- Total page weight: < 500KB
- Zero unnecessary JS islands

### Good
- LCP: < 2.5s
- CLS: < 0.1
- INP: < 200ms
- Total page weight: < 1MB

## Checklist

- [ ] Static generation used for all possible pages
- [ ] Images use Sanity CDN transforms with width/height
- [ ] LCP image has `fetchpriority="high"` and is preloaded
- [ ] All images have explicit dimensions (no CLS)
- [ ] Interactive islands use most restrictive `client:*` directive
- [ ] GROQ queries project only needed fields
- [ ] Fonts use `font-display: swap` and are preloaded
- [ ] Sanity CDN enabled for production (`useCdn: true`)
- [ ] Build output sizes reviewed
- [ ] Webhook configured for content-triggered rebuilds
