# Sanity Patterns and Best Practices

These rules MUST be followed when working with Sanity Studio v3 and the Sanity Content Lake.

## Schema Definitions

### Document Types
- One schema file per document type in `src/sanity/schemas/`
- Always use `defineType` and `defineField` for type safety
- Always include `validation` rules on required fields
- Always include `preview` configuration

```typescript
// src/sanity/schemas/post.ts
import { defineType, defineField } from 'sanity';

export const post = defineType({
  name: 'post',
  title: 'Blog Post',
  type: 'document',
  fields: [
    defineField({
      name: 'title',
      title: 'Title',
      type: 'string',
      validation: (Rule) => Rule.required().max(120),
    }),
    defineField({
      name: 'slug',
      title: 'Slug',
      type: 'slug',
      options: { source: 'title', maxLength: 96 },
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'mainImage',
      title: 'Main Image',
      type: 'image',
      options: { hotspot: true },
      fields: [
        defineField({
          name: 'alt',
          title: 'Alt Text',
          type: 'string',
          validation: (Rule) => Rule.required(),
        }),
      ],
    }),
    defineField({
      name: 'publishedAt',
      title: 'Published At',
      type: 'datetime',
    }),
    defineField({
      name: 'body',
      title: 'Body',
      type: 'blockContent',
    }),
    defineField({
      name: 'categories',
      title: 'Categories',
      type: 'array',
      of: [{ type: 'reference', to: [{ type: 'category' }] }],
    }),
  ],
  preview: {
    select: {
      title: 'title',
      author: 'author.name',
      media: 'mainImage',
    },
    prepare(selection) {
      const { author } = selection;
      return { ...selection, subtitle: author && `by ${author}` };
    },
  },
  orderings: [
    {
      title: 'Published Date, New',
      name: 'publishedAtDesc',
      by: [{ field: 'publishedAt', direction: 'desc' }],
    },
  ],
});
```

### Schema Registry
```typescript
// src/sanity/schemas/index.ts
import { post } from './post';
import { page } from './page';
import { category } from './category';
import { author } from './author';
import { blockContent } from './blockContent';
import { siteSettings } from './siteSettings';

export const schemaTypes = [
  // Document types
  post,
  page,
  category,
  author,
  // Object types
  blockContent,
  // Singletons
  siteSettings,
];
```

### Block Content (Portable Text)
```typescript
// src/sanity/schemas/blockContent.ts
import { defineType, defineArrayMember } from 'sanity';

export const blockContent = defineType({
  name: 'blockContent',
  title: 'Block Content',
  type: 'array',
  of: [
    defineArrayMember({
      type: 'block',
      styles: [
        { title: 'Normal', value: 'normal' },
        { title: 'H2', value: 'h2' },
        { title: 'H3', value: 'h3' },
        { title: 'H4', value: 'h4' },
        { title: 'Quote', value: 'blockquote' },
      ],
      marks: {
        decorators: [
          { title: 'Bold', value: 'strong' },
          { title: 'Italic', value: 'em' },
          { title: 'Code', value: 'code' },
        ],
        annotations: [
          {
            title: 'URL',
            name: 'link',
            type: 'object',
            fields: [
              {
                title: 'URL',
                name: 'href',
                type: 'url',
                validation: (Rule) =>
                  Rule.uri({ allowRelative: true, scheme: ['http', 'https', 'mailto', 'tel'] }),
              },
              {
                title: 'Open in new tab',
                name: 'blank',
                type: 'boolean',
              },
            ],
          },
        ],
      },
    }),
    defineArrayMember({
      type: 'image',
      options: { hotspot: true },
      fields: [
        {
          name: 'alt',
          type: 'string',
          title: 'Alt Text',
          validation: (Rule) => Rule.required(),
        },
        {
          name: 'caption',
          type: 'string',
          title: 'Caption',
        },
      ],
    }),
  ],
});
```

## References

### Document References
```typescript
defineField({
  name: 'author',
  title: 'Author',
  type: 'reference',
  to: [{ type: 'author' }],
  validation: (Rule) => Rule.required(),
}),

// Array of references
defineField({
  name: 'relatedPosts',
  title: 'Related Posts',
  type: 'array',
  of: [{ type: 'reference', to: [{ type: 'post' }] }],
  validation: (Rule) => Rule.max(3),
}),
```

### Dereferencing in GROQ
```groq
// Dereference a single reference
*[_type == "post"] {
  title,
  "author": author->{ name, image }
}

// Dereference array of references
*[_type == "post"] {
  title,
  "categories": categories[]->{ title, slug }
}

// Deep dereference
*[_type == "post"] {
  title,
  "author": author->{
    name,
    "bio": bio[],
    "socialLinks": socialLinks[]
  }
}
```

## Validation Rules

### Common Validation Patterns
```typescript
// Required field
validation: (Rule) => Rule.required()

// String constraints
validation: (Rule) => Rule.required().min(10).max(200)

// Unique value
validation: (Rule) => Rule.required().unique()

// Custom validation
validation: (Rule) =>
  Rule.custom((value, context) => {
    if (!value && context.document?.published) {
      return 'Required when document is published';
    }
    return true;
  })

// Regex pattern
validation: (Rule) =>
  Rule.regex(/^[a-z0-9-]+$/, { name: 'slug', invert: false })
    .error('Only lowercase letters, numbers, and hyphens allowed')

// Array length
validation: (Rule) => Rule.min(1).max(5).error('Select 1-5 categories')

// URL validation
validation: (Rule) =>
  Rule.uri({ allowRelative: false, scheme: ['http', 'https'] })
```

