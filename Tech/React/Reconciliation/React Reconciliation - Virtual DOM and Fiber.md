---
tags:
  - react
  - performance
  - frontend
  - reconciliation
  - fiber
created: 2026-06-08
source: https://www.developerway.com/posts/reconciliation-in-react
---

# Virtual DOM and Fiber Architecture

> Part 1 of [[React Reconciliation Guide]]

---

## Virtual DOM

The Virtual DOM (VDOM) is a **lightweight JavaScript object tree** that mirrors the real DOM structure. React maintains it to avoid expensive direct DOM manipulation.

**Why not just update the DOM directly?**
DOM operations are slow — reflows, repaints, layout recalculations. The VDOM lets React batch and minimize DOM writes by computing diffs in JS first.

```
Component renders → New VDOM tree created
                         ↓
              Diff against previous VDOM
                         ↓
              Only changed nodes hit the real DOM
```

---

## React Fiber (React 16+)

Fiber is a complete **rewrite of React's reconciliation engine** — from synchronous recursive tree-walking to an asynchronous, interruptible, linked-list traversal.

### Before Fiber (Stack Reconciler)
- Reconciliation was a single synchronous recursive call
- Could not be paused mid-way
- Long trees could block the main thread → janky UI

### After Fiber
- Each component corresponds to a **Fiber node** (a plain JS object)
- The work is split into small **units of work**
- React can **pause, prioritize, and resume** work between frames

### What a Fiber Node Contains

```js
{
  type,           // component function or DOM tag
  key,            // key attribute
  child,          // first child fiber
  sibling,        // next sibling fiber
  return,         // parent fiber
  pendingProps,   // props for this render
  memoizedProps,  // props from last render
  memoizedState,  // state from last render
  effectTag,      // what DOM operation is needed (UPDATE / PLACEMENT / DELETION)
}
```

### Two Fiber Trees

React maintains **two trees** at all times:

| Tree | Description |
|------|-------------|
| **Current tree** | Reflects what's currently rendered in the DOM |
| **Work-in-progress tree** | Being built during the current render |

When the work-in-progress tree is complete, React swaps it with the current tree (**double buffering**).

---

## Two Phases of Fiber Reconciliation

### Phase 1: Render (Reconciliation)
- **Interruptible** — can be paused and resumed
- Builds the work-in-progress tree
- Computes what changes are needed (diffing)
- Does NOT touch the DOM

### Phase 2: Commit
- **Synchronous and uninterruptible** — must complete in one pass
- Applies computed DOM mutations
- Runs `useEffect` / `useLayoutEffect` cleanups and setups

---

## Fiber Enables

| Feature | How Fiber Enables It |
|---------|---------------------|
| **Concurrent Mode** | Interruptible render phase |
| **Suspense** | Pause rendering and resume when data is ready |
| **Transitions** | Lower-priority renders yield to urgent updates |
| **Time Slicing** | Break large renders into chunks across frames |

---

## Related

- [[React Reconciliation - Diffing Algorithm]] — how trees are compared
- [[React Reconciliation Guide]] — back to index
