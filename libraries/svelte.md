# Svelte Conventions (2026)

## Core Principles
- Prefer Svelte's reactive assignments over manual effect frameworks.
- Keep component boundaries small and state as local as possible.
- Use runes (`$state`, `$derived`, `$effect`) for concise reactivity when available.
- Keep fetch and side effects inside explicit lifecycle blocks.

## Component Example
```svelte
<script>
  import { onMount } from 'svelte';

  let price = 19.99;
  let quantity = 1;
  $: subtotal = price * quantity;

  async function onSubmit() {
    await fetch('/api/order', {
      method: 'POST',
      body: JSON.stringify({ quantity }),
      headers: { 'Content-Type': 'application/json' },
    });
  }

  onMount(async () => {
    const res = await fetch('/api/initialize');
    const data = await res.json();
  });
</script>

<article>
  <p>{subtotal.toFixed(2)}</p>
  <button on:click={() => quantity += 1}>+1</button>
  <button on:click={onSubmit}>Buy</button>
</article>
```

## Stores
```ts
import { writable, derived } from 'svelte/store';

export const quantity = writable(1);
export const price = writable(19.99);
export const subtotal = derived([quantity, price], ([$quantity, $price]) => $quantity * $price);
```

## Reactive Patterns
- Use `$:` for derived values from local state.
- Use derived stores for shared cross-component calculations.
- Use `bind:` for simple form synchronization, not manual DOM mutation.

## Performance
- Prefer props + slots to deep context nesting.
- Use keyed `{#each}` blocks to avoid DOM churn.
- Memoize expensive calculations with derived stores or computed functions.

## Accessibility
- Use native form controls.
- Ensure all buttons with icons include `aria-label`.
- Keep keyboard interactions explicit for custom gestures.
