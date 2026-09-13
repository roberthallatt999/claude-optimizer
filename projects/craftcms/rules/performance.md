---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
  - "**/*.{css,scss,js,mjs,ts}"
  - "**/{vite,webpack,next,nuxt,astro,svelte,tailwind,postcss}.config.*"
  - "**/.htaccess"
---

# Performance Optimization Rules

These rules MUST be followed to ensure optimal performance for Craft CMS sites.

## Craft Caching

### Template Caching
- ✅ ALWAYS use `{% cache %}` tags for expensive queries
- ✅ Cache navigation components
- ✅ Cache repeated entry queries
- ✅ Set appropriate cache duration
- ❌ NEVER run database queries without caching when possible

**Navigation Caching:**
```twig
{# ✅ CORRECT: Cached navigation #}
{% cache globally for 1 hour %}
  <nav>
    {% for entry in craft.entries.section('pages').all() %}
      <a href="{{ entry.url }}">{{ entry.title }}</a>
    {% endfor %}
  </nav>
{% endcache %}

{# ❌ INCORRECT: No caching #}
<nav>
  {% for entry in craft.entries.section('pages').all() %}
    <a href="{{ entry.url }}">{{ entry.title }}</a>
  {% endfor %}
</nav>
```

### Cache Duration Guidelines
- Navigation: `globally for 1 hour` or longer
- Static content: `globally for 1 day`
- Dynamic content: `for 5 minutes` with specific cache key
- User-specific: Don't cache or use `using key currentUser.id`

**Example:**
```twig
{% cache using key 'homepage-hero' for 1 hour %}
  {% set hero = craft.entries.section('heroSlides').one() %}
  <div class="hero">
    <h1>{{ hero.title }}</h1>
    <p>{{ hero.description }}</p>
  </div>
{% endcache %}
```

## Query Optimization

### Eager Loading
- ✅ ALWAYS use `.with()` to eager load relations
- ✅ Eager load assets, categories, and related entries
- ❌ NEVER lazy load in loops (N+1 query problem)

**Correct:**
```twig
{# ✅ CORRECT: Eager loading #}
{% set entries = craft.entries()
  .section('blog')
  .with([
    'featuredImage',
    'categories',
    'author'
  ])
  .all()
%}

{% for entry in entries %}
  <article>
    <img src="{{ entry.featuredImage.one().url }}" alt="{{ entry.title }}">
    <h2>{{ entry.title }}</h2>
    <p>By {{ entry.author.one().title }}</p>
    {% for category in entry.categories.all() %}
      <span>{{ category.title }}</span>
    {% endfor %}
  </article>
{% endfor %}
```

**Incorrect:**
```twig
{# ❌ INCORRECT: Lazy loading (N+1) #}
{% set entries = craft.entries.section('blog').all() %}

{% for entry in entries %}
  <article>
    {# These create separate queries for each entry! #}
    <img src="{{ entry.featuredImage.one().url }}" alt="{{ entry.title }}">
    <p>By {{ entry.author.one().title }}</p>
  </article>
{% endfor %}
```

### Limit Query Results
- ✅ ALWAYS use `.limit()` when you don't need all entries
- ✅ Use pagination for large datasets
- ❌ NEVER load all entries if you only need a few

**Correct:**
```twig
{# Latest 5 blog posts #}
{% set recentPosts = craft.entries()
  .section('blog')
  .limit(5)
  .all()
%}

{# Paginated entries #}
{% paginate craft.entries.section('blog').limit(10) as pageInfo, entries %}
  {% for entry in entries %}
    {# Display entry #}
  {% endfor %}

  {# Pagination links #}
  {% if pageInfo.prevUrl %}
    <a href="{{ pageInfo.prevUrl }}">Previous</a>
  {% endif %}
  {% if pageInfo.nextUrl %}
    <a href="{{ pageInfo.nextUrl }}">Next</a>
  {% endif %}
{% endpaginate %}
```

## Asset Optimization

### Image Transforms
- ✅ ALWAYS use image transforms for responsive images
- ✅ Define transforms in config or use named transforms
- ✅ Use appropriate file formats (WebP when possible)
- ❌ NEVER serve full-resolution images

