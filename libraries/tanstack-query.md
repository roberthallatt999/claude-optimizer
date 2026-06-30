# TanStack Query (React Query) Conventions

> **Check installed version:** v5 (2023+) has breaking changes from v4.
> Key v5 changes: `useQuery` now requires an options object, `status: 'loading'` renamed to `'pending'`,
> `cacheTime` renamed to `gcTime`, `onSuccess/onError/onSettled` removed from `useQuery`.
> Run `cat package.json | grep '"@tanstack/react-query"'` to confirm version.

## Setup

```tsx
// providers.tsx (or layout.tsx in Next.js)
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,   // 5 minutes
      gcTime: 1000 * 60 * 10,     // 10 minutes (was cacheTime in v4)
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

## Query Keys

```ts
// keys.ts — centralize and type all query keys
export const queryKeys = {
  users: {
    all: () => ['users'] as const,
    list: (filters?: UserFilters) => ['users', 'list', filters] as const,
    detail: (id: string) => ['users', 'detail', id] as const,
  },
  posts: {
    all: () => ['posts'] as const,
    byUser: (userId: string) => ['posts', 'byUser', userId] as const,
  },
} as const;
```

## Queries (Read)

```tsx
// Basic query
const { data, isPending, isError, error } = useQuery({
  queryKey: queryKeys.users.detail(userId),
  queryFn: () => fetchUser(userId),
  enabled: !!userId, // only run when userId is set
  select: (data) => data.user, // transform/select subset
  staleTime: 1000 * 60, // override default
});

// Dependent queries
const { data: user } = useQuery({
  queryKey: queryKeys.users.detail(userId),
  queryFn: () => fetchUser(userId),
});

const { data: posts } = useQuery({
  queryKey: queryKeys.posts.byUser(user?.id ?? ''),
  queryFn: () => fetchPostsByUser(user!.id),
  enabled: !!user?.id,
});
```

## Mutations (Write)

```tsx
const { mutate, isPending, isError } = useMutation({
  mutationFn: (data: CreateUserInput) => createUser(data),
  onSuccess: (newUser) => {
    // Invalidate and refetch related queries
    queryClient.invalidateQueries({ queryKey: queryKeys.users.all() });
    // Or optimistically update cache
    queryClient.setQueryData(queryKeys.users.detail(newUser.id), newUser);
  },
  onError: (error) => {
    toast.error(`Failed: ${error.message}`);
  },
});

// Usage
<button onClick={() => mutate({ name: 'Alice', email: 'alice@example.com' })}>
  Create User
</button>
```

## Optimistic Updates

```tsx
const queryClient = useQueryClient();

const { mutate } = useMutation({
  mutationFn: updateTodo,
  onMutate: async (newTodo) => {
    await queryClient.cancelQueries({ queryKey: ['todos', newTodo.id] });
    const previous = queryClient.getQueryData(['todos', newTodo.id]);
    queryClient.setQueryData(['todos', newTodo.id], newTodo);
    return { previous };
  },
  onError: (err, newTodo, context) => {
    queryClient.setQueryData(['todos', newTodo.id], context?.previous);
  },
  onSettled: (data, err, newTodo) => {
    queryClient.invalidateQueries({ queryKey: ['todos', newTodo.id] });
  },
});
```

## Prefetching

```ts
// In Server Component (Next.js App Router)
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query';

export default async function Page() {
  const queryClient = new QueryClient();
  await queryClient.prefetchQuery({
    queryKey: queryKeys.users.list(),
    queryFn: fetchUsers,
  });

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <UserList />
    </HydrationBoundary>
  );
}
```

## Infinite Queries

```tsx
const {
  data,
  fetchNextPage,
  hasNextPage,
  isFetchingNextPage,
} = useInfiniteQuery({
  queryKey: ['posts', 'infinite'],
  queryFn: ({ pageParam }) => fetchPosts({ cursor: pageParam }),
  initialPageParam: undefined as string | undefined,
  getNextPageParam: (lastPage) => lastPage.nextCursor,
});

// Flat all pages into one array
const posts = data?.pages.flatMap((page) => page.posts) ?? [];
```

## Custom Hooks Pattern

```ts
// hooks/useUsers.ts — encapsulate query logic
export function useUser(userId: string) {
  return useQuery({
    queryKey: queryKeys.users.detail(userId),
    queryFn: () => api.users.getById(userId),
    enabled: !!userId,
  });
}

export function useCreateUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: api.users.create,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.users.all() }),
  });
}
```

## Avoid

- Fetching in `useEffect` — use `useQuery` instead
- Sharing query client between server and browser in Next.js
- Missing `enabled` on dependent queries
- Using `status === 'loading'` in v5 (it's `'pending'` now)
- Forgetting to invalidate queries after mutations
