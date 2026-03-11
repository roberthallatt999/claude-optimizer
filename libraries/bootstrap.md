# Bootstrap Conventions (2026)

## Core Principles
- Prefer utility-first layout helpers for spacing and alignment when faster, but keep semantic HTML.
- Use the grid system consistently for responsive structure.
- Favor existing components before building custom styles.

## Grid Patterns
```html
<div class="container">
  <div class="row row-cols-1 row-cols-md-3 g-4">
    <div class="col">Col 1</div>
    <div class="col">Col 2</div>
    <div class="col">Col 3</div>
  </div>
</div>
```

```html
<div class="d-flex justify-content-between align-items-center">
  <h2 class="mb-0">Title</h2>
  <button class="btn btn-primary">Save</button>
</div>
```

## Forms
```html
<form>
  <div class="mb-3">
    <label for="email" class="form-label">Email</label>
    <input id="email" type="email" class="form-control" required>
  </div>

  <div class="form-check">
    <input class="form-check-input" type="checkbox" id="terms">
    <label class="form-check-label" for="terms">I agree</label>
  </div>

  <button class="btn btn-success mt-3" type="submit">Submit</button>
</form>
```

## Component Guidance
- Use `btn`, `card`, and `alert` as primitives for UI consistency.
- Prefer `position-utilities` over custom CSS for quick state styling.
- Keep custom overrides in dedicated override files rather than inline styles.

## JavaScript Components
```js
import 'bootstrap/js/dist/modal';
import 'bootstrap/js/dist/dropdown';

const modal = new bootstrap.Modal(document.getElementById('exampleModal'));
modal.show();
```

## Accessibility
- Ensure all modals and popovers have accessible labels.
- Avoid hiding content with `display: none` when transitions are expected; prefer utility classes.
