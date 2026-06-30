# Svelte / SvelteKit Conventions (2026)

> **Check which version is installed:** Svelte 5 (Runes) vs Svelte 4 (legacy reactive).
> Run `cat package.json | grep '"svelte"'`. Svelte 5 uses `$state`, `$derived`, `$effect`, `$props()`.
> Svelte 4 uses `export let`, `$:`, `on:` event syntax.

## Core Principles
- Prefer Svelte's reactive primitives over manual DOM manipulation.
- Keep component boundaries small and state as local as possible.
- Use Runes (`$state`, `$derived`, `$effect`) in new Svelte 5 code.
- Use SvelteKit `load` functions for data fetching — not `onMount` + fetch.

---

## Svelte 5 (Runes — New Code)

### Component with Runes
```svelte
<script lang="ts">
  // Props — replaces "export let"
  let { label = 'Submit', disabled = false, onclick }: {
    label?: string;
    disabled?: boolean;
    onclick: () => void;
  } = $props();

  // Reactive state — replaces "let x; $: ..."
  let count = $state(0);
  let doubled = $derived(count * 2);

  // Side effects — replaces "onMount" and reactive statements
  $effect(() => {
    document.title = `Count: ${count}`;
    return () => { document.title = 'App'; }; // cleanup
  });
</script>

<button {disabled} {onclick}>{label} ({count})</button>
```

### Svelte 5 Event Handling
```svelte
<!-- New event syntax (no on: prefix) -->
<button onclick={() => count++}>Click</button>
<input oninput={(e) => (value = e.currentTarget.value)} />
<form onsubmit={(e) => { e.preventDefault(); handleSubmit(); }}>
```

---

## Svelte 4 (Legacy — Existing Code)

### Component Pattern
```svelte
<script lang="ts">
  import { onMount } from 'svelte';

  export let price: number = 19.99;
  export let quantity: number = 1;

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

### Svelte 4 Stores
```ts
import { writable, derived } from 'svelte/store';

export const quantity = writable(1);
export const price = writable(19.99);
export const subtotal = derived([quantity, price], ([$q, $p]) => $q * $p);
```

---

## SvelteKit Patterns

### Data Loading (Load Functions)
```ts
// +page.server.ts — server only
import type { PageServerLoad } from './$types';
export const load: PageServerLoad = async ({ params, locals }) => {
  const post = await db.post.findUnique({ where: { slug: params.slug } });
  if (!post) error(404, 'Not found');
  return { post };
};
```

```svelte
<!-- +page.svelte -->
<script lang="ts">
  import type { PageData } from './$types';
  let { data }: { data: PageData } = $props();
</script>
<h1>{data.post.title}</h1>
```

### Form Actions (Preferred Over Fetch for Forms)
```ts
// +page.server.ts
export const actions = {
  create: async ({ request }) => {
    const data = await request.formData();
    // validate and process
    redirect(303, '/success');
  },
};
```

```svelte
<form method="POST" action="?/create" use:enhance>
  <button type="submit">Submit</button>
</form>
```

---

## Template Syntax

```svelte
<!-- Conditionals -->
{#if condition}
  <p>True</p>
{:else if other}
  <p>Maybe</p>
{:else}
  <p>False</p>
{/if}

<!-- Lists — always use key expression -->
{#each items as item (item.id)}
  <li>{item.name}</li>
{:else}
  <li>No items</li>
{/each}

<!-- Async (Svelte 4) -->
{#await promise}
  <Spinner />
{:then data}
  <p>{data.name}</p>
{:catch error}
  <p>{error.message}</p>
{/await}

<!-- HTML content -->
{@html sanitizedContent}
```

## Performance
- Use keyed `{#each}` blocks — always include `(item.id)` key expression
- Prefer `+page.server.ts` `load` over `onMount` fetch (avoids client waterfall)
- Use `$app/environment`'s `browser` guard for browser-only code
- Component lazy loading with dynamic imports where routes are heavy

## Accessibility
- Use native form controls — avoid custom dropdowns when `<select>` works
- All interactive elements need accessible names
- Use `aria-live` regions for dynamic content updates
- Test keyboard navigation — SvelteKit doesn't manage focus on navigation by default
