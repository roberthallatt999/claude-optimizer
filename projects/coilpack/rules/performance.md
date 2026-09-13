---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
  - "**/*.{css,scss,js,mjs,ts}"
  - "**/{vite,webpack,next,nuxt,astro,svelte,tailwind,postcss}.config.*"
  - "**/.htaccess"
---

# Laravel Performance Optimization

## Caching

### Query Caching
```php
$posts = Cache::remember('posts', 3600, function () {
    return Post::all();
});
```

### View Caching
```bash
php artisan view:cache
php artisan config:cache
php artisan route:cache
```

## Database

### Eager Loading
```php
// N+1 problem (bad)
$posts = Post::all();
foreach ($posts as $post) {
    echo $post->author->name; // Separate query each time
}

// Eager loading (good)
$posts = Post::with('author')->get();
foreach ($posts as $post) {
    echo $post->author->name; // No extra queries
}
```

## Checklist

- [ ] Caching is implemented
- [ ] Eager loading is used
- [ ] Views/config/routes are cached
