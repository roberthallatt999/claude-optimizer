# Tina CMS

> Verify version: `cat tina/config.ts | head -5` and `cat package.json | grep tinacms`
> These patterns target Tina CMS 2.x (@tinacms/cli ≥ 1.5). The `tina/config.ts` file
> is the canonical entry point; `tina/__generated__/` is auto-generated — never edit it.

## Config Structure

```ts
// tina/config.ts
import { defineConfig } from 'tinacms'

export default defineConfig({
  branch: process.env.GITHUB_BRANCH ?? process.env.VERCEL_GIT_COMMIT_REF ?? 'main',
  clientId: process.env.NEXT_PUBLIC_TINA_CLIENT_ID,
  token: process.env.TINA_TOKEN,

  build: {
    outputFolder: 'admin',   // where the Tina admin UI is built
    publicFolder: 'public',  // Astro/Next.js public dir
  },

  media: {
    tina: {
      mediaRoot: 'uploads',
      publicFolder: 'public',
    },
  },

  schema: {
    collections: [/* ... */],
  },
})
```

## Defining Collections

```ts
// tina/config.ts — schema.collections
{
  name: 'post',
  label: 'Blog Posts',
  path: 'src/content/blog',   // where .mdx files live
  format: 'mdx',
  ui: {
    router: ({ document }) => `/blog/${document._sys.filename}`,
  },
  fields: [
    { type: 'string',   name: 'title',       label: 'Title',       required: true, isTitle: true },
    { type: 'string',   name: 'description', label: 'Description', ui: { component: 'textarea' } },
    { type: 'datetime', name: 'date',        label: 'Publish Date' },
    { type: 'boolean',  name: 'draft',       label: 'Draft' },
    { type: 'image',    name: 'hero',        label: 'Hero Image' },
    {
      type: 'string',
      name: 'tags',
      label: 'Tags',
      list: true,
    },
    {
      type: 'rich-text',
      name: 'body',
      label: 'Body',
      isBody: true,         // maps to the MDX file body
    },
  ],
}
```

## Field Types Reference

| `type` | Notes |
|--------|-------|
| `string` | Single-line; add `ui: { component: 'textarea' }` for multi-line |
| `number` | Integer or float |
| `boolean` | Toggle |
| `datetime` | ISO 8601; use `ui: { dateFormat: 'YYYY-MM-DD' }` to control display |
| `image` | Path string; stored relative to `publicFolder` |
| `reference` | Links to another collection: `{ type: 'reference', collections: ['author'] }` |
| `object` | Nested object with its own `fields` array |
| `rich-text` | MDX body; set `isBody: true` for the file body |

Add `list: true` to any type to make it a repeatable list.

## Data Fetching — Astro (SSG)

```ts
// src/pages/blog/[slug].astro
---
import { client } from '../../tina/__generated__/client'

export async function getStaticPaths() {
  const posts = await client.queries.postConnection()
  return posts.data.postConnection.edges!.map((edge) => ({
    params: { slug: edge!.node!._sys.filename },
    props:  { post: edge!.node! },
  }))
}

const { slug } = Astro.params
const { data } = await client.queries.post({ relativePath: `${slug}.mdx` })
---
<h1>{data.post.title}</h1>
```

## Data Fetching — List Page

```ts
// src/pages/blog/index.astro
---
import { client } from '../../tina/__generated__/client'

const { data } = await client.queries.postConnection({
  sort: 'date',
  filter: { draft: { eq: false } },
})
const posts = data.postConnection.edges!.map(e => e!.node!)
---
```

## References Between Collections

```ts
// Collection field
{ type: 'reference', name: 'author', label: 'Author', collections: ['author'] }

// Querying — the reference resolves to the linked document
const { data } = await client.queries.post({ relativePath: 'hello-world.mdx' })
const authorName = data.post.author?.name   // fully typed
```

## Live Editing (React / Next.js)

```tsx
import { useTina } from 'tinacms/dist/react'
import { tinaField } from 'tinacms/dist/react'

export default function Post({ data, query, variables }) {
  const { data: liveData } = useTina({ query, variables, data })

  return (
    <h1 data-tina-field={tinaField(liveData.post, 'title')}>
      {liveData.post.title}
    </h1>
  )
}
```

> `useTina` and `tinaField` are no-ops in production builds — safe to ship.

## Local vs Cloud Mode

| | Local Mode | Cloud Mode |
|---|---|---|
| Run | `npx tinacms dev -c "astro dev"` | Deploy + Tina Cloud config |
| Auth | None | GitHub OAuth via Tina Cloud |
| Saves to | Local filesystem | GitHub via Tina Cloud |
| Good for | Development | Production editorial |

### Local mode dev command (Astro)
```json
// package.json
{
  "scripts": {
    "dev": "tinacms dev -c \"astro dev\"",
    "build": "tinacms build && astro build"
  }
}
```

## Environment Variables

```bash
# .env.local — never commit
NEXT_PUBLIC_TINA_CLIENT_ID=  # from Tina Cloud dashboard
TINA_TOKEN=                   # read-only or read-write token
GITHUB_BRANCH=main            # or use VERCEL_GIT_COMMIT_REF
```

## Avoid

- Editing anything in `tina/__generated__/` — always regenerated from `tina/config.ts`
- Importing from `tinacms` for data queries — use `tina/__generated__/client` for type safety
- Storing media outside of the configured `publicFolder` path — images won't resolve
- Forgetting `isBody: true` on the rich-text field that maps to the MDX file body — the file will be saved without a body
- Running `astro build` without `tinacms build` first in CI — the generated client won't exist
