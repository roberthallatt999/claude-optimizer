# Vue Conventions (2026)

## Core Principles
- Use `<script setup>` and Composition API by default.
- Keep template logic declarative; put complex logic in computed properties and composables.
- Use `v-bind` shorthands (`:` and `@`) for readability.
- Prefer props-first and event-first component APIs.

## Component Example
```vue
<script setup lang="ts">
import { computed, ref } from 'vue';

const props = defineProps<{ price: number }>();
const emit = defineEmits<{ (e: 'buy', quantity: number): void }>();

const quantity = ref(1);
const subtotal = computed(() => props.price * quantity.value);

function increase() {
  quantity.value += 1;
}

function checkout() {
  emit('buy', quantity.value);
}
</script>

<template>
  <article class="card">
    <p>{{ quantity }} item(s)</p>
    <p>${{ subtotal.toFixed(2) }}</p>
    <button @click="increase">+1</button>
    <button @click="checkout">Buy</button>
  </article>
</template>
```

## Composables
```ts
import { onMounted, ref } from 'vue';

export function useProducts() {
  const items = ref([]);
  const loading = ref(false);

  onMounted(async () => {
    loading.value = true;
    try {
      items.value = await (await fetch('/api/products')).json();
    } finally {
      loading.value = false;
    }
  });

  return { items, loading };
}
```

## Reactive Patterns
- Use `computed` for transformations; avoid recalculating in templates.
- Use `watch` for side effects, never for pure derivation.
- Keep `ref` and `reactive` boundaries clear: one source of truth per concern.

## Performance
- Lazy-load large routes/components with `defineAsyncComponent`.
- Use `v-memo` for static sections of large lists.
- Use `:key` in `v-for` loops for stable rendering.

## Accessibility
- Prefer native form controls over custom replacements.
- Use explicit labels, ARIA attributes on custom widgets, and proper keyboard support.
