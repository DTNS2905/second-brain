---
tags:
  - react
  - hooks
  - comparison
  - decision-guide
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/hooks
---

# React Hooks — When to Use Which

> Comparison and decision guide across all React hooks. Part of [[React Hooks Guide]].

---

## The master decision tree

```
What do you actually need?

├── STATE that drives the UI
│    ├── One or two independent primitives?      → useState
│    ├── Many fields updated together?           → useReducer
│    ├── Deep prop drilling?                     → useContext (memoize the value!)
│    └── Non-React store (Redux, browser API)?   → useSyncExternalStore
│
├── VALUE that does NOT re-render
│    ├── DOM node?                               → useRef (JSX ref attribute)
│    ├── Mutable instance value (timer, prev)?   → useRef (as a container)
│    └── Expose imperative API to parent?        → useImperativeHandle (rare)
│
├── SIDE EFFECT syncing with an external system
│    ├── Default — after paint, non-blocking     → useEffect
│    ├── Must measure DOM before paint?          → useLayoutEffect
│    └── CSS-in-JS library injecting styles?     → useInsertionEffect (library-only)
│
├── PERFORMANCE — cache values across renders
│    ├── Result of an expensive calculation?     → useMemo
│    ├── Function reference for memo child?      → useCallback
│    ├── Non-blocking state update, I own setter → useTransition
│    └── Non-blocking derived value, I don't     → useDeferredValue
│
├── FORMS + ACTIONS (React 19)
│    ├── Async form submission with state?       → useActionState
│    ├── Optimistic UI while action pending?     → useOptimistic
│    ├── Read parent form's pending status?      → useFormStatus
│    └── Read a Promise inside <Suspense>?       → use
│
└── UTILITY
     ├── Unique ID (SSR-safe)?                   → useId
     └── DevTools label for a custom hook?       → useDebugValue
```

---

## Head-to-head comparisons

### useState vs useReducer

|  | useState | useReducer |
|---|----------|-----------|
| Best for | Simple primitives, independent fields | Coordinated multi-field state, many transitions |
| Update site | Scattered `setX(...)` calls | Central pure reducer |
| Testability | Test through component | Reducer testable in isolation |
| Setter identity | Stable | `dispatch` stable |
| Typical size | 1–3 fields | 4+ fields updated together |

Rule of thumb: start with `useState`. Migrate to `useReducer` when transitions get tangled or the same state is written from many places.

See [[React Hooks - useState]] · [[React Hooks - useReducer]]

---

### useEffect vs useLayoutEffect vs useInsertionEffect

|  | Runs | Blocks paint | Use for |
|---|------|--------------|---------|
| `useInsertionEffect` | Before layout effects | Yes (very early) | CSS-in-JS libs injecting styles |
| `useLayoutEffect` | After DOM mutation, before paint | **Yes** | Sync DOM measurement / mutation |
| `useEffect` | After paint | No | External-system sync (default) |

**Default is `useEffect`.** Only reach for `useLayoutEffect` if you'd see a visible flicker otherwise. Never use `useInsertionEffect` in app code.

See [[React Hooks - useEffect]] · [[React Hooks - useLayoutEffect]]

---

### useMemo vs useCallback

|  | useMemo | useCallback |
|---|---------|-------------|
| Caches | Result of a function call | The function itself |
| Signature | `useMemo(() => calc(), deps)` | `useCallback(fn, deps)` |
| Equivalence | `useCallback(fn, d) === useMemo(() => fn, d)` | — |
| Wins when | Calculation > ~1ms, or memo child prop | memo child, effect dep, hook chain |

