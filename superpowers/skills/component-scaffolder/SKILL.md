---
name: component-scaffolder
description: "Use when creating new React/Vue/Svelte components — generates typed, accessible component files following project conventions with proper exports, variants, and tests."
---

# Component Scaffolder

Scaffold well-typed, accessible components that match the project's existing conventions.

<HARD-GATE>
Before scaffolding, verify the component does not already exist. Check MEMORY.md Component Registry, then scan component directories. Never scaffold a duplicate.
</HARD-GATE>

## When to Use

Invoke when the user says:
- "Create a [ComponentName] component"
- "Add a [name] card/button/modal/form"
- "Build a [feature] component"
- "Scaffold [X]"

## Discovery Checklist

1. **Read MEMORY.md** → Component Registry, Tech Stack (to determine framework/library)
2. **Check `components/ui/`** — are there similar primitives to extend?
3. **Identify framework** — React/Vue/Svelte (from MEMORY.md or package.json)
4. **Identify style system** — Tailwind + shadcn/ui, CSS Modules, styled-components
5. **Find a similar existing component** — use as the pattern template
6. **Check if shadcn/ui has it** — `npx shadcn@latest add` may be the right move

## Questions to Ask (One at a Time)

Only ask what isn't clear from context. Stop when you have enough to scaffold:

1. What is the component's purpose? (one sentence)
2. What are its required and optional props?
3. Does it need variants (size, visual style)?
4. Does it have interactive states? (hover, focus, loading, disabled, error)
5. Where does it live — `ui/` (primitive) or `features/` (domain-specific)?
6. Does it need a unit test?

## Scaffolding Output

For a React + Tailwind + TypeScript + shadcn/ui project, produce:

### Component File (`components/[ui|features]/ComponentName.tsx`)

```tsx
import { cn } from '@/lib/utils';
// import cva if multiple variants

interface ComponentNameProps {
  // typed props
  className?: string;
}

export function ComponentName({ className, ...props }: ComponentNameProps) {
  return (
    <div className={cn('base-classes', className)} {...props}>
      {/* content */}
    </div>
  );
}
```

### Index Export Update

Add to `components/ui/index.ts` or appropriate barrel:
```ts
export { ComponentName } from './ComponentName';
```

### Unit Test (`components/[ui|features]/ComponentName.test.tsx`)

Only scaffold if the project has Vitest/Jest configured:
```tsx
import { render, screen } from '@testing-library/react';
import { ComponentName } from './ComponentName';

describe('ComponentName', () => {
  it('renders correctly', () => {
    render(<ComponentName />);
    // assertions
  });
});
```

## Framework-Specific Patterns

### Vue 3 (SFC)
```vue
<script setup lang="ts">
interface Props {
  // props
}
const props = withDefaults(defineProps<Props>(), {
  // defaults
});
</script>

<template>
  <!-- template -->
</template>
```

### Svelte 5
```svelte
<script lang="ts">
  interface Props {
    // props
  }
  let { ...props }: Props = $props();
</script>

<!-- template -->
```

## After Scaffolding

1. **Add to MEMORY.md** → Component Registry:
   ```markdown
   | ComponentName | components/ui/ComponentName.tsx | default, outline | Brief description |
   ```
2. **Verify it renders** — if dev server is running, check for console errors
3. **Confirm accessibility** — has focus state, aria labels if needed, semantic HTML

## Key Principles

- Match existing conventions exactly — check a nearby component before writing
- Use the project's `cn()` utility for className merging
- Export named (not default) exports
- Keep components focused — if it needs more than ~150 lines, suggest splitting
