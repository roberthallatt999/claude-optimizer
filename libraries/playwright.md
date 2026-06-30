# Playwright Conventions

> Playwright is the standard for end-to-end testing. Covers Chromium, Firefox, and WebKit.
> Check `playwright.config.ts` for baseURL, test directory, and browser configuration.
> Always run against a real dev/test server — never mock network in E2E tests.

## Configuration

```ts
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['html'], ['list']],
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'mobile', use: { ...devices['iPhone 13'] } },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
});
```

## Page Object Model

```ts
// e2e/pages/login.page.ts
import { type Page, type Locator, expect } from '@playwright/test';

export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.getByLabel('Email');
    this.passwordInput = page.getByLabel('Password');
    this.submitButton = page.getByRole('button', { name: 'Sign in' });
    this.errorMessage = page.getByRole('alert');
  }

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }

  async expectErrorMessage(message: string) {
    await expect(this.errorMessage).toContainText(message);
  }
}
```

## Writing Tests

```ts
// e2e/auth.spec.ts
import { test, expect } from '@playwright/test';
import { LoginPage } from './pages/login.page';

test.describe('Authentication', () => {
  test('user can log in with valid credentials', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('alice@example.com', 'password123');
    await expect(page).toHaveURL('/dashboard');
    await expect(page.getByText('Welcome, Alice')).toBeVisible();
  });

  test('shows error for invalid credentials', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('alice@example.com', 'wrong-password');
    await loginPage.expectErrorMessage('Invalid credentials');
  });
});
```

## Locator Strategies (Priority Order)

```ts
// 1. Prefer accessible locators
page.getByRole('button', { name: 'Submit' });
page.getByLabel('Email address');
page.getByPlaceholder('Search...');
page.getByText('Welcome back');
page.getByAltText('Profile photo');
page.getByTitle('Close dialog');

// 2. Test ID as fallback
page.getByTestId('submit-button');
// In component: <button data-testid="submit-button">

// 3. CSS selector only when necessary
page.locator('.toast-message');

// Avoid xpath — brittle and unreadable
```

## Assertions

```ts
// Element visibility
await expect(page.getByRole('heading')).toBeVisible();
await expect(page.getByRole('dialog')).toBeHidden();

// Text content
await expect(page.getByRole('status')).toHaveText('Saved');
await expect(page.getByRole('status')).toContainText('Saved');

// URL
await expect(page).toHaveURL('/dashboard');
await expect(page).toHaveURL(/\/posts\/\d+/);

// Input value
await expect(page.getByLabel('Name')).toHaveValue('Alice');

// Count
await expect(page.getByRole('listitem')).toHaveCount(3);

// Attribute
await expect(page.getByRole('button')).toBeDisabled();
await expect(page.getByRole('checkbox')).toBeChecked();
```

## Authentication (Reuse Session)

```ts
// e2e/fixtures/auth.ts — share auth state
import { test as base } from '@playwright/test';
import { LoginPage } from './pages/login.page';

export const test = base.extend({
  authenticatedPage: async ({ page }, use) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('alice@example.com', 'password123');
    await page.waitForURL('/dashboard');
    await use(page);
  },
});
```

```ts
// playwright.config.ts — global setup for auth
export default defineConfig({
  globalSetup: './e2e/global-setup.ts',
});

// e2e/global-setup.ts
async function globalSetup(config: FullConfig) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  // Login and save state
  await page.context().storageState({ path: 'e2e/.auth/user.json' });
  await browser.close();
}
```

## Network Interception (Sparingly)

```ts
// Mock API in E2E only when hitting real API is not feasible
await page.route('/api/users', (route) => {
  route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify([{ id: '1', name: 'Alice' }]),
  });
});

// Wait for specific network request
const responsePromise = page.waitForResponse('/api/users');
await page.click('button[data-testid="load-users"]');
const response = await responsePromise;
expect(response.status()).toBe(200);
```

## Scripts

```json
{
  "scripts": {
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:debug": "playwright test --debug",
    "test:e2e:report": "playwright show-report"
  }
}
```

## Avoid

- Hardcoded `sleep` / `waitForTimeout` — use `waitForSelector` or auto-waiting assertions
- CSS class selectors that change with refactors
- Testing implementation details (component state, redux store)
- Running E2E against production
- Testing things better covered by unit/integration tests
