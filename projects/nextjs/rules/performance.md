---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
  - "**/*.{css,scss,js,mjs,ts}"
  - "**/{vite,webpack,next,nuxt,astro,svelte,tailwind,postcss}.config.*"
  - "**/.htaccess"
---

# Next.js Performance Optimization

These rules MUST be followed for optimal Next.js performance.

## Build Optimization

### Static Generation (SSG)
- ✅ Use Static Generation whenever possible
- ✅ Generate static pages at build time
- ✅ Use ISR for semi-static content
- ❌ NEVER use Server-Side Rendering unnecessarily

**Static Pages:**
```typescript
export default async function Page() {
  const data = await fetchData();
  return <div>{data}</div>;
}
```

**Incremental Static Regeneration:**
```typescript
async function getData() {
  const res = await fetch('https://api.example.com/data', {
    next: { revalidate: 60 } // Revalidate every 60 seconds
  });
  return res.json();
}
```

## Image Optimization

### Responsive Images
```typescript
import Image from 'next/image';

// Responsive image with sizes
<Image
  src="/hero.jpg"
  alt="Hero"
  width={1200}
  height={600}
  sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
  priority // For LCP image
/>
```

### Remote Images
```javascript
// next.config.js
module.exports = {
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'example.com',
      },
    ],
  },
};
```

## Code Splitting

### Dynamic Imports
```typescript
import dynamic from 'next/dynamic';

// Load component on client only
const ClientComponent = dynamic(() => import('@/components/Client'), {
  ssr: false,
  loading: () => <Loading />
});

// Lazy load heavy components
const Chart = dynamic(() => import('react-chartjs-2'), {
  loading: () => <ChartSkeleton />
});
```

## Bundle Analysis

```bash
# Install bundle analyzer
npm install @next/bundle-analyzer

# next.config.js
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});

module.exports = withBundleAnalyzer({
  // config
});

# Run analysis
ANALYZE=true npm run build
```

## Caching Strategies

### Static Data
```typescript
const res = await fetch('https://api.example.com/config', {
  cache: 'force-cache' // Cache indefinitely (default)
});
```

### Dynamic Data
```typescript
const res = await fetch('https://api.example.com/user', {
  cache: 'no-store' // Never cache
});
```

### Revalidation
```typescript
const res = await fetch('https://api.example.com/posts', {
  next: { revalidate: 3600 } // Revalidate every hour
});
```

## Core Web Vitals

### Largest Contentful Paint (LCP)
- ✅ Preload LCP image
- ✅ Use `priority` on hero images
- ✅ Optimize image sizes

```typescript
<Image
  src="/hero.jpg"
  alt="Hero"
  width={1920}
  height={1080}
  priority // Improves LCP
/>
```

### Cumulative Layout Shift (CLS)
- ✅ Always set width/height on images
- ✅ Reserve space for dynamic content
- ❌ NEVER inject content without reserved space

### First Input Delay (FID)
- ✅ Minimize JavaScript execution time
- ✅ Use code splitting
- ✅ Defer non-critical scripts

## Checklist

- [ ] Images use next/image with proper sizing
- [ ] LCP image has priority attribute
- [ ] Heavy components are dynamically imported
- [ ] Appropriate caching strategy is used
- [ ] Bundle size is analyzed
- [ ] Static Generation is used where possible
- [ ] Fonts are optimized with next/font
