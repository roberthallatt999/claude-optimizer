# Next.js Patterns and Best Practices

These rules MUST be followed when developing with Next.js App Router (14+).

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
```

## Server vs Client Components

### Default to Server Components
- Use Server Components by default
- Add `'use client'` only when needed
- Keep interactive components client-side
- NEVER use client components unnecessarily

**Server Component (default):**
```typescript
// app/blog/page.tsx
export default async function BlogPage() {
  const posts = await fetchPosts(); // Server-side data fetching

  return (
    <div>
      {posts.map(post => (
        <article key={post.id}>
          <h2>{post.title}</h2>
        </article>
      ))}
    </div>
  );
}
```

**Client Component (when needed):**
```typescript
// components/SearchForm.tsx
'use client';

import { useState } from 'react';

export default function SearchForm() {
  const [query, setQuery] = useState('');

  return (
    <form>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
    </form>
  );
}
```

## Data Fetching

### Async Server Components
- Fetch data in Server Components
- Use `async/await` directly in components
- Leverage automatic request deduplication
- NEVER use `useEffect` for initial data fetching

**Correct:**
```typescript
async function getPost(slug: string) {
  const res = await fetch(`https://api.example.com/posts/${slug}`, {
    next: { revalidate: 3600 } // Cache for 1 hour
  });
  return res.json();
}

export default async function PostPage({ params }: { params: { slug: string } }) {
  const post = await getPost(params.slug);

  return <article>{post.title}</article>;
}
```

### Caching Strategies
- Use `{ cache: 'force-cache' }` for static data (default)
- Use `{ cache: 'no-store' }` for dynamic data
- Use `{ next: { revalidate: N } }` for ISR

```typescript
// Static data (cached)
const staticData = await fetch('https://api.example.com/config');

// Dynamic data (not cached)
const dynamicData = await fetch('https://api.example.com/user', {
  cache: 'no-store'
});

// ISR (revalidate every hour)
const revalidatedData = await fetch('https://api.example.com/posts', {
  next: { revalidate: 3600 }
});
```

## Metadata

### Static Metadata
```typescript
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'About Us',
  description: 'Learn about our organization'
};

export default function AboutPage() {
  return <div>About content</div>;
}
```

### Dynamic Metadata
```typescript
export async function generateMetadata({ params }: { params: { slug: string } }): Promise<Metadata> {
  const post = await getPost(params.slug);

  return {
    title: post.title,
    description: post.excerpt,
    openGraph: {
      title: post.title,
      description: post.excerpt,
      images: [post.imageUrl],
    },
  };
}
```

## Loading States

### loading.tsx Pattern
```typescript
// app/blog/loading.tsx
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

### Suspense Boundaries
```typescript
import { Suspense } from 'react';

export default function Page() {
  return (
    <>
      <h1>My Page</h1>
      <Suspense fallback={<LoadingSkeleton />}>
        <SlowComponent />
      </Suspense>
    </>
  );
}
```

## Error Handling

### error.tsx Pattern
```typescript
// app/blog/error.tsx
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

## Images

### Next.js Image Component
- ALWAYS use `next/image` for images
- Provide width and height
- Use `priority` for above-the-fold images
- NEVER use `<img>` tag directly

```typescript
import Image from 'next/image';

export default function Hero() {
  return (
    <Image
      src="/hero.jpg"
      alt="Hero image"
      width={1200}
      height={600}
      priority
    />
  );
}
```

## Routing

### Dynamic Routes
```typescript
// app/blog/[slug]/page.tsx
export default function PostPage({ params }: { params: { slug: string } }) {
  return <div>Post: {params.slug}</div>;
}

// Generate static paths
export async function generateStaticParams() {
  const posts = await getPosts();

  return posts.map((post) => ({
    slug: post.slug,
  }));
}
```

### Route Groups
```typescript
// app/(marketing)/about/page.tsx
// app/(marketing)/contact/page.tsx
// app/(shop)/products/page.tsx

// Organize without affecting URL structure
```

## Performance

### Code Splitting
- Use dynamic imports for heavy components
- Load client components on demand
- NEVER import everything upfront

```typescript
import dynamic from 'next/dynamic';

const HeavyChart = dynamic(() => import('@/components/Chart'), {
  loading: () => <p>Loading chart...</p>,
  ssr: false // Disable SSR if not needed
});
```

### Font Optimization
```typescript
import { Inter, Roboto_Mono } from 'next/font/google';

const inter = Inter({ subsets: ['latin'] });
const robotoMono = Roboto_Mono({ subsets: ['latin'] });

export default function Layout({ children }) {
  return (
    <html className={inter.className}>
      <body>{children}</body>
    </html>
  );
}
```

## TypeScript

### Type Safety
- Define proper TypeScript types
- Use type inference where possible
- NEVER use `any` type

```typescript
interface Post {
  id: string;
  title: string;
  content: string;
  createdAt: Date;
}

async function getPosts(): Promise<Post[]> {
  // ...
}
```

## Checklist

- [ ] Server Components used by default
- [ ] Client Components marked with 'use client'
- [ ] Data fetching uses appropriate caching
- [ ] Metadata is defined (static or dynamic)
- [ ] Loading states implemented
- [ ] Error boundaries in place
- [ ] Images use next/image component
- [ ] TypeScript types are properly defined
