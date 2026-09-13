---
paths:
  - "**/*.{html,htm,twig,php,astro,js}"
---

# Alpine.js Rules

These rules MUST be followed when writing Alpine.js components for interactive features.

## Component Initialization

### x-data Directive
- ✅ ALWAYS initialize component state with `x-data`
- ✅ Use descriptive property names
- ✅ Initialize with appropriate default values
- ❌ NEVER use global JavaScript variables for component state

**Correct:**
```html
<div x-data="{ isOpen: false, selectedTab: 'home', items: [] }">
```

**Incorrect:**
```html
<div x-data="{ o: false, t: 'h', i: [] }">  {* Cryptic names *}
<div x-data>  {* No initialization *}
```

### State Management
- ✅ Keep state close to where it's used
- ✅ Use meaningful boolean names: `isOpen`, `isVisible`, `isActive`
- ✅ Use descriptive names for data: `selectedItem`, `currentTab`, `filteredResults`
- ❌ NEVER store state in non-Alpine variables

**Correct Naming:**
```html
<div x-data="{
  isMenuOpen: false,
  selectedCategory: null,
  searchQuery: '',
  filteredItems: []
}">
```

## Event Handling

### Click Events
- ✅ Use `@click` shorthand (NOT `x-on:click`)
- ✅ Toggle booleans cleanly
- ✅ Use arrow functions for complex logic
- ❌ NEVER use inline JavaScript without Alpine syntax

**Correct:**
```html
<button @click="isOpen = !isOpen">Toggle</button>
<button @click="selectedTab = 'about'">About</button>
<button @click="items.push({ id: Date.now(), name: 'New' })">Add</button>
```

**Incorrect:**
```html
<button onclick="toggle()">Toggle</button>  {* Don't use vanilla JS *}
<button x-on:click="isOpen = !isOpen">  {* Use @click shorthand *}
```

### Other Events
- ✅ Use `@submit.prevent` for forms
- ✅ Use `@keydown.escape` for modals
- ✅ Use `@click.away` for dropdowns/modals
- ✅ Use event modifiers when appropriate

**Form Submission:**
```html
<form @submit.prevent="handleSubmit()">
```

**Escape Key:**
```html
<div @keydown.escape="isOpen = false">
```

**Click Away:**
```html
<div x-show="isOpen" @click.away="isOpen = false">
```

## Conditional Rendering

### x-show vs x-if
- ✅ Use `x-show` for frequently toggled elements (keeps in DOM)
- ✅ Use `x-if` for elements that rarely appear (removes from DOM)
- ✅ Combine with transitions for smooth animations

**x-show (Frequent toggling):**
```html
<div x-show="isOpen" class="dropdown-menu">
  {* Menu content *}
</div>
```

**x-if (Rare rendering):**
```html
<template x-if="user.isAdmin">
  <div class="admin-panel">
    {* Admin content *}
  </div>
</template>
```

### Conditional Classes
- ✅ Use `:class` or `x-bind:class` for dynamic classes
- ✅ Use object syntax for multiple conditions
- ✅ Combine with Tailwind classes

**Correct:**
```html
<button :class="{ 'bg-brand-green': isActive, 'bg-gray-400': !isActive }">

<div :class="isOpen ? 'block' : 'hidden'">

<nav>
  <a :class="{ 'border-b-2 border-brand-green font-bold': tab === 'home' }">
    Home
  </a>
</nav>
```

## Data Binding

### x-model
- ✅ Use `x-model` for form inputs
- ✅ Bind to descriptive state properties
- ✅ Use `x-model.debounce` for search inputs

**Text Input:**
```html
<input
  type="text"
  x-model="searchQuery"
  placeholder="Search..."
  class="px-4 py-2 border rounded"
/>
```

**Debounced Input:**
```html
<input
  type="text"
  x-model.debounce.500ms="searchQuery"
  placeholder="Search..."
/>
```

**Checkbox:**
```html
<input type="checkbox" x-model="agreedToTerms" />
```

**Select:**
```html
<select x-model="selectedCategory">
  <option value="">All Categories</option>
  <option value="resources">Resources</option>
  <option value="guides">Guides</option>
</select>
```

## Computed Properties

### Getters
- ✅ Use getter functions for computed values
- ✅ Name getters descriptively
- ✅ Keep getters pure (no side effects)

