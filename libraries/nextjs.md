# Next.js Conventions (2026)

## Core Principles
- Prefer App Router unless migration constraints force Pages Router.
- Use Server Components by default and opt into Client Components only when hooks/DOM are needed.
- Keep API interactions and cache revalidation explicit.

## Routing
```tsx
// app/blog/[slug]/page.tsx
import { notFound } from 'next/navigation';

interface Props {
  params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: Props) {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) return {};

  return {
    title: post.title,
    description: post.description,
  };
}

export default async function BlogPost({ params }: Props) {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) notFound();

  return <article>{post.title}</article>;
}
```

## Data Fetching
```tsx
async function fetchProducts() {
  const res = await fetch('https://api.example.com/products', {
    next: { revalidate: 60 },
  });
  if (!res.ok) throw new Error('Failed to fetch products');
  return res.json();
}
```

## Client-Only Features
```tsx
'use client';

import { useState } from 'react';

export function QuantityButton() {
  const [qty, setQty] = useState(1);
  return <button onClick={() => setQty((n) => n + 1)}>+{qty}</button>;
}
```

## Forms and Validation
- Validate on server actions where possible.
- Use `useFormState` and `useFormStatus` for progressive enhancement.

## Performance
- Use segment-level `loading.tsx`, `error.tsx`, and `not-found.tsx`.
- Cache expensive queries with `fetch` cache tags/revalidation.
- Use metadata generation per route for SEO completeness.

## Accessibility
- Preserve focus after navigation and modal actions.
- Use semantic landmarks in layout and page templates.
