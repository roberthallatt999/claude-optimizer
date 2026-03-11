# Accessibility Rules

These rules MUST be followed for all frontend development.

## WCAG 2.1 AA Compliance

### Images
- All `<img>` elements MUST have an `alt` attribute
- Decorative images use `alt=""`
- Complex images need detailed descriptions

### Interactive Elements
- All interactive elements MUST be keyboard accessible
- Focus indicators MUST be visible
- Use semantic HTML elements (`<button>`, `<a>`, `<nav>`)

### Forms
- All form inputs MUST have associated `<label>` elements
- Error messages MUST be programmatically associated
- Required fields MUST be indicated

### Color & Contrast
- Text MUST have minimum 4.5:1 contrast ratio (normal text)
- Large text MUST have minimum 3:1 contrast ratio
- Information MUST NOT be conveyed by color alone

### Navigation
- Skip navigation link for keyboard users
- Consistent navigation across pages
- Breadcrumbs for deep content hierarchies

### ARIA
- Use ARIA attributes only when semantic HTML is insufficient
- `aria-label` for elements without visible text
- `aria-expanded` for toggleable sections
- `role="alert"` for dynamic status messages
