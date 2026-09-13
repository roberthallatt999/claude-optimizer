---
paths:
  - "**/*.blade.php"
---

# Blade Template Rules (Sage/Roots)

These rules MUST be followed when writing Blade templates in WordPress Sage theme.

## Template Structure

### Blade Syntax
- ✅ Use `@` directives for control structures
- ✅ Use `{{ }}` for escaped output
- ✅ Use `{!! !!}` only for trusted HTML
- ❌ NEVER use PHP tags in Blade files

**Correct:**
```blade
@if($posts)
  @foreach($posts as $post)
    <article>
      <h2>{{ $post->post_title }}</h2>
      <div>{!! $post->post_content !!}</div>
    </article>
  @endforeach
@endif
```

## WordPress Integration

### The Loop
```blade
@if (have_posts())
  @while (have_posts())
    @php(the_post())
    @include('partials.content-' . get_post_type())
  @endwhile
@endif
```

### Template Parts
```blade
{{-- Include partial --}}
@include('partials.header')

{{-- Include with data --}}
@include('components.card', ['title' => $title, 'content' => $content])
```

## Checklist

- [ ] Use Blade directives, not PHP tags
- [ ] Escape output with {{ }}
- [ ] Sanitize HTML output
- [ ] Follow WordPress template hierarchy
