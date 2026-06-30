# tRPC Conventions

> tRPC provides end-to-end typesafe APIs without codegen. It works in Next.js, Nuxt (via `trpc-nuxt`),
> and any Node.js backend. Check `package.json` for `@trpc/server` version — v10 (most common) vs v11 (2024+).
> v11 changes: middleware API updated, new `createCallerFactory`, better streaming support.

## Setup (Next.js App Router — T3-style)

```ts
// src/server/api/trpc.ts — core tRPC initialization
import { initTRPC, TRPCError } from '@trpc/server';
import { auth } from '@/server/auth';
import type { Session } from 'next-auth';
import superjson from 'superjson';
import { ZodError } from 'zod';

interface CreateContextOptions {
  session: Session | null;
}

export const createTRPCContext = async (opts: { headers: Headers }) => {
  const session = await auth();
  return { session, ...opts };
};

const t = initTRPC.context<typeof createTRPCContext>().create({
  transformer: superjson,
  errorFormatter({ shape, error }) {
    return {
      ...shape,
      data: {
        ...shape.data,
        zodError: error.cause instanceof ZodError ? error.cause.flatten() : null,
      },
    };
  },
});

export const createTRPCRouter = t.router;
export const createCallerFactory = t.createCallerFactory;

// Public procedure — no auth required
export const publicProcedure = t.procedure;

// Protected procedure — requires authenticated session
const enforceAuth = t.middleware(({ ctx, next }) => {
  if (!ctx.session?.user) throw new TRPCError({ code: 'UNAUTHORIZED' });
  return next({ ctx: { session: { ...ctx.session, user: ctx.session.user } } });
});

export const protectedProcedure = t.procedure.use(enforceAuth);
```

## Router Definition

```ts
// src/server/api/routers/post.ts
import { z } from 'zod';
import { createTRPCRouter, protectedProcedure, publicProcedure } from '@/server/api/trpc';

export const postRouter = createTRPCRouter({
  list: publicProcedure
    .input(z.object({
      limit: z.number().min(1).max(100).default(20),
      cursor: z.string().optional(),
    }))
    .query(async ({ ctx, input }) => {
      const posts = await ctx.db.post.findMany({
        take: input.limit + 1,
        cursor: input.cursor ? { id: input.cursor } : undefined,
        where: { published: true },
        orderBy: { createdAt: 'desc' },
      });
      const nextCursor = posts.length > input.limit ? posts.pop()?.id : undefined;
      return { posts, nextCursor };
    }),

  getById: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(async ({ ctx, input }) => {
      const post = await ctx.db.post.findUnique({ where: { id: input.id } });
      if (!post) throw new TRPCError({ code: 'NOT_FOUND' });
      return post;
    }),

  create: protectedProcedure
    .input(z.object({
      title: z.string().min(1).max(200),
      content: z.string().min(1),
    }))
    .mutation(async ({ ctx, input }) => {
      return ctx.db.post.create({
        data: { ...input, authorId: ctx.session.user.id },
      });
    }),

  delete: protectedProcedure
    .input(z.object({ id: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const post = await ctx.db.post.findFirst({
        where: { id: input.id, authorId: ctx.session.user.id },
      });
      if (!post) throw new TRPCError({ code: 'FORBIDDEN' });
      return ctx.db.post.delete({ where: { id: input.id } });
    }),
});

// src/server/api/root.ts — combine all routers
import { postRouter } from './routers/post';

export const appRouter = createTRPCRouter({
  post: postRouter,
});

export type AppRouter = typeof appRouter;
```

## Next.js App Router — Server Adapter

```ts
// src/app/api/trpc/[trpc]/route.ts
import { fetchRequestHandler } from '@trpc/server/adapters/fetch';
import { appRouter } from '@/server/api/root';
import { createTRPCContext } from '@/server/api/trpc';

const handler = (req: Request) =>
  fetchRequestHandler({
    endpoint: '/api/trpc',
    req,
    router: appRouter,
    createContext: () => createTRPCContext({ headers: req.headers }),
    onError: process.env.NODE_ENV === 'development'
      ? ({ path, error }) => console.error(`tRPC Error on ${path ?? '<no-path>'}:`, error)
      : undefined,
  });

export { handler as GET, handler as POST };
```

## Client Setup

```ts
// src/trpc/react.tsx — React client
'use client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { loggerLink, unstable_httpBatchStreamLink } from '@trpc/client';
import { createTRPCReact } from '@trpc/react-query';
import type { AppRouter } from '@/server/api/root';
import superjson from 'superjson';

export const api = createTRPCReact<AppRouter>();

export function TRPCReactProvider({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  const [trpcClient] = useState(() =>
    api.createClient({
      links: [
        loggerLink({ enabled: (op) => process.env.NODE_ENV === 'development' }),
        unstable_httpBatchStreamLink({
          transformer: superjson,
          url: `${getBaseUrl()}/api/trpc`,
        }),
      ],
    })
  );

  return (
    <api.Provider client={trpcClient} queryClient={queryClient}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </api.Provider>
  );
}
```

## Usage in Components

```tsx
'use client';
import { api } from '@/trpc/react';

// Query (read)
export function PostList() {
  const { data, isLoading } = api.post.list.useQuery({ limit: 10 });

  if (isLoading) return <Spinner />;
  return <ul>{data?.posts.map(p => <li key={p.id}>{p.title}</li>)}</ul>;
}

// Mutation (write)
export function CreatePost() {
  const utils = api.useUtils();
  const create = api.post.create.useMutation({
    onSuccess: () => utils.post.list.invalidate(),
  });

  return (
    <button onClick={() => create.mutate({ title: 'My Post', content: '...' })}>
      {create.isPending ? 'Creating...' : 'Create'}
    </button>
  );
}

// Server-side caller (in Server Components)
import { createCaller } from '@/server/api/root';
import { createTRPCContext } from '@/server/api/trpc';

const caller = createCaller(await createTRPCContext({ headers: new Headers() }));
const posts = await caller.post.list({ limit: 10 });
```

## Error Handling

```ts
import { TRPCError } from '@trpc/server';

// Throw typed errors in procedures
throw new TRPCError({ code: 'NOT_FOUND', message: 'Post not found' });
throw new TRPCError({ code: 'FORBIDDEN', message: 'You cannot delete this' });
throw new TRPCError({ code: 'BAD_REQUEST', message: 'Invalid input', cause: zodError });

// Handle on client
const create = api.post.create.useMutation({
  onError: (error) => {
    if (error.data?.zodError) {
      // Field validation errors
      const fieldErrors = error.data.zodError.fieldErrors;
    }
    toast.error(error.message);
  },
});
```

## Avoid

- Skipping Zod validation on inputs — always use `.input(schema)`
- Calling procedures directly from client components without `api.*` — bypasses type safety
- Mixing REST routes and tRPC for the same resource
- Forgetting `superjson` transformer when passing Dates (they'd serialize as strings)
