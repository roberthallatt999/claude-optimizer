# SvelteKit Patterns

## File-Based Routing

SvelteKit routes are directories under `src/routes/`. Files in each directory:

| File | Purpose | Runs On |
|------|---------|---------|
| `+page.svelte` | Page component | Client + Server (SSR) |
| `+page.ts` | Shared load function | Both |
| `+page.server.ts` | Server-only load + actions | Server only |
| `+layout.svelte` | Layout wrapper | Client + Server |
| `+layout.server.ts` | Layout data load | Server only |
| `+server.ts` | API endpoint | Server only |
| `+error.svelte` | Error page | Client |

## Always Use Generated Types

```ts
// Good — generated, always accurate
import type { PageLoad, PageData, Actions } from './$types';

// Never — manual typing drifts from reality
import type { Load } from '@sveltejs/kit';
```

## Data Loading Rules

1. **`+page.server.ts`** for database access, auth checks, secrets
2. **`+page.ts`** for public API calls that can run on both server and client
3. **Never import server-only modules** (db, secret env vars) in `+page.ts`
4. **Return only serializable data** from `load` functions

## Locals Pattern (Authentication)

Always set `locals.user` in `hooks.server.ts` and check it in protected routes:

```ts
// hooks.server.ts
export const handle: Handle = async ({ event, resolve }) => {
  const session = await getSession(event.cookies);
  event.locals.user = session?.user ?? null;
  return resolve(event);
};

// Protected +page.server.ts
export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) redirect(303, '/login');
  return { user: locals.user };
};
```

## Form Actions Are Preferred Over Fetch

```svelte
<!-- Good — form action with progressive enhancement -->
<form method="POST" action="?/create" use:enhance>
  <input name="title" />
  <button type="submit">Create</button>
</form>

<!-- Use fetch/SWR only for real-time or optimistic updates -->
```

## Error Handling

```ts
import { error, fail, redirect } from '@sveltejs/kit';

// 404/500 etc. — terminates load, shows +error.svelte
error(404, 'Post not found');

// Form validation failure — returns to page with error data
return fail(400, { message: 'Title required' });

// Redirect after action
redirect(303, '/posts');
```

## `$lib` Import Alias

Always use `$lib` for imports across directories — never relative paths:

```ts
// Good
import { db } from '$lib/server/db';
import { Button } from '$lib/components/ui/button.svelte';
import { formatDate } from '$lib/utils/format';

// Avoid
import { db } from '../../../../lib/server/db';
```

## Svelte 5 Runes (Use in New Code)

```svelte
<script lang="ts">
  // Reactive state
  let count = $state(0);

  // Derived (replaces $: derived)
  let doubled = $derived(count * 2);

  // Props (replaces export let)
  let { label = 'Click', onclick }: { label?: string; onclick: () => void } = $props();

  // Side effects (replaces reactive statements + onMount)
  $effect(() => {
    document.title = `Count: ${count}`;
    return () => { document.title = 'App'; }; // cleanup
  });
</script>
```

## Server-Side Rendering Caveats

```ts
// Browser-only code must be guarded
import { browser } from '$app/environment';

if (browser) {
  // Safe — only runs in browser
  localStorage.setItem('key', 'value');
}

// Or use onMount (runs only in browser)
import { onMount } from 'svelte';
onMount(() => { /* browser-only */ });
```
