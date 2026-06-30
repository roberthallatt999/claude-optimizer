# Vitest Conventions

> Vitest is Jest-compatible but ESM-native and Vite-powered.
> It shares the same assertion API as Jest — `describe`, `it`, `expect`, `vi` (instead of `jest`).
> Check `vitest.config.ts` for coverage provider, globals setting, and test environment.

## Configuration

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    globals: true,
    environment: 'jsdom',       // 'node' for API/utility tests
    setupFiles: ['./src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      exclude: ['node_modules', 'src/test'],
    },
  },
});
```

```ts
// src/test/setup.ts
import '@testing-library/jest-dom';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => { cleanup(); });
```

## Unit Tests

```ts
// src/lib/utils.test.ts
import { describe, it, expect } from 'vitest';
import { formatDate, slugify } from './utils';

describe('formatDate', () => {
  it('formats a date as YYYY-MM-DD', () => {
    expect(formatDate(new Date('2024-01-15'))).toBe('2024-01-15');
  });

  it('returns empty string for invalid date', () => {
    expect(formatDate(new Date('invalid'))).toBe('');
  });
});

describe('slugify', () => {
  it.each([
    ['Hello World', 'hello-world'],
    ['  spaces  ', 'spaces'],
    ['Café & Pastry', 'cafe-pastry'],
  ])('slugifies %s → %s', (input, expected) => {
    expect(slugify(input)).toBe(expected);
  });
});
```

## React Component Tests

```tsx
// src/components/Button.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from './Button';

describe('Button', () => {
  it('renders with label', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByRole('button', { name: /click me/i })).toBeInTheDocument();
  });

  it('calls onClick when clicked', async () => {
    const user = userEvent.setup();
    const handleClick = vi.fn();
    render(<Button onClick={handleClick}>Click</Button>);
    await user.click(screen.getByRole('button'));
    expect(handleClick).toHaveBeenCalledOnce();
  });

  it('is disabled when loading', () => {
    render(<Button loading>Loading</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

## Mocking

```ts
import { vi, beforeEach, afterEach } from 'vitest';

// Mock module
vi.mock('@/lib/api', () => ({
  fetchUser: vi.fn().mockResolvedValue({ id: '1', name: 'Alice' }),
}));

// Mock specific export
import * as api from '@/lib/api';
vi.spyOn(api, 'fetchUser').mockResolvedValue({ id: '1', name: 'Alice' });

// Mock with factory
const mockFetch = vi.fn();
global.fetch = mockFetch;

// Reset between tests
beforeEach(() => { vi.clearAllMocks(); });
afterEach(() => { vi.restoreAllMocks(); });

// Fake timers
vi.useFakeTimers();
vi.runAllTimers();
vi.useRealTimers();
```

## Async Testing

```ts
it('fetches and displays user', async () => {
  vi.mocked(fetchUser).mockResolvedValue({ id: '1', name: 'Alice' });

  render(<UserProfile userId="1" />);

  // Wait for async state
  expect(await screen.findByText('Alice')).toBeInTheDocument();
  expect(screen.queryByRole('progressbar')).not.toBeInTheDocument();
});

it('shows error state on failure', async () => {
  vi.mocked(fetchUser).mockRejectedValue(new Error('Not found'));

  render(<UserProfile userId="1" />);

  expect(await screen.findByRole('alert')).toHaveTextContent('Not found');
});
```

## Snapshot Testing

```ts
// Use sparingly — only for stable UI output
it('matches snapshot', () => {
  const { asFragment } = render(<Badge variant="success">Active</Badge>);
  expect(asFragment()).toMatchSnapshot();
});

// Inline snapshots (preferred — no separate .snap file)
expect(formatDate(new Date('2024-01-15'))).toMatchInlineSnapshot('"2024-01-15"');
```

## Test Scripts

```json
{
  "scripts": {
    "test": "vitest",
    "test:run": "vitest run",
    "test:coverage": "vitest run --coverage",
    "test:ui": "vitest --ui"
  }
}
```

## Coverage Thresholds

```ts
// vitest.config.ts
coverage: {
  thresholds: {
    lines: 80,
    functions: 80,
    branches: 70,
  }
}
```

## Avoid

- `@testing-library/user-event` v13 patterns in v14 (setup() API changed)
- Testing implementation details (internal state, method calls)
- Snapshot-heavy test suites — they create noise on refactors
- `waitFor` polling loops when `findBy*` queries work
- Mocking entire modules when `vi.spyOn` on a specific export is enough
