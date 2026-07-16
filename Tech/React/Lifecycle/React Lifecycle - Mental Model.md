---
tags:
  - react
  - lifecycle
  - mental-model
  - frontend
created: 2026-07-16
source: https://react.dev/learn/lifecycle-of-reactive-effects
---

# React Lifecycle — Mental Model

> Three orthogonal axes (phase × purpose × concurrency) that replace the class-era linear timeline. Part of [[React Lifecycle Guide]].

---

## The old mental model, and why it lies

The React 15 lifecycle read like a script: `constructor` → `componentWillMount` → `render` → `componentDidMount` → *(N updates)* → `componentWillUnmount`. One class instance, one arrow of time, one guarantee that each method fired exactly once per transition.

Under Fiber + concurrent rendering that story fails on every clause:

- **Render is retryable.** React may invoke your component function 2–3 times before committing — or discard the work entirely if a higher-priority update arrives. Anything impure you did in render happened for nothing.
- **State is not tied to a class instance.** Hook slots are keyed by *position in the fiber tree*. Two consecutive commits render "the same component" — but there is no `this`, no instance identity, no `didMount` hook you can hang onto.
- **Mount is not a moment.** With StrictMode (dev), `<Activity>` (React 19), and fast refresh, a component's setup/cleanup pair can run multiple times over its life. Treat "mount" as a **contract** the component must satisfy every time — not an event that fires once.

The class model wasn't wrong for React 15. It's wrong for React 18+.

---

## Three axes

The modern lifecycle is not a timeline — it's a **cube**. Every setup, cleanup, ref attach, and state reset lives at one coordinate.

### Phase

- **render** — pure, retryable, no side effects, no DOM access. React may call it, throw the result away, and call it again.
- **commit** — impure, atomic, uninterruptible. All DOM mutations, all ref attachments, all effect setups/cleanups.

If it touches anything outside its own return value, it belongs in commit.

### Purpose

- **mount** — the first commit for this fiber (this position in the tree with this element type).
- **update** — a subsequent commit for the same fiber, with new props or state.
- **unmount** — the fiber is removed from the tree (or reparented with a different type/key).

Purpose is a property of the *transition between commits*, not of a moment in time.

### Concurrency

- **sync** — flushed synchronously (input events, `flushSync`, legacy roots). Cannot be interrupted.
- **default** — normal `setState` in event handlers; batched, but urgent.
- **transition** — marked non-urgent via `startTransition` / `useTransition`; interruptible, discardable.
- **idle** — scheduler-idle work (rare; internal / experimental).

Concurrency determines whether a render is allowed to be thrown away before it commits.

**Every effect lives at a coordinate `(phase, purpose, concurrency)` in this cube.** "A setup that runs on mount during a transition" is a real, distinct thing from "a setup that runs on mount during a sync commit" — the second cannot be discarded, the first can be.

---

## Class → hooks translation

| Class method | Modern equivalent |
|--------------|-------------------|
| `constructor` | Initializer arg: `useState(() => init)` / `useRef(init)` |
| `componentDidMount` | `useEffect(fn, [])` |
| `componentDidUpdate` | `useEffect(fn, [deps])` |
| `componentWillUnmount` | `return () => cleanup` from `useEffect` |
| `getSnapshotBeforeUpdate` | `useLayoutEffect` reading DOM before paint |
| `getDerivedStateFromProps` | Compute during render — no effect, no state |
| `shouldComponentUpdate` | `React.memo(Component, arePropsEqual)` |
| `componentDidCatch` | `<ErrorBoundary>` (still class-only in 2026) |

**This is a translation guide, not a mental model — `useEffect(fn, [])` is NOT `componentDidMount`.** It fires twice in StrictMode, re-fires after remount via `<Activity>`, may run cleanup then setup again after a fast refresh, and receives its cleanup in reverse-child order relative to siblings. See [[React Lifecycle - StrictMode Double Invoke]].

---

## Render vs commit — the atomic split

Two phases. The reconciler enforces the boundary.

```
   props/state change
          │
          ▼
   ┌──────────────┐   retryable
   │    RENDER    │   interruptible
   │   (pure)     │   discardable
   │              │   NO DOM writes
   │  build WIP   │   NO ref reads
   │  fiber tree  │   NO setState side effects
   └──────┬───────┘
          │  (commit scheduled)
          ▼
   ┌──────────────┐   atomic
   │    COMMIT    │   uninterruptible
   │   (impure)   │   synchronous
   │              │
   │  DOM mutate  │
   │  refs attach │
   │  effects fire│
   └──────┬───────┘
          │
          ▼
     browser paints
```

