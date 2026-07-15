---
tags:
  - react
  - hooks
  - context
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useContext
---

# React Hooks — useContext

> Read a value from the nearest matching provider above. Part of [[React Hooks Guide]].

---

## Signature

```ts
const value = useContext(SomeContext);
```

`SomeContext` is created via `createContext(defaultValue)`. `useContext` returns the current value from the nearest matching `<SomeContext value={...}>` above in the tree, or the `defaultValue` if no provider exists.

---

## When to use

- Passing data deep into the tree without prop-drilling — theme, current user, locale, router.
- Sharing values that update over time — every consumer auto-re-renders when the provider's `value` changes.
- Global-ish state paired with [[React Hooks - useReducer]] — provide `state` and `dispatch` on two separate contexts.

## When NOT to use

- **Fast-changing values** (mouse position, animation frames) — every consumer re-renders on each change.
- Passing values only 1–2 levels deep — plain props are simpler and don't force subtree re-renders.
- As a general-purpose state manager for large, independently updating slices — use a real store.

---

## Why all consumers re-render

React compares old and new `value` with `Object.is`. If they differ, **every** component that calls `useContext(ThatContext)` re-renders — even if wrapped in `React.memo`.

> `React.memo` skips re-renders caused by **parent renders**, not by **context updates**.

This is why inline object literals in the provider are toxic:

```jsx
// ❌ New object every render → all consumers re-render every time
<AuthContext value={{ currentUser, login: () => setUser(x) }}>
  {children}
</AuthContext>
```

```jsx
// ✅ Memoized value + stable callback
const login = useCallback((r) => setUser(r.user), []);
const value = useMemo(() => ({ currentUser, login }), [currentUser, login]);

<AuthContext value={value}>{children}</AuthContext>
```

See [[React Re-renders - Context Re-renders]] for the deep dive.

---

## Minimal correct example

```tsx
const ThemeContext = createContext<'light' | 'dark'>('light');

function App() {
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  return (
    <ThemeContext value={theme}>
      <Toolbar />
    </ThemeContext>
  );
}

function Toolbar() {
  const theme = useContext(ThemeContext);
  return <div className={`toolbar-${theme}`} />;
}
```

React 19 note: `<Context value={...}>` replaces the older `<Context.Provider value={...}>`.

---

## Optimization patterns

### 1. Memoize the value

```jsx
const value = useMemo(() => ({ user, setUser }), [user]);
<UserContext value={value}>
```

### 2. Stabilize callbacks with useCallback

```jsx
const login = useCallback((creds) => api.login(creds), []);
```

### 3. Split contexts by read/write

```jsx
// Two contexts — one for state, one for dispatch
<StateContext value={state}>
  <DispatchContext value={dispatch}>
    {children}
  </DispatchContext>
</StateContext>
```

Components that only dispatch don't re-render when state changes. `dispatch` from [[React Hooks - useReducer]] has a stable identity, so `DispatchContext` never invalidates on its own.

### 4. Composition — sidestep context entirely

Accept `children` as JSX so intermediate wrappers don't re-render. See [[React Component Composition - Children as Props]].

---

## Anti-pattern: inline value literal

```jsx
// ❌ Every parent render creates a fresh object → all consumers re-render
function Provider({ children }) {
  const [user, setUser] = useState(null);
  return (
    <AuthContext value={{ user, setUser }}>
      {children}
    </AuthContext>
  );
}
```

```jsx
// ✅ Stable reference via useMemo
function Provider({ children }) {
  const [user, setUser] = useState(null);
  const value = useMemo(() => ({ user, setUser }), [user]);
  return <AuthContext value={value}>{children}</AuthContext>;
}
```

---

## Caveats

- `useContext(Ctx)` **skips** any `<Ctx value>` **inside** the same component that calls it — it only looks upward.
- React 19: `<SomeContext>` can be used directly as a provider (no `.Provider`).
- The value can be anything — including a Promise for use with [[React Hooks - React 19 Actions Hooks]].
- Default value is used only when there's no provider — not when the provider renders `value={undefined}`.

---

## Related

- [[React Re-renders - Context Re-renders]] — full deep dive on the re-render behavior
- [[React Hooks - useReducer]] — the classic pairing for scoped app state
- [[React Component Composition Guide]] — composition often replaces context entirely
- [[React Hooks - useMemo]] — memoize the value
- [[React Hooks - useCallback]] — stabilize callbacks inside the value
