---
tags:
  - web
  - react
  - rendering
  - performance
  - frontend
created: 2026-10-21
source: https://react.dev/reference/react/useLayoutEffect
---

# Web Reflow and Repaint - In React

> React decides *what* DOM changes; the browser still has to reflow and repaint. Where React helps, where it can make things worse, and the patterns that keep layout to once per frame. Part of [[Web Reflow and Repaint Guide]].

---

## Where React sits in the pipeline

```
setState ─► render (pure JS, no DOM) ─► commit (DOM mutations) ─► useLayoutEffect ─► [Style → Layout → Paint] ─► useEffect
                                                                    ▲ reading layout here forces it early
```

- **Render phase** touches no DOM, so it costs no reflow. Re-renders that produce the same output give an empty diff, so there are no DOM writes ([[React Reconciliation - Diffing Algorithm]]).
- **Commit phase** applies all mutations in one go. With automatic batching (React 18+), several `setState` calls → one commit → layout is dirty only once ([[React Reconciliation - Virtual DOM and Fiber]]).
- React itself **never reads layout**. Forced reflow in a React app always comes from *your* code (or a library) reading geometry.

So "VDOM avoids reflow" is half true. It **batches writes**. It can't stop you from reading in between.

---

## Things in React code that cause extra reflow

| Cause | Why | Fix |
|-------|-----|-----|
| Unstable / index `key`s on reorder | Nodes get destroyed and recreated instead of moved, so more DOM mutations | Stable ids ([[React Reconciliation - Keys]]) |
| Changing component type at the same position | Whole subtree remounts | Keep the type stable, toggle props |
| Animating via state every frame | Re-render + inline `top/left` style each frame → layout per frame | CSS transition / WAAPI on `transform`, or write the ref directly |
| Reading layout in many children's layout effects, each writing to the DOM | Thrashing across components | Read in effects, write via state (see below) |
| `window.resize` + `getBoundingClientRect` | Forced layout on every resize event | `ResizeObserver` |
| Huge lists | Layout cost scales with box count | Virtualize, or `content-visibility: auto` |

---

## Measure before paint: `useLayoutEffect`

When you must read geometry and render based on it **without a visible flicker**:

```tsx
function Tooltip({ anchorRect, children }) {
  const ref = useRef<HTMLDivElement>(null);
  const [placeAbove, setPlaceAbove] = useState(false);

  useLayoutEffect(() => {
    const { height } = ref.current!.getBoundingClientRect(); // forced layout (intentional, once)
    setPlaceAbove(anchorRect.bottom + height > window.innerHeight);
  }, [anchorRect]);

  return <div ref={ref} className={placeAbove ? 'above' : 'below'}>{children}</div>;
}
```

What happens:
1. Commit writes the DOM, so layout is dirty.
2. `getBoundingClientRect()` forces **one** layout.
3. `setPlaceAbove` schedules a sync re-render. React processes it **before paint**.
4. Second commit, then the browser runs layout again at frame end, then paints once.

That's two layouts, zero flicker. Fine for one tooltip, but not for 500 rows. Details in [[React Hooks - useLayoutEffect]].

### Read in effects, write through state

```tsx
// ❌ Each child: read then write the DOM directly → N forced layouts
useLayoutEffect(() => {
  const h = ref.current!.offsetHeight;
  ref.current!.style.minHeight = h + 'px';
});

// ✅ Each child only reads; writes go through state, flushed together after all layout effects
useLayoutEffect(() => {
  setHeight(ref.current!.offsetHeight);
});
```

Layout effects run child → parent within one commit ([[React Lifecycle - Effect Ordering]]). If none of them write to the DOM, only the first read pays for layout. The rest read clean geometry.

---

## Observe instead of polling: `ResizeObserver`

```tsx
function useSize<T extends Element>(ref: RefObject<T>) {
  const [size, setSize] = useState<DOMRectReadOnly | null>(null);
  useLayoutEffect(() => {
    const ro = new ResizeObserver(([entry]) => setSize(entry.contentRect));
    ro.observe(ref.current!);
    return () => ro.disconnect();
  }, [ref]);
  return size;
}
```

- Callbacks fire **after layout, before paint**, with geometry the browser already computed. No forced reflow.
- If the callback changes size again, the browser loops. Past its depth limit you get `ResizeObserver loop completed with undelivered notifications`. This is a warning, not a crash, but it means a multi-frame flash. Fix it by wrapping the write in `requestAnimationFrame` or by skipping when the size didn't change.

---

## Animate without re-rendering

```tsx
// ❌ 60 renders/sec, layout each frame
const [x, setX] = useState(0);
useEffect(() => { const id = requestAnimationFrame(function f(t) { setX(t / 10); requestAnimationFrame(f); }); }, []);
return <div style={{ left: x }} />;

// ✅ No React work per frame, composite only
const ref = useRef<HTMLDivElement>(null);
useEffect(() => {
  const anim = ref.current!.animate(
    [{ transform: 'translateX(0)' }, { transform: 'translateX(300px)' }],
    { duration: 600, iterations: Infinity, direction: 'alternate' }
  );
  return () => anim.cancel();
}, []);
return <div ref={ref} />;
```

Animation libraries like Motion (Framer Motion) follow the same idea: they animate `transform`/`opacity` outside React's render cycle. See [[Web Reflow and Repaint - Compositor-Only Animations]].

---

## `flushSync` + read

```tsx
flushSync(() => setItems(next));      // commit happens synchronously here
listRef.current!.lastElementChild!.scrollIntoView(); // forced layout. Fine once, bad in a loop
```

`flushSync` is the escape hatch when you need the DOM updated *now* to measure or scroll it. Call it once per user action, never per item.

---

## Checklist

- [ ] No geometry reads in render functions.
- [ ] Layout reads only in `useLayoutEffect` / ref callbacks / observers, and **no direct DOM writes between reads**.
- [ ] Animations use `transform`/`opacity` via CSS, WAAPI or a motion lib, not per-frame `setState`.
- [ ] Stable keys on lists that reorder.
- [ ] Long lists virtualized or `content-visibility: auto`.
- [ ] Verified with Paint flashing + Performance panel ([[Web Reflow and Repaint - Measuring in DevTools]]).

---

## Related

- [[React Hooks - useLayoutEffect]]
- [[React Lifecycle - Mount Semantics]] — JSX → commit → paint timeline
- [[React Re-renders Guide]] — fewer renders → fewer commits → fewer layouts
