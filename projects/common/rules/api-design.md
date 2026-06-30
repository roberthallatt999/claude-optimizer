# API Design Rules

## Purpose

Maintain consistent, secure, and well-typed API patterns across web projects.

## Validate All Input at the Boundary

Every API route MUST validate and parse its input before touching business logic:

```ts
// Next.js App Router
import { z } from 'zod';
import { NextRequest, NextResponse } from 'next/server';

const createPostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
  published: z.boolean().default(false),
});

export async function POST(req: NextRequest) {
  const result = createPostSchema.safeParse(await req.json());
  if (!result.success) {
    return NextResponse.json(
      { error: 'Validation failed', issues: result.error.flatten().fieldErrors },
      { status: 400 }
    );
  }
  // result.data is typed and validated
}
```

## Consistent Response Shape

Use a consistent envelope across ALL API responses:

```ts
// Success
{ data: T, meta?: { page: number; total: number } }

// Error
{ error: string, code?: string, issues?: Record<string, string[]> }

// Never mix styles within a project
```

## Authentication Check Pattern

```ts
// lib/api/auth.ts — reusable auth guard
import { auth } from '@/lib/auth';
import { NextRequest, NextResponse } from 'next/server';

export async function requireAuth(req: NextRequest) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  return session;
}

// Usage in routes
export async function GET(req: NextRequest) {
  const authResult = await requireAuth(req);
  if (authResult instanceof NextResponse) return authResult;
  const { user } = authResult;
  // ...
}
```

## HTTP Status Codes

| Situation | Status |
|-----------|--------|
| Success (GET, PUT, PATCH) | 200 |
| Created (POST) | 201 |
| No content (DELETE) | 204 |
| Bad input / validation | 400 |
| Unauthenticated | 401 |
| Forbidden (authenticated, no permission) | 403 |
| Not found | 404 |
| Conflict (duplicate, optimistic lock) | 409 |
| Unprocessable entity | 422 |
| Internal server error | 500 |

Never return 200 with `{ error: ... }` in the body — use the correct status code.

## Pagination

```ts
// Standard pagination response
interface PaginatedResponse<T> {
  data: T[];
  meta: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
}

// Cursor-based (for feeds/infinite scroll)
interface CursorResponse<T> {
  data: T[];
  nextCursor: string | null;
  hasMore: boolean;
}
```

## Error Handling

```ts
// lib/api/errors.ts
export class ApiError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly code?: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// Route handler wrapper
export function withErrorHandler(
  handler: (req: NextRequest, ctx: RouteContext) => Promise<NextResponse>
) {
  return async (req: NextRequest, ctx: RouteContext): Promise<NextResponse> => {
    try {
      return await handler(req, ctx);
    } catch (err) {
      if (err instanceof ApiError) {
        return NextResponse.json(
          { error: err.message, code: err.code },
          { status: err.statusCode }
        );
      }
      console.error('[API Error]', err);
      return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
    }
  };
}
```

## Rate Limiting

For any public-facing route, add rate limiting:

```ts
// Using Upstash Ratelimit or similar
import { Ratelimit } from '@upstash/ratelimit';
import { Redis } from '@upstash/redis';

const ratelimit = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(10, '10 s'),
});

const identifier = req.headers.get('x-forwarded-for') ?? 'anonymous';
const { success } = await ratelimit.limit(identifier);
if (!success) {
  return NextResponse.json({ error: 'Too many requests' }, { status: 429 });
}
```

## CORS

```ts
// middleware.ts
export function middleware(req: NextRequest) {
  const origin = req.headers.get('origin');
  const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') ?? [];

  const response = NextResponse.next();
  if (origin && allowedOrigins.includes(origin)) {
    response.headers.set('Access-Control-Allow-Origin', origin);
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
  return response;
}
```

## tRPC Pattern (if applicable)

```ts
// server/trpc.ts
import { initTRPC, TRPCError } from '@trpc/server';
import { auth } from '@/lib/auth';

const t = initTRPC.context<Context>().create();
export const router = t.router;
export const publicProcedure = t.procedure;
export const protectedProcedure = t.procedure.use(async ({ ctx, next }) => {
  if (!ctx.session?.user) throw new TRPCError({ code: 'UNAUTHORIZED' });
  return next({ ctx: { user: ctx.session.user } });
});
```

## What NOT to Do

- Return sensitive data (passwords, tokens, full PII) in API responses
- Skip input validation on any route — even "internal" ones
- Use GET for state-changing operations
- Include stack traces in production error responses
- Build REST endpoints when tRPC is already in the stack
