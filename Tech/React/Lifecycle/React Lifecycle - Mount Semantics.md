---
tags:
  - react
  - lifecycle
  - mounting
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/useEffect
---

# React Lifecycle — Mount Semantics

> Trace one component from JSX call to visible paint — and understand why "rendered ≠ mounted" under Fiber. Part of [[React Lifecycle Guide]].

---

## The mount path

The pipeline from JSX to paint, in strict order:

1. `createElement(Component, props, children)` produces a plain object element
2. React reconciler creates a work-in-progress (WIP) fiber
3. React calls your function component (render phase, pure)
4. Return value reconciled against previous fiber tree
5. Commit phase: DOM mutations applied
6. Refs attached (object refs assigned; callback refs called)
7. `useInsertionEffect` setup runs
8. `useLayoutEffect` setup runs (children before parents)
9. Browser paints — user sees the frame
10. `useEffect` setup runs (children before parents)

```
JSX
 │
 ▼
createElement()  ── plain object {type, props, key}
 │
 ▼
Reconciler ─── build WIP fiber tree
 │
 ▼
Render phase  ── call component(), pure, interruptible
 │              (initializers run here: useState/useRef/useMemo)
 │
 ▼   ═════ speculative up to this point ═════
 │
Commit phase ── DOM mutations, refs attached
 │
 ├── useInsertionEffect setup
 ├── useLayoutEffect setup   (child → parent)
 │
 ▼
Browser paint
 │
 └── useEffect setup         (child → parent, async)
```

Everything above the double line is discardable. Everything below is mounted.

---

## Rendered ≠ mounted

Under concurrent rendering, a component may be *rendered but never mounted*. Its WIP fiber can be thrown away because:

- A higher-priority update arrived and preempted the render
- A Suspense boundary threw a promise mid-tree
- `startTransition` was interrupted by an urgent update

No commit → no effect setup → no cleanup. The render phase must be pure precisely because its output is provisional.

```
Interrupted render                    Committed render
──────────────────                    ────────────────
render()  ─┐                          render()  ─┐
render()  │ ← preempted               render()  │
render()  │   (discarded)             commit    │
   ✗       ┘                          effects   ┘  ← mounted
```

Contrast with legacy class components: `render()` was followed by `componentDidMount()` in the same synchronous pass. Render *was* commit. That coupling is gone.

> "Render is a query; commit is a fact." — the modern mental model. A render asks *what would this look like?*; a commit says *this is now real*.

Consequences:

- Never rely on render count for anything user-visible
- Never open resources in the render body — they leak on interrupted renders
- Never assume a `useMemo`'d value's identity survives to commit — it may be recomputed and discarded

---

## Initializers run during render

`useState(() => heavyInit())` and `useRef(heavyInit())` (via initial arg) run in the *render* phase, before commit. Two implications:

- If render is discarded, the init cost was paid for nothing (still cheaper than running every render, which is the alternative for `useState(heavyInit())` without the lazy form)
- Initializers must be pure — no side effects (analytics, subscriptions, WebSockets, DOM reads, `Math.random` for stable IDs — use [[React Hooks - useId]] instead)

```jsx
// ❌ Side effect in state initializer runs during render — fires on interrupted renders too,
//    with no cleanup path
const [conn] = useState(() => {
  const c = openWebSocket(url);
  return c;
});
```

```jsx
// ✅ Open the connection in an effect — commit-gated, cleanup on unmount / url change
const connRef = useRef<WS | null>(null);
useEffect(() => {
  const c = openWebSocket(url);
  connRef.current = c;
  return () => c.close();
}, [url]);
```

The lazy initializer form exists for **expensive pure computation** (parsing a large blob, seeding a map), not for I/O.

---

## Child-first, then parent (for effects)

A rule people get wrong: on mount, the **commit order is top-down** (React builds the DOM tree parent-first so children can be inserted into their parent), but **effect setup runs bottom-up** (child effects before parent effects).

Reason: parent effects often depend on children being mounted and refs attached. A parent that reads `childRef.current.getBoundingClientRect()` in `useLayoutEffect` needs the child to have already committed and attached its ref.

```
<App>
  <Header />
  <Body>
    <Item />
  </Body>
</App>
```

Effect setup order on mount:

```
Header effect  →  Item effect  →  Body effect  →  App effect
```