## GROQ Query Patterns

### Basic Queries
```groq
// All documents of a type
*[_type == "post"]

// Filter and sort
*[_type == "post"] | order(publishedAt desc) [0...10]

// Single document by slug
*[_type == "post" && slug.current == $slug][0]

// Filter by reference
*[_type == "post" && references($categoryId)]
```

### Projections
```groq
// Select specific fields
*[_type == "post"] {
  _id,
  title,
  slug,
  publishedAt,
  "imageUrl": mainImage.asset->url,
  "categoryTitles": categories[]->title
}

// Computed fields
*[_type == "post"] {
  title,
  "excerpt": pt::text(body)[0...200],
  "wordCount": length(pt::text(body))
}
```

### Parameterized Queries
```typescript
// ALWAYS use parameters — never string interpolation
export async function getPostsByCategory(categorySlug: string) {
  return sanityClient.fetch(
    `*[_type == "post" && $categorySlug in categories[]->slug.current] | order(publishedAt desc) {
      _id,
      title,
      slug,
      publishedAt,
      mainImage
    }`,
    { categorySlug }
  );
}
```

## Image Handling

### urlFor() Helper
```typescript
// src/lib/sanity.ts
import imageUrlBuilder from '@sanity/image-url';

const builder = imageUrlBuilder(sanityClient);

export function urlFor(source: any) {
  return builder.image(source);
}
```

### Image Transforms
```astro
---
import { urlFor } from '@/lib/sanity';
---

<!-- Responsive image with Sanity CDN transforms -->
<img
  src={urlFor(post.mainImage).width(800).height(450).format('webp').url()}
  alt={post.mainImage.alt || post.title}
  width="800"
  height="450"
  loading="lazy"
/>

<!-- Thumbnail -->
<img
  src={urlFor(post.mainImage).width(200).height(200).fit('crop').url()}
  alt={post.mainImage.alt || ''}
/>

<!-- Responsive with srcset -->
<img
  src={urlFor(post.mainImage).width(800).url()}
  srcset={`
    ${urlFor(post.mainImage).width(400).url()} 400w,
    ${urlFor(post.mainImage).width(800).url()} 800w,
    ${urlFor(post.mainImage).width(1200).url()} 1200w
  `}
  sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 800px"
  alt={post.mainImage.alt || post.title}
  loading="lazy"
/>
```

### Hotspot and Crop
```typescript
// Enable hotspot in schema
defineField({
  name: 'mainImage',
  type: 'image',
  options: { hotspot: true },  // Allows editors to set focal point
}),

// Hotspot is automatically respected by urlFor()
urlFor(image).width(800).height(450).url()
// Crops around the hotspot focal point
```

## Portable Text Rendering

### Astro Portable Text Component
```astro
---
// src/components/PortableText.astro
import { PortableText as PortableTextRenderer } from '@portabletext/react';
import { urlFor } from '@/lib/sanity';

interface Props {
  value: any[];
}

const { value } = Astro.props;

const components = {
  types: {
    image: ({ value }) => {
      return `<figure>
        <img
          src="${urlFor(value).width(800).url()}"
          alt="${value.alt || ''}"
          loading="lazy"
        />
        ${value.caption ? `<figcaption>${value.caption}</figcaption>` : ''}
      </figure>`;
    },
  },
  marks: {
    link: ({ children, value }) => {
      const target = value.blank ? ' target="_blank" rel="noopener noreferrer"' : '';
      return `<a href="${value.href}"${target}>${children}</a>`;
    },
  },
};
---

<div class="prose prose-lg max-w-none">
  <PortableTextRenderer value={value} components={components} client:load />
</div>
```

## Singleton Documents

### Settings Pattern
```typescript
// src/sanity/schemas/siteSettings.ts
import { defineType, defineField } from 'sanity';

export const siteSettings = defineType({
  name: 'siteSettings',
  title: 'Site Settings',
  type: 'document',
  fields: [
    defineField({ name: 'title', title: 'Site Title', type: 'string' }),
    defineField({ name: 'description', title: 'Site Description', type: 'text' }),
    defineField({ name: 'logo', title: 'Logo', type: 'image' }),
  ],
  // Prevent creating multiple instances
  __experimental_actions: [/* 'create', */ 'update', /* 'delete', */ 'publish'],
});

// Query singleton
export async function getSiteSettings() {
  return sanityClient.fetch(`*[_type == "siteSettings"][0]`);
}
```

## Type Generation

### Generate Types from Schema
```bash
# Extract schema and generate TypeScript types
npx sanity schema extract
npx sanity typegen generate
```

```typescript
// Use generated types
import type { Post, Category } from '@/types/sanity';

export async function getPosts(): Promise<Post[]> {
  return sanityClient.fetch(`*[_type == "post"] | order(publishedAt desc)`);
}
```

## Checklist

Before committing:
- [ ] All schemas use `defineType` and `defineField`
- [ ] Required fields have validation rules
- [ ] All document types have `preview` configuration
- [ ] Image fields have `hotspot: true` and alt text fields
- [ ] GROQ queries use parameters (no string interpolation)
- [ ] Queries project only needed fields (no unnecessary `...` spread)
- [ ] References are properly dereferenced in queries
- [ ] Types are generated from schema (`npx sanity typegen generate`)
- [ ] Portable Text is rendered through a dedicated component
