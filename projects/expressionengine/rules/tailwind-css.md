---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx,css,scss}"
  - "**/tailwind.config.*"
---

# Tailwind CSS Rules

These rules MUST be followed when writing Tailwind CSS classes for the {{PROJECT_NAME}} website.

## Brand Color System

### Official Brand Colors
- ✅ `brand-green` ({{BRAND_GREEN}}) - Primary actions, hero sections, navigation
- ✅ `brand-blue` ({{BRAND_BLUE}}) - Links, secondary actions
- ✅ `brand-orange` ({{BRAND_ORANGE}}) - Highlights, important notices
- ✅ `brand-light-green` ({{BRAND_LIGHT_GREEN}}) - Light accents, hover states

### Color Usage Rules
- ✅ ALWAYS use brand colors for primary UI elements
- ✅ Use `text-gray-*` for body text (gray-800, gray-700, gray-600)
- ✅ Use `bg-white` and `bg-gray-*` for backgrounds
- ❌ NEVER use arbitrary color values (text-[#abc123])
- ❌ NEVER use default Tailwind colors (green-500, blue-500) for brand elements

### Correct Color Application

**Buttons:**
```html
✅ Correct:
<button class="text-white bg-brand-green hover:bg-opacity-90">
<button class="border-2 border-brand-blue text-brand-blue hover:bg-brand-blue hover:text-white">

❌ Incorrect:
<button class="text-white bg-green-500">
<button class="bg-[{{BRAND_GREEN}}] text-white">
```

**Links:**
```html
✅ Correct:
<a href="#" class="underline text-brand-blue hover:text-brand-green">

❌ Incorrect:
<a href="#" class="text-blue-500 hover:text-green-500">
```

**Headings:**
```html
✅ Correct:
<h1 class="text-4xl font-bold text-brand-green">

❌ Incorrect:
<h1 class="text-4xl font-bold text-green-700">
```

**Sections:**
```html
✅ Correct:
<section class="py-16 text-white bg-brand-green">

❌ Incorrect:
<section class="py-16 text-white bg-green-600">
```

## Responsive Design (Mobile-First)

### Breakpoint Usage
- ✅ ALWAYS start with mobile styles (no prefix)
- ✅ Add responsive variants progressively: `sm:`, `md:`, `lg:`, `xl:`
- ✅ Test at all breakpoints: mobile (base), tablet (md:), desktop (lg:)
- ❌ NEVER write desktop-first styles

### Breakpoints
- Base: < 640px (mobile)
- `sm:` 640px (large mobile)
- `md:` 768px (tablet)
- `lg:` 1024px (desktop)
- `xl:` 1280px (large desktop)

### Responsive Patterns

**Layout (Correct):**
```html
✅ Mobile-first:
<div class="flex flex-col gap-4 md:flex-row">

❌ Desktop-first:
<div class="flex flex-row gap-4 md:flex-col">
```

**Text Sizing (Correct):**
```html
✅ Mobile-first:
<h1 class="text-3xl font-bold md:text-4xl lg:text-5xl">

❌ Desktop-first:
<h1 class="text-5xl font-bold lg:text-4xl md:text-3xl">
```

**Grid (Correct):**
```html
✅ Mobile-first:
<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">

❌ Desktop-first:
<div class="grid grid-cols-3 gap-6 lg:grid-cols-2 md:grid-cols-1">
```

**Spacing (Correct):**
```html
✅ Mobile-first:
<section class="py-8 md:py-12 lg:py-20">

❌ Desktop-first:
<section class="py-20 lg:py-12 md:py-8">
```

## Container and Spacing

### Container Pattern
- ✅ ALWAYS use `container mx-auto px-4` for main content
- ✅ Use `max-w-*` classes for content width limits
- ✅ Use consistent padding: `px-4` for mobile, `px-6` for larger screens

**Correct:**
```html
<div class="container px-4 py-8 mx-auto">
  <div class="max-w-3xl mx-auto">
    {* content *}
  </div>
</div>
```

### Spacing Scale
- ✅ Use Tailwind's spacing scale: `px-4`, `py-8`, `gap-6`
- ✅ Maintain consistent spacing throughout the site
- ❌ NEVER use arbitrary values: `p-[17px]`

**Standard Spacing:**
- Small gaps: `gap-2`, `gap-4`
- Medium gaps: `gap-6`, `gap-8`
- Large gaps: `gap-10`, `gap-12`
- Section padding: `py-8`, `py-12`, `py-16`, `py-20`
- Container padding: `px-4`, `px-6`

## Typography

### Font Family
- ✅ ALWAYS use `font-sans` for body text
- ✅ System font stack is configured in tailwind.config.js
- ❌ NEVER use `font-serif`, `font-mono` unless specifically required

### Text Sizing
- ✅ Use responsive text sizes
- ✅ Maintain clear hierarchy

**Text Scale:**
```html
<h1 class="text-4xl md:text-5xl lg:text-6xl">  {* Main heading *}
<h2 class="text-3xl md:text-4xl">               {* Subheading *}
<h3 class="text-2xl md:text-3xl">               {* Section heading *}
<p class="text-base md:text-lg">                {* Body text *}
<small class="text-sm">                         {* Small text *}
```

### Line Height
- ✅ Use appropriate leading for readability
- Headings: `leading-tight`, `leading-snug`
- Body: `leading-normal`, `leading-relaxed`

**Correct:**
```html
<h1 class="text-4xl font-bold leading-tight">
<p class="text-lg leading-relaxed">
```

### Font Weight
- Headings: `font-bold` (700)
- Emphasis: `font-semibold` (600)
- Body: `font-normal` (400)
- Light: `font-light` (300)

## Layout Patterns

### Grid Layouts
- ✅ ALWAYS start with single column on mobile
- ✅ Add columns progressively at larger breakpoints

**2-Column:**
```html
<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
```

**3-Column:**
```html
<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
```

**4-Column:**
```html
<div class="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
```

### Flexbox Layouts
- ✅ Use flex for component-level layouts
- ✅ Switch flex direction at breakpoints

**Horizontal to Vertical:**
```html
<div class="flex flex-col items-center justify-between gap-4 md:flex-row">
```

**Centered Content:**
```html
<div class="flex items-center justify-center min-h-screen">
```

**Space Between:**
```html
<div class="flex items-center justify-between gap-4">
```

## Component Styling

### Buttons
- ✅ Use consistent padding: `px-6 py-3` or `px-4 py-2`
- ✅ Add hover states
- ✅ Add transitions
- ✅ Use brand colors

**Primary Button:**
```html
<button class="px-6 py-3 text-white transition-colors rounded-lg bg-brand-green hover:bg-opacity-90">
  Click Me
</button>
```

**Secondary Button:**
```html
<button class="px-6 py-3 transition-colors border-2 rounded-lg border-brand-blue text-brand-blue hover:bg-brand-blue hover:text-white">
  Learn More
</button>
```

**Alert Button:**
```html
<button class="px-6 py-3 text-white transition-colors rounded-lg bg-brand-orange hover:bg-opacity-90">
  Important
</button>
```

### Cards
- ✅ Use consistent styling across all cards
- ✅ Add subtle shadows
- ✅ Use rounded corners

**Standard Card:**
```html
<div class="p-6 bg-white rounded-lg shadow">
  <h3 class="mb-2 text-xl font-bold">Card Title</h3>
  <p class="text-gray-700">Card content</p>
</div>
```

**Bordered Card:**
```html
<div class="p-6 bg-white border-l-4 rounded shadow-sm border-brand-green">
  <h3 class="mb-2 text-xl font-bold">Card Title</h3>
  <p class="text-gray-700">Card content</p>
</div>
```

**Hover Effect Card:**
```html
<div class="p-6 transition-shadow bg-white rounded-lg shadow hover:shadow-lg">
  <h3 class="mb-2 text-xl font-bold">Card Title</h3>
  <p class="text-gray-700">Card content</p>
</div>
```

### Forms
- ✅ Consistent input styling
- ✅ Clear focus states
- ✅ Error states with brand-orange

**Input:**
```html
<input
  type="text"
  class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-brand-blue focus:ring-2 focus:ring-brand-blue/20"
/>
```

**Input with Error:**
```html
<input
  type="text"
  class="w-full px-4 py-2 border border-red-500 rounded-lg focus:outline-none focus:border-red-500 focus:ring-2 focus:ring-red-500/20"
/>
<p class="mt-1 text-sm text-red-500">Error message</p>
```

## Visual Effects

### Shadows
- ✅ Use Tailwind's shadow scale
- Light: `shadow-sm`
- Default: `shadow`
- Medium: `shadow-md`
- Large: `shadow-lg`

### Rounded Corners
- ✅ Use consistent rounding
- Small: `rounded` (4px)
- Medium: `rounded-lg` (8px)
- Full: `rounded-full` (circle/pill)

### Transitions
- ✅ ALWAYS add transitions to interactive elements
- ✅ Use `transition-colors` for color changes
- ✅ Use `transition-shadow` for shadow changes
- ✅ Use `transition-all` sparingly (performance)

**Correct:**
```html
<button class="transition-colors bg-brand-green hover:bg-opacity-90">
<div class="transition-shadow shadow hover:shadow-lg">
```

### Opacity
- ✅ Use opacity modifiers: `bg-brand-green/50` (50% opacity)
- ✅ Use `hover:bg-opacity-90` for button hover states

## Visibility and Display

### Responsive Visibility
- ✅ Hide/show elements at breakpoints when needed

**Hide on Mobile:**
```html
<div class="hidden md:block">
```

**Show Only on Mobile:**
```html
<div class="md:hidden">
```

**Responsive Display:**
```html
<div class="block md:inline-block lg:inline">
```

## Anti-Patterns to Avoid

### ❌ NEVER Do These:
1. **Arbitrary values** - Use Tailwind's scale
   ```html
   ❌ class="p-[17px] text-[#abc123]"
   ✅ class="p-4 text-brand-green"
   ```

2. **Non-brand colors for UI** - Always use brand colors
   ```html
   ❌ class="bg-green-500"
   ✅ class="bg-brand-green"
   ```

3. **Desktop-first responsive** - Always mobile-first
   ```html
   ❌ class="flex-row md:flex-col"
   ✅ class="flex-col md:flex-row"
   ```

4. **Inconsistent spacing** - Use spacing scale
   ```html
   ❌ class="px-3 py-5"
   ✅ class="px-4 py-6"
   ```

5. **Missing transitions** - Always animate changes
   ```html
   ❌ class="hover:bg-brand-green"
   ✅ class="transition-colors hover:bg-brand-green"
   ```

6. **Hardcoded widths** - Use responsive utilities
   ```html
   ❌ class="w-[350px]"
   ✅ class="w-full md:w-1/2 lg:w-1/3"
   ```

## Build Process

### Development
- ✅ Run `npm run dev` during development
- ✅ Watch mode rebuilds on file changes
- ✅ Live browser reload with Browser-Sync
- ✅ Unminified output for debugging

### Production
- ✅ Run `npm run build` before deployment
- ✅ Minified and optimized
- ✅ Unused classes removed (PurgeCSS)

## Validation Checklist

Before committing any Tailwind code:
- [ ] Brand colors used correctly
- [ ] Mobile-first responsive design
- [ ] Consistent spacing scale
- [ ] Transitions on interactive elements
- [ ] Proper container/padding structure
- [ ] Semantic class ordering
- [ ] No arbitrary values
- [ ] Tested at all breakpoints
