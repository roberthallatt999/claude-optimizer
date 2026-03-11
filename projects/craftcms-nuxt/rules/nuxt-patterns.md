# Nuxt 3 Patterns and Best Practices

These rules MUST be followed when developing with Nuxt 3.

## Component Structure

### Script Setup
- Use `<script setup lang="ts">` for all components
- Use Composition API exclusively (no Options API)
- Leverage auto-imports (no manual imports for Vue/Nuxt APIs)

```vue
<script setup lang="ts">
// Props
const props = defineProps<{
  title: string;
  count?: number;
}>();

// Emits
const emit = defineEmits<{
  update: [value: string];
}>();

// Composables
const { data } = await useFetch('/api/data');
</script>

<template>
  <div>
    <h1>{{ title }}</h1>
  </div>
</template>
```

## Data Fetching

### useFetch and useAsyncData
- Use `useFetch` for simple API calls
- Use `useAsyncData` for complex data fetching logic
- NEVER use `$fetch` in components directly (causes double fetching in SSR)

```vue
<script setup lang="ts">
// Simple fetch
const { data: posts } = await useFetch('/api/posts');

// With options
const { data, pending, error, refresh } = await useFetch('/api/posts', {
  query: { page: 1 },
  transform: (response) => response.data,
});

// Complex fetching with useAsyncData
const { data: combined } = await useAsyncData('combined', async () => {
  const [posts, categories] = await Promise.all([
    $fetch('/api/posts'),
    $fetch('/api/categories'),
  ]);
  return { posts, categories };
});
</script>
```

## Routing

### File-Based Routes
```
pages/
├── index.vue           # /
├── about.vue           # /about
├── blog/
│   ├── index.vue       # /blog
│   └── [slug].vue      # /blog/:slug
├── [...slug].vue       # Catch-all
└── [[optional]].vue    # Optional param
```

### Route Middleware
```typescript
// middleware/auth.ts
export default defineNuxtRouteMiddleware((to, from) => {
  const { loggedIn } = useUserSession();
  if (!loggedIn.value) {
    return navigateTo('/login');
  }
});
```

## Layouts

```vue
<!-- layouts/default.vue -->
<template>
  <div>
    <AppHeader />
    <main>
      <slot />
    </main>
    <AppFooter />
  </div>
</template>

<!-- Usage in page -->
<script setup lang="ts">
definePageMeta({
  layout: 'default',
});
</script>
```

## SEO & Head

```vue
<script setup lang="ts">
// Per-page head
useHead({
  title: 'Page Title',
  meta: [
    { name: 'description', content: 'Page description' },
  ],
});

// Or use useSeoMeta for convenience
useSeoMeta({
  title: 'Page Title',
  ogTitle: 'Page Title',
  description: 'Description',
  ogDescription: 'Description',
  ogImage: '/og-image.jpg',
});
</script>
```

## State Management

### useState (SSR-safe)
```typescript
// composables/useCounter.ts
export const useCounter = () => {
  const count = useState('counter', () => 0);
  const increment = () => count.value++;
  return { count, increment };
};
```

### Pinia (complex state)
```typescript
// stores/auth.ts
export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null);
  const isLoggedIn = computed(() => !!user.value);

  async function login(credentials: Credentials) {
    user.value = await $fetch('/api/auth/login', {
      method: 'POST',
      body: credentials,
    });
  }

  return { user, isLoggedIn, login };
});
```

## Server Routes

```typescript
// server/api/posts.get.ts
export default defineEventHandler(async (event) => {
  const query = getQuery(event);
  // Proxy to Craft CMS GraphQL
  const data = await $fetch(process.env.CRAFT_GRAPHQL_URL!, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.CRAFT_GRAPHQL_TOKEN}`,
    },
    body: { query: POSTS_QUERY, variables: query },
  });
  return data;
});
```

## Checklist

- [ ] Components use `<script setup lang="ts">`
- [ ] Data fetching uses `useFetch` or `useAsyncData` (not `$fetch` in components)
- [ ] SEO meta defined with `useHead` or `useSeoMeta`
- [ ] Sensitive API tokens are in server-side code only
- [ ] Layouts and pages follow file-based conventions
- [ ] TypeScript types defined for all props and API responses