Cleanup order on unmount is the same shape (child first). This makes teardown safe: a parent unsubscribing from an event bus won't fire callbacks into an already-torn-down child.

`useLayoutEffect` follows the same child-first ordering, just synchronously before paint.

---

## What each initializer sees

| Hook init | Runs during | Reads |
|-----------|-------------|-------|
| `useState(v)` / `useState(() => v)` | Render (first only) | Only the initializer arg |
| `useReducer(r, initArg, init)` | Render (first only) | `initArg` + `init` fn |
| `useRef(v)` | Render (first only) | `v` (not tracked) |
| `useMemo(fn, deps)` | Render (every time deps change) | Closed-over values of *this* render |
| Effect setup | Commit | Closed-over values of *this* render |

Key takeaway: state/ref initializers are frozen after first mount — passing a new `initialValue` prop won't re-seed state. If you need to reset on prop change, pass `key={id}` to remount, or store the prop in state with a manual sync.

---

## Anti-pattern: side effects in the component body

The classic mount-semantics bug — a side effect placed at render level. It runs on every render (including interrupted ones), leaks on unmount, and duplicates in Strict Mode.

```jsx
// ❌ Runs during every render, including interrupted ones
function Chat({ url }) {
  const conn = openWebSocket(url);
  return <div>...</div>;
}
```

```jsx
// ✅ Effect-gated — runs after commit, cleans up on unmount
function Chat({ url }) {
  useEffect(() => {
    const conn = openWebSocket(url);
    return () => conn.close();
  }, [url]);
  return <div>...</div>;
}
```

Same rule applies to:

- `document.title = ...` (put in effect, or use a title library)
- `localStorage.setItem(...)` reactively (event handler is usually better)
- `analytics.track(...)` on mount (effect with `[]` deps + Strict Mode guard)
- Reading `window.innerWidth` for layout (use `useLayoutEffect` or [[React Hooks - useSyncExternalStore]])

If the code touches anything outside React state, it belongs in an effect or an event handler — never the render body.

---

## Anti-pattern: reading refs during render

Refs get their `.current` value **after commit**. Reading them during render sees either `null` (first render) or the *previous* commit's value.

```jsx
// ❌ ref.current is null on first render, stale on subsequent renders
function Measure() {
  const ref = useRef<HTMLDivElement>(null);
  const width = ref.current?.offsetWidth ?? 0;
  return <div ref={ref}>{width}px</div>;
}
```

```jsx
// ✅ Measure after commit, before paint — trigger a re-render with the value
function Measure() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    setWidth(ref.current!.offsetWidth);
  }, []);
  return <div ref={ref}>{width}px</div>;
}
```

See [[React Hooks - useRef]] for the ref attachment timing rules.

---

## Summary — mount semantics at a glance

| Concept | Rule |
|---------|------|
| Render phase | Pure, interruptible, may run multiple times before commit |
| Commit phase | Real, synchronous, DOM is now live |
| Mount | First commit for this fiber |
| Initializers (`useState`/`useRef`/`useReducer`) | Render phase, must be pure |
| Refs | Attached during commit, safe to read in effects |
| `useLayoutEffect` | After commit, before paint, child → parent |
| `useEffect` | After paint, child → parent |
| Interrupted render | No commit → no effects → no cleanup needed |
| Side effects in body | Always wrong — move to effect or handler |

---

## Practical mental model

Think of **mount as "commit is called for the first time on this fiber."** Everything before commit is speculative: renders can be discarded, initializers can run for nothing, `useMemo` values can be recomputed. Everything after commit is a mounted component with effects running, refs attached, DOM live.

The whole modern lifecycle — Suspense, transitions, offscreen rendering, Strict Mode's double-invocation — is a natural consequence of this one split. Once you stop equating render with mount, the rest of concurrent React stops feeling like magic and starts feeling like accounting.

---

## Related

- [[React Reconciliation - Virtual DOM and Fiber]] — the WIP fiber and commit phase
- [[React Hooks - useState]] — initializer semantics
- [[React Hooks - useRef]] — ref attachment timing
- [[React Lifecycle - Effect Ordering]] — the exact per-commit sequence (next in reading order)
- [[React Lifecycle - Transitions and Interruptible Renders]] — how concurrency reshapes mounting
- [[React Lifecycle Guide]]
