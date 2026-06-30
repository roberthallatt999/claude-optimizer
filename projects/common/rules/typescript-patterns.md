# TypeScript Patterns Rule

## Purpose

Maintain type safety and consistency across TypeScript projects.

## CRITICAL: Strict Mode Required

All TypeScript projects MUST use `strict: true` in `tsconfig.json`. Never disable strict mode to silence errors — fix them.

```jsonc
// tsconfig.json minimum
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true
  }
}
```

## Type Definitions

### Single Source of Truth

**Never duplicate types.** Derive types from schemas and database models:

```ts
// Good — one source
const userSchema = z.object({ id: z.string(), email: z.string() });
type User = z.infer<typeof userSchema>;

// Good — derive from Prisma
type PostWithAuthor = Prisma.PostGetPayload<{ include: { author: true } }>;

// Avoid — manual type that can drift from schema
interface User {
  id: string;
  email: string;
}
```

### Discriminated Unions for State

```ts
// Good — exhaustive, type-safe
type RequestState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

// Avoid — boolean flags that allow impossible states
interface BadState { loading: boolean; error: Error | null; data: T | null; }
```

### Branded Types for IDs

Prevent accidentally passing a `PostId` where a `UserId` is expected:

```ts
type UserId = string & { readonly __brand: 'UserId' };
type PostId = string & { readonly __brand: 'PostId' };
```

## Avoid `any`

```ts
// Bad
function processData(data: any) { ... }

// Good — use unknown and narrow
function processData(data: unknown) {
  if (!isUser(data)) throw new Error('Invalid user data');
  // data is now typed as User
}
```

## Non-Null Assertions

Use `!` only at system boundaries (e.g., after verifying a value exists):

```ts
// Bad — silent runtime error if null
const name = user!.name;

// Good — explicit guard
if (!user) throw new Error('User required');
const name = user.name;
```

## Function Signatures

Always type return values on exported functions:

```ts
// Good — explicit return type catches logic errors
export async function getUser(id: string): Promise<User | null> {
  return db.user.findUnique({ where: { id } });
}

// Avoid — implicit return type can widen unexpectedly
export async function getUser(id: string) { ... }
```

## Generics

Constrain generics with `extends`:

```ts
// Good
function getProperty<T extends object, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

// Avoid — unconstrained T is too permissive
function getProperty<T>(obj: T, key: string): unknown { ... }
```

## Exhaustive Checks

Add a never-check to ensure all union cases are handled:

```ts
function exhaustive(value: never): never {
  throw new Error(`Unhandled case: ${JSON.stringify(value)}`);
}

switch (state.status) {
  case 'idle': return null;
  case 'loading': return <Spinner />;
  case 'success': return <Data data={state.data} />;
  case 'error': return <Error error={state.error} />;
  default: return exhaustive(state); // compile error if case added without handler
}
```

## What NOT to Do

- `as` type assertions without a type guard
- `// @ts-ignore` or `// @ts-nocheck` without a comment explaining why
- Enums — use `const` object with `as const` or literal union instead
- `interface` for utility types, mapped types, or conditional types — use `type`
- Widening types at API boundaries — be explicit about what callers can send

## When Reading TypeScript Files

1. Check `tsconfig.json` for `strict` mode and `target` before assuming syntax
2. Check `package.json` for TS version — some features require v5+
3. Prefer `z.infer`, `Prisma.GetPayload`, or `ReturnType<>` over hand-written types
4. If you see `any`, flag it and suggest the correct type
