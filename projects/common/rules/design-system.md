# Design System Rules

## Purpose

Maintain visual consistency and prevent design drift across web projects.

## Design Token Priority

Always check for existing design tokens before using arbitrary values:

```ts
// Check in this order:
// 1. Tailwind config (tailwind.config.ts / @theme {} block)
// 2. CSS custom properties in globals.css
// 3. shadcn/ui CSS variables (--primary, --background, etc.)
// 4. Only then consider arbitrary values
```

```css
/* Bad — arbitrary color that bypasses the design system */
.button { background: #2563eb; }

/* Good — uses the design token */
.button { background: var(--color-primary); }
/* or Tailwind: */
<div class="bg-primary" />
```

## Component Structure

All reusable components must follow this structure:

```tsx
// Good — composable, typed, accessible
interface CardProps {
  children: React.ReactNode;
  className?: string;
  as?: React.ElementType;
}

export function Card({ children, className, as: Component = 'div' }: CardProps) {
  return (
    <Component className={cn('rounded-lg border bg-card p-6 shadow-sm', className)}>
      {children}
    </Component>
  );
}

// Avoid — hardcoded styles, no composition
function Card({ title, body }) {
  return (
    <div style={{ border: '1px solid #ccc', padding: '24px', borderRadius: '8px' }}>
      <h3>{title}</h3>
      <p>{body}</p>
    </div>
  );
}
```

## Variant Management (cva)

Use `class-variance-authority` for multi-variant components:

```tsx
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

const buttonVariants = cva(
  'inline-flex items-center justify-center rounded-md font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground hover:bg-primary/90',
        destructive: 'bg-destructive text-destructive-foreground hover:bg-destructive/90',
        outline: 'border border-input bg-background hover:bg-accent',
        ghost: 'hover:bg-accent hover:text-accent-foreground',
      },
      size: {
        sm: 'h-8 px-3 text-xs',
        md: 'h-10 px-4 text-sm',
        lg: 'h-12 px-6 text-base',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'md',
    },
  }
);

interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export function Button({ variant, size, className, ...props }: ButtonProps) {
  return (
    <button className={cn(buttonVariants({ variant, size }), className)} {...props} />
  );
}
```

## Spacing Scale

Use the spacing scale consistently. Never mix scale values with arbitrary values:

```html
<!-- Good — uses scale -->
<div class="p-4 mt-6 gap-2">

<!-- Avoid — mixing scales and arbitrary values -->
<div class="p-4 mt-[24px] gap-2">
```

## Typography Hierarchy

Maintain a consistent type scale. Check existing headings before adding new sizes:

```html
<!-- Enforce logical heading order: h1 → h2 → h3 -->
<!-- Use text-* utilities from the type scale, not arbitrary sizes -->
<h1 class="text-4xl font-bold tracking-tight">Page Title</h1>
<h2 class="text-2xl font-semibold">Section Title</h2>
<h3 class="text-xl font-medium">Subsection</h3>
<p class="text-base text-muted-foreground">Body text</p>
```

## Color Usage Rules

1. **Text on background**: Verify contrast ratio ≥ 4.5:1 (WCAG AA)
2. **Interactive elements**: Must have focus states (ring/outline)
3. **Status colors**: Use semantic tokens, not raw colors
   - Error: `text-destructive` / `bg-destructive`
   - Success: `text-green-600` / project token
   - Warning: `text-yellow-600` / project token
4. **Never** use color as the only way to convey information

## Icon Usage

```tsx
// Prefer a single icon library per project (Lucide, Heroicons, Phosphor)
import { ChevronRight, X, Check } from 'lucide-react';

// Always include aria-label for icon-only buttons
<button aria-label="Close dialog">
  <X className="h-4 w-4" />
</button>

// Decorative icons get aria-hidden
<Check className="h-4 w-4 text-green-600" aria-hidden="true" />
<span>Verified</span>
```

## Animation Rules

- Prefer CSS transitions (`transition-*` utilities) over JS animations for simple state changes
- Use Framer Motion / Motion for complex sequences, shared layout animations
- Always respect `prefers-reduced-motion`:
  ```css
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: 0.01ms !important;
      transition-duration: 0.01ms !important;
    }
  }
  ```

## Component Inventory Protocol

Before creating a new component:
1. Check `components/ui/` for existing primitives (shadcn/ui, Radix)
2. Check `components/` for existing feature components
3. Check `MEMORY.md` → Component Registry section
4. Only create new if nothing covers the need

After creating a new component, add it to MEMORY.md:
```markdown
### Component Registry
| Component | Path | Variants | Notes |
|-----------|------|----------|-------|
| Button | components/ui/button.tsx | default, outline, ghost | shadcn/ui |
| UserCard | components/features/UserCard.tsx | compact, full | custom |
```
