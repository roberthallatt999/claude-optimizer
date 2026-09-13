---
paths:
  - "docs/**/*.{md,mdx}"
  - "blog/**/*.{md,mdx}"
  - "src/pages/**/*.{md,mdx}"
---

# Markdown Content Rules (Docusaurus)

These rules MUST be followed when writing Markdown content for Docusaurus.

## Frontmatter

### Required Metadata
```markdown
---
id: unique-id
title: Page Title
description: Brief description for SEO
---
```

## Heading Structure

### Proper Hierarchy
- ✅ Start with h2 (Docusaurus generates h1 from title)
- ✅ Maintain logical order
- ✅ Don't skip levels

```markdown
## Main Section

Content here.

### Subsection

More content.
```

## Links

### Internal Links
```markdown
[Link to another doc](./other-doc.md)
[Link to specific section](./other-doc.md#section)
```

### External Links
```markdown
[External link](https://example.com)
```

## Code Blocks

### With Language Syntax
```markdown
\`\`\`javascript
function hello() {
  console.log('Hello World');
}
\`\`\`
```

### With Title
```markdown
\`\`\`js title="src/hello.js"
console.log('Hello');
\`\`\`
```

## Admonitions

```markdown
:::note
This is a note
:::

:::tip
This is a tip
:::

:::warning
This is a warning
:::

:::danger
This is dangerous
:::
```

## Checklist

- [ ] Frontmatter is complete
- [ ] Heading hierarchy is correct
- [ ] Code blocks have language specified
- [ ] Links are properly formatted
