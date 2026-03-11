# Next.js App Router Patterns (Headless CMS)

These rules MUST be followed when developing the Next.js frontend for headless ExpressionEngine.

## App Router Structure

### File Conventions
- Use `app/` directory for App Router
- Use `page.tsx` for route pages
- Use `layout.tsx` for shared layouts
- Use `loading.tsx` for loading states
- Use `error.tsx` for error handling
- NEVER mix Pages Router and App Router

**Correct Structure:**
```
app/
├── layout.tsx          # Root layout
├── page.tsx            # Home page
├── about/
│   └── page.tsx        # /about
├── blog/
│   ├── page.tsx        # /blog
│   ├── layout.tsx      # Blog layout
│   ├── loading.tsx     # Blog loading
│   └── [slug]/
│       └── page.tsx    # /blog/[slug]
├── (marketing)/        # Route group
│   └── contact/
│       └── page.tsx    # /contact
└── components/         # Shared components
```

## Server vs Client Components

### Default to Server Components
- Use Server Components by default
- Add `'use client'` only when needed (state, events, browser APIs)
- Keep interactive components as small client-side leaves

**Server Component (default):**
```tsx
// app/blog/page.tsx
import { fetchEntries } from '@/lib/api';

export default async function BlogPage() {
  const { data: posts } = await fetchEntries('blog', { limit: 10 });

  return (
    <main>
      <h1>Blog</h1>
      {posts.map((post) => (
        <article key={post.slug}>
          <h2>{post.title}</h2>
        </article>
      ))}
    </main>
  );
}
```

**Client Component (when needed):**
```tsx
// components/SearchForm.tsx
'use client';

import { useState } from 'react';

export default function SearchForm() {
  const [query, setQuery] = useState('');

  return (
    <form>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
    </form>
  );
}
```

## Data Fetching from Coilpack API

### API Client Pattern
```typescript
// lib/api.ts
const API_BASE = process.env.COILPACK_API_URL!;

async function apiFetch<T>(path: string, options?: RequestInit & { revalidate?: number }): Promise<T> {
  const { revalidate = 3600, ...fetchOptions } = options ?? {};

  const res = await fetch(`${API_BASE}${path}`, {
    ...fetchOptions,
    next: { revalidate },
  });

  if (!res.ok) {
    throw new Error(`API error ${res.status}: ${res.statusText}`);
  }

  return res.json();
}

export async function fetchEntries(channel: string, params?: {
  limit?: number;
  offset?: number;
}) {
  const searchParams = new URLSearchParams({
    limit: String(params?.limit ?? 10),
    offset: String(params?.offset ?? 0),
  });

  return apiFetch<EntriesResponse>(`/v1/entries/${channel}?${searchParams}`);
}

export async function fetchEntry(channel: string, slug: string) {
  return apiFetch<EntryResponse>(`/v1/entries/${channel}/${slug}`);
}

export async function fetchPage(slug: string) {
  return apiFetch<PageResponse>(`/v1/pages/${slug}`);
}

export async function fetchNavigation(menu: string) {
  return apiFetch<NavigationResponse>(`/v1/navigation/${menu}`, {
    revalidate: 86400, // Navigation changes rarely
  });
}
```

### Caching Strategies
- Use `{ cache: 'force-cache' }` for static data (default)
- Use `{ cache: 'no-store' }` for dynamic data
- Use `{ next: { revalidate: N } }` for ISR

```typescript
// Static data (cached indefinitely)
const config = await apiFetch('/v1/config');

// Dynamic data (never cached)
const user = await apiFetch('/v1/user', { cache: 'no-store' });

// ISR (revalidate every hour)
const posts = await apiFetch('/v1/entries/blog', { revalidate: 3600 });
```

## TypeScript Types

### Define Types for API Responses
```typescript
// types/api.ts
export interface Entry {
  id: number;
  title: string;
  slug: string;
  date: string;
  status: string;
  channel: string;
  fields: Record<string, unknown>;
  categories: Category[];
  author: {
    id: number;
    name: string;
  };
}

export interface Category {
  id: number;
  name: string;
  slug: string;
}

export interface EntriesResponse {
  data: Entry[];
  meta: {
    total: number;
    limit: number;
    offset: number;
  };
}

export interface EntryResponse {
  data: Entry;
}
```

## Metadata

### Static Metadata
```typescript
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'About Us',
  description: 'Learn about our organization',
};
```

### Dynamic Metadata from API
```typescript
export async function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Promise<Metadata> {
  const { data: entry } = await fetchEntry('pages', params.slug);

  return {
    title: entry.title,
    description: entry.fields.meta_description as string,
    openGraph: {
      title: entry.title,
      images: entry.fields.og_image ? [entry.fields.og_image as string] : [],
    },
  };
}
```

## Dynamic Routes with Static Generation

```typescript
// app/blog/[slug]/page.tsx
import { fetchEntries, fetchEntry } from '@/lib/api';
import { notFound } from 'next/navigation';

export default async function PostPage({ params }: { params: { slug: string } }) {
  const { data: post } = await fetchEntry('blog', params.slug);

  if (!post) notFound();

  return (
    <article>
      <h1>{post.title}</h1>
      <div dangerouslySetInnerHTML={{ __html: post.fields.body as string }} />
    </article>
  );
}

// Generate static paths at build time
export async function generateStaticParams() {
  const { data: posts } = await fetchEntries('blog', { limit: 100 });

  return posts.map((post) => ({
    slug: post.slug,
  }));
}
```

## Loading and Error States

### loading.tsx
```typescript
export default function Loading() {
  return (
    <div className="animate-pulse">
      <div className="h-8 bg-gray-200 rounded w-3/4 mb-4"></div>
      <div className="h-4 bg-gray-200 rounded w-full mb-2"></div>
      <div className="h-4 bg-gray-200 rounded w-5/6"></div>
    </div>
  );
}
```

### error.tsx
```typescript
'use client';

export default function Error({
  error,
  reset,
}: {
  error: Error;
  reset: () => void;
}) {
  return (
    <div>
      <h2>Something went wrong!</h2>
      <button onClick={() => reset()}>Try again</button>
    </div>
  );
}
```

## Images from EE

### Using next/image with Remote Images
```typescript
// next.config.js
module.exports = {
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'your-ddev-site.ddev.site',
      },
    ],
  },
};
```

```tsx
import Image from 'next/image';

<Image
  src={entry.fields.featured_image as string}
  alt={entry.fields.image_alt as string}
  width={1200}
  height={600}
  priority // For above-the-fold images
/>
```

## Environment Variables

```bash
# frontend/.env.local
COILPACK_API_URL=https://your-ddev-site.ddev.site/api
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

- Server-only variables: no prefix (e.g., `COILPACK_API_URL`)
- Client-accessible variables: `NEXT_PUBLIC_` prefix

## Checklist

- [ ] Server Components used by default
- [ ] Client Components marked with 'use client'
- [ ] API client uses proper caching/revalidation
- [ ] TypeScript types defined for all API responses
- [ ] Metadata defined (static or dynamic)
- [ ] Loading states implemented
- [ ] Error boundaries in place
- [ ] Images use next/image with remote patterns
- [ ] Environment variables properly scoped
- [ ] generateStaticParams for dynamic routes
