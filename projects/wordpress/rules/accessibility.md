---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
---

# Accessibility Rules (WCAG 2.1 AA Compliance)

These rules MUST be followed to ensure the {{PROJECT_NAME}} website is accessible to all users.

## Semantic HTML

### Use Proper HTML Elements
- ✅ ALWAYS use semantic HTML5 elements
- ✅ Use `<nav>`, `<main>`, `<article>`, `<section>`, `<aside>`, `<header>`, `<footer>`
- ❌ NEVER use `<div>` when a semantic element is appropriate

**Correct:**
```html
<nav class="main-navigation">
  <ul>
    <li><a href="/">Home</a></li>
  </ul>
</nav>

<main class="content">
  <article class="resource">
    <header>
      <h1>Resource Title</h1>
    </header>
    <section class="content">
      <p>Content here</p>
    </section>
  </article>
</main>

<aside class="sidebar">
  <section class="related">
    <h2>Related Resources</h2>
  </section>
</aside>

<footer class="site-footer">
  <p>&copy; 2024 {{PROJECT_NAME}}</p>
</footer>
```

**Incorrect:**
```html
<div class="nav">  {* Use <nav> *}
<div class="main">  {* Use <main> *}
<div class="article">  {* Use <article> *}
```

### Heading Hierarchy
- ✅ ALWAYS maintain proper heading hierarchy
- ✅ One `<h1>` per page
- ✅ Don't skip heading levels (h1 → h2 → h3, NOT h1 → h3)
- ❌ NEVER use headings for styling only

**Correct:**
```html
<h1>Page Title</h1>
  <h2>Section Title</h2>
    <h3>Subsection Title</h3>
    <h3>Another Subsection</h3>
  <h2>Another Section</h2>
```

**Incorrect:**
```html
<h1>Page Title</h1>
  <h3>Section</h3>  {* Skipped h2 *}
  <h2>Another</h2>  {* Out of order *}
```

## Images and Media

### Alt Text
- ✅ ALWAYS provide `alt` attributes on images
- ✅ Describe the content/function, not the file
- ✅ Use empty alt (`alt=""`) for decorative images
- ❌ NEVER omit alt attribute

**Content Images:**
```html
<img
  src="/images/child-checkup.jpg"
  alt="Healthcare provider examining a young child"
  class="rounded-lg"
/>
```

**Decorative Images:**
```html
<img
  src="/images/decorative-pattern.png"
  alt=""
  aria-hidden="true"
  class="absolute"
/>
```

**Functional Images (icons in buttons):**
```html
<button type="submit" class="bg-brand-green text-white px-6 py-2">
  <img src="/icons/search.svg" alt="" aria-hidden="true" />
  <span>Search</span>
</button>
```

**Icon-only Buttons:**
```html
<button aria-label="Close modal" @click="isOpen = false">
  <img src="/icons/close.svg" alt="" aria-hidden="true" />
</button>
```

### Video and Audio
- ✅ Provide captions for video content
- ✅ Provide transcripts for audio content
- ✅ Include controls attribute

```html
<video controls>
  <source src="/videos/tutorial.mp4" type="video/mp4" />
  <track
    kind="captions"
    src="/videos/tutorial-en.vtt"
    srclang="en"
    label="English"
  />
  <track
    kind="captions"
    src="/videos/tutorial-fr.vtt"
    srclang="fr"
    label="Français"
  />
</video>
```

## Links and Buttons

### Link Text
- ✅ Link text MUST describe the destination
- ✅ Avoid generic text like "click here" or "read more"
- ✅ Make links distinguishable (underline, color, context)

**Correct:**
```html
<a href="/resources/immunization" class="text-brand-blue underline">
  View Resource Details
</a>

<a href="/about" class="text-brand-blue hover:text-brand-green">
  Learn about our organization
</a>
```

**Incorrect:**
```html
<a href="/resources/immunization">Click here</a>
<a href="/resources/immunization">Read more</a>
```

### Buttons vs Links
- ✅ Use `<button>` for actions (open modal, submit form, toggle)
- ✅ Use `<a>` for navigation (go to another page)
- ❌ NEVER use a link styled as a button for actions

**Button (Action):**
```html
<button
  type="button"
  @click="isOpen = true"
  class="bg-brand-green text-white px-6 py-2 rounded"
>
  Open Modal
</button>
```

**Link (Navigation):**
```html
<a
  href="/resources"
  class="inline-block bg-brand-green text-white px-6 py-2 rounded"
>
  View Resources
</a>
```

## Forms

### Label Association
- ✅ ALWAYS associate labels with inputs using `for` attribute
- ✅ Provide visible labels (not just placeholder)
- ✅ Group related inputs with `<fieldset>` and `<legend>`

**Text Input:**
```html
<div class="mb-4">
  <label for="email" class="block text-gray-700 font-bold mb-2">
    Email Address
  </label>
  <input
    type="email"
    id="email"
    name="email"
    class="w-full px-4 py-2 border rounded"
    required
  />
</div>
```

