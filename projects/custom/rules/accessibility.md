---
paths:
  - "**/*.{html,htm,twig,php,vue,svelte,astro,jsx,tsx,mdx}"
---

# Accessibility Standards

## WCAG 2.1 AA Compliance

### Perceivable

- Provide text alternatives for non-text content
- Ensure sufficient color contrast (4.5:1 for normal text, 3:1 for large text)
- Don't rely on color alone to convey information
- Ensure content is readable and functional when text is resized up to 200%

### Operable

- All functionality must be keyboard accessible
- Provide visible focus indicators for interactive elements
- Give users enough time to read and use content
- Don't design content in a way that causes seizures

### Understandable

- Use clear, simple language appropriate for the audience
- Make navigation consistent across pages
- Help users avoid and correct mistakes in forms
- Provide helpful error messages

### Robust

- Use semantic HTML elements appropriately
- Ensure compatibility with assistive technologies
- Validate HTML to avoid parsing issues

## Implementation Checklist

- [ ] All images have appropriate alt text
- [ ] Form fields have associated labels
- [ ] Links have descriptive text
- [ ] Heading hierarchy is logical (h1 → h2 → h3)
- [ ] Skip links are provided for keyboard users
- [ ] Focus order is logical
- [ ] ARIA is used only when native HTML is insufficient
