# React Conventions (2026)

## Core Principles
- Use function components with hooks; avoid class components unless maintaining legacy code.
- Prefer server-first data loading only when using Next.js or a similar framework.
- Keep component responsibility narrow and compose small reusable UI primitives.
- Co-locate styles, markup, and behavior where it improves clarity.

## Component Pattern
```tsx
import { useMemo, useState } from 'react';

type Product = {
  id: number;
  title: string;
  price: number;
};

export function ProductCard({ product }: { product: Product }) {
  const [quantity, setQuantity] = useState(1);

  const subtotal = useMemo(() => {
    return product.price * quantity;
  }, [product.price, quantity]);

  return (
    <article className="rounded-lg border p-4">
      <h3>{product.title}</h3>
      <p>${product.price.toFixed(2)}</p>
      <label htmlFor={`qty-${product.id}`}>Qty</label>
      <input
        id={`qty-${product.id}`}
        type="number"
        min={1}
        value={quantity}
        onChange={(event) => setQuantity(Number(event.target.value))}
      />
      <p>Total: ${subtotal.toFixed(2)}</p>
    </article>
  );
}
```

## Data Fetching in Effects
```tsx
import { useEffect, useState } from 'react';

function useProducts() {
  const [products, setProducts] = useState([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const controller = new AbortController();

    (async () => {
      try {
        const response = await fetch('/api/products', { signal: controller.signal });
        if (!response.ok) throw new Error('Failed to load products');
        const payload = await response.json();
        if (active) setProducts(payload);
      } catch (err) {
        if ((err as DOMException).name !== 'AbortError') {
          setError((err as Error).message);
        }
      }
    })();

    return () => {
      active = false;
      controller.abort();
    };
  }, []);

  return { products, error };
}
```

## State Management
- Prefer local state first, then context, then external store (Zustand, Redux Toolkit, Jotai).
- Keep mutations co-located with UI interactions to reduce implicit global coupling.

## Performance
- Memoize expensive derived values with `useMemo` and stable callbacks with `useCallback`.
- Split code with `React.lazy` and `Suspense` for route/component-level code splitting.
- Debounce search input and throttle scroll/resize listeners.

## Accessibility
- Use semantic markup and explicit labels.
- Ensure all interactive controls have accessible names.
- Manage focus for modals, drawers, and route transitions.