**Radio Group:**
```html
<fieldset class="mb-4">
  <legend class="text-gray-700 font-bold mb-2">
    Language Preference
  </legend>
  <div class="space-y-2">
    <label class="flex items-center">
      <input type="radio" name="language" value="en" class="mr-2" />
      English
    </label>
    <label class="flex items-center">
      <input type="radio" name="language" value="fr" class="mr-2" />
      Français
    </label>
  </div>
</fieldset>
```

### Error Messages
- ✅ Associate error messages with inputs using `aria-describedby`
- ✅ Make errors visible and clear
- ✅ Use color AND text/icons (not color alone)

**Input with Error:**
```html
<div class="mb-4">
  <label for="email" class="block text-gray-700 font-bold mb-2">
    Email Address
  </label>
  <input
    type="email"
    id="email"
    name="email"
    aria-describedby="email-error"
    aria-invalid="true"
    class="w-full px-4 py-2 border border-red-500 rounded"
  />
  <p id="email-error" class="text-red-500 text-sm mt-1" role="alert">
    <span aria-hidden="true">⚠</span> Please enter a valid email address
  </p>
</div>
```

### Required Fields
- ✅ Mark required fields visually and in code
- ✅ Use `required` attribute
- ✅ Indicate required fields in legend/label

**Required Field:**
```html
<label for="name" class="block text-gray-700 font-bold mb-2">
  Full Name <span class="text-red-500" aria-label="required">*</span>
</label>
<input
  type="text"
  id="name"
  name="name"
  required
  aria-required="true"
  class="w-full px-4 py-2 border rounded"
/>
```

## Keyboard Navigation

### Focus Indicators
- ✅ ALWAYS provide visible focus indicators
- ✅ Use Tailwind's focus utilities
- ❌ NEVER remove focus outlines without replacement

**Correct:**
```html
<button class="bg-brand-green text-white px-6 py-2 rounded focus:outline-none focus:ring-2 focus:ring-brand-green focus:ring-offset-2">
  Click Me
</button>

<a href="/resources" class="text-brand-blue underline focus:outline-none focus:ring-2 focus:ring-brand-blue">
  View Resources
</a>

<input
  type="text"
  class="px-4 py-2 border rounded focus:outline-none focus:border-brand-blue focus:ring-2 focus:ring-brand-blue/20"
/>
```

**Incorrect:**
```html
<button class="focus:outline-none">  {* No replacement focus indicator *}
```

### Tab Order
- ✅ Ensure logical tab order matches visual order
- ✅ Use `tabindex="0"` to add elements to tab order
- ✅ Use `tabindex="-1"` to remove from tab order (programmatically focusable)
- ❌ NEVER use positive tabindex values (1, 2, 3...)

**Custom Interactive Element:**
```html
<div
  role="button"
  tabindex="0"
  @click="toggleMenu()"
  @keydown.enter="toggleMenu()"
  @keydown.space.prevent="toggleMenu()"
  class="cursor-pointer"
>
  Toggle Menu
</div>
```

### Keyboard Shortcuts
- ✅ Support Enter and Space for buttons/controls
- ✅ Support Escape to close modals/dropdowns
- ✅ Support arrow keys for navigation (tabs, menus)

**Modal with Escape:**
```html
<div
  x-show="isOpen"
  @keydown.escape="isOpen = false"
  role="dialog"
  aria-modal="true"
  aria-labelledby="modal-title"
>
  <h2 id="modal-title">Modal Title</h2>
  {* Modal content *}
</div>
```

## Color Contrast

### Contrast Ratios (WCAG AA)
- ✅ Text: Minimum 4.5:1 contrast ratio
- ✅ Large text (18pt+): Minimum 3:1 contrast ratio
- ✅ UI components: Minimum 3:1 contrast ratio

**Acceptable Combinations:**
```html
{* White text on brand-green ({{BRAND_GREEN}}) - 4.8:1 ratio ✅ *}
<div class="bg-brand-green text-white">

{* White text on brand-blue ({{BRAND_BLUE}}) - 5.2:1 ratio ✅ *}
<div class="bg-brand-blue text-white">

{* Dark gray text on white - 12:1 ratio ✅ *}
<p class="text-gray-800">

{* Medium gray text on white - 7:1 ratio ✅ *}
<p class="text-gray-600">
```

**Check Contrast:**
Use tools like:
- WebAIM Contrast Checker
- Chrome DevTools (Inspect > Accessibility)
- Figma contrast plugins

### Don't Rely on Color Alone
- ✅ Use multiple indicators (color + icon + text)
- ✅ Provide text alternatives for color-coded info

