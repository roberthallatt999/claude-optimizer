# Performance Optimization (EE Backend + Next.js Frontend)

These rules MUST be followed for optimal performance across both the ExpressionEngine/Coilpack backend and Next.js frontend.

## Backend Performance (Coilpack/Laravel)

### API Response Caching

```php
// Cache expensive EE queries
public function index(Request $request, string $channel): JsonResponse
{
    $cacheKey = "api:entries:{$channel}:" . md5($request->getQueryString());

    return Cache::remember($cacheKey, 3600, function () use ($request, $channel) {
        $entries = ee('Channel')->getEntries([
            'channel' => $channel,
            'limit' => $request->input('limit', 10),
        ]);

        return response()->json(new EntryCollection($entries));
    });
}
```

### Laravel Cache Commands
```bash
# Cache configuration, routes, and views for production
ddev artisan config:cache
ddev artisan route:cache
ddev artisan view:cache

# Clear all caches
ddev artisan optimize:clear
ddev ee cache:clear
```

### Database Query Optimization

```php
// Eager loading (good)
$posts = Post::with('author', 'categories')->get();

// Only needed columns
$users = User::select('id', 'name')->get();

// Avoid N+1 queries
$entries = ee('Channel')->getEntries([
    'channel' => 'blog',
    'limit' => 10,
    // Specify only needed fields to reduce query load
]);
```

### HTTP Cache Headers

```php
// Set appropriate cache headers on API responses
return response()->json($data)
    ->header('Cache-Control', 'public, max-age=3600, s-maxage=3600')
    ->header('Vary', 'Accept, Accept-Encoding');
```

## Frontend Performance (Next.js)

### Static Generation (SSG)
- Use Static Generation whenever possible
- Generate static pages at build time
- Use ISR for semi-static content
- NEVER use Server-Side Rendering unnecessarily

```typescript
// Static page with ISR
export default async function Page() {
  const data = await fetchEntries('pages', {
    revalidate: 3600, // Revalidate every hour
  });
  return <div>{/* render data */}</div>;
}
```

### Incremental Static Regeneration (ISR)

```typescript
// Fetch with revalidation
async function getData() {
  const res = await fetch(`${API_BASE}/v1/entries/blog`, {
    next: { revalidate: 60 }, // Revalidate every 60 seconds
  });
  return res.json();
}
```

### ISR Strategy by Content Type

| Content Type | Revalidation | Reason |
|-------------|-------------|--------|
| Navigation | 86400 (1 day) | Rarely changes |
| Blog posts | 3600 (1 hour) | Moderate updates |
| Home page | 300 (5 min) | Frequently updated |
| User data | 0 (no-store) | Always fresh |

## Image Optimization

### Use next/image
- ALWAYS use `next/image` for images
- Provide width and height to prevent layout shift
- Use `priority` for above-the-fold (LCP) images
- NEVER use `<img>` tag directly

```tsx
import Image from 'next/image';

// Hero image (above the fold)
<Image
  src={entry.heroImage}
  alt={entry.heroAlt}
  width={1200}
  height={600}
  priority // Improves LCP
  sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
/>

// Below-the-fold image (lazy loaded by default)
<Image
  src={entry.thumbnail}
  alt={entry.thumbAlt}
  width={400}
  height={300}
  sizes="(max-width: 768px) 100vw, 33vw"
/>
```

### Remote Image Configuration
```javascript
// next.config.js
module.exports = {
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'your-ddev-site.ddev.site',
      },
    ],
    formats: ['image/avif', 'image/webp'],
  },
};
```

## Code Splitting

### Dynamic Imports
```typescript
import dynamic from 'next/dynamic';

// Load heavy components on demand
const Chart = dynamic(() => import('@/components/Chart'), {
  loading: () => <ChartSkeleton />,
  ssr: false, // Client-only component
});

// Lazy load below-the-fold sections
const Newsletter = dynamic(() => import('@/components/Newsletter'));
```

## Font Optimization

```typescript
import { Inter } from 'next/font/google';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
});

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html className={inter.className}>
      <body>{children}</body>
    </html>
  );
}
```

## Core Web Vitals

### Largest Contentful Paint (LCP)
- Preload LCP image with `priority` prop
- Optimize image sizes from EE
- Minimize server response time (cache API responses)

### Cumulative Layout Shift (CLS)
- Always set width/height on images
- Reserve space for dynamic content
- Use skeleton loading states
- NEVER inject content without reserved space

### First Input Delay / Interaction to Next Paint
- Minimize JavaScript execution time
- Use code splitting and dynamic imports
- Defer non-critical scripts
- Keep client components small

## Bundle Analysis

```bash
# Install bundle analyzer
npm install @next/bundle-analyzer

# next.config.js
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});
module.exports = withBundleAnalyzer({ /* config */ });

# Run analysis
ANALYZE=true npm run build
```

## Performance Targets

### Frontend
- LCP: < 2.5 seconds
- CLS: < 0.1
- INP: < 200ms
- Time to Interactive: < 3.5 seconds

### Backend API
- TTFB: < 200ms (cached)
- TTFB: < 500ms (uncached)
- API response time: < 100ms (cached)

## Checklist

### Backend
- [ ] API responses are cached
- [ ] Database queries are optimized (eager loading, select specific columns)
- [ ] Cache headers set on API responses
- [ ] Laravel config/routes/views cached in production
- [ ] EE caches cleared after content updates

### Frontend
- [ ] Images use next/image with proper sizing
- [ ] LCP image has priority attribute
- [ ] Heavy components are dynamically imported
- [ ] Appropriate ISR revalidation strategy per content type
- [ ] Bundle size is analyzed
- [ ] Fonts optimized with next/font
- [ ] Static Generation used where possible
- [ ] Skeleton loading states for dynamic content
