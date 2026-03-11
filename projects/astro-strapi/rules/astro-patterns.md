# Astro Patterns and Best Practices

These rules MUST be followed when developing with Astro.

## Component Structure

### Astro Components
- Use `.astro` files for all static/server-rendered components (default)
- Keep frontmatter (`---`) focused on data fetching and props
- Extract complex logic to `lib/` utility files
- NEVER use framework components (React, Vue) when an Astro component suffices

**Correct Astro Component:**
```astro
---
// src/components/ArticleCard.astro
interface Props {
  title: string;
  slug: string;
  excerpt: string;
  image?: string;
}

const { title, slug, excerpt, image } = Astro.props;
---

<article class="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition">
  {image && <img src={image} alt="" class="w-full h-48 object-cover rounded-t-lg" loading="lazy" />}
  <h3 class="text-xl font-bold mb-2">{title}</h3>
  <p class="text-gray-600 mb-4">{excerpt}</p>
  <a href={`/blog/${slug}`} class="text-brand-primary hover:underline">
    Read more
  </a>
</article>
```

## Layouts

### Layout Pattern
- Use layouts for shared page structure (head, header, footer)
- Pass metadata via props
- Use `<slot />` for content injection

```astro
---
// src/layouts/BaseLayout.astro
interface Props {
  title: string;
  description?: string;
  image?: string;
}

const { title, description, image } = Astro.props;
---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title}</title>
  {description && <meta name="description" content={description} />}
  {image && <meta property="og:image" content={image} />}
</head>
<body>
  <header>
    <slot name="header" />
  </header>
  <main>
    <slot />
  </main>
  <footer>
    <slot name="footer" />
  </footer>
</body>
</html>
```

### Named Slots
```astro
---
import BaseLayout from '@/layouts/BaseLayout.astro';
---

<BaseLayout title="About Us">
  <Fragment slot="header">
    <nav><!-- Custom header --></nav>
  </Fragment>

  <h1>About Us</h1>
  <p>Main content goes here.</p>

  <Fragment slot="footer">
    <p>Custom footer content</p>
  </Fragment>
</BaseLayout>
```

## Pages and Routing

### File-Based Routing
- Pages live in `src/pages/`
- File name becomes the URL path
- Use `[param].astro` for dynamic routes
- Use `[...slug].astro` for catch-all routes

```
src/pages/
├── index.astro          # /
├── about.astro          # /about
├── blog/
│   ├── index.astro      # /blog
│   └── [slug].astro     # /blog/:slug
└── [...slug].astro      # Catch-all (404 fallback)
```

### Static Paths (SSG)
```astro
---
// src/pages/blog/[slug].astro
import { getArticles, getArticle } from '@/lib/strapi';
import BaseLayout from '@/layouts/BaseLayout.astro';

export async function getStaticPaths() {
  const { data: articles } = await getArticles(100);
  return articles.map((article) => ({
    params: { slug: article.attributes.slug },
    props: { article },
  }));
}

const { article } = Astro.props;
---

<BaseLayout title={article.attributes.title}>
  <article>
    <h1>{article.attributes.title}</h1>
    <div set:html={article.attributes.content} />
  </article>
</BaseLayout>
```

## Islands Architecture

### Client Directives
- `client:load` — Hydrate immediately on page load (use sparingly)
- `client:idle` — Hydrate when browser is idle (good default for interactive)
- `client:visible` — Hydrate when component enters viewport (best for below-fold)
- `client:media="(query)"` — Hydrate when media query matches
- `client:only="react"` — Skip SSR entirely, render only on client

**Rules:**
- Default to no client directive (static rendering)
- Use `client:visible` for below-the-fold interactive components
- Use `client:idle` for above-the-fold interactive components
- Use `client:load` only when immediate interactivity is critical
- NEVER add client directives to components that don't need interactivity

```astro
---
import StaticCard from '@/components/StaticCard.astro';
import SearchWidget from '@/components/interactive/SearchWidget.tsx';
import Newsletter from '@/components/interactive/Newsletter.tsx';
import MapEmbed from '@/components/interactive/MapEmbed.tsx';
---

<!-- Static by default (no JS shipped) -->
<StaticCard title="Hello" />

<!-- Interactive: hydrate when idle -->
<SearchWidget client:idle />

<!-- Interactive: hydrate when visible -->
<Newsletter client:visible />

<!-- Interactive: hydrate on desktop only -->
<MapEmbed client:media="(min-width: 768px)" />
```

## Data Fetching

### Frontmatter Fetching (Build Time)
```astro
---
// All code in frontmatter runs at build time (SSG) or request time (SSR)
import { fetchStrapi } from '@/lib/strapi';

const { data: articles } = await fetchStrapi('/articles', {
  'populate': '*',
  'sort': 'publishedAt:desc',
  'pagination[pageSize]': '10',
});
---

<ul>
  {articles.map((article) => (
    <li>{article.attributes.title}</li>
  ))}
</ul>
```

### Error Handling
```astro
---
let articles = [];
try {
  const response = await fetchStrapi('/articles');
  articles = response.data;
} catch (error) {
  console.error('Failed to fetch articles:', error);
}
---

{articles.length > 0 ? (
  <ul>
    {articles.map((a) => <li>{a.attributes.title}</li>)}
  </ul>
) : (
  <p>No articles available.</p>
)}
```

## Content Collections

### Local Content (Optional)
```typescript
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.date(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };
```

## Scoped Styles

### Component-Scoped CSS
```astro
---
// Styles are scoped to this component by default
---

<div class="wrapper">
  <h2>Scoped heading</h2>
</div>

<style>
  .wrapper {
    max-width: 60ch;
    margin: 0 auto;
  }

  h2 {
    color: var(--color-primary);
  }
</style>
```

### Global Styles
```astro
<style is:global>
  /* Use sparingly — affects all components */
  .prose img {
    border-radius: 0.5rem;
  }
</style>
```

## TypeScript

### Type Props
- ALWAYS define `Props` interface in frontmatter
- Use TypeScript for all utility functions in `lib/`
- Define types for Strapi API responses in `types/`

```typescript
// src/types/strapi.ts
export interface StrapiAttributes<T> {
  id: number;
  attributes: T;
}

export interface ArticleAttributes {
  title: string;
  slug: string;
  content: string;
  excerpt: string;
  publishedAt: string;
  featuredImage: {
    data: StrapiAttributes<{
      url: string;
      alternativeText: string;
    }>;
  };
}
```

## Checklist

Before committing:
- [ ] Astro components used for static content (no unnecessary framework components)
- [ ] Client directives used only where interactivity is needed
- [ ] `getStaticPaths()` defined for all dynamic routes in SSG mode
- [ ] Props interface defined for all components
- [ ] Error handling for API calls
- [ ] Images use `loading="lazy"` for below-fold content
- [ ] Layouts used consistently across pages
