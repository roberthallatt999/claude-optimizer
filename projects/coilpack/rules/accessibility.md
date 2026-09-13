---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
---

# Accessibility Rules (WCAG 2.1 AA Compliance)

These rules MUST be followed to ensure Craft CMS sites are accessible to all users.

## Semantic HTML

### Use Proper HTML Elements
- ✅ ALWAYS use semantic HTML5 elements
- ✅ Use `<nav>`, `<main>`, `<article>`, `<section>`, `<aside>`, `<header>`, `<footer>`
- ❌ NEVER use `<div>` when a semantic element is appropriate

**Correct:**
```twig
<nav class="main-navigation">
  <ul>
    {% for item in navigation %}
      <li><a href="{{ item.url }}">{{ item.title }}</a></li>
    {% endfor %}
  </ul>
</nav>

<main class="content">
  <article class="entry">
    <header>
      <h1>{{ entry.title }}</h1>
    </header>
    <section class="content">
      {{ entry.body }}
    </section>
  </article>
</main>
```

**Incorrect:**
```twig
<div class="navigation">
  <div class="nav-items">...</div>
</div>
```

## Headings

### Proper Heading Hierarchy
- ✅ ALWAYS maintain logical heading order (h1 → h2 → h3)
- ✅ Use ONE h1 per page (typically the page title)
- ✅ Don't skip heading levels
- ❌ NEVER use headings for styling alone

**Correct:**
```twig
<h1>{{ entry.title }}</h1>
<section>
  <h2>Section Title</h2>
  <h3>Subsection</h3>
</section>
```

**Incorrect:**
```twig
<h1>Page Title</h1>
<h3>Next Section</h3> {# Skipped h2 #}
```

## Images

### Alt Text Requirements
- ✅ ALWAYS provide descriptive alt text for content images
- ✅ Use empty alt="" for decorative images
- ✅ Avoid "image of" or "picture of" in alt text
- ❌ NEVER leave alt attribute empty for content images

**Correct:**
```twig
{# Content image #}
<img src="{{ entry.image.url }}" alt="{{ entry.image.title }}" />

{# Decorative image #}
<img src="/images/decorative-border.svg" alt="" />
```

## Forms

### Form Accessibility
- ✅ ALWAYS associate labels with inputs using `for` attribute
- ✅ Use `<fieldset>` and `<legend>` for related form groups
- ✅ Provide clear error messages
- ✅ Use `aria-describedby` for help text
- ❌ NEVER use placeholder as a label

**Correct:**
```twig
<form>
  <div class="form-group">
    <label for="email">Email Address</label>
    <input
      type="email"
      id="email"
      name="email"
      aria-describedby="email-help"
      required
    />
    <p id="email-help" class="help-text">We'll never share your email.</p>
  </div>
</form>
```

## Links

### Link Text Best Practices
- ✅ Link text must describe the destination
- ✅ Use descriptive text, not "click here" or "read more"
- ✅ External links should indicate they open in new window
- ❌ NEVER use generic link text

**Correct:**
```twig
<a href="{{ entry.url }}">{{ entry.title }}</a>
<a href="{{ externalUrl }}" target="_blank" rel="noopener">
  Visit the official website
  <span class="sr-only">(opens in new window)</span>
</a>
```

**Incorrect:**
```twig
<a href="{{ entry.url }}">Click here</a>
<a href="{{ entry.url }}">Read more</a>
```

## Color Contrast

### WCAG AA Requirements
- ✅ Normal text: 4.5:1 contrast ratio minimum
- ✅ Large text (18pt+): 3:1 contrast ratio minimum
- ✅ Test color combinations with a contrast checker
- ❌ NEVER rely on color alone to convey information

**Correct:**
```twig
{# High contrast text #}
<p class="text-gray-900 bg-white">Readable text</p>

{# Icon with text label #}
<button>
  <svg>...</svg>
  <span>Delete</span>
</button>
```

## Keyboard Navigation

### Focus Management
- ✅ ALWAYS ensure all interactive elements are keyboard accessible
- ✅ Provide visible focus states
- ✅ Maintain logical tab order
- ❌ NEVER remove focus outlines without replacement

**Correct:**
```css
/* Visible focus state */
button:focus {
  outline: 2px solid #0066cc;
  outline-offset: 2px;
}
```

## ARIA

### When to Use ARIA
- ✅ Use ARIA when native HTML doesn't provide needed semantics
- ✅ Use ARIA landmarks for navigation regions
- ✅ Use `aria-label` for icon-only buttons
- ❌ NEVER use ARIA when native HTML is sufficient

**Correct:**
```twig
{# Icon-only button needs aria-label #}
<button aria-label="Close dialog">
  <svg>...</svg>
</button>

{# Text button doesn't need ARIA #}
<button>Close</button>

{# Landmark for main navigation #}
<nav aria-label="Main navigation">
  {# navigation items #}
</nav>
```

## Screen Reader Text

### Visually Hidden But Accessible
- ✅ Use sr-only class for screen reader only text
- ✅ Provide context for icon-only elements
- ❌ NEVER use display:none or visibility:hidden for important content

**Tailwind sr-only class:**
```twig
<a href="{{ entry.url }}">
  Read more
  <span class="sr-only">about {{ entry.title }}</span>
</a>
```

## Tables

### Accessible Data Tables
- ✅ ALWAYS use `<th>` for headers with `scope` attribute
- ✅ Provide `<caption>` for table description
- ✅ Use proper table structure
- ❌ NEVER use tables for layout

**Correct:**
```twig
<table>
  <caption>Project Timeline</caption>
  <thead>
    <tr>
      <th scope="col">Task</th>
      <th scope="col">Due Date</th>
    </tr>
  </thead>
  <tbody>
    {% for task in tasks %}
      <tr>
        <td>{{ task.name }}</td>
        <td>{{ task.date }}</td>
      </tr>
    {% endfor %}
  </tbody>
</table>
```

## Testing Checklist

Before deployment, verify:
- [ ] All images have appropriate alt text
- [ ] All form inputs have associated labels
- [ ] Keyboard navigation works throughout
- [ ] Color contrast meets WCAG AA standards
- [ ] Heading hierarchy is logical
- [ ] No content is only accessible via mouse
- [ ] Screen reader announces content correctly
- [ ] Focus indicators are visible
