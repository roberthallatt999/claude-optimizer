# Zustand Conventions

> **Check version:** Zustand v4 (most common) vs v5 (2024+).
> v5 changes: `createStore` API updated, `subscribeWithSelector` middleware merged in.
> Run `cat package.json | grep '"zustand"'` before writing stores.

## Basic Store

```ts
import { create } from 'zustand';
import { devtools } from 'zustand/middleware';

interface BearState {
  bears: number;
  fish: number;
  addBear: () => void;
  eatFish: () => void;
  reset: () => void;
}

const initialState = { bears: 0, fish: 0 };

export const useBearStore = create<BearState>()(
  devtools(
    (set) => ({
      ...initialState,
      addBear: () => set((state) => ({ bears: state.bears + 1 }), false, 'addBear'),
      eatFish: () => set((state) => ({ fish: state.fish - 1 }), false, 'eatFish'),
      reset: () => set(initialState, false, 'reset'),
    }),
    { name: 'BearStore' }
  )
);
```

## Slice Pattern (Large Stores)

```ts
// slices/authSlice.ts
import type { StateCreator } from 'zustand';

export interface AuthSlice {
  user: User | null;
  isAuthenticated: boolean;
  login: (user: User) => void;
  logout: () => void;
}

export const createAuthSlice: StateCreator<AuthSlice> = (set) => ({
  user: null,
  isAuthenticated: false,
  login: (user) => set({ user, isAuthenticated: true }),
  logout: () => set({ user: null, isAuthenticated: false }),
});

// slices/uiSlice.ts
export interface UISlice {
  sidebarOpen: boolean;
  toggleSidebar: () => void;
}

export const createUISlice: StateCreator<UISlice> = (set) => ({
  sidebarOpen: false,
  toggleSidebar: () => set((state) => ({ sidebarOpen: !state.sidebarOpen })),
});

// store.ts — compose slices
import { create } from 'zustand';
import { devtools } from 'zustand/middleware';

type AppStore = AuthSlice & UISlice;

export const useAppStore = create<AppStore>()(
  devtools((...a) => ({
    ...createAuthSlice(...a),
    ...createUISlice(...a),
  }), { name: 'AppStore' })
);
```

## Selectors (Prevent Re-renders)

```tsx
// Bad — subscribes to entire store, re-renders on any change
const { bears, addBear } = useBearStore();

// Good — subscribe only to what you use
const bears = useBearStore((state) => state.bears);
const addBear = useBearStore((state) => state.addBear);

// Derived selector — use shallow for objects
import { shallow } from 'zustand/shallow';

const { bears, fish } = useBearStore(
  (state) => ({ bears: state.bears, fish: state.fish }),
  shallow
);
```

## Persistence

```ts
import { persist, createJSONStorage } from 'zustand/middleware';

const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      theme: 'system' as Theme,
      locale: 'en',
      setTheme: (theme) => set({ theme }),
      setLocale: (locale) => set({ locale }),
    }),
    {
      name: 'settings-storage',       // localStorage key
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({       // only persist these keys
        theme: state.theme,
        locale: state.locale,
      }),
    }
  )
);
```

## Async Actions

```ts
interface UserStore {
  users: User[];
  status: 'idle' | 'loading' | 'error';
  error: string | null;
  fetchUsers: () => Promise<void>;
}

const useUserStore = create<UserStore>()((set) => ({
  users: [],
  status: 'idle',
  error: null,
  fetchUsers: async () => {
    set({ status: 'loading', error: null });
    try {
      const users = await api.users.list();
      set({ users, status: 'idle' });
    } catch (err) {
      set({ status: 'error', error: (err as Error).message });
    }
  },
}));
```

## Outside React (Vanilla Access)

```ts
// Access store outside components (event handlers, utilities, SSE handlers)
const { login, logout } = useAuthStore.getState();

// Subscribe to changes outside React
const unsubscribe = useAuthStore.subscribe(
  (state) => state.user,
  (user) => { if (!user) redirectToLogin(); }
);
```

## When to Use Zustand

- Global UI state (modals, sidebar, themes, notifications)
- Authentication / session state
- Shopping cart, multi-step forms, wizard state
- Shared state between distant components

**Don't use for:** server data (use TanStack Query), URL state (use router params), form state (use React Hook Form).

## Avoid

- Storing derived state — compute it in selectors
- Subscribing to the whole store in components
- Async side effects without loading/error states
- Mutating state directly (always use `set`)
