# Supabase Conventions

> **Always check `@supabase/supabase-js` version:** v2 (most common) vs the newer MCP-first approach.
> Auth, realtime, and storage APIs changed significantly from v1 to v2.
> Run `cat package.json | grep supabase` to confirm.

## Client Setup

```ts
// lib/supabase/client.ts — browser client (use in components/'use client')
import { createBrowserClient } from '@supabase/ssr';
import type { Database } from '@/types/supabase';

export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}

// lib/supabase/server.ts — server client (use in Server Components, API routes)
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export async function createClient() {
  const cookieStore = await cookies();
  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (cookiesToSet) => {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        },
      },
    }
  );
}
```

## Type Generation

```bash
# Generate types from your database schema
npx supabase gen types typescript --project-id <project-id> > src/types/supabase.ts

# Or from local (requires running supabase locally)
npx supabase gen types typescript --local > src/types/supabase.ts
```

## Database Queries

```ts
const supabase = createClient();

// Select
const { data: users, error } = await supabase
  .from('users')
  .select('id, email, name, created_at')
  .eq('active', true)
  .order('created_at', { ascending: false })
  .limit(20);

// Select with join
const { data: posts } = await supabase
  .from('posts')
  .select(`
    id, title, body, created_at,
    author:users(id, name, avatar_url)
  `)
  .eq('published', true);

// Insert
const { data: newUser, error } = await supabase
  .from('users')
  .insert({ email: 'alice@example.com', name: 'Alice' })
  .select()
  .single();

// Update
const { error } = await supabase
  .from('users')
  .update({ name: 'Alice Smith' })
  .eq('id', userId);

// Delete
const { error } = await supabase
  .from('users')
  .delete()
  .eq('id', userId);

// Always handle errors
if (error) throw new Error(`Supabase error: ${error.message}`);
```

## Authentication

```ts
// Sign up
const { data, error } = await supabase.auth.signUp({
  email: 'alice@example.com',
  password: 'secure-password',
});

// Sign in (password)
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'alice@example.com',
  password: 'secure-password',
});

// Sign in (OAuth)
await supabase.auth.signInWithOAuth({
  provider: 'github',
  options: { redirectTo: `${window.location.origin}/auth/callback` },
});

// Sign out
await supabase.auth.signOut();

// Get current user (server-safe)
const { data: { user } } = await supabase.auth.getUser();

// Auth state listener (client only)
useEffect(() => {
  const { data: { subscription } } = supabase.auth.onAuthStateChange(
    (event, session) => {
      if (event === 'SIGNED_OUT') router.push('/login');
    }
  );
  return () => subscription.unsubscribe();
}, []);
```

## Row Level Security (RLS)

```sql
-- Enable RLS on all tables
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

-- Users can only read their own data
CREATE POLICY "Users read own data"
  ON users FOR SELECT
  USING (auth.uid() = id);

-- Users can only insert their own posts
CREATE POLICY "Users insert own posts"
  ON posts FOR INSERT
  WITH CHECK (auth.uid() = author_id);

-- Published posts are public
CREATE POLICY "Public read published posts"
  ON posts FOR SELECT
  USING (published = true);
```

## Storage

```ts
// Upload file
const { data, error } = await supabase.storage
  .from('avatars')
  .upload(`${userId}/avatar.jpg`, file, {
    upsert: true,
    contentType: 'image/jpeg',
  });

// Get public URL
const { data: { publicUrl } } = supabase.storage
  .from('avatars')
  .getPublicUrl(`${userId}/avatar.jpg`);
```

## Realtime

```ts
// Subscribe to table changes
const channel = supabase
  .channel('schema-db-changes')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'messages',
    filter: `room_id=eq.${roomId}`,
  }, (payload) => {
    setMessages((prev) => [...prev, payload.new as Message]);
  })
  .subscribe();

// Cleanup
return () => { supabase.removeChannel(channel); };
```

## Environment Variables

```bash
# Required
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key

# Server-only (never expose to client)
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

## Avoid

- Using `service_role` key on the client — server only
- Skipping RLS on production tables
- Fetching without error handling (`const { data } = await supabase...`)
- Using old `supabase-js` v1 patterns (no `@supabase/ssr`)
- Calling `getSession()` on the server (use `getUser()` — it validates the JWT)
