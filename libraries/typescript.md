# TypeScript Conventions

> **Always check `tsconfig.json` for `strict` mode and target before assuming available features.**
> Strict mode enables `strictNullChecks`, `noImplicitAny`, `strictFunctionTypes`, and others.
> Target (`ES2020`, `ESNext`, etc.) determines which native APIs are available without polyfills.

## Configuration

```jsonc
// tsconfig.json — recommended strict baseline
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "skipLibCheck": true
  }
}
```

## Type Definitions

### Prefer interfaces for object shapes, types for unions/intersections
```ts
// Object shapes → interface
interface User {
  id: string;
  email: string;
  role: 'admin' | 'member' | 'viewer';
  createdAt: Date;
}

// Unions, mapped types, computed → type alias
type Status = 'idle' | 'loading' | 'success' | 'error';
type Nullable<T> = T | null;
type Optional<T> = T | undefined;
type RequiredKeys<T, K extends keyof T> = Omit<T, K> & Required<Pick<T, K>>;
```

### Discriminated unions for state machines
```ts
type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

function render(state: AsyncState<User[]>) {
  switch (state.status) {
    case 'loading': return <Spinner />;
    case 'success': return <List data={state.data} />;
    case 'error': return <Error message={state.error.message} />;
    default: return null;
  }
}
```

## Utility Types

```ts
// Built-in utilities — use these before defining custom ones
type UserPreview = Pick<User, 'id' | 'email'>;
type PartialUser = Partial<User>;
type RequiredUser = Required<User>;
type UserWithoutId = Omit<User, 'id'>;
type ReadonlyUser = Readonly<User>;

// Record for dictionaries
type RolePermissions = Record<User['role'], string[]>;

// ReturnType / Parameters — extract from existing functions
type FetchResult = ReturnType<typeof fetchUser>;
type FetchArgs = Parameters<typeof fetchUser>;

// Conditional types
type NonNullable<T> = T extends null | undefined ? never : T;
type Awaited<T> = T extends Promise<infer U> ? U : T;
```

## Generics

```ts
// Constrain with extends
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

// Default type parameters
interface PaginatedResponse<T = unknown> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
}

// Generic components (React)
interface TableProps<T> {
  rows: T[];
  columns: Array<{ key: keyof T; label: string }>;
  onRowClick?: (row: T) => void;
}
```

## Narrowing

```ts
// Type guards
function isUser(value: unknown): value is User {
  return (
    typeof value === 'object' &&
    value !== null &&
    'id' in value &&
    'email' in value
  );
}

// Assertion functions
function assertDefined<T>(value: T | undefined, name: string): asserts value is T {
  if (value === undefined) {
    throw new Error(`Expected ${name} to be defined`);
  }
}

// Exhaustive checking
function exhaustive(value: never): never {
  throw new Error(`Unhandled case: ${JSON.stringify(value)}`);
}
```

## Common Patterns

### API response typing
```ts
type ApiResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: string; code?: number };

async function apiFetch<T>(url: string): Promise<ApiResult<T>> {
  const res = await fetch(url);
  if (!res.ok) return { ok: false, error: res.statusText, code: res.status };
  return { ok: true, data: await res.json() as T };
}
```

### Branded types (prevent mixing IDs)
```ts
type UserId = string & { readonly __brand: 'UserId' };
type PostId = string & { readonly __brand: 'PostId' };

const toUserId = (id: string): UserId => id as UserId;
// TypeScript will now reject passing a PostId where UserId is expected
```

### `satisfies` operator (v4.9+)
```ts
const palette = {
  red: [255, 0, 0],
  green: '#00ff00',
} satisfies Record<string, string | number[]>;

// palette.red is inferred as number[], not string | number[]
```

## Avoid

- `any` — use `unknown` and narrow instead
- Non-null assertions (`!`) except at system boundaries
- `as` casts without a guard (use type narrowing instead)
- Enums — use `const` objects with `as const` or union types
- Namespace/module syntax (legacy)
