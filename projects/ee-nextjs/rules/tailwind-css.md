# Tailwind CSS Rules (React/TSX)

These rules MUST be followed when writing Tailwind CSS classes in React/TSX components.

## Brand Color System

### Using Brand Colors
- ALWAYS check project's `tailwind.config.ts` for brand colors
- Use brand color names defined in the config
- Use `text-gray-*` for body text (gray-800, gray-700, gray-600)
- Use `bg-white` and `bg-gray-*` for backgrounds
- NEVER use arbitrary color values (text-[#abc123])
- NEVER use default Tailwind colors for brand elements

### Check tailwind.config.ts
```typescript
// Example brand colors (check actual project config)
import type { Config } from 'tailwindcss';

const config: Config = {
  theme: {
    extend: {
      colors: {
        'brand-primary': '#0066cc',
        'brand-secondary': '#ff6600',
      },
    },
  },
};
```

### Color Usage
```tsx
// Correct:
<button className="text-white bg-brand-primary hover:bg-opacity-90">
<button className="border-2 border-brand-primary text-brand-primary hover:bg-brand-primary hover:text-white">

// Incorrect:
<button className="text-white bg-blue-500">
<button className="bg-[#0066cc] text-white">
```

## Responsive Design (Mobile-First)

### Breakpoint Rules
- ALWAYS write mobile styles first (no prefix)
- Use `sm:`, `md:`, `lg:`, `xl:` for larger screens
- Test on mobile devices
- NEVER write desktop-first styles

**Correct:**
```tsx
{/* Mobile: stacked, Desktop: side-by-side */}
<div className="flex flex-col md:flex-row gap-4">
  <div className="w-full md:w-1/2">Column 1</div>
  <div className="w-full md:w-1/2">Column 2</div>
</div>

{/* Mobile: small text, Desktop: larger */}
<h1 className="text-2xl md:text-4xl lg:text-5xl">{title}</h1>
```

## Spacing and Layout

### Consistent Spacing
- Use Tailwind's spacing scale (0, 1, 2, 4, 6, 8, 12, 16, 20, 24...)
- Use `space-y-*` for vertical spacing between children
- Use `gap-*` for flexbox/grid spacing
- NEVER use arbitrary values unless absolutely necessary

**Correct:**
```tsx
{/* Consistent vertical spacing */}
<div className="space-y-4">
  <p>Paragraph 1</p>
  <p>Paragraph 2</p>
</div>

{/* Grid with gaps */}
<div className="grid grid-cols-1 md:grid-cols-3 gap-6">
  {entries.map((entry) => (
    <div key={entry.id}>{entry.title}</div>
  ))}
</div>
```

## Typography

### Font Size and Line Height
- Use Tailwind's text size classes (text-sm, text-base, text-lg, etc.)
- Use `prose` class for rich text content from CMS
- NEVER manually set font sizes with arbitrary values

**Correct:**
```tsx
<h1 className="text-4xl font-bold">{entry.title}</h1>
<p className="text-base text-gray-700">{entry.summary}</p>

{/* Rich text content from ExpressionEngine */}
<div
  className="prose prose-lg max-w-none"
  dangerouslySetInnerHTML={{ __html: entry.body }}
/>
```

## Utility Class Organization

### Class Order Convention
1. Layout (flex, grid, position)
2. Spacing (margin, padding)
3. Sizing (width, height)
4. Typography (font, text)
5. Visual (background, border, shadow)
6. Interactive (hover, focus, active)

**Correct:**
```tsx
<button className="flex items-center px-6 py-3 text-base font-semibold text-white bg-brand-primary rounded-lg shadow-md hover:bg-opacity-90 focus:outline-none focus:ring-2 focus:ring-brand-primary">
  Click Me
</button>
```

## Common Patterns

### Buttons
```tsx
{/* Primary button */}
<Link
  href={entry.url}
  className="inline-block px-6 py-3 text-white bg-brand-primary rounded-lg hover:bg-opacity-90 transition"
>
  {entry.buttonText}
</Link>

{/* Secondary button */}
<Link
  href={entry.url}
  className="inline-block px-6 py-3 border-2 border-brand-primary text-brand-primary rounded-lg hover:bg-brand-primary hover:text-white transition"
>
  {entry.buttonText}
</Link>
```

### Cards
```tsx
<div className="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition">
  <h3 className="text-xl font-bold mb-2">{entry.title}</h3>
  <p className="text-gray-600 mb-4">{entry.summary}</p>
  <Link href={entry.url} className="text-brand-primary hover:underline">
    Read more
  </Link>
</div>
```

### Grid Layouts
```tsx
{/* Responsive grid: 1 col mobile, 2 cols tablet, 3 cols desktop */}
<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  {entries.map((entry) => (
    <div key={entry.id} className="bg-white rounded-lg p-6">
      {entry.title}
    </div>
  ))}
</div>
```

## Container and Max Width

### Content Width Management
- Use `container mx-auto` for centered content
- Use `max-w-*` utilities for content width
- Add horizontal padding for mobile

**Correct:**
```tsx
<div className="container mx-auto px-4 max-w-7xl">
  {/* Content */}
</div>
```

## Performance Best Practices

### Content Paths for Purging
```typescript
// tailwind.config.ts
const config: Config = {
  content: [
    './app/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './lib/**/*.{ts,tsx}',
  ],
};
```

### Avoiding Bloat
- Use `@apply` sparingly (prefer utility classes in components)
- NEVER create unnecessary custom CSS
- Use `cn()` or `clsx()` for conditional classes

```tsx
import { cn } from '@/lib/utils';

<button className={cn(
  'px-4 py-2 rounded-lg transition',
  variant === 'primary' && 'bg-brand-primary text-white',
  variant === 'secondary' && 'border-2 border-brand-primary text-brand-primary',
)}>
  {children}
</button>
```

## Accessibility with Tailwind

### Focus States
- ALWAYS include visible focus states
- Use `focus:ring-*` for focus indicators
- NEVER use `focus:outline-none` without replacement

```tsx
<button className="bg-brand-primary text-white px-6 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-primary focus:ring-offset-2">
  Click Me
</button>
```

### Screen Reader Only Content
```tsx
<Link href={entry.url}>
  Read more
  <span className="sr-only">about {entry.title}</span>
</Link>
```

## Checklist

Before committing:
- [ ] Brand colors are used consistently
- [ ] Mobile-first responsive design is applied
- [ ] Spacing scale is consistent
- [ ] Focus states are visible
- [ ] No arbitrary values (unless documented why)
- [ ] Classes are organized logically
- [ ] Accessibility is maintained