**Correct:**
```html
<div x-data="{
  items: ['Apple', 'Banana', 'Cherry'],
  search: '',
  get filteredItems() {
    return this.items.filter(item =>
      item.toLowerCase().includes(this.search.toLowerCase())
    )
  }
}">
  <input x-model="search" type="text" placeholder="Filter..." />

  <template x-for="item in filteredItems" :key="item">
    <li x-text="item"></li>
  </template>
</div>
```

## Loops and Lists

### x-for
- ✅ ALWAYS use `:key` with `x-for`
- ✅ Use `<template>` as the wrapper for `x-for`
- ✅ Keep unique, stable keys

**Correct:**
```html
<template x-for="(item, index) in items" :key="item.id">
  <div class="item" x-text="item.name"></div>
</template>
```

**Incorrect:**
```html
<div x-for="item in items">  {* Missing :key *}
  <span x-text="item"></span>
</div>
```

## Transitions

### x-transition
- ✅ ALWAYS add transitions to toggled elements
- ✅ Use `x-transition` for default fade
- ✅ Use custom transitions for specific effects

**Simple Transition:**
```html
<div x-show="isOpen" x-transition>
  Content with fade in/out
</div>
```

**Custom Transition:**
```html
<div
  x-show="isOpen"
  x-transition:enter="transition ease-out duration-300"
  x-transition:enter-start="opacity-0 transform scale-95"
  x-transition:enter-end="opacity-100 transform scale-100"
  x-transition:leave="transition ease-in duration-200"
  x-transition:leave-start="opacity-100 transform scale-100"
  x-transition:leave-end="opacity-0 transform scale-95"
>
  Content with custom animation
</div>
```

## Text and HTML Binding

### x-text
- ✅ Use `x-text` for simple text content
- ✅ Escapes HTML automatically (safe)

**Correct:**
```html
<span x-text="userName"></span>
<p x-text="message"></p>
```

### x-html
- ⚠️  Use `x-html` ONLY when absolutely necessary
- ⚠️  NEVER use with user-generated content (XSS risk)
- ✅ Sanitize content before using x-html

**Use Sparingly:**
```html
{* Only for trusted, CMS-generated HTML *}
<div x-html="trustedHtmlContent"></div>
```

## Component Patterns

### Dropdown Menu
```html
<div x-data="{ isOpen: false }" class="relative">
  <button
    @click="isOpen = !isOpen"
    class="px-4 py-2 bg-brand-green text-white rounded"
  >
    Menu
  </button>

  <div
    x-show="isOpen"
    @click.away="isOpen = false"
    x-transition
    class="absolute right-0 mt-2 w-48 bg-white rounded shadow-lg"
  >
    <a href="#" class="block px-4 py-2 hover:bg-gray-100">Option 1</a>
    <a href="#" class="block px-4 py-2 hover:bg-gray-100">Option 2</a>
  </div>
</div>
```

### Modal Dialog
```html
<div x-data="{ isOpen: false }">
  <button @click="isOpen = true" class="bg-brand-blue text-white px-4 py-2">
    Open Modal
  </button>

  <div
    x-show="isOpen"
    @keydown.escape="isOpen = false"
    x-transition
    class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
  >
    <div
      @click.away="isOpen = false"
      class="bg-white rounded-lg p-8 max-w-md"
    >
      <h2 class="text-2xl font-bold mb-4">Modal Title</h2>
      <p class="text-gray-700 mb-6">Modal content here</p>
      <button
        @click="isOpen = false"
        class="bg-brand-green text-white px-6 py-2 rounded"
      >
        Close
      </button>
    </div>
  </div>
</div>
```

### Tabs Component
```html
<div x-data="{ activeTab: 'tab1' }">
  <div class="flex border-b">
    <button
      @click="activeTab = 'tab1'"
      :class="{ 'border-b-2 border-brand-green font-bold': activeTab === 'tab1' }"
      class="px-4 py-2"
    >
      Tab 1
    </button>
    <button
      @click="activeTab = 'tab2'"
      :class="{ 'border-b-2 border-brand-green font-bold': activeTab === 'tab2' }"
      class="px-4 py-2"
    >
      Tab 2
    </button>
  </div>

  <div x-show="activeTab === 'tab1'" x-transition class="p-4">
    Tab 1 Content
  </div>
  <div x-show="activeTab === 'tab2'" x-transition class="p-4">
    Tab 2 Content
  </div>
</div>
```

