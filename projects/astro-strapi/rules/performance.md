# Performance Optimization

These rules MUST be followed for optimal Astro + Strapi performance.

## Astro Performance

### Static Generation (SSG)
- Use Static Generation by default — Astro's greatest strength
- Generate all pages at build time when possible
- Use SSR only for pages that require per-request data (previews, auth)
- NEVER use SSR unnecessarily

```astro
---
// SSG: Data fetched at build time, page served as static HTML
import { getArticles } from '@/lib/strapi';

const { data: articles } = await getArticles();
---

<ul>
  {articles.map((article) => (
    <li>{article.attributes.title}</li>
  ))}
</ul>
```

### Islands Architecture
- Ship zero JavaScript by default
- Add client directives only for interactive components
- Use `client:visible` for below-fold interactive content
- Use `client:idle` for above-fold interactive content
- NEVER use `client:load` unless immediate interactivity is critical

**Performance impact of client directives:**
```
No directive   → 0 KB JS (static HTML only)
client:visible → JS loaded when component enters viewport
client:idle    → JS loaded when browser is idle
client:load    → JS loaded immediately (use sparingly)
```

### Partial Hydration Best Practices
```astro
---
import Header from '@/components/Header.astro';       // Static (0 JS)
import ArticleList from '@/components/ArticleList.astro'; // Static (0 JS)
import SearchBar from '@/components/SearchBar.tsx';     // Interactive
import Newsletter from '@/components/Newsletter.tsx';   // Interactive
---

<Header />
<SearchBar client:idle />
<ArticleList />
<Newsletter client:visible />
```

### Image Optimization
- Use Astro's built-in `<Image />` component for local images
- Use `loading="lazy"` for below-fold images
- Provide `width` and `height` to prevent layout shift
- Use modern formats (WebP, AVIF) when possible

```astro
---
import { Image } from 'astro:assets';
import heroImage from '@/assets/hero.jpg';
---

<!-- Local image with Astro optimization -->
<Image src={heroImage} alt="Hero" width={1200} height={600} />

<!-- Remote image from Strapi (use standard img with lazy loading) -->
<img
  src={`${strapiUrl}${article.image.url}`}
  alt={article.image.alternativeText}
  width={800}
  height={400}
  loading="lazy"
  decoding="async"
/>
```

### Code Splitting
- Astro automatically code-splits per page
- Each island loads its own JavaScript bundle independently
- Use dynamic imports in island components for heavy dependencies

```tsx
// components/interactive/Chart.tsx
import { lazy, Suspense } from 'react';

const ChartLib = lazy(() => import('chart.js'));

export default function Chart({ data }) {
  return (
    <Suspense fallback={<div>Loading chart...</div>}>
      <ChartLib data={data} />
    </Suspense>
  );
}
```

### Font Optimization
```astro
<!-- Preload critical fonts -->
<link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin />

<style>
  @font-face {
    font-family: 'Inter';
    src: url('/fonts/inter-var.woff2') format('woff2');
    font-display: swap; /* Prevent invisible text */
  }
</style>
```

### CSS Optimization
- Tailwind CSS purges unused styles automatically in production
- Prefer utility classes over custom CSS
- Use scoped styles in `.astro` files (automatically scoped)
- Minimize use of `is:global` styles

## Strapi Performance

### API Response Optimization

#### Select Only Needed Fields
```typescript
// Fetch only title and slug instead of all fields
const articles = await fetchStrapi('/articles', {
  'fields[0]': 'title',
  'fields[1]': 'slug',
  'fields[2]': 'excerpt',
});
```

#### Populate Selectively
```typescript
// Populate only needed relations (not populate=*)
const articles = await fetchStrapi('/articles', {
  'populate[category][fields][0]': 'name',
  'populate[category][fields][1]': 'slug',
  'populate[featuredImage][fields][0]': 'url',
  'populate[featuredImage][fields][1]': 'alternativeText',
});
```

### Pagination
- ALWAYS paginate list endpoints
- Use reasonable page sizes (10-25 items)
- NEVER fetch all records at once in production

```typescript
// Paginated fetch
const articles = await fetchStrapi('/articles', {
  'pagination[page]': '1',
  'pagination[pageSize]': '10',
  'sort': 'publishedAt:desc',
});
```

### API Caching (Strapi Middleware)
```typescript
// src/middlewares/cache.ts
export default (config, { strapi }) => {
  return async (ctx, next) => {
    // Set cache headers for public API responses
    await next();

    if (ctx.method === 'GET' && ctx.status === 200) {
      ctx.set('Cache-Control', 'public, max-age=300, s-maxage=600');
    }
  };
};
```

### Database Optimization
- Add indexes on frequently queried fields (slug, publishedAt)
- Use `$eq` filters instead of `$contains` when possible (faster)
- Limit population depth to avoid N+1 queries
- Monitor slow queries in development

```typescript
// config/database.ts — enable query logging in development
export default ({ env }) => ({
  connection: {
    client: 'sqlite',
    connection: {
      filename: env('DATABASE_FILENAME', '.tmp/data.db'),
    },
    debug: env('NODE_ENV') === 'development',
  },
});
```

## Build Optimization

### Strapi Build
```bash
# Build Strapi admin panel (production)
NODE_ENV=production npm run build

# Start with production optimizations
NODE_ENV=production npm run start
```

### Astro Build
```bash
# Build static site
npm run build

# Analyze bundle size
npx astro build --verbose
```

## Core Web Vitals

### Largest Contentful Paint (LCP)
- Preload hero images
- Use `fetchpriority="high"` on LCP images
- Avoid large layout shifts from loading content

```astro
<img
  src={heroImage}
  alt="Hero"
  width={1200}
  height={600}
  fetchpriority="high"
  decoding="async"
/>
```

### Cumulative Layout Shift (CLS)
- Always set width/height on images
- Reserve space for dynamic content
- Avoid inserting content above existing content
- Use CSS `aspect-ratio` for responsive media

```astro
<div class="aspect-video">
  <img src={videoThumb} alt="" class="object-cover w-full h-full" loading="lazy" />
</div>
```

### Interaction to Next Paint (INP)
- Minimize JavaScript execution (islands architecture helps)
- Avoid long tasks in event handlers
- Use `client:visible` to defer non-critical interactivity

## Monitoring

### Performance Targets
| Metric | Excellent | Good | Needs Improvement |
|--------|-----------|------|-------------------|
| LCP | < 1.0s | < 2.5s | > 2.5s |
| CLS | < 0.05 | < 0.1 | > 0.1 |
| INP | < 100ms | < 200ms | > 200ms |
| TTFB | < 200ms | < 500ms | > 500ms |

## Checklist

Before deployment:
- [ ] Pages are statically generated where possible
- [ ] Client directives used sparingly and appropriately
- [ ] Images optimized with proper dimensions and lazy loading
- [ ] Strapi API responses use field selection and selective population
- [ ] List endpoints are paginated
- [ ] Cache headers are set on API responses
- [ ] Tailwind CSS is purged in production
- [ ] Fonts use `font-display: swap`
- [ ] Core Web Vitals meet "Good" thresholds
