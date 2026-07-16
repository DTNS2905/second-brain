---
tags:
  - react
  - lifecycle
  - strict-mode
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/StrictMode
---

# React Lifecycle — StrictMode Double Invoke

> StrictMode's dev-only double-invoke is intentionally a stress test for idempotence — not a bug, not a performance issue, and not to be defeated with ref guards. In React 19, offscreen remounts via `<Activity>` make this behavior a production reality. Part of [[React Lifecycle Guide]].

---

## What StrictMode is

A dev-only wrapper (`<StrictMode>`) that intentionally invokes certain functions **twice** to catch impure code. It is stripped from production builds — the extra invocations do not run for users. It is **not** a performance toggle, not a "safety mode" you turn off when things get slow, and not something to work around.

```jsx
// index.tsx — typical placement at the app root
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

The wrapper is scoped: only its subtree is under StrictMode. You can wrap a specific feature during migration.

---

## What gets doubled

| Doubled | Not doubled |
|---------|-------------|
| Function component render | Event handlers |
| `useState(() => …)` initializer | Ref `.current` assignments |
| `useReducer(reducer, init, initFn)` init | Non-strict subtrees |
| `useMemo` / `useCallback` factory | State setter calls themselves |
| Effect setup + cleanup + setup (mount) | `useRef(init)` argument (only runs once) |
| Class `constructor`, `render`, `shouldComponentUpdate`, etc. (legacy) | Production builds (entirely disabled) |

The pattern: anything React expects to be **pure** or **idempotent** gets doubled. Anything user-triggered (a click, a keypress) runs exactly as the user intends.

---

## The intent — idempotence

The key insight — the entire reason StrictMode exists — is a single contract React wants your effect code to satisfy:

> *"Safe to run, cleanup, and run again with no observable difference from running once."*

If your effect cannot survive **setup → cleanup → setup**, it has a latent bug that will ship to production. StrictMode surfaces that bug in dev so you can fix it before users hit it via Fast Refresh, `<Activity>`, route changes with `key` swaps, or Suspense fallback recovery. See [[React Hooks - useEffect]] for the cleanup contract StrictMode is testing.

---

## The three most common breakages and their fixes

### Counter increment on mount

```jsx
// ❌ Doubles in StrictMode; ships as "user visited twice" bug on any remount
useEffect(() => {
  setViews(v => v + 1);
}, []);
```

```jsx
// ✅ Derive views from server state, or increment in the click handler that caused the visit
function onNavigate() {
  analytics.pageView(path);
}
```

The effect version is *fundamentally broken*: any remount — Fast Refresh, `<Activity>` toggle, `key` change — will double-count. The click handler runs exactly when the user did the thing, exactly once per action, and never on remount. This is a common instance of "You Might Not Need an Effect."

---

### Fetch without a race guard

```jsx
// ❌ Second setup fires while first fetch is still in flight; both may setResults
useEffect(() => {
  fetch(url).then(r => r.json()).then(setResults);
}, [url]);
```

```jsx
// ✅ AbortController — first setup aborts before second runs
useEffect(() => {
  const ctrl = new AbortController();
  fetch(url, { signal: ctrl.signal })
    .then(r => r.json())
    .then(setResults)
    .catch(e => { if (e.name !== 'AbortError') throw e; });
  return () => ctrl.abort();
}, [url]);
```

The race isn't hypothetical. Under StrictMode dev, the setup-cleanup-setup sequence guarantees two overlapping fetches on the first render. Without a cleanup that aborts (or an `ignore` flag), the older response can arrive last and overwrite the newer one. Cross-link [[React Lifecycle - Unmount and Cleanup Patterns]] for the full race-guard vocabulary.

---

### Analytics session double-tracked

```jsx
// ❌ Two sessions started on mount in dev; two are started on any Activity remount in prod
useEffect(() => {
  analytics.startSession(userId);
}, [userId]);
```

```jsx
// ✅ Dedupe at the module level, or return a cleanup that ends the session
useEffect(() => {
  const session = analytics.startSession(userId);
  return () => analytics.endSession(session);
}, [userId]);
```

The fix isn't "start once" — it's making session lifetime match component lifetime. When the component's effect is torn down (unmount, `userId` change, Activity hide), the session ends. When it comes back, a new session starts. That's *correct* behavior. Session counts are now driven by real component lifetime, which is what you actually want.

If the analytics library truly needs a single global session per app run, initialize it at module scope — not in a component effect.

---

## The ref-guard escape hatch is (almost always) wrong

```jsx
// ❌ Bypasses the stress test — bug still ships
const didInit = useRef(false);
useEffect(() => {
  if (didInit.current) return;
  didInit.current = true;
  analytics.pageView();
}, []);
```

The ref-guard pattern makes StrictMode green, but the underlying effect is still non-idempotent — it will double-fire on any real remount (Activity toggle, Fast Refresh, route change with `key` swap). You've silenced the warning, not fixed the bug. StrictMode's job is exactly to expose non-idempotent effects; guarding around it defeats the point.

The only legitimate use is a **truly one-time init that has no cleanup semantics** — e.g., initializing a monitoring library that guards itself against re-init. And even then, it's often better to do that at **module scope**, outside React entirely:

```jsx
// ✅ Module scope — runs exactly once per page load, no React lifecycle involved
Sentry.init({ dsn: '...' });

