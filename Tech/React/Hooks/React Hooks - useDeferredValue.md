---
tags:
  - react
  - hooks
  - concurrency
  - performance
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useDeferredValue
---

# React Hooks — useDeferredValue

> Return a **lagged** copy of a value so an expensive dependent view doesn't block the UI. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useDeferredValue<T>(value: T, initialValue?: T): T;
```

Returns a value that "trails behind" the input. Without `initialValue`, no deferral happens on the first render — deferral kicks in on updates.

---

## How it works

1. Render N: `deferred === value`.
2. `value` changes to `value2`.
3. React re-renders **immediately** with the **old** deferred value — the UI stays consistent.
4. React schedules a **background, interruptible** re-render with `value2`.
5. If a new update arrives during that background render, React discards it and starts over.

The lag is not a fixed timer — it's driven by React's priority scheduler and device speed.

---

## When to use

- **Keep an input responsive** while a heavy dependent view (`SlowList`, chart) lags behind.
- **Show stale search results** while `<Suspense>` loads fresh ones — users see previous results (not a spinner) until new data commits.
- **Visual staleness indicator** — dim the deferred subtree when `value !== deferredValue`.

---

## How it differs from useTransition

- **Value-based, not action-based.** Use when you **receive** `value` (prop, hook result) and can't wrap the setter.
- No `isPending` — infer staleness from `value !== deferredValue`.
- Both use the same concurrent-rendering priority: deferred renders can be interrupted by urgent updates.

|  | `useTransition` | `useDeferredValue` |
|---|-----------------|--------------------|
| Wraps | The **setter** | The **value** |
| Best when | You call `setX` | Value comes from a prop |
| Signal | `isPending` boolean | `value !== deferred` check |

See [[React Hooks - useTransition]].

---

## When NOT to use

- You want a **fixed debounce/throttle** — use those; `useDeferredValue` has no configurable delay.
- You need to prevent network requests per keystroke — deferring the value **doesn't stop them**; use debouncing.
- You control the setter — `useTransition` gives you `isPending` and more direct intent.

---

## Minimal correct example

```tsx
function SearchPage() {
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query);
  const isStale = query !== deferredQuery;

  return (
    <>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
      <Suspense fallback={<h2>Loading…</h2>}>
        <div style={{ opacity: isStale ? 0.5 : 1 }}>
          <SearchResults query={deferredQuery} />
        </div>
      </Suspense>
    </>
  );
}
```

Typing keeps the input snappy; the heavy `<SearchResults>` re-renders in the background at low priority.

---

## Anti-pattern: fresh object literal each render

```jsx
// ❌ New object every render — deferred value never stabilizes → perpetual background render
function Chart({ data }) {
  const deferredConfig = useDeferredValue({ sortBy: 'name', data });
}
```

```jsx
// ✅ Primitive or memoized reference
function Chart({ data }) {
  const config = useMemo(() => ({ sortBy: 'name', data }), [data]);
  const deferredConfig = useDeferredValue(config);
}
```

Pass **primitives or referentially stable values**. A fresh object literal each render makes the deferred value permanently "different."

---

## Anti-pattern: expecting a fixed delay

```jsx
// ❌ Deferred does NOT wait 300ms — it just lags when the CPU is busy
const [q, setQ] = useState('');
const deferred = useDeferredValue(q);
// User expects a stable "300ms after typing" — that's not what this does
```

```jsx
// ✅ For a fixed debounce, use setTimeout / a debounce hook
useEffect(() => {
  const id = setTimeout(() => setDebounced(q), 300);
  return () => clearTimeout(id);
}, [q]);
```

---

## Caveats

- Inside a `useTransition` action, `useDeferredValue` returns the new value immediately (no deferral).
- Effects don't fire from background renders until they commit.
- Deferred values can be discarded and restarted repeatedly under high input pressure.
- Cannot be called conditionally.

---

## Summary

```
You want to keep the UI responsive during an expensive render.
  ├── Do you own the setter (setX)?
  │     ├── YES → useTransition (gives you isPending)
  │     └── NO  → useDeferredValue (value-based)
  ├── Do you need a fixed delay?
  │     └── Neither — use debounce/throttle
  └── Do you need to stop network requests per keystroke?
        └── Neither — use debounce
```

---

## Related

- [[React Hooks - useTransition]] — action-based counterpart
- [[React Hooks - useMemo]] — stabilize objects before deferring them
- [[React memo Guide]] — often paired to prevent the deferred subtree from re-rendering unnecessarily
