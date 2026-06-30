# Framer Motion / Motion Conventions

> **Package rename (2024):** `framer-motion` is being superseded by `motion` (shorter package name).
> Both have the same API. Check `package.json` for which is installed.
> Import from `'motion/react'` (new) or `'framer-motion'` (legacy) accordingly.

## Core Imports

```tsx
// New package (motion v11+)
import { motion, AnimatePresence, useAnimation, useInView, useScroll, useTransform } from 'motion/react';

// Legacy package
import { motion, AnimatePresence } from 'framer-motion';
```

## Basic Animation

```tsx
// Animate on mount
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.3, ease: 'easeOut' }}
>
  Content
</motion.div>

// Animate on hover/tap
<motion.button
  whileHover={{ scale: 1.05 }}
  whileTap={{ scale: 0.95 }}
  transition={{ type: 'spring', stiffness: 400, damping: 17 }}
>
  Click me
</motion.button>

// Exit animation (requires AnimatePresence parent)
<motion.div
  initial={{ opacity: 0 }}
  animate={{ opacity: 1 }}
  exit={{ opacity: 0, x: -20 }}
>
  Dismissible content
</motion.div>
```

## AnimatePresence (Mount/Unmount)

```tsx
export function Modal({ isOpen, children }: { isOpen: boolean; children: React.ReactNode }) {
  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          key="modal-overlay"
          className="fixed inset-0 bg-black/50"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
        >
          <motion.div
            className="bg-white rounded-lg p-6"
            initial={{ scale: 0.9, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.9, opacity: 0 }}
            transition={{ type: 'spring', stiffness: 300, damping: 30 }}
          >
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
```

## List Animations

```tsx
// Stagger children
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0 },
};

function AnimatedList({ items }: { items: string[] }) {
  return (
    <motion.ul variants={containerVariants} initial="hidden" animate="visible">
      {items.map((item) => (
        <motion.li key={item} variants={itemVariants}>
          {item}
        </motion.li>
      ))}
    </motion.ul>
  );
}
```

## Scroll Animations

```tsx
import { useInView } from 'motion/react';
import { useRef } from 'react';

function FadeInSection({ children }: { children: React.ReactNode }) {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: '-100px' });

  return (
    <motion.section
      ref={ref}
      initial={{ opacity: 0, y: 40 }}
      animate={isInView ? { opacity: 1, y: 0 } : {}}
      transition={{ duration: 0.5, ease: 'easeOut' }}
    >
      {children}
    </motion.section>
  );
}

// Scroll-linked progress
import { useScroll, useTransform } from 'motion/react';

function ParallaxHero() {
  const { scrollY } = useScroll();
  const y = useTransform(scrollY, [0, 500], [0, 150]);

  return (
    <div className="overflow-hidden h-screen">
      <motion.img
        src="/hero.jpg"
        style={{ y }}
        className="w-full h-[120%] object-cover"
      />
    </div>
  );
}
```

## Layout Animations

```tsx
// Automatically animate layout changes (reorder, resize)
<motion.div layout className="flex gap-4 flex-wrap">
  {items.map((item) => (
    <motion.div key={item.id} layout>
      {item.name}
    </motion.div>
  ))}
</motion.div>

// Shared layout animation between routes
<motion.div layoutId={`card-${id}`} className="card">
  <motion.h2 layoutId={`title-${id}`}>{title}</motion.h2>
</motion.div>
```

## Performance Guidelines

```tsx
// Use transform properties — avoid animating layout-triggering properties
// Good: opacity, x, y, scale, rotate
// Avoid: width, height, margin, padding, top, left

// Use will-change hint for heavy animations
<motion.div
  style={{ willChange: 'transform' }}
  animate={{ x: 100 }}
/>

// Reduce motion for accessibility
import { useReducedMotion } from 'motion/react';

function AnimatedCard() {
  const shouldReduceMotion = useReducedMotion();

  return (
    <motion.div
      initial={{ opacity: 0, y: shouldReduceMotion ? 0 : 20 }}
      animate={{ opacity: 1, y: 0 }}
    />
  );
}
```

## Transition Presets

```ts
// Spring (natural feel for UI interactions)
transition={{ type: 'spring', stiffness: 400, damping: 17 }}

// Ease (smooth for content reveals)
transition={{ duration: 0.3, ease: 'easeOut' }}
transition={{ duration: 0.5, ease: [0.25, 0.1, 0.25, 1] }} // cubic-bezier

// Tween (linear/controlled)
transition={{ type: 'tween', duration: 0.2 }}
```

## Avoid

- Animating `width`/`height` — use `scaleX`/`scaleY` + `layout` instead
- Missing `key` on AnimatePresence children
- `useAnimation()` for simple animations — use `animate` prop instead
- Forgetting `useReducedMotion()` for accessibility compliance
- Overusing motion — 1-3 animations per interaction is enough
