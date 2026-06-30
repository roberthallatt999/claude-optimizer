---
name: design-system-builder
description: "Use when establishing or extending a project's design system — creating/updating design tokens, building component libraries, documenting visual patterns, or auditing design consistency."
---

# Design System Builder

Build, document, and maintain a consistent design system — from token setup through component library to audit.

<HARD-GATE>
Before creating ANY new component or token, check the existing Component Registry in MEMORY.md and scan `components/ui/` and `components/` directories. Do NOT create something that already exists.
</HARD-GATE>

## When to Use This Skill

Invoke when the user wants to:
- Set up a new design system from scratch
- Add design tokens (colors, typography, spacing, radius)
- Create new reusable components with proper variants
- Audit existing components for consistency
- Document an existing design system
- Migrate from arbitrary styles to a token-based system

## Phase 1: Discovery

1. **Read MEMORY.md** — check existing Design Tokens, Component Registry, and Tech Stack
2. **Scan component directories** — `components/ui/`, `components/`, `src/components/`
3. **Check existing token setup:**
   - Tailwind: `tailwind.config.ts` or `@theme {}` block in CSS
   - shadcn/ui: CSS custom properties in `globals.css`
   - Plain CSS: `:root` custom properties
4. **Identify framework** — affects component patterns (React/Vue/Svelte)

## Phase 2: Token Audit

Check for these token categories and flag gaps:

| Category | CSS Variable Pattern | Tailwind Config Key |
|----------|---------------------|---------------------|
| Colors | `--color-primary`, `--color-bg` | `colors` |
| Typography | `--font-sans`, `--font-heading` | `fontFamily` |
| Spacing | (use Tailwind scale) | `spacing` |
| Border radius | `--radius` | `borderRadius` |
| Shadows | (use Tailwind scale) | `boxShadow` |
| Transitions | `--duration-fast: 150ms` | `transitionDuration` |

Report gaps to the user before proceeding.

## Phase 3: Component Inventory

Before building anything, create a table:

```markdown
| Component | Exists? | Location | Gaps/Issues |
|-----------|---------|----------|-------------|
| Button | Yes | components/ui/button.tsx | Missing loading state |
| Input | Yes | components/ui/input.tsx | Missing error state |
| Modal | No | — | Needs building |
| Card | Partial | components/Card.tsx | Not typed, no variants |
```

Present the table to the user and agree on priority order before building.

## Phase 4: Building Components

For each new or updated component:

1. **Check shadcn/ui first** — run `npx shadcn@latest add [name]` if applicable
2. **Follow the variant pattern** — use `cva` (class-variance-authority) for multi-variant components
3. **Type all props** — extend HTML element props where appropriate
4. **Include states** — default, hover, focus, disabled, loading, error
5. **Test accessibility** — keyboard nav, aria labels, focus management
6. **Export from index** — add to `components/ui/index.ts` barrel file

### Component Template

```tsx
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

const componentVariants = cva(
  'base-classes',
  {
    variants: {
      variant: { default: '', /* ... */ },
      size: { sm: '', md: '', lg: '' },
    },
    defaultVariants: { variant: 'default', size: 'md' },
  }
);

interface ComponentProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof componentVariants> {
  // Additional props
}

export function Component({ variant, size, className, ...props }: ComponentProps) {
  return (
    <div className={cn(componentVariants({ variant, size }), className)} {...props} />
  );
}
```

## Phase 5: Documentation

After building, update:

1. **MEMORY.md Component Registry** — add new entries to the table
2. **MEMORY.md Design Tokens** — document any new tokens added
3. **Storybook or docs** (if present) — add component story

## Phase 6: Consistency Audit

When asked to audit existing code:

1. Search for hardcoded colors: `grep -r "style={{" --include="*.tsx"` and `grep -r "#[0-9a-fA-F]{3,6}"` 
2. Search for inline styles that should be utilities: `grep -r "style={"` 
3. Search for magic spacing numbers: `px-\[`, `py-\[`, `m-\[`, `p-\[`
4. Report findings in a table with file references
5. Propose replacements using existing tokens

## Key Principles

- **Tokens over hardcodes** — every color, font, and spacing value should reference a token
- **Composition over inheritance** — build small primitives, compose into features
- **Accessibility by default** — focus states, ARIA, color contrast built in
- **Progressive enhancement** — base styles work without JS, enhance with interaction
- **Single source of truth** — design tokens defined once, used everywhere
- **YAGNI** — only build what's needed; don't build speculative variants