**Correct (Multiple Indicators):**
```html
<div class="flex items-center gap-2 text-red-600">
  <svg class="w-5 h-5" aria-hidden="true">
    {* Error icon *}
  </svg>
  <span>Error: Form submission failed</span>
</div>

<div class="flex items-center gap-2 text-green-600">
  <svg class="w-5 h-5" aria-hidden="true">
    {* Success icon *}
  </svg>
  <span>Success: Form submitted</span>
</div>
```

## ARIA Attributes

### When to Use ARIA
- ✅ Use ARIA when native HTML doesn't provide needed semantics
- ✅ First rule of ARIA: Don't use ARIA if HTML can do it
- ❌ NEVER use ARIA to fix poorly structured HTML

### Common ARIA Attributes

**aria-label:**
```html
<button aria-label="Close modal" @click="isOpen = false">
  <svg aria-hidden="true">×</svg>
</button>
```

**aria-labelledby:**
```html
<section aria-labelledby="resources-heading">
  <h2 id="resources-heading">Featured Resources</h2>
  {* Section content *}
</section>
```

**aria-describedby:**
```html
<input
  type="password"
  id="password"
  aria-describedby="password-requirements"
/>
<p id="password-requirements" class="text-sm text-gray-600">
  Password must be at least 8 characters
</p>
```

**aria-expanded (for dropdowns/accordions):**
```html
<button
  @click="isOpen = !isOpen"
  :aria-expanded="isOpen"
  aria-controls="dropdown-menu"
>
  Menu
</button>
<div id="dropdown-menu" x-show="isOpen">
  {* Menu items *}
</div>
```

**aria-live (for dynamic updates):**
```html
<div aria-live="polite" aria-atomic="true" class="sr-only">
  <span x-text="statusMessage"></span>
</div>
```

**aria-current (for navigation):**
```html
<nav>
  <a href="/" :aria-current="currentPage === 'home' ? 'page' : null">
    Home
  </a>
</nav>
```

### Role Attribute
- ✅ Use `role` when native HTML semantics aren't sufficient
- ❌ NEVER override native HTML roles

**Custom Interactive Elements:**
```html
<div
  role="button"
  tabindex="0"
  @click="handleAction()"
  @keydown.enter="handleAction()"
  @keydown.space.prevent="handleAction()"
>
  Custom Button
</div>
```

**Modal Dialog:**
```html
<div
  role="dialog"
  aria-modal="true"
  aria-labelledby="dialog-title"
  x-show="isOpen"
>
  <h2 id="dialog-title">Dialog Title</h2>
</div>
```

## Screen Reader Support

### Visually Hidden Text
- ✅ Use `.sr-only` class for screen-reader-only text
- ✅ Provide context for icons and visual indicators

**Screen Reader Only Text:**
```html
<span class="sr-only">Skip to main content</span>

<button class="p-2">
  <svg aria-hidden="true">
    {* Icon *}
  </svg>
  <span class="sr-only">Search</span>
</button>
```

**Add to global CSS:**
```css
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}
```

### Skip Links
- ✅ Provide skip navigation links
- ✅ Make them visible on focus

**Skip Link:**
```html
<a
  href="#main-content"
  class="sr-only focus:not-sr-only focus:absolute focus:top-0 focus:left-0 focus:z-50 focus:bg-brand-green focus:text-white focus:px-6 focus:py-3"
>
  Skip to main content
</a>

<main id="main-content">
  {* Page content *}
</main>
```

## Language and Direction

### Language Attributes
- ✅ Set `lang` attribute on `<html>` tag
- ✅ Mark language changes with `lang` attribute

**HTML Tag:**
```html
<html lang="en">  {* or lang="fr" *}
```

**Language Switching:**
```html
{if lang == 'en'}
  <html lang="en">
{if:else}
  <html lang="fr">
{/if}
```

**Mixed Language Content:**
```html
<p>
  The site is called
  <span lang="fr">{{PROJECT_NAME_FR}}</span>
  in French.
</p>
```

## Bilingual Accessibility

### Both Languages Accessible
- ✅ Ensure BOTH English and French versions are fully accessible
- ✅ Translate alt text, labels, and ARIA attributes
- ✅ Maintain same accessibility features in both languages

**Bilingual Alt Text:**
```html
{if lang == 'en'}
  <img src="child-checkup.jpg" alt="Healthcare provider examining a young child" />
{if:else}
  <img src="child-checkup.jpg" alt="Professionnel de la santé examinant un jeune enfant" />
{/if}
```

## Validation Checklist

Before committing any code:
- [ ] Semantic HTML elements used appropriately
- [ ] Proper heading hierarchy (h1 → h2 → h3)
- [ ] All images have alt text
- [ ] Forms have associated labels
- [ ] Keyboard navigation works
- [ ] Visible focus indicators present
- [ ] Color contrast meets WCAG AA (4.5:1)
- [ ] ARIA attributes used correctly
- [ ] Screen reader tested (if possible)
- [ ] Both English and French accessible
- [ ] No reliance on color alone
- [ ] Skip links provided
