# Accessibility Rules (WCAG 2.1 AA Compliance)

These rules MUST be followed to ensure Astro + Sanity sites are accessible to all users.

## Semantic HTML

### Use Proper HTML Elements
- ALWAYS use semantic HTML5 elements
- Use `<nav>`, `<main>`, `<article>`, `<section>`, `<aside>`, `<header>`, `<footer>`
- NEVER use `<div>` when a semantic element is appropriate

**Correct:**
```astro
<nav class="main-navigation">
  <ul>
    {navItems.map((item) => (
      <li><a href={item.url}>{item.title}</a></li>
    ))}
  </ul>
</nav>

<main class="content">
  <article class="entry">
    <header>
      <h1>{post.title}</h1>
    </header>
    <section class="body">
      <PortableText value={post.body} />
    </section>
  </article>
</main>
```

**Incorrect:**
```astro
<div class="navigation">
  <div class="nav-items">...</div>
</div>
```

## Headings

### Proper Heading Hierarchy
- ALWAYS maintain logical heading order (h1 -> h2 -> h3)
- Use ONE h1 per page (typically the page title)
- Don't skip heading levels
- NEVER use headings for styling alone

**Correct:**
```astro
<h1>{post.title}</h1>
<section>
  <h2>Section Title</h2>
  <h3>Subsection</h3>
</section>
```

**Incorrect:**
```astro
<h1>Page Title</h1>
<h3>Next Section</h3> <!-- Skipped h2 -->
```

## Images

### Alt Text Requirements
- ALWAYS provide descriptive alt text for content images
- Use empty alt="" for decorative images
- Avoid "image of" or "picture of" in alt text
- NEVER leave alt attribute missing for content images
- Sanity image fields should always include an alt text field

**Correct:**
```astro
---
import { urlFor } from '@/lib/sanity';
---

<!-- Content image from Sanity -->
<img
  src={urlFor(post.mainImage).width(800).url()}
  alt={post.mainImage.alt || post.title}
/>

<!-- Decorative image -->
<img src="/images/decorative-border.svg" alt="" />
```

## Forms

### Form Accessibility
- ALWAYS associate labels with inputs using `for` attribute
- Use `<fieldset>` and `<legend>` for related form groups
- Provide clear error messages
- Use `aria-describedby` for help text
- NEVER use placeholder as a label

**Correct:**
```astro
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
- Link text must describe the destination
- Use descriptive text, not "click here" or "read more"
- External links should indicate they open in new window
- NEVER use generic link text

**Correct:**
```astro
<a href={`/blog/${post.slug.current}`}>{post.title}</a>
<a href={externalUrl} target="_blank" rel="noopener noreferrer">
  Visit the official website
  <span class="sr-only">(opens in new window)</span>
</a>
```

**Incorrect:**
```astro
<a href={post.url}>Click here</a>
<a href={post.url}>Read more</a>
```

## Color Contrast

### WCAG AA Requirements
- Normal text: 4.5:1 contrast ratio minimum
- Large text (18pt+): 3:1 contrast ratio minimum
- Test color combinations with a contrast checker
- NEVER rely on color alone to convey information

**Correct:**
```astro
<!-- High contrast text -->
<p class="text-gray-900 bg-white">Readable text</p>

<!-- Icon with text label -->
<button>
  <svg>...</svg>
  <span>Delete</span>
</button>
```

## Keyboard Navigation

### Focus Management
- ALWAYS ensure all interactive elements are keyboard accessible
- Provide visible focus states
- Maintain logical tab order
- NEVER remove focus outlines without replacement

**Correct:**
```css
/* Visible focus state */
button:focus-visible {
  outline: 2px solid #0066cc;
  outline-offset: 2px;
}
```

## ARIA

### When to Use ARIA
- Use ARIA when native HTML doesn't provide needed semantics
- Use ARIA landmarks for navigation regions
- Use `aria-label` for icon-only buttons
- NEVER use ARIA when native HTML is sufficient

**Correct:**
```astro
<!-- Icon-only button needs aria-label -->
<button aria-label="Close dialog">
  <svg>...</svg>
</button>

<!-- Text button doesn't need ARIA -->
<button>Close</button>

<!-- Landmark for main navigation -->
<nav aria-label="Main navigation">
  <!-- navigation items -->
</nav>
```

## Screen Reader Text

### Visually Hidden But Accessible
- Use sr-only class for screen reader only text
- Provide context for icon-only elements
- NEVER use display:none or visibility:hidden for important content

**Tailwind sr-only class:**
```astro
<a href={`/blog/${post.slug.current}`}>
  Read more
  <span class="sr-only">about {post.title}</span>
</a>
```

## Tables

### Accessible Data Tables
- ALWAYS use `<th>` for headers with `scope` attribute
- Provide `<caption>` for table description
- Use proper table structure
- NEVER use tables for layout

**Correct:**
```astro
<table>
  <caption>Project Timeline</caption>
  <thead>
    <tr>
      <th scope="col">Task</th>
      <th scope="col">Due Date</th>
    </tr>
  </thead>
  <tbody>
    {tasks.map((task) => (
      <tr>
        <td>{task.name}</td>
        <td>{task.date}</td>
      </tr>
    ))}
  </tbody>
</table>
```

## Reduced Motion

### Respect User Preferences
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
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
- [ ] Sanity image schemas include alt text fields with validation
