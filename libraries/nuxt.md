# Nuxt Conventions (2026)

## Core Principles
- Prefer file-based routing with `pages/` and server routes for shared rendering patterns.
- Use composables for data loading and side-effect encapsulation.
- Use caching and hydration boundaries to reduce waterfall requests.

## Page Example
```vue
<script setup>
const route = useRoute();
const { data: post } = await useAsyncData(`post-${route.params.slug}`, () =>
  $fetch(`/api/posts/${route.params.slug}`)
);
</script>

<template>
  <article v-if="post">
    <h1>{{ post.title }}</h1>
    <ContentRenderer :value="post.body" />
  </article>
</template>
```

## Server API Routes
```ts
// server/api/products.get.ts
export default defineEventHandler(async () => {
  return [{ id: 1, name: 'Product A' }];
});
```

## SEO and Meta
```ts
useHead({
  title: 'Product Catalog',
  meta: [
    { name: 'description', content: 'Discover latest products' },
  ],
});
```

## Performance
- Use `useAsyncData` with explicit keys for cache reuse.
- Keep payload small and avoid over-fetching in shared layouts.
- Use lazy hydration for non-critical client widgets.
