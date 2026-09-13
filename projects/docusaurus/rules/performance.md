---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
  - "**/*.{css,scss,js,mjs,ts}"
  - "**/{vite,webpack,next,nuxt,astro,svelte,tailwind,postcss}.config.*"
  - "**/.htaccess"
---

# Docusaurus Performance Optimization

## Build Optimization

### Static Site Generation
- ✅ Pre-render all pages at build time
- ✅ Use Docusaurus's built-in optimization
- ✅ Minimize custom JavaScript

## Images

### Image Optimization
```markdown
![Alt text](./image.png)

// Or using static assets
![Alt text](/img/image.png)
```

## Code Splitting

### Dynamic Imports
```javascript
import dynamic from 'next/dynamic';

const HeavyComponent = dynamic(() => import('./HeavyComponent'));
```

## Checklist

- [ ] Images are optimized
- [ ] JavaScript is minimized
- [ ] Static generation is used
- [ ] Bundle size is analyzed