**Correct:**
```twig
{# Define transform #}
{% set thumb = {
  mode: 'crop',
  width: 400,
  height: 300,
  quality: 80,
  format: 'webp'
} %}

<img
  src="{{ entry.image.one().url(thumb) }}"
  alt="{{ entry.image.one().title }}"
  width="400"
  height="300"
  loading="lazy"
/>
```

### Lazy Loading
- ✅ Use `loading="lazy"` for below-the-fold images
- ✅ Omit for above-the-fold images
- ✅ Consider `fetchpriority="high"` for LCP images

**Example:**
```twig
{# Hero image - loads immediately #}
<img
  src="{{ entry.heroImage.one().url }}"
  alt="{{ entry.title }}"
  fetchpriority="high"
/>

{# Gallery images - lazy load #}
{% for image in entry.gallery.all() %}
  <img
    src="{{ image.url({ width: 600 }) }}"
    alt="{{ image.title }}"
    loading="lazy"
  />
{% endfor %}
```

## Database Queries

### Efficient Querying
- ✅ Use specific fields in `.select()` when possible
- ✅ Use `.one()` instead of `.all()` when fetching single entry
- ✅ Use `.exists()` to check if entries exist
- ❌ NEVER fetch full entries when you only need specific fields

**Correct:**
```twig
{# Only fetch needed fields #}
{% set titles = craft.entries()
  .section('blog')
  .select(['title', 'id'])
  .all()
%}

{# Check if entry exists #}
{% set hasProjects = craft.entries()
  .section('projects')
  .exists()
%}

{# Get single entry efficiently #}
{% set aboutPage = craft.entries()
  .section('pages')
  .slug('about')
  .one()
%}
```

## Element Queries

### Query Caching
- ✅ Use `.cache()` to cache element queries
- ✅ Set appropriate cache duration
- ❌ Don't cache user-specific queries globally

**Example:**
```twig
{# Cache element query results #}
{% set entries = craft.entries()
  .section('blog')
  .limit(10)
  .cache()
  .all()
%}
```

## Frontend Assets

### CSS and JavaScript
- ✅ Minify CSS and JavaScript in production
- ✅ Use `defer` or `async` for non-critical JavaScript
- ✅ Inline critical CSS
- ❌ NEVER load unnecessary libraries

**Correct:**
```twig
{# Critical CSS inline #}
<style>
  {{ source('_critical.css') }}
</style>

{# Defer non-critical CSS #}
<link rel="preload" href="/dist/main.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
<noscript><link rel="stylesheet" href="/dist/main.css"></noscript>

{# Async JavaScript #}
<script src="/dist/main.js" defer></script>
```

## Matrix Fields

### Efficient Matrix Queries
- ✅ Eager load Matrix block relations
- ✅ Limit Matrix blocks when possible
- ❌ NEVER lazy load Matrix block relations in loops

**Correct:**
```twig
{% set entry = craft.entries()
  .section('pages')
  .slug('home')
  .with([
    ['contentBlocks.image'],
    ['contentBlocks.relatedEntries']
  ])
  .one()
%}

{% for block in entry.contentBlocks.all() %}
  {% switch block.type %}
    {% case 'imageBlock' %}
      <img src="{{ block.image.one().url }}" alt="{{ block.image.one().title }}">
    {% case 'relatedEntriesBlock' %}
      {% for relatedEntry in block.relatedEntries.all() %}
        <h3>{{ relatedEntry.title }}</h3>
      {% endfor %}
  {% endswitch %}
{% endfor %}
```

## Craft Configuration

### General Config (config/general.php)
```php
<?php
return [
  '*' => [
    // Enable template caching
    'enableTemplateCaching' => true,

    // Cache duration
    'cacheDuration' => 3600,

    // Optimize image loading
    'optimizeImageFilesize' => true,

    // Generate transforms before page load
    'generateTransformsBeforePageLoad' => true,
  ],
  'production' => [
    // Disable Dev Mode in production
    'devMode' => false,
  ],
];
```

## Performance Checklist

Before deployment:
- [ ] Template caching is enabled
- [ ] Eager loading is used for all relations
- [ ] Image transforms are defined
- [ ] Lazy loading is applied to below-fold images
- [ ] Unnecessary queries are removed
- [ ] CSS and JS are minified
- [ ] Database indexes are optimized
- [ ] Cache warming strategy is in place
