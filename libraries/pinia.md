# Pinia Conventions (Vue)

> Pinia is the official Vue state management library (replaces Vuex).
> Check `package.json` for `"pinia"` version. v2 is stable and current.
> Works with Vue 3 and Nuxt 3 (auto-imported with `@pinia/nuxt` module).

## Setup

```ts
// main.ts (Vue standalone)
import { createApp } from 'vue';
import { createPinia } from 'pinia';
import App from './App.vue';

const app = createApp(App);
app.use(createPinia());
app.mount('#app');
```

```ts
// nuxt.config.ts (Nuxt 3 — Pinia is auto-imported)
export default defineNuxtConfig({
  modules: ['@pinia/nuxt'],
});
```

## Defining Stores

### Composition API Style (Recommended)
```ts
// stores/counter.ts
import { ref, computed } from 'vue';
import { defineStore } from 'pinia';

export const useCounterStore = defineStore('counter', () => {
  // state
  const count = ref(0);
  const name = ref('Eduardo');

  // getters (computed)
  const doubleCount = computed(() => count.value * 2);
  const greeting = computed(() => `Hello, ${name.value}!`);

  // actions
  function increment() {
    count.value++;
  }

  function reset() {
    count.value = 0;
  }

  return { count, name, doubleCount, greeting, increment, reset };
});
```

### Options API Style (Alternative)
```ts
// stores/user.ts
import { defineStore } from 'pinia';

export const useUserStore = defineStore('user', {
  state: () => ({
    user: null as User | null,
    isLoading: false,
  }),

  getters: {
    isAuthenticated: (state) => !!state.user,
    displayName: (state) => state.user?.name ?? 'Guest',
  },

  actions: {
    async login(email: string, password: string) {
      this.isLoading = true;
      try {
        this.user = await authService.login(email, password);
      } finally {
        this.isLoading = false;
      }
    },

    logout() {
      this.user = null;
    },
  },
});
```

## Usage in Components

```vue
<script setup lang="ts">
import { storeToRefs } from 'pinia';
import { useCounterStore } from '@/stores/counter';
import { useUserStore } from '@/stores/user';

const counterStore = useCounterStore();
const userStore = useUserStore();

// Destructure reactive properties with storeToRefs (preserves reactivity)
// Don't destructure actions — they don't need storeToRefs
const { count, doubleCount } = storeToRefs(counterStore);
const { user, isAuthenticated } = storeToRefs(userStore);

// Actions can be destructured directly
const { increment, reset } = counterStore;
</script>

<template>
  <div>
    <p>Count: {{ count }} (double: {{ doubleCount }})</p>
    <button @click="increment">+</button>
    <button @click="reset">Reset</button>
    <p v-if="isAuthenticated">Welcome, {{ user?.name }}!</p>
  </div>
</template>
```

## Async Actions

```ts
// stores/posts.ts
import { defineStore } from 'pinia';
import { ref } from 'vue';

export const usePostStore = defineStore('posts', () => {
  const posts = ref<Post[]>([]);
  const status = ref<'idle' | 'loading' | 'error'>('idle');
  const error = ref<string | null>(null);

  async function fetchPosts() {
    status.value = 'loading';
    error.value = null;
    try {
      const response = await fetch('/api/posts');
      if (!response.ok) throw new Error('Failed to fetch posts');
      posts.value = await response.json();
      status.value = 'idle';
    } catch (err) {
      error.value = (err as Error).message;
      status.value = 'error';
    }
  }

  async function createPost(data: CreatePostInput) {
    const response = await fetch('/api/posts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!response.ok) throw new Error('Failed to create post');
    const post: Post = await response.json();
    posts.value.unshift(post);
    return post;
  }

  return { posts, status, error, fetchPosts, createPost };
});
```

## Store Composition (Cross-store Access)

```ts
// stores/cart.ts — uses user store
import { defineStore } from 'pinia';
import { useUserStore } from './user';

export const useCartStore = defineStore('cart', () => {
  // Compose with another store inside actions/getters
  function checkout() {
    const userStore = useUserStore();
    if (!userStore.isAuthenticated) throw new Error('Must be logged in');
    // ...
  }

  return { checkout };
});
```

## Persistence (Plugin)

```ts
// main.ts — add persistence plugin
import { createPinia } from 'pinia';
import piniaPluginPersistedstate from 'pinia-plugin-persistedstate';

const pinia = createPinia();
pinia.use(piniaPluginPersistedstate);

// In store — enable persistence
export const useSettingsStore = defineStore('settings', {
  state: () => ({ theme: 'light', locale: 'en' }),
  persist: true, // persists entire state to localStorage
  // or: persist: { key: 'app-settings', storage: sessionStorage, pick: ['theme'] }
});
```

## Nuxt 3 — SSR Considerations

```ts
// In composables or pages — Pinia is auto-imported in Nuxt
const store = usePostStore();

// Fetch on server (runs during SSR, state hydrated to client)
await store.fetchPosts();

// For server-only setup in useAsyncData
const { data } = await useAsyncData('posts', () => store.fetchPosts());
```

## Testing Stores

```ts
import { setActivePinia, createPinia } from 'pinia';
import { useCounterStore } from '@/stores/counter';

describe('Counter Store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('increments count', () => {
    const store = useCounterStore();
    expect(store.count).toBe(0);
    store.increment();
    expect(store.count).toBe(1);
  });
});
```

## When to Use Pinia

- Shared state between unrelated components
- User auth session across the app
- Shopping cart, notification queue, multi-step forms
- Data cached at the app level (avoid re-fetching)

**Don't use for:** Server data with caching (prefer VueQuery/nuxt-query), route params (use `useRoute`), component-local state.

## Avoid

- Destructuring store state without `storeToRefs` — loses reactivity
- Calling `useStore()` at the top level of a non-setup context (use inside `setup` or `<script setup>`)
- Direct mutation of state outside actions in options stores
- Circular store dependencies (A imports B imports A)