Both are useless unless something downstream (`React.memo`, another hook's deps) actually inspects the reference.

See [[React Hooks - useMemo]] · [[React Hooks - useCallback]]

---

### useTransition vs useDeferredValue

|  | useTransition | useDeferredValue |
|---|---------------|------------------|
| Wraps | The **setter** call | The **value** you receive |
| You own | The state update site | Only how you use the value |
| Pending signal | `isPending` flag | Manual `value !== deferred` |
| Fixed delay | ❌ (priority-based) | ❌ (priority-based) |
| Best when | You call `setX` yourself | Value comes from prop/hook |

Neither is a debounce. For a fixed delay use `setTimeout` or a debounce hook.

See [[React Hooks - useTransition]] · [[React Hooks - useDeferredValue]]

---

### useContext vs useSyncExternalStore

|  | useContext | useSyncExternalStore |
|---|-----------|----------------------|
| State lives in | React tree | External store |
| Update trigger | Provider re-render | Store `subscribe` callback |
| Re-render scope | Every consumer | Only components reading changed data |
| Best for | Theme, user, locale (rarely changes) | Redux/Zustand, browser APIs |

Context is optimized for **static-ish tree-scoped values**. High-frequency updates through context re-render every consumer.

See [[React Hooks - useContext]] · [[React Hooks - Store and Utility Hooks]] · [[React Re-renders - Context Re-renders]]

---

### useRef vs useState

|  | useRef | useState |
|---|--------|----------|
| Triggers re-render | ❌ No | ✅ Yes |
| Access during render | ❌ Illegal | ✅ Fine |
| Access in handlers/effects | ✅ Fine | ✅ Fine |
| Use for | DOM nodes, timer IDs, prev value | Anything the user sees |

Rule: *if it affects what the user sees, it's state, not a ref.*

See [[React Hooks - useRef]]

---

### useActionState vs useTransition

|  | useActionState | useTransition |
|---|----------------|---------------|
| Manages state | ✅ | ❌ |
| Pending flag | ✅ | ✅ |
| Wired for `<form action>` | ✅ | Manual |
| Multiple calls | Queue serially | Parallel |
| Best for | Async form submits | Any expensive state update |

`useActionState` = `useTransition` + state + form wiring for the common form-submit case.

See [[React Hooks - React 19 Actions Hooks]]

---

## Quick lookup — "I want to..."

| I want to... | Hook |
|--------------|------|
| Store a value that updates the UI | [[React Hooks - useState]] |
| Store coordinated multi-field state | [[React Hooks - useReducer]] |
| Share a value across the subtree | [[React Hooks - useContext]] |
| Sync with a WebSocket / browser API | [[React Hooks - useEffect]] |
| Measure a DOM node before paint | [[React Hooks - useLayoutEffect]] |
| Get a DOM node reference | [[React Hooks - useRef]] |
| Persist a mutable value across renders without re-rendering | [[React Hooks - useRef]] |
| Expose imperative methods to a parent | [[React Hooks - useRef]] (useImperativeHandle) |
| Skip re-running an expensive calculation | [[React Hooks - useMemo]] |
| Stabilize a callback for a memoized child | [[React Hooks - useCallback]] |
| Keep the UI responsive during a big update | [[React Hooks - useTransition]] |
| Same, but value comes from props | [[React Hooks - useDeferredValue]] |
| Show optimistic UI while an action runs | [[React Hooks - React 19 Actions Hooks]] |
| Track a form's async submission state | [[React Hooks - React 19 Actions Hooks]] (useActionState) |
| Read the parent form's pending state | [[React Hooks - React 19 Actions Hooks]] (useFormStatus) |
| Read a Promise or Context conditionally | [[React Hooks - React 19 Actions Hooks]] (use) |
| Subscribe to an external store | [[React Hooks - Store and Utility Hooks]] (useSyncExternalStore) |
| Generate a stable unique ID | [[React Hooks - Store and Utility Hooks]] (useId) |
| Label a custom hook in DevTools | [[React Hooks - Store and Utility Hooks]] (useDebugValue) |

---

## Priority order for performance concerns

React docs' recommended order for fixing perf:

1. **Composition first** — pass JSX as `children` so wrappers don't re-render the subtree. See [[React Component Composition Guide]].
2. **Local state** — don't lift higher than needed.
3. **`React.memo`** — for genuinely stable components. See [[React memo Guide]].
4. **`useMemo` / `useCallback`** — only when they enable step 3 or fix a hook chain.
5. **`useTransition` / `useDeferredValue`** — for expensive updates you can't avoid.

Don't skip to step 4. Composition and `memo` cover most cases.

---

## Related

- [[React Hooks Guide]] — the index
- [[React Hooks - Rules of Hooks]] — how these hooks are allowed to compose
- [[React Hooks - Custom Hooks]] — packaging hook combinations for reuse
- [[React Re-renders Guide]] — the perf lens on hooks
- [[React memo Guide]] — the memoization pairing
