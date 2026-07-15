---
tags:
  - react
  - hooks
  - performance
  - memoization
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useCallback
---

# React Hooks — useCallback

> Cache **the function itself** across renders. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useCallback<T extends (...args: any[]) => any>(
  fn: T,
  dependencies: DependencyList
): T;
```

Returns a memoized version of `fn`. React returns the **same function reference** between renders as long as `dependencies` compare equal via `Object.is`.

---

## Relation to useMemo

```ts
// Mental model:
useCallback(fn, deps) === useMemo(() => fn, deps);
```

- [[React Hooks - useMemo]] caches the **result** of calling a function.
- `useCallback` caches **the function itself**.

Same cache semantics, same deps rules, same anti-patterns.

---

## When it matters

### 1. Passing to a `React.memo` child

Without `useCallback`, the parent creates a new function reference each render → `memo` skips nothing:

```jsx
const ShippingForm = memo(function ShippingForm({ onSubmit }) { /* ... */ });

// ✅ Stable reference — memo actually works
const handleSubmit = useCallback(
  (order) => post(`/buy/${productId}`, order),
  [productId]
);
<ShippingForm onSubmit={handleSubmit} />
```

### 2. Dependency of another hook

A stable function in `useEffect` deps stops the effect from re-running every parent render.

```jsx
const onData = useCallback((d) => process(d), []);
useEffect(() => subscribe(onData), [onData]);
```

### 3. Dependency of another `useCallback` / `useMemo`

Stabilizing one function often unblocks a chain of memoization downstream.

---

## When NOT to use

- Handlers passed to **plain DOM elements** (`<button onClick={...}>`) — new function each render is fine, DOM doesn't care.
- One-off callbacks used only inside the same component.
- Functions whose deps change **every render** — you pay the memoization cost and get nothing back.

From the docs: *"Caching a function with `useCallback` is only valuable in the specific cases mentioned above. There is no benefit in other cases."*

---

## Minimal correct example

```tsx
const ShippingForm = memo(function ShippingForm({ onSubmit }: Props) {
  /* ... */
});

function ProductPage({ productId, referrer, theme }: Props) {
  const handleSubmit = useCallback((orderDetails: Order) => {
    post(`/product/${productId}/buy`, { referrer, orderDetails });
  }, [productId, referrer]);

  return (
    <div className={theme}>
      <ShippingForm onSubmit={handleSubmit} />
    </div>
  );
}
```

---

## Anti-pattern: memo child + non-memoized callback

```jsx
// ❌ Memo child, but a new function every render → memo does nothing
function ProductPage({ productId, theme }) {
  function handleSubmit(o) { post(`/buy/${productId}`, o); }
  return (
    <div className={theme}>
      <ShippingForm onSubmit={handleSubmit} />
    </div>
  );
}
```

```jsx
// ✅ Stable reference — ShippingForm only re-renders when productId changes
function ProductPage({ productId, theme }) {
  const handleSubmit = useCallback(
    (o) => post(`/buy/${productId}`, o),
    [productId]
  );
  return (
    <div className={theme}>
      <ShippingForm onSubmit={handleSubmit} />
    </div>
  );
}
```

---

## Anti-pattern: useCallback on DOM handlers

```jsx
// ❌ No downstream memo — pure overhead
function Button({ label }) {
  const handleClick = useCallback(() => console.log(label), [label]);
  return <button onClick={handleClick}>{label}</button>;
}
```

```jsx
// ✅ Just declare the function
function Button({ label }) {
  return <button onClick={() => console.log(label)}>{label}</button>;
}
```

The DOM doesn't shallow-compare `onClick` — there's nothing to memoize against.

---

## Reading fresh values without adding deps — `useEffectEvent`

If your callback needs the latest value of some state but shouldn't invalidate whenever that state changes, extract an **Effect Event** (currently experimental, canary):

```jsx
import { experimental_useEffectEvent as useEffectEvent } from 'react';

function ChatRoom({ roomId, theme }) {
  const onConnected = useEffectEvent(() => {
    showNotification('Connected!', theme); // sees latest theme
  });

  useEffect(() => {
    const conn = createConnection(roomId);
    conn.on('connected', onConnected);
    conn.connect();
    return () => conn.disconnect();
  }, [roomId]); // theme is NOT a dep
}
```

Not officially released; use it only when the alternative is a much messier ref pattern.

---

## Caveats

- Strict Mode calls the memoized function **twice in dev** if invoked during render (it shouldn't be) — keep it pure of side effects.
- `Object.is` equality on dependencies triggers a new function.
- Cannot be called conditionally.
- React may discard the cache on its own — don't rely on identity for correctness, only for perf.

---

## Summary — do I need useCallback?

```
Is the function...
  ├── A prop to a React.memo component?          ✅ useCallback
  ├── A dep of another hook (useEffect, etc)?    ✅ useCallback
  ├── Used only inside this component?           ❌ don't bother
  └── A DOM event handler (onClick, onChange)?   ❌ don't bother
```

---

## Related

- [[React Hooks - useMemo]] — same cache mechanism for values
- [[React memo Guide]] — the pairing that makes useCallback pay off
- [[React Re-renders - useMemo and useCallback]] — usage in re-render prevention
- [[React memo - Stable Props]]
