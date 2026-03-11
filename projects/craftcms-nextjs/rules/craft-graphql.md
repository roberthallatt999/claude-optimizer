# Craft CMS GraphQL API Rules

These rules MUST be followed when working with Craft CMS's GraphQL API in headless mode.

## Schema Configuration

- Configure GraphQL schemas in Craft CMS admin: Settings > GraphQL
- Create separate schemas for public and private access
- Use tokens for authenticated API access
- Never expose admin-level GraphQL schemas publicly

## Query Patterns

### Entry Queries
```graphql
# List entries with pagination
query GetEntries($section: [String], $limit: Int, $offset: Int) {
  entries(section: $section, limit: $limit, offset: $offset, orderBy: "postDate DESC") {
    id
    title
    slug
    postDate @formatDateTime(format: "Y-m-d")
    url
  }
  entryCount(section: $section)
}
```

### Type-Specific Fields
```graphql
# Use inline fragments for section-specific fields
query GetBlogPost($slug: [String]) {
  entry(section: "blog", slug: $slug) {
    title
    slug
    postDate
    ... on blog_blog_Entry {
      summary
      body
      featuredImage {
        url @transform(width: 1200, height: 630, mode: "crop")
        alt
        width
        height
      }
      categories {
        title
        slug
      }
    }
  }
}
```

### Asset Transforms
```graphql
# Always use transforms for images
query {
  entry(section: "pages", slug: "home") {
    ... on pages_pages_Entry {
      heroImage {
        url @transform(width: 1920, quality: 85)
        url @transform(width: 768, quality: 80) @alias(as: "mobileUrl")
        alt
      }
    }
  }
}
```

### Matrix / Content Builder
```graphql
query GetPageWithBlocks($slug: [String]) {
  entry(section: "pages", slug: $slug) {
    ... on pages_pages_Entry {
      contentBlocks {
        ... on contentBlocks_text_BlockType {
          typeHandle
          text
        }
        ... on contentBlocks_image_BlockType {
          typeHandle
          image {
            url @transform(width: 800)
            alt
          }
          caption
        }
        ... on contentBlocks_quote_BlockType {
          typeHandle
          quoteText
          attribution
        }
      }
    }
  }
}
```

## Best Practices

1. **Always specify sections** in entry queries to limit scope
2. **Use transforms** for all image URLs (never serve originals)
3. **Request only needed fields** to minimize response size
4. **Use aliases** when requesting the same field with different transforms
5. **Enable query caching** in Craft CMS for production performance
6. **Use fragments** for reusable field sets across queries
7. **Handle null entries** — always check if query returns null before rendering

## Security

- Store GraphQL tokens in environment variables, never in frontend code
- Use server-side API routes in Next.js to proxy GraphQL requests
- Configure CORS headers on Craft CMS to only allow your frontend origin
- Use read-only GraphQL schemas for public-facing queries
- Never expose mutation capabilities to unauthenticated users
