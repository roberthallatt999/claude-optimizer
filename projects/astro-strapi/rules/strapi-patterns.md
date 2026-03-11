# Strapi Patterns and Best Practices

These rules MUST be followed when developing with Strapi.

## Content Types

### Structure
- Each content type lives in `src/api/<content-type>/`
- Contains: `content-types/`, `controllers/`, `routes/`, `services/`
- Use the Content-Type Builder in admin for initial creation
- Fine-tune schemas in JSON files for version control

```
src/api/article/
├── content-types/
│   └── article/
│       └── schema.json         # Field definitions
├── controllers/
│   └── article.ts              # Request handlers
├── routes/
│   └── article.ts              # Route definitions
└── services/
    └── article.ts              # Business logic
```

### Schema Definition
```json
{
  "kind": "collectionType",
  "collectionName": "articles",
  "info": {
    "singularName": "article",
    "pluralName": "articles",
    "displayName": "Article"
  },
  "attributes": {
    "title": { "type": "string", "required": true },
    "slug": { "type": "uid", "targetField": "title" },
    "content": { "type": "richtext" },
    "excerpt": { "type": "text" },
    "featuredImage": { "type": "media", "allowedTypes": ["images"] },
    "category": {
      "type": "relation",
      "relation": "manyToOne",
      "target": "api::category.category"
    }
  }
}
```

### Content Type Rules
- Use `collectionType` for repeated entries (articles, products)
- Use `singleType` for unique pages (homepage, settings)
- Use `uid` type for slug fields, linked to `title` via `targetField`
- Define `required: true` on essential fields
- Use `relation` types for associations between content types

## REST API Patterns

### Default Endpoints
```
GET    /api/articles              # List all articles
GET    /api/articles/:id          # Get single article
POST   /api/articles              # Create article
PUT    /api/articles/:id          # Update article
DELETE /api/articles/:id          # Delete article
```

### Query Parameters
```
?populate=*                       # Populate all relations
?populate[0]=category             # Populate specific relation
?filters[title][$contains]=astro  # Filter by field
?sort=publishedAt:desc            # Sort results
?pagination[page]=1               # Pagination (page-based)
?pagination[pageSize]=10
?fields[0]=title&fields[1]=slug   # Select specific fields
```

### Population (Deep)
```
?populate[category][populate]=*
?populate[seo][populate][ogImage][fields][0]=url
```

## Controllers

### Default Controller (Auto-generated)
```typescript
// src/api/article/controllers/article.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreController('api::article.article');
```

### Custom Controller
```typescript
// src/api/article/controllers/article.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreController('api::article.article', ({ strapi }) => ({
  // Override find to add custom logic
  async find(ctx) {
    // Add default population
    ctx.query = {
      ...ctx.query,
      populate: ['category', 'featuredImage'],
    };

    const { data, meta } = await super.find(ctx);
    return { data, meta };
  },

  // Custom action
  async findBySlug(ctx) {
    const { slug } = ctx.params;

    const entity = await strapi.db.query('api::article.article').findOne({
      where: { slug },
      populate: ['category', 'featuredImage'],
    });

    if (!entity) {
      return ctx.notFound('Article not found');
    }

    const sanitizedEntity = await this.sanitizeOutput(entity, ctx);
    return this.transformResponse(sanitizedEntity);
  },
}));
```

## Services

### Default Service
```typescript
// src/api/article/services/article.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreService('api::article.article');
```

### Custom Service
```typescript
// src/api/article/services/article.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreService('api::article.article', ({ strapi }) => ({
  async findPublished(limit = 10) {
    return strapi.entityService.findMany('api::article.article', {
      filters: { publishedAt: { $notNull: true } },
      sort: { publishedAt: 'desc' },
      limit,
      populate: ['category', 'featuredImage'],
    });
  },

  async findByCategory(categorySlug: string) {
    return strapi.entityService.findMany('api::article.article', {
      filters: {
        category: { slug: categorySlug },
        publishedAt: { $notNull: true },
      },
      populate: ['category', 'featuredImage'],
    });
  },
}));
```

## Custom Routes

### Adding Custom Routes
```typescript
// src/api/article/routes/custom-article.ts
export default {
  routes: [
    {
      method: 'GET',
      path: '/articles/slug/:slug',
      handler: 'article.findBySlug',
      config: {
        auth: false,
      },
    },
  ],
};
```

## Middleware

### Route Middleware
```typescript
// src/api/article/middlewares/article-logger.ts
export default (config, { strapi }) => {
  return async (ctx, next) => {
    const start = Date.now();
    await next();
    const duration = Date.now() - start;
    strapi.log.info(`Article request took ${duration}ms`);
  };
};
```

### Global Middleware
```typescript
// src/middlewares/cors-custom.ts
export default (config, { strapi }) => {
  return async (ctx, next) => {
    ctx.set('X-Custom-Header', 'value');
    await next();
  };
};
```

## Lifecycle Hooks

### Model Lifecycle
```typescript
// src/api/article/content-types/article/lifecycles.ts
export default {
  beforeCreate(event) {
    const { data } = event.params;
    // Auto-generate excerpt from content
    if (data.content && !data.excerpt) {
      data.excerpt = data.content.substring(0, 200) + '...';
    }
  },

  afterCreate(event) {
    const { result } = event;
    // Trigger webhook, send notification, etc.
    strapi.log.info(`Article created: ${result.title}`);
  },

  beforeUpdate(event) {
    const { data } = event.params;
    // Validate or transform data before update
  },

  afterUpdate(event) {
    const { result } = event;
    // Invalidate cache, trigger rebuild, etc.
  },

  afterDelete(event) {
    const { result } = event;
    // Clean up related resources
  },
};
```

## Plugins

### Common Plugins
- `@strapi/plugin-graphql` — GraphQL API
- `@strapi/plugin-i18n` — Internationalization
- `@strapi/plugin-seo` — SEO metadata
- `@strapi/plugin-users-permissions` — Authentication (built-in)

### Plugin Configuration
```typescript
// config/plugins.ts
export default ({ env }) => ({
  graphql: {
    enabled: false, // REST is primary; enable if needed
  },
  'users-permissions': {
    config: {
      jwtSecret: env('JWT_SECRET'),
    },
  },
});
```

## API Permissions

### Configuration Steps
1. Go to Settings > Users & Permissions > Roles
2. Select "Public" role for unauthenticated access
3. Enable `find` and `findOne` for content types the frontend needs
4. NEVER enable `create`, `update`, or `delete` on the Public role
5. Use API tokens for authenticated frontend access

## Database Configuration

### Development (SQLite)
```typescript
// config/database.ts
export default ({ env }) => ({
  connection: {
    client: 'sqlite',
    connection: {
      filename: env('DATABASE_FILENAME', '.tmp/data.db'),
    },
    useNullAsDefault: true,
  },
});
```

### Production (PostgreSQL)
```typescript
export default ({ env }) => ({
  connection: {
    client: 'postgres',
    connection: {
      host: env('DATABASE_HOST'),
      port: env.int('DATABASE_PORT', 5432),
      database: env('DATABASE_NAME'),
      user: env('DATABASE_USERNAME'),
      password: env('DATABASE_PASSWORD'),
    },
  },
});
```

## Checklist

Before committing:
- [ ] Content type schemas are well-defined with proper types
- [ ] Required fields are marked
- [ ] Relations are properly configured
- [ ] Custom controllers sanitize output
- [ ] API permissions are configured (Public role)
- [ ] Lifecycle hooks handle side effects cleanly
- [ ] Services contain reusable business logic
- [ ] Custom routes are documented
