---
paths:
  - "system/user/templates/**"
---

# ExpressionEngine Template Rules

These rules MUST be followed when writing or modifying ExpressionEngine templates.

## File Organization

### Template Location
- ✅ All templates MUST be in `/system/user/templates/{{TEMPLATE_GROUP}}/`
- ✅ Organize by template groups (e.g., `home/`, `about/`, `resources/`)
- ✅ Use lowercase kebab-case for template names: `about-us.html`, `resource-detail.html`
- ❌ NEVER create templates outside the designated template group

### File Structure
```
/system/user/templates/{{TEMPLATE_GROUP}}/
├── home/
│   └── index.html
├── about/
│   ├── index.html
│   └── team.html
├── resources/
│   ├── index.html
│   └── detail.html
└── stash/
    └── _partials.html
```

## Indentation and Formatting

### Required Format
- ✅ ALWAYS use 2-space indentation (NOT tabs)
- ✅ One level of indentation per nesting level
- ✅ Blank line between major sections
- ✅ Consistent spacing around operators

### Example
```
{if lang == 'en'}
  <div class="container">
    {exp:channel:entries channel="pages"}
      <h1>{title}</h1>
    {/exp:channel:entries}
  </div>
{/if}
```

## Tag Syntax

### Conditional Blocks
- ✅ ALWAYS close conditional blocks with `{/if}`
- ✅ Use spaces around operators: `lang == 'en'` NOT `lang=='en'`
- ✅ Use `{if:else}` NOT `{else}`
- ❌ NEVER nest more than 3 levels deep

**Correct:**
```
{if lang == 'en'}
  English content
{if:else}
  French content
{/if}
```

**Incorrect:**
```
{if lang=='en'}English{else}French{/if}
```

### Channel Entries
- ✅ ALWAYS specify the channel parameter
- ✅ Use meaningful variable names
- ✅ Close all channel:entries tags
- ✅ Cache with Stash when appropriate

**Correct:**
```
{exp:channel:entries channel="pages" limit="10"}
  <article>
    <h2>{title}</h2>
    <div>{body}</div>
  </article>
{/exp:channel:entries}
```

**Incorrect:**
```
{exp:channel:entries}
  {title}
{/exp:channel:entries}
```

## Stash Caching Rules

### When to Cache
- ✅ ALWAYS cache navigation components
- ✅ ALWAYS cache channel:entries queries
- ✅ ALWAYS cache Structure:nav calls
- ✅ Cache any database-intensive operation

### Cache Scope Selection
- ✅ Use `scope="site"` for content shared across all visitors
- ✅ Use `scope="user"` for user-specific content
- ✅ Use `scope="local"` for temporary page-build data
- ❌ NEVER use the wrong scope (causes cache pollution)

### Static vs TTL Caching
- ✅ Use `static="yes"` for content that NEVER changes (navigation)
- ✅ Use `ttl="86400"` (1 day) for content that changes daily
- ✅ Use `ttl="3600"` (1 hour) for frequently updated content
- ❌ NEVER cache without TTL unless using `static="yes"`

**Navigation (static):**
```
{exp:stash:set name="main_nav" scope="site" static="yes"}
  {exp:structure:nav channel="pages" max_depth="2"}
    <a href="{url}">{title}</a>
  {/exp:structure:nav}
{/exp:stash:set}

{exp:stash:get name="main_nav"}
```

**Content listing (TTL):**
```
{exp:stash:set name="featured_resources" scope="site" ttl="86400"}
  {exp:channel:entries channel="resources" limit="5"}
    {title}
  {/exp:channel:entries}
{/exp:stash:set}

{exp:stash:get name="featured_resources"}
```

## Variable Naming

### Naming Convention
- ✅ Use snake_case for Stash variable names: `main_nav`, `page_title`
- ✅ Use descriptive names: `featured_resources` NOT `fr`
- ✅ Prefix partials with underscore: `_meta_tags`, `_header`
- ❌ NEVER use single-letter or cryptic names

**Correct:**
```
{exp:stash:set name="page_meta_title"}
{exp:stash:set name="featured_resources"}
```

**Incorrect:**
```
{exp:stash:set name="pmt"}
{exp:stash:set name="fr"}
```

## Comments

### When to Comment
- ✅ Comment complex conditional logic
- ✅ Comment cache invalidation strategies
- ✅ Explain non-obvious EE tag behavior
- ✅ Document bilingual sections

### Comment Format
```
{* This is a single-line comment *}

{*
  Multi-line comment explaining
  complex logic or behavior
*}
```

**Example:**
```
{* Cache navigation - invalidate when menu structure changes *}
{exp:stash:set name="main_nav" scope="site" static="yes"}
  {exp:structure:nav channel="pages"}
    {title}
  {/exp:structure:nav}
{/exp:stash:set}
```

## Structure Add-on

### Navigation Usage
- ✅ ALWAYS cache Structure:nav calls
- ✅ Specify `max_depth` parameter
- ✅ Use `show_all_children` when needed
- ✅ Use semantic HTML in navigation

**Correct:**
```
{exp:stash:set name="site_nav" scope="site" static="yes"}
  <nav>
    {exp:structure:nav channel="pages" max_depth="3" show_all_children="yes"}
      <a href="{url}" class="{if current}active{/if}">
        {title}
      </a>
    {/exp:structure:nav}
  </nav>
{/exp:stash:set}
```

## Performance Requirements

### Database Queries
- ✅ ALWAYS wrap channel:entries in Stash caching
- ✅ Limit query results appropriately
- ✅ Use `limit` parameter to prevent runaway queries
- ❌ NEVER nest channel:entries tags (massive performance hit)

### Template Parsing
- ✅ Use Stash to avoid re-parsing the same template multiple times
- ✅ Set appropriate TTL values based on content update frequency
- ❌ NEVER parse templates without caching considerations

## Embed Usage

### Embed Syntax
- ✅ Use embeds for reusable components: `{embed="_meta_tags"}`
- ✅ Pass parameters to embeds: `{embed="_header" title="Home"}`
- ✅ Prefix partial templates with underscore
- ❌ NEVER create deep embed chains (max 2 levels)

**Correct:**
```
{embed="_meta_tags"
  title="About Us"
  description="Learn about our organization"
}
```

## Anti-Patterns to Avoid

### ❌ NEVER Do These:
1. **Nested channel:entries** - Causes exponential database queries
2. **Uncached navigation** - Runs on every page load
3. **Missing cache scope** - Defaults to inefficient scope
4. **Hardcoded content** - Use channel entries instead
5. **Missing closing tags** - Causes template errors
6. **Deep nesting** - Max 3 levels of conditionals/loops

### ❌ Bad Example (Nested queries):
```
{* WRONG - Don't do this! *}
{exp:channel:entries channel="categories"}
  {exp:channel:entries channel="posts" category="{category_id}"}
    {title}
  {/exp:channel:entries}
{/exp:channel:entries}
```

### ✅ Good Example (Use relationships):
```
{exp:channel:entries channel="posts"}
  {title}
  {categories}{category_name}{/categories}
{/exp:channel:entries}
```

## Validation Checklist

Before committing any template:
- [ ] 2-space indentation throughout
- [ ] All tags properly closed
- [ ] Stash caching implemented for queries
- [ ] Appropriate cache scope and TTL
- [ ] Descriptive variable names
- [ ] Comments for complex logic
- [ ] Bilingual support included
- [ ] No nested channel:entries
- [ ] Performance considerations addressed
