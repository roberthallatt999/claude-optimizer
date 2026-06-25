# Tailwind CSS Rules

These rules MUST be followed when writing Tailwind CSS classes for Craft CMS projects.

## Brand Color System

### Using Brand Colors
- ✅ ALWAYS check project's `tailwind.config.js` for brand colors
- ✅ Use brand color names defined in the config
- ✅ Use `text-gray-*` for body text (gray-800, gray-700, gray-600)
- ✅ Use `bg-white` and `bg-gray-*` for backgrounds
- ❌ NEVER use arbitrary color values (text-[#abc123])
- ❌ NEVER use default Tailwind colors for brand elements

### Check tailwind.config.js
```javascript
// Example brand colors (check actual project config)
module.exports = {
  theme: {
    extend: {
      colors: {
        'brand-primary': '#0066cc',
        'brand-secondary': '#ff6600',
      }
    }
  }
}
```

### Color Usage
```twig
✅ Correct:
<button class="text-white bg-brand-primary hover:bg-opacity-90">
<button class="border-2 border-brand-primary text-brand-primary hover:bg-brand-primary hover:text-white">

❌ Incorrect:
<button class="text-white bg-blue-500">
<button class="bg-[#0066cc] text-white">
```

## Responsive Design (Mobile-First)

### Breakpoint Rules
- ✅ ALWAYS write mobile styles first (no prefix)
- ✅ Use `sm:`, `md:`, `lg:`, `xl:` for larger screens
- ✅ Test on mobile devices
- ❌ NEVER write desktop-first styles

**Correct:**
```twig
{# Mobile: stacked, Desktop: side-by-side #}
<div class="flex flex-col md:flex-row gap-4">
  <div class="w-full md:w-1/2">Column 1</div>
  <div class="w-full md:w-1/2">Column 2</div>
</div>

{# Mobile: small text, Desktop: larger #}
<h1 class="text-2xl md:text-4xl lg:text-5xl">{{ entry.title }}</h1>
```

**Incorrect:**
```twig
{# Desktop-first (don't do this) #}
<div class="flex flex-row sm:flex-col">
```

## Spacing and Layout

### Consistent Spacing
- ✅ Use Tailwind's spacing scale (0, 1, 2, 4, 6, 8, 12, 16, 20, 24...)
- ✅ Use `space-y-*` for vertical spacing between children
- ✅ Use `gap-*` for flexbox/grid spacing
- ❌ NEVER use arbitrary values unless absolutely necessary

**Correct:**
```twig
{# Consistent vertical spacing #}
<div class="space-y-4">
  <p>Paragraph 1</p>
  <p>Paragraph 2</p>
  <p>Paragraph 3</p>
</div>

{# Grid with gaps #}
<div class="grid grid-cols-1 md:grid-cols-3 gap-6">
  {% for entry in entries %}
    <div>{{ entry.title }}</div>
  {% endfor %}
</div>
```

## Typography

### Font Size and Line Height
- ✅ Use Tailwind's text size classes (text-sm, text-base, text-lg, etc.)
- ✅ Tailwind automatically sets appropriate line-height
- ✅ Use `prose` class for rich text content
- ❌ NEVER manually set font sizes with arbitrary values

**Correct:**
```twig
<h1 class="text-4xl font-bold">{{ entry.title }}</h1>
<h2 class="text-2xl font-semibold">{{ entry.subtitle }}</h2>
<p class="text-base text-gray-700">{{ entry.summary }}</p>

{# Rich text content #}
<div class="prose prose-lg max-w-none">
  {{ entry.body }}
</div>
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
```twig
<button class="flex items-center px-6 py-3 text-base font-semibold text-white bg-brand-primary rounded-lg shadow-md hover:bg-opacity-90 focus:outline-none focus:ring-2 focus:ring-brand-primary">
  Click Me
</button>
```

## Common Patterns

### Buttons
```twig
{# Primary button #}
<a href="{{ entry.url }}" class="inline-block px-6 py-3 text-white bg-brand-primary rounded-lg hover:bg-opacity-90 transition">
  {{ entry.buttonText }}
</a>

{# Secondary button #}
<a href="{{ entry.url }}" class="inline-block px-6 py-3 border-2 border-brand-primary text-brand-primary rounded-lg hover:bg-brand-primary hover:text-white transition">
  {{ entry.buttonText }}
</a>
```

### Cards
```twig
<div class="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition">
  <h3 class="text-xl font-bold mb-2">{{ entry.title }}</h3>
  <p class="text-gray-600 mb-4">{{ entry.summary }}</p>
  <a href="{{ entry.url }}" class="text-brand-primary hover:underline">
    Read more
  </a>
</div>
```

### Grid Layouts
```twig
{# Responsive grid: 1 col mobile, 2 cols tablet, 3 cols desktop #}
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  {% for entry in entries %}
    <div class="bg-white rounded-lg p-6">
      {{ entry.title }}
    </div>
  {% endfor %}
</div>
```

## Container and Max Width

### Content Width Management
- ✅ Use `container mx-auto` for centered content
- ✅ Use `max-w-*` utilities for content width
- ✅ Add horizontal padding for mobile

**Correct:**
```twig
<div class="container mx-auto px-4 max-w-7xl">
  {# Content #}
</div>

{# Or for narrower content #}
<div class="mx-auto px-4 max-w-4xl">
  {# Content #}
</div>
```

## Performance Best Practices

### Avoiding Bloat
- ✅ Purge unused styles in production (configured in tailwind.config.js)
- ✅ Use `@apply` sparingly (prefer utility classes in templates)
- ✅ Use JIT mode for faster builds
- ❌ NEVER create unnecessary custom CSS

**tailwind.config.js:**
```javascript
module.exports = {
  content: [
    './templates/**/*.{twig,html}',
  ],
  // JIT is automatic in current Tailwind — verify the installed major version in package.json
}
```

## Dark Mode (if applicable)

### Dark Mode Classes
- ✅ Use `dark:` variant for dark mode styles
- ✅ Test both light and dark modes
- ❌ Don't assume default mode

**Example:**
```twig
<div class="bg-white dark:bg-gray-900 text-gray-900 dark:text-white">
  {{ entry.content }}
</div>
```

## Accessibility with Tailwind

### Focus States
- ✅ ALWAYS include visible focus states
- ✅ Use `focus:ring-*` for focus indicators
- ❌ NEVER use `focus:outline-none` without replacement

**Correct:**
```twig
<button class="bg-brand-primary text-white px-6 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-primary focus:ring-offset-2">
  Click Me
</button>
```

### Screen Reader Only Content
```twig
<a href="{{ entry.url }}">
  Read more
  <span class="sr-only">about {{ entry.title }}</span>
</a>
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
