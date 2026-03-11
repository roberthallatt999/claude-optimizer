# Tailwind CSS Rules

These rules MUST be followed when writing styles with Tailwind CSS.

## Utility-First Approach
- Prefer Tailwind utility classes over custom CSS
- Use `@apply` sparingly (only for repeated complex patterns)
- Keep component styles co-located in Vue `<template>` blocks

## Responsive Design
- Use mobile-first approach: `sm:`, `md:`, `lg:`, `xl:`, `2xl:`
- Default styles apply to mobile; add breakpoint prefixes for larger screens
- Test all breakpoints before committing

## Component Patterns

```vue
<!-- Correct: utilities in template -->
<template>
  <div class="flex items-center gap-4 p-6 bg-white rounded-lg shadow-md">
    <h2 class="text-xl font-bold text-gray-900">{{ title }}</h2>
    <p class="text-gray-600 mt-2">{{ description }}</p>
  </div>
</template>

<!-- Avoid: excessive @apply -->
<style>
/* Only use @apply for truly repeated complex patterns */
.btn-primary {
  @apply inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:ring-2 focus:ring-offset-2 focus:ring-blue-500;
}
</style>
```

## Dark Mode
- Use `dark:` variant when dark mode is supported
- Ensure all interactive states have dark mode variants

## Performance
- Configure `content` paths in `tailwind.config.ts` to include all template files
- Avoid dynamically constructing class names (breaks purging)
- Use arbitrary values `[]` sparingly

## Checklist
- [ ] Mobile-first responsive design applied
- [ ] Hover/focus states defined for interactive elements
- [ ] Proper spacing scale used (not arbitrary px values)
- [ ] Color palette uses project's design tokens
