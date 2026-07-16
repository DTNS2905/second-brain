---
tags:
  - react
  - lifecycle
  - effects
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/useEffect
---

# React Lifecycle — Effect Ordering

> The precise per-commit firing order for every effect flavor — the ordering contract between siblings, between parent and child, and between cleanup and setup across a re-render. Part of [[React Lifecycle Guide]].

---

## The per-commit sequence

Every commit walks the same pipeline. Memorize this — every ordering bug comes from misunderstanding one of these steps.

1. **Render phase completes** — React has the WIP fiber tree ready. No DOM has been touched yet. Nothing user-visible has changed.
2. **DOM mutations applied** — insertions, updates, deletions are committed to the DOM. This is synchronous and atomic; the browser hasn't painted yet.
3. **Ref detachment** — old refs (from the previous commit) get `null` (object refs) or their cleanup runs (callback refs, React 19). This happens *before* new refs attach.
4. **`useInsertionEffect` cleanup → setup** — CSS-in-JS libraries only. Refs are not yet attached at this stage, and no state may be read that depends on layout.
5. **`useLayoutEffect` cleanup** (child-first) → **ref attachment** → **`useLayoutEffect` setup** (child-first). Synchronous. **Blocks paint.**
6. **Browser paints** — the user finally sees the frame.
7. **`useEffect` cleanup** (child-first) → **`useEffect` setup** (child-first). Asynchronous, does not block the paint.

```
┌─────────────────────────────────────────────────────────────┐
│  Render phase (pure functions, no side effects)             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Commit phase — synchronous, blocks paint                   │
│                                                             │
│    1. DOM mutations                                         │
│    2. Ref detach (old refs → null / cleanup)                │
│    3. useInsertionEffect  cleanup → setup                   │
│    4. useLayoutEffect     cleanup (child → parent)          │
│    5. Ref attach          (child → parent)                  │
│    6. useLayoutEffect     setup   (child → parent)          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ╔═══════════════╗
                    ║ BROWSER PAINT ║
                    ╚═══════════════╝
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Passive phase — asynchronous, after paint                  │
│                                                             │
│    7. useEffect  cleanup (child → parent)                   │
│    8. useEffect  setup   (child → parent)                   │
└─────────────────────────────────────────────────────────────┘
```

The **child-first** rule holds for every phase where cleanup and setup fan out over the tree.

---

## Sibling effect order within one component

Multiple effects inside a single component run **top-to-bottom for setup, bottom-to-top for cleanup**. This mirrors typical resource nesting: open A, then open B; on the way out, close B, then close A.

```jsx
function Chart() {
  useEffect(() => {
    console.log('setup A');
    return () => console.log('cleanup A');
  }, []);

  useEffect(() => {
    console.log('setup B');
    return () => console.log('cleanup B');
  }, []);
}
// Mount:   setup A → setup B
// Unmount: cleanup B → cleanup A
```

If effect B depends on something effect A set up (a global, a shared subscription), this order is exactly what you want. Reordering the two `useEffect` calls swaps their execution order — hooks run in source order.

---

## Parent-child ordering (child-first for effects)

The rule that surprises people migrating from classes.

- **Classes:** `componentDidMount` fires child → parent, `componentWillUnmount` fires parent → child.
- **Hooks:** `useEffect` setup fires child → parent, `useEffect` cleanup also fires child → parent.

The mount direction happens to match classes. The **unmount direction is flipped** — that's the trap.

```
<App>
  <Body>
    <Item />
  </Body>
</App>
```

```
Mount:
  Item   useEffect setup
  Body   useEffect setup
  App    useEffect setup

Unmount:
  Item   useEffect cleanup
  Body   useEffect cleanup
  App    useEffect cleanup
```

Consequence: **a parent effect can safely read state or DOM that its children's effects produced** — the children ran first. But a parent's *cleanup* also runs last, so a parent-created resource is still alive when the children tear down.

See [[React Lifecycle - Mount Semantics]] for the mount pipeline and [[React Lifecycle - Unmount and Cleanup Patterns]] for teardown patterns that rely on this order.

---

## What each cleanup sees

Cleanup functions close over the values of the render that **created them**, not the render that runs them. This is the single biggest source of confusion around effect timing.

| When cleanup runs | Values it sees |
|-------------------|----------------|
| Before next setup (deps changed) | Values from the *previous* render |
| On unmount | Values from the *last* render that committed |
| Never (interrupted render / concurrent bail-out) | N/A — the corresponding setup never ran |

```jsx
useEffect(() => {
  console.log('setup   with count =', count);
  return () => console.log('cleanup with count =', count);
}, [count]);

// Render 1 (count = 0):  setup: 0
// Render 2 (count = 1):  cleanup: 0, setup: 1
// Render 3 (count = 2):  cleanup: 1, setup: 2
// Unmount at count = 2:  cleanup: 2
```

Each cleanup pairs with the setup that spawned it, closing over the exact same `count`. If you want the cleanup to see the *current* value, either add the value to deps (so a new cleanup is scheduled each time it changes) or read from a ref.

---

## useLayoutEffect vs useEffect timing

| Effect | Fires when | Blocks paint? | Sees committed DOM? |
|--------|-----------|---------------|---------------------|
| `useInsertionEffect` | Before layout effects, before ref attach | Yes | No (styles being injected) |
| Ref callback | After DOM mutations, before layout effects | Yes | Yes |
| `useLayoutEffect` | After DOM mutations & refs, before paint | Yes | Yes |
| `useEffect` | After paint | No | Yes |

