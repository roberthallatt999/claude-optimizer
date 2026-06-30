# Prisma ORM Conventions

> **Check Prisma version:** v5 (2023+) vs v6 (2024+).
> v6 changes: new Prisma Client initialization, `omit` is GA, `prisma.$extends` pattern stable.
> Run `cat package.json | grep '"prisma"'` to confirm.

## Schema Definition

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  email     String   @unique
  name      String?
  role      Role     @default(MEMBER)
  posts     Post[]
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@index([email])
  @@map("users")
}

enum Role {
  ADMIN
  MEMBER
  VIEWER
}

model Post {
  id        String   @id @default(cuid())
  title     String
  content   String?
  published Boolean  @default(false)
  author    User     @relation(fields: [authorId], references: [id], onDelete: Cascade)
  authorId  String
  tags      Tag[]
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@index([authorId])
  @@map("posts")
}

model Tag {
  id    String @id @default(cuid())
  name  String @unique
  posts Post[]

  @@map("tags")
}
```

## Client Singleton

```ts
// lib/db.ts — single instance per application
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const db =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = db;
```

## CRUD Operations

```ts
import { db } from '@/lib/db';

// Create
const user = await db.user.create({
  data: {
    email: 'alice@example.com',
    name: 'Alice',
    posts: {
      create: [{ title: 'First Post' }],
    },
  },
  include: { posts: true },
});

// Read
const user = await db.user.findUniqueOrThrow({
  where: { id: userId },
  select: { id: true, email: true, name: true },
});

// List with filtering
const posts = await db.post.findMany({
  where: {
    published: true,
    author: { role: 'MEMBER' },
    createdAt: { gte: new Date('2024-01-01') },
  },
  orderBy: { createdAt: 'desc' },
  take: 20,
  skip: (page - 1) * 20,
  include: {
    author: { select: { id: true, name: true } },
    tags: true,
  },
});

// Update
const updated = await db.user.update({
  where: { id: userId },
  data: { name: 'Alice Smith' },
});

// Upsert
const user = await db.user.upsert({
  where: { email: 'alice@example.com' },
  update: { name: 'Alice' },
  create: { email: 'alice@example.com', name: 'Alice' },
});

// Delete
await db.user.delete({ where: { id: userId } });

// Soft delete pattern
await db.user.update({
  where: { id: userId },
  data: { deletedAt: new Date() },
});
```

## Transactions

```ts
// Sequential transaction
const [user, post] = await db.$transaction([
  db.user.update({ where: { id: userId }, data: { name: 'Alice' } }),
  db.post.create({ data: { title: 'New Post', authorId: userId } }),
]);

// Interactive transaction (for complex logic)
const result = await db.$transaction(async (tx) => {
  const user = await tx.user.findUniqueOrThrow({ where: { id: userId } });
  if (user.credits < 10) throw new Error('Insufficient credits');

  await tx.user.update({
    where: { id: userId },
    data: { credits: { decrement: 10 } },
  });

  return tx.order.create({
    data: { userId, amount: 10 },
  });
});
```

## Migrations

```bash
# Create migration (dev — applies immediately)
npx prisma migrate dev --name add-user-role

# Preview changes without applying
npx prisma migrate dev --create-only

# Apply in production
npx prisma migrate deploy

# Reset dev database
npx prisma migrate reset

# Push schema changes without migration (prototyping only)
npx prisma db push

# Generate Prisma Client after schema change
npx prisma generate

# Open Prisma Studio (GUI)
npx prisma studio
```

## Type Utilities

```ts
import type { Prisma, User, Post } from '@prisma/client';

// Get type of query result including relations
type PostWithAuthor = Prisma.PostGetPayload<{
  include: { author: { select: { id: true; name: true } } };
}>;

// Input types
type CreatePostInput = Prisma.PostCreateInput;
type UpdateUserInput = Prisma.UserUpdateInput;

// Use Prisma.validator for validated objects
const userData = Prisma.validator<Prisma.UserCreateInput>()({
  email: 'alice@example.com',
  name: 'Alice',
});
```

## Avoid

- `findFirst` when you expect exactly one result — use `findUniqueOrThrow`
- Creating a new `PrismaClient` per request — use the singleton pattern
- Raw queries when Prisma's query builder covers it
- `$queryRaw` with string interpolation — use `$queryRaw` with tagged template literals
- Forgetting `await` on Prisma calls (silent failure)
- Exposing full Prisma types on API boundaries — use explicit `select` or DTOs
