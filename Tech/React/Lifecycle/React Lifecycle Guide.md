---
tags:
  - react
  - lifecycle
  - guide
  - frontend
created: 2026-07-16
source: https://react.dev/learn/lifecycle-of-reactive-effects
---

# React Lifecycle Guide

> The modern React lifecycle is not a linear timeline of class methods — it's a **system** of three phases (render, commit, effect) running under a concurrent scheduler that can interrupt, retry, or discard work in flight. This guide covers the lifecycle **hooks-first**, from mount to unmount, through Suspense and transitions.

---

## Prereqs

Read first — this guide assumes them:

- [[React Hooks - useEffect]] — effect setup / cleanup contract
- [[React Reconciliation - Virtual DOM and Fiber]] — the render/commit split

---

## Contents

### Foundations

- [[React Lifecycle - Mental Model]] — three axes: phase × purpose × concurrency
- [[React Lifecycle - Mount Semantics]] — JSX → element → fiber → commit → paint, step by step

### The commit sequence

- [[React Lifecycle - Effect Ordering]] — exact per-commit firing order for every effect flavor
- [[React Lifecycle - Ref Lifecycle and Cleanup]] — object refs, callback refs, and React 19's ref cleanup return

### Dev tools & teardown

- [[React Lifecycle - StrictMode Double Invoke]] — the idempotence stress test
- [[React Lifecycle - Unmount and Cleanup Patterns]] — AbortController, timers, subscriptions, leaks

### Concurrent world

- [[React Lifecycle - Suspense Lifecycle]] — the fourth state
- [[React Lifecycle - Transitions and Interruptible Renders]] — "render is a query, commit is a fact"

---

## What "lifecycle" means in 2026

In React 15, a component had a lifecycle: instantiate → `componentDidMount` → repeated `componentDidUpdate` → `componentWillUnmount`. One class instance, one linear timeline.

Under Fiber + concurrent rendering, none of that survives:

- **Render is retryable and abandonable.** React may call your component 3 times before deciding to commit, or never commit at all.
- **State is disconnected from the render function.** Two "instances" of the same component in two consecutive commits share hook slots — the identity is the **position in the fiber tree**, not a class instance.
- **Effects run *after* commit, in a strictly ordered pipeline.** They are the closest analogue to lifecycle callbacks — but they run in reverse-child order and cleanup mirrors setup.
- **StrictMode intentionally mounts every component twice** (dev). If your effect can't survive it, it can't survive production either — remounts are a shipping feature in React 19 via `<Activity>`.
- **Suspense adds a fourth state**: rendering, committed, suspended, unmounted. State survives suspension.

The modern lifecycle mental model is best expressed as three orthogonal axes:

| Axis | Values |
|------|--------|
| **Phase** | render (pure) vs commit (impure, atomic) |
| **Purpose** | mount vs update vs unmount |
| **Concurrency** | sync (input) vs default vs transition vs idle |

Every effect, ref attach, and state reset lives at a specific *coordinate* in this cube. See [[React Lifecycle - Mental Model]] for the diagrams.

---

## Class → hooks quick map

The one comparison table permitted in this folder. Every downstream note is hooks-only.

| Class method | Modern equivalent |
|--------------|-------------------|
| `constructor` | Initializer arg to `useState(() => …)` / `useRef(init)` |
| `componentDidMount` | `useEffect(fn, [])` |
| `componentDidUpdate` | `useEffect(fn, [deps])` |
| `componentWillUnmount` | Cleanup returned from `useEffect` |
| `getSnapshotBeforeUpdate` | `useLayoutEffect` reading DOM |
| `getDerivedStateFromProps` | Compute during render (no effect needed) |
| `shouldComponentUpdate` | `React.memo` + custom comparator |
| `componentDidCatch` | `<ErrorBoundary>` (still class-only in 2026) |

**Warning**: this table is a *translation guide*, not a mental model. `useEffect(fn, [])` is NOT `componentDidMount` — it fires twice in StrictMode, may run in dev after unmount+remount, and receives cleanup in a fundamentally different order. See [[React Lifecycle - StrictMode Double Invoke]].

---

## Reading order for someone new

1. **[[React Lifecycle - Mental Model]]** — get oriented
2. **[[React Lifecycle - Mount Semantics]]** — trace one mount end-to-end
3. **[[React Lifecycle - Effect Ordering]]** — memorize the per-commit sequence
4. **[[React Lifecycle - StrictMode Double Invoke]]** — internalize idempotence
5. **[[React Lifecycle - Unmount and Cleanup Patterns]]** — the practical toolkit
6. **[[React Lifecycle - Ref Lifecycle and Cleanup]]** — the React 19 refresh
7. **[[React Lifecycle - Suspense Lifecycle]]** — add the fourth state
8. **[[React Lifecycle - Transitions and Interruptible Renders]]** — the concurrent finale

---

## Related topics in this vault

- [[React Hooks Guide]] — every built-in hook, one page each
- [[React Reconciliation Guide]] — Fiber, diffing, keys
- [[React Re-renders Guide]] — why re-renders happen and how to prevent them
- [[React Component Composition Guide]] — the pattern layer above lifecycle