Rule of thumb: reach for `useEffect` first. Escalate to [[React Hooks - useLayoutEffect]] only when you must **read layout and set state before the user sees the frame** — otherwise you'll cause a visible flicker.

`useInsertionEffect` is not for application code. See below.

---

## Why useInsertionEffect is restricted

`useInsertionEffect` runs **before refs attach** and **before layout effects**. That timing exists for exactly one reason: CSS-in-JS libraries need to inject a `<style>` tag *before* layout effects measure the DOM, so measurements reflect the injected rules.

Consequences of that early timing:

- Refs are stale — `.current` still holds the previous ref target.
- `useState` / `useReducer` state updates queued here won't cause the current pass to see them.
- No DOM measurements — layout has not yet been computed with the new styles.

```jsx
// ❌ Reading a ref in useInsertionEffect
useInsertionEffect(() => {
  el.current.getBoundingClientRect();   // .current is stale here
});
```

```jsx
// ✅ Only inject styles; leave measurement to useLayoutEffect
useInsertionEffect(() => {
  const style = document.createElement('style');
  style.textContent = generatedCss;
  document.head.appendChild(style);
  return () => style.remove();
});
```

If you're not writing a CSS-in-JS runtime, you should not be using `useInsertionEffect`.

---

## Ref detachment before setup

Refs have their own micro-lifecycle inside the commit phase. On a re-render where a ref *changes target* (or the ref-holding component unmounts):

1. React first calls the old ref with `null` (object refs) or invokes the old callback ref's cleanup return (React 19 callback refs).
2. Only then does React attach the new ref.

This means at the moment `useLayoutEffect` runs, the ref you see is guaranteed to point at the *current* commit's DOM node, never the previous one.

```jsx
<div ref={(node) => {
  if (node) subscribe(node);
  return () => unsubscribe(node);      // React 19: called on detach
}} />
```

On React 18 and below, the same callback ref is called with `null` on detach:

```jsx
<div ref={(node) => {
  if (node === null) {
    unsubscribe(prev);
  } else {
    subscribe(node);
    prev = node;
  }
}} />
```

See [[React Lifecycle - Ref Lifecycle and Cleanup]] for the full ref cleanup story and [[React Hooks - useRef]] for the underlying hook.

---

## Practical pitfall: expecting cleanup order to match commit order

The commonest ordering bug: assuming cleanup fires top-down like the commit itself. It doesn't — cleanup fans out **child-first**, exactly like setup.

```jsx
// ❌ Assumes parent cleanup runs before children — it doesn't
function Parent() {
  useEffect(() => {
    const socket = openSocket();
    window.__socket = socket;
    return () => socket.close();          // runs LAST
  }, []);
  return <Child />;
}

function Child() {
  useEffect(() => {
    return () => {
      window.__socket.send('bye');        // still works — parent socket is alive
    };
  }, []);
}
// Unmount order: Child cleanup ('bye' sent) → Parent cleanup (socket.close)
```

The reverse assumption is what usually causes bugs:

```jsx
// ❌ Author thought parent cleanup runs first, so cleaned up shared context
function Parent() {
  useEffect(() => {
    return () => {
      SharedRegistry.reset();             // runs LAST — children already ran
    };
  }, []);
  return <ChildList />;
}
```

That code is actually **safe** — children clean up first, so `SharedRegistry` is still populated when they need it. The version that breaks is the one that flips the intuition:

```jsx
// ✅ Correct mental model: parent cleanup runs after all descendant cleanups
useEffect(() => {
  const registry = new Registry();
  ChildContext.set(registry);
  return () => {
    // Safe to tear down — every child cleanup has already run.
    registry.destroy();
  };
}, []);
```

If you need the reverse — a parent effect that runs *first* at teardown — hoist the resource lifecycle up to a common ancestor or an external store rather than fighting the ordering.

---

## Summary table

| Step | What React does | Order across tree | Notes |
|------|-----------------|-------------------|-------|
| 1 | Render (pure) | Parent → child | No side effects |
| 2 | Commit DOM mutations | Depth-first per fiber | Atomic |
| 3 | Old ref detach | Child → parent | `null` / callback cleanup |
| 4 | `useInsertionEffect` cleanup → setup | Child → parent | CSS-in-JS only, no refs |
| 5 | `useLayoutEffect` cleanup | Child → parent | Blocks paint |
| 6 | New ref attach | Child → parent | `.current` now current |
| 7 | `useLayoutEffect` setup | Child → parent | Blocks paint |
| 8 | **Paint** | — | Frame becomes visible |
| 9 | `useEffect` cleanup | Child → parent | Async, post-paint |
| 10 | `useEffect` setup | Child → parent | Async, post-paint |

Within a single component, hooks fire **top-to-bottom for setup, bottom-to-top for cleanup**. Across the tree, every effect phase — setup *and* cleanup — fans out **child-first**.

---

## Related

- [[React Hooks - useEffect]] — the primary effect hook
- [[React Hooks - useLayoutEffect]] — when to block paint
- [[React Lifecycle - Mount Semantics]] — the mount pipeline (previous in reading order)
- [[React Lifecycle - Ref Lifecycle and Cleanup]] — ref detach/attach details
- [[React Lifecycle - Unmount and Cleanup Patterns]] — teardown patterns using cleanup order
- [[React Lifecycle Guide]]
