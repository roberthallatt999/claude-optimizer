---
paths:
  - "templates/**"
  - "**/*.twig"
---

# Craft CMS Twig Template Rules

These rules MUST be followed when writing Twig templates for Craft CMS projects.

## Template Structure

### Template Organization
- ✅ Use `_layouts/` for base templates
- ✅ Use `_partials/` or `_includes/` for reusable components
- ✅ Use `_components/` for complex reusable blocks
- ❌ NEVER duplicate template code

**Directory Structure:**
```
templates/
├── _layouts/
│   └── base.twig
├── _partials/
│   ├── _header.twig
│   ├── _footer.twig
│   └── _navigation.twig
├── _components/
│   ├── _card.twig
│   └── _hero.twig
├── index.twig
└── about.twig
```

## Template Inheritance

### Extending Layouts
- ✅ ALWAYS extend from a base layout
- ✅ Use blocks for content areas
- ✅ Keep layouts DRY (Don't Repeat Yourself)

**Base Layout (_layouts/base.twig):**
```twig
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}{{ siteName }}{% endblock %}</title>
  {% block head %}{% endblock %}
</head>
<body>
  {% include '_partials/_header.twig' %}

  <main>
    {% block content %}{% endblock %}
  </main>

  {% include '_partials/_footer.twig' %}

  {% block scripts %}{% endblock %}
</body>
</html>
```

**Page Template (about.twig):**
```twig
{% extends '_layouts/base.twig' %}

{% block title %}{{ entry.title }} - {{ siteName }}{% endblock %}

{% block content %}
  <article>
    <h1>{{ entry.title }}</h1>
    {{ entry.body }}
  </article>
{% endblock %}
```

## Entry Queries

### Fetching Entries
- ✅ Use `craft.entries()` for queries
- ✅ Always specify `.section()`
- ✅ Use `.one()` for single entry, `.all()` for multiple
- ✅ Check if entry exists before using

**Correct:**
```twig
{# Single entry #}
{% set entry = craft.entries()
  .section('pages')
  .slug('about')
  .one()
%}

{% if entry %}
  <h1>{{ entry.title }}</h1>
{% endif %}

{# Multiple entries #}
{% set blogPosts = craft.entries()
  .section('blog')
  .orderBy('postDate DESC')
  .limit(5)
  .all()
%}

{% for post in blogPosts %}
  <article>
    <h2>{{ post.title }}</h2>
  </article>
{% endfor %}
```

**Incorrect:**
```twig
{# ❌ Missing null check #}
{% set entry = craft.entries.section('pages').slug('about').one() %}
<h1>{{ entry.title }}</h1> {# Error if entry doesn't exist! #}
```

## Entry Properties

### Common Entry Fields
- `{{ entry.title }}` - Entry title
- `{{ entry.url }}` - Entry URL
- `{{ entry.id }}` - Entry ID
- `{{ entry.slug }}` - Entry slug
- `{{ entry.postDate }}` - Post date
- `{{ entry.author }}` - Entry author

**Example:**
```twig
{% for post in blogPosts %}
  <article>
    <h2><a href="{{ post.url }}">{{ post.title }}</a></h2>
    <time datetime="{{ post.postDate|date('Y-m-d') }}">
      {{ post.postDate|date('F j, Y') }}
    </time>
    <p>By {{ post.author.fullName }}</p>
  </article>
{% endfor %}
```

## Custom Fields

### Accessing Custom Fields
- ✅ Access custom fields directly on the entry
- ✅ Check field type documentation for correct usage
- ✅ Use field handles (not labels)

**Common Field Types:**
```twig
{# Plain Text / Rich Text #}
{{ entry.bodyContent }}

{# Assets (Images) #}
{% set image = entry.featuredImage.one() %}
{% if image %}
  <img src="{{ image.url }}" alt="{{ image.title }}">
{% endif %}

{# Entries (Relations) #}
{% for relatedEntry in entry.relatedPosts.all() %}
  <a href="{{ relatedEntry.url }}">{{ relatedEntry.title }}</a>
{% endfor %}

{# Categories #}
{% for category in entry.categories.all() %}
  <span>{{ category.title }}</span>
{% endfor %}

{# Matrix Field #}
{% for block in entry.contentBlocks.all() %}
  {% switch block.type %}
    {% case 'textBlock' %}
      <div>{{ block.text }}</div>
    {% case 'imageBlock' %}
      <img src="{{ block.image.one().url }}" alt="{{ block.image.one().title }}">
  {% endswitch %}
{% endfor %}
```

## Assets

### Working with Images
- ✅ ALWAYS use transforms for images
- ✅ Provide alt text
- ✅ Check if asset exists
- ❌ NEVER use original large images

**Correct:**
```twig
{% set image = entry.featuredImage.one() %}
{% if image %}
  {% set transform = {
    mode: 'crop',
    width: 800,
    height: 600,
    quality: 85
  } %}

  <img
    src="{{ image.url(transform) }}"
    alt="{{ image.title }}"
    width="800"
    height="600"
    loading="lazy"
  />
{% endif %}
```

### Responsive Images
```twig
{% set image = entry.heroImage.one() %}
{% if image %}
  <picture>
    <source
      media="(min-width: 768px)"
      srcset="{{ image.url({ width: 1200 }) }}"
    />
    <source
      media="(min-width: 480px)"
      srcset="{{ image.url({ width: 768 }) }}"
    />
    <img
      src="{{ image.url({ width: 480 }) }}"
      alt="{{ image.title }}"
      loading="lazy"
    />
  </picture>
{% endif %}
```

## Conditionals

### Template Logic
- ✅ Use Twig conditionals for logic
- ✅ Keep logic simple in templates
- ❌ NEVER put complex business logic in templates

**Correct:**
```twig
{% if entry.showSidebar %}
  <aside>
    {% include '_partials/_sidebar.twig' %}
  </aside>
{% endif %}

{% if blogPosts|length > 0 %}
  {% for post in blogPosts %}
    {# Display post #}
  {% endfor %}
{% else %}
  <p>No blog posts found.</p>
{% endif %}
```

## Macros and Includes

### Reusable Components with Includes
- ✅ Use `include` for simple partials
- ✅ Pass variables with `with`
- ✅ Use `only` to limit variable scope

**Correct:**
```twig
{# _components/_card.twig #}
<div class="card">
  <h3>{{ title }}</h3>
  <p>{{ description }}</p>
  <a href="{{ url }}">Read more</a>
</div>

{# Usage #}
{% include '_components/_card.twig' with {
  title: entry.title,
  description: entry.summary,
  url: entry.url
} only %}
```

### Macros for Repeatable Logic
```twig
{# _macros/buttons.twig #}
{% macro primary(text, url) %}
  <a href="{{ url }}" class="btn btn-primary">{{ text }}</a>
{% endmacro %}

{% macro secondary(text, url) %}
  <a href="{{ url }}" class="btn btn-secondary">{{ text }}</a>
{% endmacro %}

{# Usage #}
{% import '_macros/buttons.twig' as buttons %}

{{ buttons.primary('Learn More', entry.url) }}
{{ buttons.secondary('Contact Us', '/contact') }}
```

## Navigation

### Building Navigation
```twig
{% cache globally for 1 hour %}
  <nav>
    <ul>
      {% set pages = craft.entries()
        .section('pages')
        .orderBy('lft')
        .all()
      %}

      {% for page in pages %}
        <li class="{% if page.id == entry.id %}active{% endif %}">
          <a href="{{ page.url }}">{{ page.title }}</a>
        </li>
      {% endfor %}
    </ul>
  </nav>
{% endcache %}
```

### Structure-Based Navigation
```twig
{% set navEntries = craft.entries()
  .section('pages')
  .level(1)
  .all()
%}

<nav>
  <ul>
    {% nav entry in navEntries %}
      <li>
        <a href="{{ entry.url }}">{{ entry.title }}</a>
        {% ifchildren %}
          <ul>
            {% children %}
          </ul>
        {% endifchildren %}
      </li>
    {% endnav %}
  </ul>
</nav>
```

## SEO

### Meta Tags
```twig
{# _layouts/base.twig #}
<head>
  <title>{% block seoTitle %}{{ entry.title ?? siteName }}{% endblock %}</title>
  <meta name="description" content="{% block seoDescription %}{{ entry.seoDescription ?? siteDescription }}{% endblock %}">

  {# Open Graph #}
  <meta property="og:title" content="{% block ogTitle %}{{ entry.title ?? siteName }}{% endblock %}">
  <meta property="og:description" content="{% block ogDescription %}{{ entry.seoDescription ?? siteDescription }}{% endblock %}">
  <meta property="og:image" content="{% block ogImage %}{{ entry.seoImage.one().url ?? defaultOgImage }}{% endblock %}">
  <meta property="og:url" content="{{ entry.url ?? siteUrl }}">
</head>
```

## Forms

### Craft Forms
```twig
<form method="post">
  {{ csrfInput() }}
  {{ actionInput('contact-form/send') }}
  {{ redirectInput('contact/thanks') }}

  <div>
    <label for="name">Name</label>
    <input type="text" id="name" name="name" required>
  </div>

  <div>
    <label for="email">Email</label>
    <input type="email" id="email" name="email" required>
  </div>

  <div>
    <label for="message">Message</label>
    <textarea id="message" name="message" required></textarea>
  </div>

  <button type="submit">Send</button>
</form>
```

## Filters

### Common Twig Filters
```twig
{# Date formatting #}
{{ entry.postDate|date('F j, Y') }}

{# Markdown to HTML #}
{{ entry.body|markdown }}

{# Truncate text #}
{{ entry.summary|slice(0, 150) ~ '...' }}

{# URL encoding #}
{{ searchQuery|url_encode }}

{# JSON encoding #}
{{ dataArray|json_encode|raw }}
```

## Checklist

Before committing templates:
- [ ] Extends base layout
- [ ] Uses blocks appropriately
- [ ] Entries are checked for existence
- [ ] Images use transforms
- [ ] Navigation is cached
- [ ] SEO meta tags are included
- [ ] Forms include CSRF token
- [ ] Code is DRY (no duplication)
