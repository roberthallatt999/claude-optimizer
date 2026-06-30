# Zod Conventions

> **Check installed version:** `zod` v3 is most common; v4 (2025+) has breaking changes.
> v4 changes: `z.string().email()` → validation message API changed; `z.discriminatedUnion` behavior updated.
> Run `cat package.json | grep '"zod"'` before writing schemas.

## Core Patterns

```ts
import { z } from 'zod';

// Primitives
const nameSchema = z.string().min(1).max(100).trim();
const ageSchema = z.number().int().positive().max(150);
const emailSchema = z.string().email().toLowerCase();
const urlSchema = z.string().url();
const uuidSchema = z.string().uuid();
const dateSchema = z.coerce.date(); // parses strings/numbers to Date
```

## Object Schemas

```ts
const userSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string().min(1).max(100),
  role: z.enum(['admin', 'member', 'viewer']),
  age: z.number().int().min(0).max(150).optional(),
  createdAt: z.coerce.date(),
});

// Derive TypeScript type from schema — single source of truth
type User = z.infer<typeof userSchema>;

// Partial / pick / omit
const userUpdateSchema = userSchema.partial().required({ id: true });
const userPreviewSchema = userSchema.pick({ id: true, email: true, name: true });
const userCreateSchema = userSchema.omit({ id: true, createdAt: true });
```

## Parsing & Validation

```ts
// parse() throws ZodError on failure
const user = userSchema.parse(rawData);

// safeParse() returns { success, data } | { success: false, error }
const result = userSchema.safeParse(rawData);
if (result.success) {
  console.log(result.data); // typed as User
} else {
  console.error(result.error.flatten()); // friendly error map
}

// parseAsync for async refinements
const user = await userSchema.parseAsync(rawData);
```

## Transformations & Refinements

```ts
const slugSchema = z
  .string()
  .min(1)
  .transform((s) => s.toLowerCase().replace(/\s+/g, '-'));

const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .regex(/[A-Z]/, 'Must contain uppercase')
  .regex(/[0-9]/, 'Must contain a number');

const signUpSchema = z
  .object({
    password: passwordSchema,
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  });
```

## Arrays & Records

```ts
const tagsSchema = z.array(z.string().min(1)).min(1).max(10);
const settingsSchema = z.record(z.string(), z.boolean());

// Tuple (fixed length, typed positions)
const coordinateSchema = z.tuple([z.number(), z.number()]);

// Union / discriminated union
const eventSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('click'), x: z.number(), y: z.number() }),
  z.object({ type: z.literal('keypress'), key: z.string() }),
]);
```

## Integration with React Hook Form

```ts
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

type LoginForm = z.infer<typeof loginSchema>;

function LoginForm() {
  const { register, handleSubmit, formState: { errors } } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  });

  return (
    <form onSubmit={handleSubmit((data) => console.log(data))}>
      <input {...register('email')} />
      {errors.email && <p>{errors.email.message}</p>}
    </form>
  );
}
```

## API Route Validation

```ts
// Next.js App Router example
import { NextRequest, NextResponse } from 'next/server';

const bodySchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
});

export async function POST(req: NextRequest) {
  const result = bodySchema.safeParse(await req.json());
  if (!result.success) {
    return NextResponse.json(
      { errors: result.error.flatten().fieldErrors },
      { status: 400 }
    );
  }
  // result.data is fully typed
}
```

## Error Formatting

```ts
try {
  userSchema.parse(rawData);
} catch (err) {
  if (err instanceof z.ZodError) {
    // Flat field errors map
    const fieldErrors = err.flatten().fieldErrors;
    // { email: ['Invalid email'], name: ['Required'] }
  }
}
```

## Avoid

- Overly complex schema chains — break into named sub-schemas
- Mixing parse() and safeParse() inconsistently in the same module
- Forgetting `.trim()` on user-facing string inputs
- Re-defining types when `z.infer<typeof schema>` covers them
