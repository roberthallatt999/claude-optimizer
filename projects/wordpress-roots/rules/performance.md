---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
  - "**/*.{css,scss,js,mjs,ts}"
  - "**/{vite,webpack,next,nuxt,astro,svelte,tailwind,postcss}.config.*"
  - "**/.htaccess"
---

# WordPress Performance Optimization

These rules MUST be followed for optimal WordPress/Sage performance.

## Caching

### Object Caching
- ✅ Use `wp_cache_set()` and `wp_cache_get()`
- ✅ Cache database queries
- ✅ Set appropriate expiration times

```php
$posts = wp_cache_get('recent_posts');
if (false === $posts) {
  $posts = get_posts(['numberposts' => 10]);
  wp_cache_set('recent_posts', $posts, '', 3600);
}
```

## Database Queries

### WP_Query Best Practices
- ✅ Limit query results
- ✅ Only query needed fields
- ✅ Use `'no_found_rows' => true` when not paginating

```php
$query = new WP_Query([
  'post_type' => 'post',
  'posts_per_page' => 5,
  'fields' => 'ids', // Only return IDs
  'no_found_rows' => true,
]);
```

## Asset Optimization

### Enqueue Scripts Properly
```php
wp_enqueue_script('app', asset('scripts/app.js'), ['jquery'], null, true);
wp_enqueue_style('app', asset('styles/app.css'));
```

## Checklist

- [ ] Object caching is used
- [ ] Database queries are optimized
- [ ] Assets are properly enqueued
- [ ] Images are lazy loaded
