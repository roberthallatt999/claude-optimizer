# Bulma Conventions (2026)

## Core Principles
- Use class-first composition from Bulma modules.
- Keep helpers local and avoid overusing custom global styles.
- Let the grid and spacing helpers express intent first.

## Layout
```html
<div class="container">
  <div class="columns is-multiline is-variable is-4">
    <div class="column is-12-tablet is-6-desktop">
      <article class="box">Left</article>
    </div>
    <div class="column is-12-tablet is-6-desktop">
      <article class="box">Right</article>
    </div>
  </div>
</div>
```

## Hero + Card
```html
<section class="hero is-link is-medium">
  <div class="hero-body">
    <p class="title">Product Overview</p>
    <p class="subtitle">Concise summary goes here</p>
  </div>
</section>

<div class="card">
  <div class="card-content">
    <p class="title">Card Title</p>
    <p class="content">Card content</p>
  </div>
</div>
```

## Form Controls
```html
<div class="field">
  <label class="label">Email</label>
  <div class="control">
    <input class="input" type="email" placeholder="you@example.com">
  </div>
</div>

<div class="field">
  <div class="control">
    <label class="checkbox"><input type="checkbox"> I agree</label>
  </div>
</div>
```

## Best Practices
- Use `is-one-quarter`, `is-half`, etc. only where they improve readability.
- Use `.notification` for status messaging patterns.
- Use modifiers (`is-success`, `is-danger`, etc.) consistently.