export function App() { /* … */ }
```

Rule of thumb: if you're reaching for `didInit`, the answer is usually (a) move it to module scope, (b) put it in an event handler, or (c) add a real cleanup.

---

## React 19: `<Activity>` makes remounts a production feature

React 19 ships `<Activity>` — a way to preserve component state while unmounting effects. When a subtree switches from `mode="visible"` to `mode="hidden"`:

- All effect cleanups in the subtree run.
- State is preserved.
- Refs are preserved.
- The DOM is detached.

When it switches back to `visible`:

- The DOM is re-attached.
- Effect setups run again — with the preserved state.

```jsx
<Activity mode={isTabActive ? 'visible' : 'hidden'}>
  <TabContents />
</Activity>
```

This is StrictMode's setup → cleanup → setup showing up in **production**, driven by user action. Every effect that broke under StrictMode will now break under `<Activity>` for real users. The dev warning was the free preview.

Cross-link [[React Hooks - React 19 Actions Hooks]] (or wherever Activity ends up covered — update the link when the note lands).

---

## What StrictMode does NOT double

- **Event handlers** (`onClick`, `onChange`, submit) — user actions run exactly once per user action.
- **`useRef(init)`** — the initializer arg runs exactly once, even in StrictMode. (This is why the `didInit` ref pattern works to *silence* the warning — but see above for why silencing is wrong.)
- **Ref `.current` writes** — imperative, not tracked by React.
- **Non-strict subtrees** — StrictMode is scoped to its subtree. A `<StrictMode>` boundary only affects descendants.
- **Production builds** — entirely disabled. Zero doubled invocations for real users. Zero overhead.
- **State setter calls** — the setter identity is stable and the call itself is not doubled; the *render* it triggers may be double-invoked (per the render column above), but the setter fires once.

---

## The mount → cleanup → mount cycle in detail

For a component mounting under StrictMode, the exact sequence is:

1. Component function called (render #1)
2. Component function called again (render #2 — dev-only extra run to check purity)
3. Commit
4. Effect setup #1
5. Effect cleanup #1
6. Effect setup #2

Only after step 6 is the component in its steady state. If your effect assumes step 4 is the only setup, or that no cleanup runs "on mount," you have a bug.

The same shape applies to `useLayoutEffect`, `useInsertionEffect`, and (in class components) `componentDidMount` + `componentWillUnmount` + `componentDidMount` cycles.

For a component **updating** (dep change) under StrictMode, the effect setup + cleanup is **not** doubled — only the initial mount. Subsequent updates behave normally: cleanup old, setup new.

---

## Also happens in production (not just StrictMode)

The setup → cleanup → setup pattern is not merely a dev artifact. Real production triggers:

- **React 19 `<Activity>` toggle** — hide/show cycles remount effects on the whole subtree.
- **Fast Refresh** (dev with `react-refresh`, but visible to users of dev builds) — edits to a component file remount its effects.
- **`key` prop change** — passing a new `key` to a component tells React to unmount and mount a fresh instance. Common with `<Route key={pathname} />` patterns.
- **Suspense fallback swap** — when a boundary shows its fallback and then reveals content again, the newly-committed content mounts fresh.
- **Concurrent-features remounts** — React may discard partially-rendered trees and re-render. Effects for discarded trees never commit; the retry commits fresh.

Any of these will hit non-idempotent effects. StrictMode is the cheapest way to find them before they hit users.

---

## Debugging checklist

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "It works, then StrictMode broke it" | Non-idempotent effect | Add cleanup that mirrors setup |
| Two API calls on page load | Missing race guard | AbortController or `ignore` flag |
| Duplicate analytics events | Effect doing user-action work | Move to event handler |
| State increments by 2 on mount | `setState` in mount effect | Derive from props, or trigger from event |
| Two socket connections | Missing `disconnect()` in cleanup | Return cleanup that calls disconnect |
| "Only in dev" — silences in prod build | You verified it exists in dev | It also happens on Activity/Fast Refresh — fix it |

---

## Summary

| Rule | Why |
|------|-----|
| StrictMode is a stress test, not a bug | Surfaces non-idempotent effects |
| Every effect must survive setup → cleanup → setup | Same pattern happens in prod via Activity, Fast Refresh, key changes |
| Fix the effect, not the symptom | Ref guards silence warnings but ship the bug |
| Event handlers over mount effects for user actions | Handlers run when the user acts, exactly once |
| Cleanup mirrors setup | Connect ↔ disconnect, subscribe ↔ unsubscribe, fetch ↔ abort |
| Init at module scope for truly-once work | Not React's lifecycle |

---

## Related

- [[React Hooks - useEffect]] — the effect contract StrictMode is testing
- [[React Lifecycle - Unmount and Cleanup Patterns]] — AbortController and race patterns
- [[React Hooks - useState]] — initializer double-invoke behavior
- [[React Hooks - Custom Hooks]] — anti-patterns around lifecycle wrappers
- [[React Lifecycle Guide]]
