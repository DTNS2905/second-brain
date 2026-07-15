---
tags:
  - react
  - hooks
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useSyncExternalStore
---

# React Hooks — Store & Utility Hooks

> `useSyncExternalStore`, `useId`, and `useDebugValue` — three specialized hooks with narrow but important use cases. Part of [[React Hooks Guide]].

---

## `useSyncExternalStore` — subscribe to external stores

Source: https://react.dev/reference/react/useSyncExternalStore

### Signature

```ts
function useSyncExternalStore<T>(
  subscribe: (onStoreChange: () => void) => () => void,
  getSnapshot: () => T,
  getServerSnapshot?: () => T
): T;
```

Safely subscribes a component to state **outside** React.

- `subscribe(cb)` — registers `cb` to fire on store change; returns unsubscribe.
- `getSnapshot()` — returns current value. **Must return referentially the same value when the store hasn't changed** (or React re-renders infinitely).
- `getServerSnapshot()` — required for SSR / hydration.

This is the primitive that **Redux, Zustand, Jotai, Apollo** use under the hood.

### When to use

- Integrating a third-party store into React.
- Subscribing to browser APIs with events: `navigator.onLine`, `window.matchMedia`, `document.visibilityState`.
- Legacy non-React state that emits change events.

### When NOT to use

- Pure in-React state — use [[React Hooks - useState]] / [[React Hooks - useReducer]].
- Data that already flows through props/context.
- Very high-frequency mutations that would thrash layout.

### Example

```tsx
function subscribe(cb: () => void) {
  window.addEventListener('online', cb);
  window.addEventListener('offline', cb);
  return () => {
    window.removeEventListener('online', cb);
    window.removeEventListener('offline', cb);
  };
}

export function useOnlineStatus() {
  return useSyncExternalStore(
    subscribe,
    () => navigator.onLine,     // client snapshot
    () => true                  // server snapshot
  );
}
```

### Anti-pattern: unstable snapshot

```jsx
// ❌ New object every call → infinite render loop
function getSnapshot() {
  return { online: navigator.onLine };
}
```

```jsx
// ✅ Return a primitive, or cache the object outside
function getSnapshot() {
  return navigator.onLine;
}
```

If the store value is an object, cache it in the store itself so `getSnapshot` returns the same reference until the store actually mutates.

---

## `useId` — stable SSR-safe unique IDs

Source: https://react.dev/reference/react/useId

### Signature

```ts
function useId(): string;
```

Generates a stable string ID derived from the component's **position in the render tree** — so server-rendered markup and client hydration produce identical IDs.

Each `useId()` call in a component instance returns a distinct value, but the same call site returns the same ID across renders.

### When to use

- Wiring `<label htmlFor>` to `<input id>` inside reusable components.
- ARIA attributes: `aria-describedby`, `aria-labelledby`, `aria-controls`.
- Multiple related IDs from one call — append suffixes: `` `${id}-name` ``, `` `${id}-email` ``.
- Multiple React apps on one page — pass `identifierPrefix` to `createRoot` to prevent collisions.

### When NOT to use

- **List item keys.** Keys must come from your data, not from `useId` (which is per-component, not per-item).
- Cache keys for `use()` — must be data-derived so caches survive across mounts.
- Async Server Components — not supported there.
- When the ID must be human-readable or predictable.

### Example

```tsx
function PasswordField() {
  const hintId = useId();
  return (
    <>
      <label>Password: <input type="password" aria-describedby={hintId} /></label>
      <p id={hintId}>Must be at least 12 characters.</p>
    </>
  );
}
```

### Anti-pattern: useId for list keys

```jsx
// ❌ Same key on every item, AND rules-of-hooks violation
{items.map(item => {
  const id = useId();
  return <li key={id}>{item.name}</li>;
})}
```

```jsx
// ✅ Use a stable data field
{items.map(item => <li key={item.id}>{item.name}</li>)}
```

See [[React Reconciliation - Keys]] for the full guide on list keys.

---

## `useDebugValue` — DevTools label for custom hooks

Source: https://react.dev/reference/react/useDebugValue

### Signature

```ts
function useDebugValue<T>(value: T, format?: (value: T) => any): void;
```

Attaches a human-readable label to a custom hook, visible in **React DevTools** next to the hook name.

If `format` is provided, it's only called when DevTools inspects the hook — use this to defer expensive formatting.

### When to use

- Custom hooks in a **shared library** where consumers benefit from inspecting internal state.
- Wrapping opaque values (Dates, Maps, references) with a readable label.

### When NOT to use

- Every custom hook in an app — it's noise for simple ones.
- Formatting that is already cheap and readable (e.g., a boolean).
- Regular components — the value won't appear anywhere useful.

### Example

```tsx
function useOnlineStatus() {
  const isOnline = useSyncExternalStore(
    subscribe,
    () => navigator.onLine,
    () => true
  );
  useDebugValue(isOnline ? 'Online' : 'Offline');
  return isOnline;
}

function useLastFetch(url: string) {
  const [date, setDate] = useState<Date | null>(null);
  useDebugValue(date, d => d?.toISOString() ?? 'never'); // formatter deferred
  return date;
}
```

In DevTools: `useOnlineStatus: "Online"` instead of `useOnlineStatus: true`.

---

## Summary

| Hook | Purpose | Key gotcha |
|------|---------|------------|
| `useSyncExternalStore` | Bridge non-React state into React | `getSnapshot` must be referentially stable |
| `useId` | Stable IDs across SSR/CSR | Never use for list keys |
| `useDebugValue` | Label custom hooks in DevTools | Only useful inside custom hooks |

---

## Related

- [[React Hooks - Custom Hooks]] — where `useDebugValue` shines
- [[React Reconciliation - Keys]] — the correct source of list keys
- [[React Hooks - useContext]] — often works together with `useSyncExternalStore` in library APIs
