# Astro Patterns and Best Practices

These rules MUST be followed when developing with Astro 4.x in this project.

## Component Architecture

### Astro Components (Default — Zero JS)
- Use `.astro` files for all static content (default)
- Astro components render to HTML at build time with zero client-side JavaScript
- Use framework components (React, Vue, Svelte) only for interactive islands

**Standard Astro Component:**
```astro
---
// Frontmatter: runs at build time (server-side only)
interface Props {
  title: string;
  description?: string;
}

const { title, description } = Astro.props;
---

<article class="card">
  <h2>{title}</h2>
  {description && <p>{description}</p>}
</article>

<style>
  /* Scoped styles: only apply to this component */
  .card {
    @apply bg-white rounded-lg shadow-md p-6;
  }
</style>
```

### Islands Architecture (Interactive Components)
- Use `client:*` directives to hydrate framework components
- Choose the most restrictive hydration strategy that works

```astro
---
import Counter from '@/components/interactive/Counter.tsx';
import Gallery from '@/components/interactive/Gallery.tsx';
import Newsletter from '@/components/interactive/Newsletter.tsx';
---

<!-- Immediate hydration (above-the-fold interactive content) -->
<Counter client:load />

<!-- Hydrate when visible in viewport -->
<Gallery client:visible />

<!-- Hydrate when browser is idle -->
<Newsletter client:idle />

<!-- Hydrate only on matching media query -->
<Counter client:media="(min-width: 768px)" />
```

**Hydration Priority:**
| Directive | When to Use |
|-----------|-------------|
| `client:load` | Critical interactivity needed immediately |
| `client:idle` | Important but not urgent (forms, newsletter) |
| `client:visible` | Below-the-fold interactive content |
| `client:media` | Responsive interactivity (desktop-only features) |
| `client:only` | Client-only rendering (no SSR fallback) |

## Layouts

### Base Layout Pattern
```astro
---
// src/layouts/BaseLayout.astro
interface Props {
  title: string;
  description?: string;
  image?: string;
}

const { title, description, image } = Astro.props;
const canonicalURL = new URL(Astro.url.pathname, Astro.site);
---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link rel="canonical" href={canonicalURL} />
  <title>{title}</title>
  {description && <meta name="description" content={description} />}

  <!-- Open Graph -->
  <meta property="og:title" content={title} />
  {description && <meta property="og:description" content={description} />}
  {image && <meta property="og:image" content={image} />}
</head>
<body>
  <slot name="header" />
  <main>
    <slot />
  </main>
  <slot name="footer" />
</body>
</html>
```

### Named Slots
```astro
---
import BaseLayout from '@/layouts/BaseLayout.astro';
import Header from '@/components/Header.astro';
import Footer from '@/components/Footer.astro';
---

<BaseLayout title="Home">
  <Header slot="header" />
  <h1>Welcome</h1>
  <p>Page content here.</p>
  <Footer slot="footer" />
</BaseLayout>
```

## Pages and Routing

### Static Pages
```astro
---
// src/pages/about.astro
import BaseLayout from '@/layouts/BaseLayout.astro';
---

<BaseLayout title="About Us" description="Learn about our team">
  <h1>About Us</h1>
  <p>Static content rendered at build time.</p>
</BaseLayout>
```

### Dynamic Routes (SSG)
```astro
---
// src/pages/blog/[slug].astro
import BaseLayout from '@/layouts/BaseLayout.astro';
import { getPosts, getPost } from '@/lib/sanity';

export async function getStaticPaths() {
  const posts = await getPosts(100);
  return posts.map((post) => ({
    params: { slug: post.slug.current },
  }));
}

const { slug } = Astro.params;
const post = await getPost(slug);
---

<BaseLayout title={post.title}>
  <article>
    <h1>{post.title}</h1>
  </article>
</BaseLayout>
```

### Pagination
```astro
---
// src/pages/blog/[...page].astro
import type { GetStaticPaths } from 'astro';
import { getPosts } from '@/lib/sanity';

export const getStaticPaths: GetStaticPaths = async ({ paginate }) => {
  const posts = await getPosts(100);
  return paginate(posts, { pageSize: 10 });
};

const { page } = Astro.props;
---

{page.data.map((post) => (
  <article>
    <h2>{post.title}</h2>
  </article>
))}

<nav>
  {page.url.prev && <a href={page.url.prev}>Previous</a>}
  {page.url.next && <a href={page.url.next}>Next</a>}
</nav>
```

## Data Fetching

### Fetching in Frontmatter
- All data fetching happens in the frontmatter (`---`) block
- Runs at build time for SSG, at request time for SSR
- Use `Astro.glob()` for local files, API calls for remote data

```astro
---
// Data fetching runs at build time
import { getPosts, urlFor } from '@/lib/sanity';

const posts = await getPosts(10);
---

{posts.map((post) => (
  <article>
    {post.mainImage && (
      <img
        src={urlFor(post.mainImage).width(800).height(450).url()}
        alt={post.title}
        loading="lazy"
      />
    )}
    <h2>{post.title}</h2>
  </article>
))}
```

### Content Collections (Local Content)
```typescript
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.coerce.date(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };
```

## Styling

### Scoped Styles
```astro
<div class="wrapper">
  <slot />
</div>

<style>
  /* Scoped to this component only */
  .wrapper {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 1rem;
  }
</style>
```

### Global Styles with Tailwind
```astro
---
// In layout or page
import '@/styles/global.css';
---
```

### Using `class:list` for Conditional Classes
```astro
---
const { variant = 'primary', size = 'md' } = Astro.props;
---

<button
  class:list={[
    'btn',
    { 'btn-primary': variant === 'primary' },
    { 'btn-secondary': variant === 'secondary' },
    { 'btn-sm': size === 'sm', 'btn-lg': size === 'lg' },
  ]}
>
  <slot />
</button>
```

## TypeScript

### Props Interface
- Always define a `Props` interface for component props
- Use Astro's built-in type inference

```astro
---
interface Props {
  title: string;
  tags?: string[];
  featured?: boolean;
}

const { title, tags = [], featured = false } = Astro.props;
---
```

### Import Aliases
```json
// tsconfig.json
{
  "extends": "astro/tsconfigs/strict",
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  }
}
```

## Checklist

Before committing:
- [ ] Static components use `.astro` files (no unnecessary JS)
- [ ] Interactive components use the most restrictive `client:*` directive
- [ ] Props interfaces defined for all components
- [ ] Layouts use proper `<slot />` patterns
- [ ] Data fetching is in frontmatter only
- [ ] Images use lazy loading for below-the-fold content
- [ ] Scoped styles used where appropriate
- [ ] TypeScript strict mode with no `any` types
