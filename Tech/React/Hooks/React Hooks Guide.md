---
tags:
  - react
  - hooks
  - guide
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/hooks
---

# React Hooks Guide

> Complete reference for every built-in React hook — signature, when to use, when not to use, and how they compare.

---

## Contents

### Core hooks (use these every day)

- [[React Hooks - useState]] — local reactive state
- [[React Hooks - useReducer]] — state with centralized transitions
- [[React Hooks - useEffect]] — synchronize with an external system
- [[React Hooks - useLayoutEffect]] — sync DOM work before paint
- [[React Hooks - useContext]] — read from the nearest provider
- [[React Hooks - useRef]] — non-reactive value or DOM node

### Performance hooks

- [[React Hooks - useMemo]] — cache expensive calculations
- [[React Hooks - useCallback]] — cache function identity
- [[React Hooks - useTransition]] — non-blocking state updates
- [[React Hooks - useDeferredValue]] — value-based counterpart to useTransition

### React 19 (Actions & Suspense)

- [[React Hooks - React 19 Actions Hooks]] — `use`, `useActionState`, `useOptimistic`, `useFormStatus`

### Specialized / utility

- [[React Hooks - Store and Utility Hooks]] — `useSyncExternalStore`, `useId`, `useDebugValue`

### Concepts

- [[React Hooks - Rules of Hooks]] — the call-order invariant that makes all of this work
- [[React Hooks - Custom Hooks]] — packaging stateful logic for reuse

### Cross-cutting

- **[[React Hooks - When to Use Which]]** — comparison tables and decision trees across every hook

---

## What is a hook?

A **hook** is a function that lets a function component "hook into" React features — state, effects, context, refs, transitions, etc. Hooks are how modern React components hold state and coordinate with the outside world.

Two invariants hold for every hook (see [[React Hooks - Rules of Hooks]]):

1. **Only called at the top level** of a function component or another custom hook — never inside conditions, loops, nested functions, or after early returns.
2. **Only called from React functions** — not from event handlers, plain JS functions, or class components.

Under the hood, React identifies each hook call by its **positional index** — the *N*-th `useState` in a component is state slot *N*. That's why the ordering must be identical across renders.

---

## Full hook inventory

### From `react`

| Hook | Purpose | Notes |
|------|---------|-------|
| `useState` | Local reactive state | Batches updates; use functional form for prev-based |
| `useReducer` | State with centralized transitions | Best for coordinated multi-field state |
| `useEffect` | External-system sync, after paint | Default effect choice |
| `useLayoutEffect` | Sync DOM work, before paint | Only when needed; blocks paint |
| `useInsertionEffect` | Inject styles before layout | **CSS-in-JS libraries only** |
| `useContext` | Read the nearest provider | Every consumer re-renders on change |
| `useRef` | Non-reactive mutable value / DOM ref | Access in handlers/effects, not during render |
| `useImperativeHandle` | Custom parent-visible API via ref | Rare — prefer props |
| `useMemo` | Cache a computed value | Only pays off in narrow cases |
| `useCallback` | Cache a function reference | `useCallback(fn, d) ≡ useMemo(() => fn, d)` |
| `useTransition` | Wrap setter as non-blocking | Gives `isPending` |
| `useDeferredValue` | Return a lagged value | Value-based counterpart to `useTransition` |
| `useId` | Stable SSR-safe unique ID | **Never** for list keys |
| `useSyncExternalStore` | Bridge external store into React | Redux/Zustand primitive |
| `useDebugValue` | Label custom hook in DevTools | Library-facing |
| `use` (React 19) | Read Promise or Context | Not a hook — callable conditionally |
| `useActionState` (React 19) | Async form actions with `isPending` | Replaces `useFormState` |
| `useOptimistic` (React 19) | Show optimistic UI during action | Must run inside `startTransition` |

### From `react-dom`

| Hook | Purpose |
|------|---------|
| `useFormStatus` | Parent form's submission state (must be inside `<form>` child) |

---

## Quick-choice cheat sheet

```
STATE
  useState        — simple local value
  useReducer      — coordinated multi-field state
  useContext      — tree-scoped shared value
  useSyncExternalStore — non-React store

VALUE (no re-render)
  useRef          — DOM node or mutable instance value
  useImperativeHandle — expose API to parent (rare)

SIDE EFFECT
  useEffect       — sync with external system (default)
  useLayoutEffect — sync DOM before paint
  useInsertionEffect — CSS-in-JS libs only

PERFORMANCE
  useMemo         — cache a value
  useCallback     — cache a function
  useTransition   — non-blocking setter
  useDeferredValue — non-blocking derived value

REACT 19 ACTIONS
  use             — read Promise/Context (allowed conditionally)
  useActionState  — form + isPending + serialized queue
  useOptimistic   — optimistic UI during action
  useFormStatus   — parent form pending state (from react-dom)

UTILITY
  useId           — stable unique ID (SSR-safe)
  useDebugValue   — DevTools label
```

For deeper comparisons see **[[React Hooks - When to Use Which]]**.

---

## Related topics in this vault

- [[React Re-renders Guide]] — hooks in the context of preventing unnecessary re-renders
- [[React memo Guide]] — the memoization pairing that makes `useMemo` / `useCallback` matter
- [[React Component Composition Guide]] — often replaces context and memo entirely
- [[React Reconciliation Guide]] — how hooks fit into the fiber/commit lifecycle

---

## Learning path

For someone new to hooks:

1. Read [[React Hooks - Rules of Hooks]] — the two rules that make everything else make sense.
2. Master [[React Hooks - useState]] and [[React Hooks - useEffect]] — these cover 80% of daily work.
3. Read [[React Hooks - useEffect]]'s "You Might Not Need an Effect" section — the most common mistake.
4. Learn [[React Hooks - useRef]] for DOM access.
5. Learn [[React Hooks - useContext]] and [[React Hooks - useReducer]] for cross-tree state.
6. Study perf hooks (`useMemo`, `useCallback`, `useTransition`, `useDeferredValue`) — **only after** understanding when re-renders are actually a problem. See [[React Re-renders Guide]] first.
7. Learn [[React Hooks - Custom Hooks]] to package your own reusable logic.
8. Explore [[React Hooks - React 19 Actions Hooks]] when working with forms and Server Actions.