### Accordion
```html
<div x-data="{ openItem: null }">
  <template x-for="(item, index) in items" :key="index">
    <div class="border-b">
      <button
        @click="openItem = openItem === index ? null : index"
        class="w-full text-left px-4 py-3 font-bold hover:bg-gray-100 flex justify-between items-center"
      >
        <span x-text="item.title"></span>
        <span x-text="openItem === index ? '−' : '+'"></span>
      </button>

      <div
        x-show="openItem === index"
        x-transition
        class="px-4 py-3 bg-gray-50"
      >
        <p x-text="item.content"></p>
      </div>
    </div>
  </template>
</div>
```

## Magic Properties

### Common Magic Properties
- ✅ `$el` - Reference to current element
- ✅ `$refs` - Reference to marked elements
- ✅ `$watch` - Watch for state changes
- ✅ `$dispatch` - Dispatch custom events
- ✅ `$nextTick` - Wait for DOM update

**Using $refs:**
```html
<div x-data>
  <input x-ref="searchInput" type="text" />
  <button @click="$refs.searchInput.focus()">Focus Input</button>
</div>
```

**Using $watch:**
```html
<div x-data="{ count: 0 }" x-init="$watch('count', value => console.log(value))">
  <button @click="count++">Increment</button>
</div>
```

## Accessibility

### Keyboard Navigation
- ✅ ALWAYS support keyboard interaction
- ✅ Use `@keydown.escape` to close modals/dropdowns
- ✅ Add `tabindex` where needed
- ✅ Manage focus properly

**Modal with Escape Key:**
```html
<div
  x-show="isOpen"
  @keydown.escape="isOpen = false"
  @click.away="isOpen = false"
>
  {* Modal content *}
</div>
```

### ARIA Attributes
- ✅ Add appropriate ARIA attributes
- ✅ Use `:aria-expanded` for toggles
- ✅ Use `:aria-hidden` for hidden content

**Accessible Dropdown:**
```html
<button
  @click="isOpen = !isOpen"
  :aria-expanded="isOpen"
  aria-haspopup="true"
>
  Menu
</button>

<div
  x-show="isOpen"
  :aria-hidden="!isOpen"
  role="menu"
>
  {* Menu items *}
</div>
```

## Performance

### Keep State Minimal
- ✅ Only store what you need in state
- ✅ Use computed properties for derived data
- ❌ NEVER duplicate data in state

**Correct:**
```html
<div x-data="{
  items: [...],
  search: '',
  get filtered() {
    return this.items.filter(i => i.includes(this.search))
  }
}">
```

**Incorrect:**
```html
<div x-data="{
  items: [...],
  search: '',
  filteredItems: []  {* Don't duplicate - use computed *}
}">
```

### Avoid Deep Nesting
- ✅ Keep component nesting shallow
- ✅ Break complex components into smaller pieces
- ❌ NEVER nest x-data components more than 2 levels deep

## Anti-Patterns to Avoid

### ❌ NEVER Do These:

1. **Global JavaScript with Alpine**
   ```html
   ❌ <button onclick="toggle()">
   ✅ <button @click="isOpen = !isOpen">
   ```

2. **Missing :key in loops**
   ```html
   ❌ <template x-for="item in items">
   ✅ <template x-for="item in items" :key="item.id">
   ```

3. **x-html with user content**
   ```html
   ❌ <div x-html="userComment">  {* XSS vulnerability *}
   ✅ <div x-text="userComment">  {* Safe, escaped *}
   ```

4. **No transitions on toggle**
   ```html
   ❌ <div x-show="isOpen">
   ✅ <div x-show="isOpen" x-transition>
   ```

5. **Cryptic state names**
   ```html
   ❌ x-data="{ o: false, t: 'h' }"
   ✅ x-data="{ isOpen: false, selectedTab: 'home' }"
   ```

6. **Inline complex logic**
   ```html
   ❌ <div x-show="items.filter(i => i.active).length > 0 && user.isAdmin">
   ✅ <div x-show="hasActiveItems && userIsAdmin">
   ```

## Validation Checklist

Before committing Alpine.js code:
- [ ] All state initialized in x-data
- [ ] Descriptive property names used
- [ ] Transitions added to toggled elements
- [ ] :key provided for all x-for loops
- [ ] Click-away handlers for dropdowns/modals
- [ ] Escape key handler for modals
- [ ] Appropriate ARIA attributes
- [ ] No x-html with user content
- [ ] Computed properties for derived data
- [ ] Performance considerations addressed
