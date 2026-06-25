# Tailwind CSS Conventions

> **Verify the installed Tailwind major version before assuming config or syntax.**
> Check `package.json` (`tailwindcss` dependency) — do not assume a version. The
> two current lines differ significantly:
> - **v3:** JavaScript config (`tailwind.config.js` with `module.exports`), a
>   `content: []` array, and `@tailwind base/components/utilities` in CSS.
> - **v4:** CSS-first config — `@import "tailwindcss";` plus a `@theme { }` block
>   in your CSS; automatic content detection; `tailwind.config.js` is optional.
>
> The utility-class guidance below applies to both. The config example is v3-style;
> translate it to a `@theme` block when the project is on v4.

## General Principles
- Use Tailwind utilities; avoid custom CSS unless necessary
- Extract repeated patterns into components, not @apply
- Follow mobile-first responsive design (sm:, md:, lg:, xl:, 2xl:)
- Use design tokens from config (colors, spacing) not arbitrary values

## Class Organization
Order classes logically for readability:
1. Layout (flex, grid, container)
2. Position (relative, absolute, z-index)
3. Box model (w-, h-, p-, m-)
4. Typography (text-, font-, leading-)
5. Visual (bg-, border-, shadow-)
6. Interactive (hover:, focus:, transition)

```html
<div class="flex items-center justify-between p-4 bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow">
```

## Responsive Patterns
```html
<!-- Mobile-first: stack on mobile, row on md+ -->
<div class="flex flex-col md:flex-row gap-4">

<!-- Hide on mobile, show on lg+ -->
<nav class="hidden lg:block">

<!-- Different spacing at breakpoints -->
<section class="py-8 md:py-12 lg:py-16">
```

## Common Utility Combinations

### Centering
```html
<!-- Flex center -->
<div class="flex items-center justify-center">

<!-- Grid center -->
<div class="grid place-items-center">

<!-- Absolute center -->
<div class="absolute inset-0 flex items-center justify-center">
```

### Cards
```html
<div class="bg-white rounded-lg shadow-md overflow-hidden">
  <img class="w-full h-48 object-cover" src="..." alt="...">
  <div class="p-4">
    <h3 class="font-semibold text-lg">Title</h3>
    <p class="text-gray-600 mt-2">Description</p>
  </div>
</div>
```

### Buttons
```html
<button class="inline-flex items-center justify-center px-4 py-2 bg-blue-600 text-white font-medium rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors">
  Button
</button>
```

### Forms
```html
<input type="text" class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500">

<label class="flex items-center gap-2">
  <input type="checkbox" class="w-4 h-4 text-blue-600 rounded border-gray-300 focus:ring-blue-500">
  <span class="text-sm text-gray-700">Remember me</span>
</label>
```

### Typography
```html
<!-- Prose for long-form content -->
<article class="prose prose-lg max-w-none">

<!-- Truncate text -->
<p class="truncate">...</p>
<p class="line-clamp-3">...</p>
```

## Customization
<!-- v3 (JS config) shown below. For v4, define the same tokens in a CSS `@theme { }` block instead. -->
```javascript
// tailwind.config.js — Tailwind v3
module.exports = {
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        heading: ['Poppins', 'sans-serif'],
      },
      spacing: {
        '18': '4.5rem',
        '88': '22rem',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
  ],
}
```

## Dark Mode
```html
<!-- Class-based dark mode -->
<div class="bg-white dark:bg-gray-900 text-gray-900 dark:text-white">

<!-- Toggle dark mode via class on html element -->
<html class="dark">
```

## Avoid
- Arbitrary values when design token exists: use `p-4` not `p-[17px]`
- @apply for one-off styles
- !important (use proper specificity)
- Inline styles alongside Tailwind classes
- Overly long class strings — extract to components
