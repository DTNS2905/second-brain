---
tags:
  - react
  - hooks
  - effects
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useLayoutEffect
---

# React Hooks — useLayoutEffect

> Same shape as [[React Hooks - useEffect]], but **runs before the browser paints**. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useLayoutEffect(
  setup: () => void | (() => void),
  dependencies?: ReadonlyArray<unknown>
): void;
```

Identical to `useEffect`. The only difference is **timing**.

---

## useEffect vs useLayoutEffect

| | `useEffect` | `useLayoutEffect` |
|---|-------------|-------------------|
| Fires | After browser paints | **Before** browser paints |
| Blocks paint? | No | **Yes** — until the effect (and any state updates it triggers) finish |
| Runs on server? | No | No (warns in SSR) |
| Typical use | Sync with external systems | Read layout, then re-render synchronously so the user never sees the intermediate frame |

React guarantees that any state updates scheduled inside `useLayoutEffect` complete **before the next paint**.

---

## When you actually need it

The canonical case: **measure a DOM node, then re-render based on that measurement, all before the user sees anything**.

- Tooltip that must know its own height to decide whether to render above or below the anchor.
- Auto-resizing textarea that measures `scrollHeight` before painting.
- Scroll restoration — set `scrollTop` synchronously so the page never flashes at the wrong position.
- Any two-pass render where the first pass would flicker.

---

## When NOT to use

React's docs open with a **Pitfall**:
> "useLayoutEffect can hurt performance. Prefer `useEffect` when possible."

Skip it for:

- Anything that doesn't require synchronous DOM measurement.
- Data fetching, subscriptions, logging, analytics — never block paint for those.
- Anywhere `requestAnimationFrame` or CSS could achieve the same effect.

---

## Minimal correct example

```tsx
import { useLayoutEffect, useRef, useState } from 'react';

function Tooltip() {
  const ref = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(0);

  useLayoutEffect(() => {
    setHeight(ref.current!.getBoundingClientRect().height);
  }, []);

  return (
    <div ref={ref} style={{ transform: `translateY(${-height}px)` }}>
      ...
    </div>
  );
}
```

React measures and re-renders inside the same synchronous frame — no flicker.

---

## Anti-pattern: blocking paint for non-visual work

```jsx
// ❌ Blocks paint for something the user never sees
useLayoutEffect(() => {
  logAnalytics('viewed', pageId);
}, [pageId]);
```

```jsx
// ✅ useEffect — never block paint for telemetry
useEffect(() => {
  logAnalytics('viewed', pageId);
}, [pageId]);
```

---

## SSR caveat

`useLayoutEffect` **cannot** run on the server. If a component is server-rendered, either:

- Use `useEffect` (accept the tiny flicker), or
- Render only after hydration (`useState(false)` → set to `true` in effect), or
- Mark the component client-only.

Otherwise React warns during SSR.

---

## useInsertionEffect (side note)

React also ships `useInsertionEffect` — runs **before** layout effects, intended for **CSS-in-JS library authors** to inject `<style>` tags before layout is read.

App code should not use it: refs aren't attached, `setState` is disallowed, and the DOM isn't yet updated. If you reach for it, you almost certainly want `useLayoutEffect` (sync DOM work before paint) or `useEffect` (everything else).

Source: https://react.dev/reference/react/useInsertionEffect

---

## Effect timing order (per commit)

1. `useInsertionEffect` — before DOM refs attach, before layout effects.
2. `useLayoutEffect` — DOM updated, refs attached; sync work before paint.
3. **Browser paints.**
4. `useEffect` — after paint.

---

## Decision guide

```
Do you need to run code after DOM commit?
  ├── Injecting <style> tags for a CSS-in-JS lib?
  │     └── useInsertionEffect (library-only)
  ├── Must read/write DOM before the user sees the frame?
  │     └── useLayoutEffect
  └── Everything else (subscriptions, fetch, analytics, timers)
        └── useEffect
```

---

## Related

- [[React Hooks - useEffect]] — non-blocking default
- [[React Hooks - useRef]] — the ref you'll measure inside a layout effect
- [[React Hooks - Rules of Hooks]]