Render is called *the model*: a pure function of props and state to a tree of elements. React may call it, memoize it, throw it away. Nothing you do in render is guaranteed to be observed.

Commit is *the fact*: it happens once per accepted render, applies all DOM mutations in a single synchronous pass, and only then fires effects. See [[React Reconciliation - Virtual DOM and Fiber]] for the reconciler-level view.

---

## Mount is a contract, not a moment

Under classes, `componentDidMount` fired once. Under hooks, "mount" is expressed as a **setup + cleanup pair** — and React reserves the right to run that pair multiple times for the same conceptual instance:

- **StrictMode (dev)** — mounts, unmounts, remounts every component to verify cleanup is symmetric.
- **`<Activity>` (React 19)** — hides a subtree and later revives it; setup and cleanup run each cycle.
- **Fast refresh** — module edits re-run effects with cleanup preserving state.

The correct mental model: *"my effect promises that, for every setup, there will be a matching cleanup that fully reverses it."*

```jsx
// ❌ Assumes mount is a moment — analytics fires twice in StrictMode,
//    and again on every <Activity> revive.
useEffect(() => {
  analytics.trackMount(name);
}, []);
```

```jsx
// ✅ Mount is a contract — every start is paired with an end.
useEffect(() => {
  const session = analytics.startSession(name);
  return () => analytics.endSession(session);
}, [name]);
```

The ✅ version is idempotent: run it 1x, 2x, 100x — the observable state (open sessions) is always consistent. That is what "mounted" means in 2026. See [[React Hooks - useEffect]] for the full cleanup contract.

---

## The lifecycle as a state machine

Forget the timeline. Draw the state machine.

```
        ┌────────────────────────────────────────────┐
        │                                            │
        ▼                                            │
   ┌──────────┐   setState / props change   ┌────────┴────────┐
   │ unmounted│ ─────────────────────────▶  │    rendering    │
   └──────────┘                              └────────┬────────┘
        ▲                                             │
        │ parent unmounts / key changes               │ render completes
        │                                             ▼
        │                                    ┌─────────────────┐
        │            higher-priority ┌─────  │   committed     │
        │            work arrives    │       └────────┬────────┘
        │                            ▼                │
        │                  ┌───────────────────┐      │ effects flush
        │                  │  render-discarded │      ▼
        │                  └───────────────────┘  ┌───────────────┐
        │                                          │  effects-run  │
        │  deps change / unmount                   └───────┬───────┘
        └──────────────────────────────────────────────────┘
                            cleanup-pending
```

Add Suspense: a `suspended` state sits between `rendering` and `committed` — the fiber is paused, no commit yet, state preserved. See [[React Lifecycle - Suspense Lifecycle]].

Add transitions: `render-discarded` is a first-class terminal state, not an error. Work started; work thrown away; nothing committed; no cleanup needed because no setup ran. See [[React Lifecycle - Transitions and Interruptible Renders]].

Concrete transitions worth naming:

- `unmounted → rendering` — initial mount begins.
- `rendering → render-discarded` — a transition was superseded; no user-visible effect.
- `rendering → committed` — the render was accepted; the DOM is now consistent with the new tree.
- `committed → effects-run` — `useLayoutEffect` then browser paint then `useEffect`.
- `effects-run → cleanup-pending → effects-run` — deps changed; cleanup then setup runs again.
- `effects-run → cleanup-pending → unmounted` — parent removed the fiber; final cleanup.

The states are not phases in time — they are **positions in a graph** any given fiber can be in on any given frame.

---

## Where to go next

- [[React Lifecycle - Mount Semantics]] — trace one mount end-to-end (next in reading order)
- [[React Lifecycle - Effect Ordering]] — the exact per-commit firing sequence
- [[React Lifecycle - StrictMode Double Invoke]] — the idempotence stress test that enforces the "mount is a contract" model
- [[React Lifecycle - Unmount and Cleanup Patterns]] — practical AbortController / timer / subscription teardown
- [[React Lifecycle - Suspense Lifecycle]] — the fourth state that breaks the linear model completely
- [[React Lifecycle - Transitions and Interruptible Renders]] — "render is a query, commit is a fact"

---

## Related

- [[React Reconciliation - Virtual DOM and Fiber]] — the render/commit split at the reconciler level
- [[React Hooks - useEffect]] — the primary carrier of lifecycle semantics under hooks
- [[React Re-renders - Why Components Re-render]] — what triggers re-entry to render phase
- [[React Lifecycle Guide]] — the folder index
- [[React Lifecycle - Mount Semantics]] — trace one mount end-to-end (next in reading order)
