---
tags:
  - react
  - lifecycle
  - effects
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/useEffect
---

# React Lifecycle — Unmount and Cleanup Patterns

> Unmounting is where sloppy code turns into memory leaks and race conditions. Four resource categories, four canonical patterns. Part of [[React Lifecycle Guide]].

---

## What triggers an unmount

- **Parent unmount** — chain from ancestor removal. Every descendant unmounts child-first.
- **Conditional render flips false** — `{show && <X />}` removes `<X />` from the tree.
- **`key` prop change** — React treats different keys as different components, so the old one unmounts and a fresh one mounts (state resets).
- **Suspense fallback swap** — when a suspend re-fires with pending children, the new pending content unmounts. See [[React Lifecycle - Suspense Lifecycle]].
- **Route change** — a page-level tree unmounts when the router swaps routes.
- **`<Activity mode="hidden">` toggle (React 19)** — unmounts effects but preserves state and DOM. Effect setup + cleanup must be symmetric because the same component will re-run setup when it becomes visible again.

---

## The cleanup contract

Every setup must have a cleanup that reverses it. Cleanup runs child-first, before the parent's cleanup, and before the next effect setup on the same component when a dependency changes. Miss a cleanup and you leak the resource for the lifetime of the page. See [[React Lifecycle - Effect Ordering]].

---

## Category 1: Subscriptions

Pub/sub stores, WebSockets, custom event buses, and any DOM listener attached to a node you don't own (document, window, or a shared root).

```jsx
// ✅ Return the unsubscribe from the effect
useEffect(() => {
  const unsub = store.subscribe(fn);
  return unsub;
}, [store]);
```

WebSockets need both the listener removal and the socket close — closing alone doesn't detach listeners synchronously in every implementation:

```jsx
useEffect(() => {
  const ws = new WebSocket(url);
  ws.addEventListener('message', onMessage);
  return () => {
    ws.removeEventListener('message', onMessage);
    ws.close();
  };
}, [url]);
```

DOM events at the document/window level — the node outlives your component, so the listener must be explicitly removed:

```jsx
useEffect(() => {
  const onKey = (e: KeyboardEvent) => { /* … */ };
  document.addEventListener('keydown', onKey);
  return () => document.removeEventListener('keydown', onKey);
}, []);
```

The handler reference passed to `removeEventListener` must be identical to the one passed to `addEventListener` — inline arrow functions in each call site won't work.

---

## Category 2: Timers

Timers are the easiest resource to leak because they're invisible until you profile.

```jsx
// ✅ Interval — clear on cleanup
useEffect(() => {
  const id = setInterval(tick, 1000);
  return () => clearInterval(id);
}, [tick]);
```

When the timeout id needs to be cleared from outside the effect (e.g., cancelled by a button click), stash it in a ref:

```jsx
// ✅ Timeout stored in a ref so it can be cleared elsewhere
const timeoutRef = useRef<number>(0);
useEffect(() => {
  timeoutRef.current = window.setTimeout(fire, delay);
  return () => clearTimeout(timeoutRef.current);
}, [delay, fire]);
```

Anti-pattern — no cleanup, timer fires forever:

```jsx
// ❌ setInterval without cleanup — leaks forever
useEffect(() => {
  setInterval(tick, 1000);
}, []);
```

Under [[React Lifecycle - StrictMode Double Invoke]] this leaks *two* intervals per mount in dev, which is exactly why StrictMode surfaces the bug.

---

## Category 3: Network requests

The modern pattern: `AbortController`. The legacy pattern: `let ignore = true` flag. Both still valid; `AbortController` is preferred because it actually cancels the network work instead of just discarding the response.

```jsx
// ✅ AbortController — cancels the request, not just the setState
useEffect(() => {
  const ctrl = new AbortController();
  fetch(`/api/user/${id}`, { signal: ctrl.signal })
    .then(r => r.json())
    .then(setUser)
    .catch(e => { if (e.name !== 'AbortError') console.error(e); });
  return () => ctrl.abort();
}, [id]);
```

The `AbortError` catch is required — aborting rejects the fetch promise, and you don't want to log the intentional cancel as an error.

```jsx
// ✅ ignore flag — legitimate when the API doesn't support signals
useEffect(() => {
  let ignore = false;
  legacyClient.fetchUser(id).then(u => {
    if (!ignore) setUser(u);
  });
  return () => { ignore = true; };
}, [id]);
```

The bug this prevents:

```jsx
// ❌ Neither — stale response can overwrite the newer one
useEffect(() => {
  fetch(`/api/user/${id}`).then(r => r.json()).then(setUser);
}, [id]);
```

User changes `id` from 1 → 2. Request 1 (slow) resolves after request 2. Without a guard, request 1's data overwrites request 2's data — user sees the wrong profile with no error thrown. The state is silently, deterministically wrong.

Cross-link [[React Lifecycle - StrictMode Double Invoke]] — StrictMode surfaces exactly this bug in dev because the double-invoked effect fires two requests and the guard's absence becomes visible.

---

## Category 4: Imperative DOM / third-party libraries

Chart libraries, map libraries, WebGL contexts, jQuery plugins, virtualized grids — anything that grabs a DOM node and mounts non-React state onto it.

```jsx
// ✅ Callback ref with cleanup (React 19) is often the cleanest shape
const setMap = (el: HTMLDivElement) => {
  const map = new mapboxgl.Map({ container: el, style, center });
  return () => map.remove();
};
return <div ref={setMap} />;
```

The callback-ref return-cleanup form is new in React 19 and pairs naturally with imperative libraries because the setup happens when React actually has the DOM node, and teardown runs when the node detaches.

Or with `useEffect` + `useRef` (works in every React version):

```jsx
useEffect(() => {
  const map = new mapboxgl.Map({
    container: containerRef.current!,
    style,
    center,
  });
  return () => map.remove();
}, [style]);
```

Same principle for charts:

```jsx
useEffect(() => {
  const chart = new Chart(containerRef.current!, config);
  return () => chart.destroy();
}, [config]);
```

Every third-party UI library has a teardown method — `map.remove()`, `chart.destroy()`, `editor.destroy()`, `swiper.destroy()`. Not calling it leaks the DOM subtree, event listeners, WebGL contexts, and the library's internal state.

---

## The setup–cleanup mirror rule

For every "acquire" in setup, there is a matching "release" in cleanup, **in reverse order**. If B depends on A, close B before A.

```jsx
// ✅ Symmetric
useEffect(() => {
  const a = openA();
  const b = openB(a);
  const c = openC(b);
  return () => {
    closeC(c);
    closeB(b);
    closeA(a);
  };
}, []);
```

Reverse order matters when resources have dependencies: closing `A` before `C` might invalidate a handle `C` still holds, causing an error inside `closeC`. Mirror the acquisition order and dependencies unwind cleanly.

---

## Detached-DOM memory leaks

A common leak pattern: a component subscribes an event listener to a DOM node, but stores a reference to the node in a closure that outlives the mount (e.g., in a module-level array, a Redux store, or an EventEmitter registered outside React). Even after the component unmounts and React removes the node from the document, the reference in the outside store keeps the entire subtree alive.

In Chrome DevTools Memory Profiler:

- Take a heap snapshot after the leaky flow (mount → unmount → interact).
- Filter for `Detached HTMLDivElement` (or the specific element type).
- Expand the **Retainers** panel — the path leads back to the module, store, or emitter still holding the node.
- The retainer is where your leak is.

Fixes:

- Don't retain the node in outside stores at all; hold data, not DOM references.
- If the outside store *must* hold a reference for the mount's duration, explicitly clear it in the effect's cleanup: `return () => { store.detach(nodeId); };`
- Prefer `WeakRef` / `WeakMap` for cache-like structures that hold DOM nodes.

---

## Race conditions on rapid re-mount

```jsx
// ❌ Stale promise resolves after unmount, calls setUser on unmounted component
// React logs a warning in dev, silent in prod, but the setState is a no-op.
// Worse: if the fetch has side effects (analytics, logging), they still fire.
useEffect(() => {
  fetchUser(id).then(setUser);
}, [id]);
```

```jsx
// ✅ Either AbortController or ignore flag (see Category 3)
useEffect(() => {
  const ctrl = new AbortController();
  fetchUser(id, { signal: ctrl.signal }).then(setUser).catch(() => {});
  return () => ctrl.abort();
}, [id]);
```

Rapid re-mount is common on route changes, list virtualization, and any UI where the user can flip between items quickly. Without guarding the async result you get non-deterministic UI — the "last one wins" order depends on network jitter, not user intent.

---

## Anti-patterns

| Bad | Fix |
|-----|-----|
| Cleanup that closes over `.current` of a ref that changed between setup and cleanup | Store the value in a local variable at setup time and close over the local |
| Cleanup that awaits before releasing (`return async () => { await …; unsub(); }`) | Cleanup must be synchronous; React ignores the returned promise |
| Assuming cleanup runs before the next effect setup — it does, but on the same commit, only for the changed deps | Understand [[React Lifecycle - Effect Ordering]] |
| Forgetting cleanup on `<Activity>` remount — hidden mode unmounts effects but the component is still there | Effect setup + cleanup must be symmetric, even for Activity-hidden components |
| Registering the same DOM listener on every render because dep array is missing | Correct the dep array; keep the handler stable or wrap in `useEffectEvent` |
| Using an inline arrow in both `addEventListener` and `removeEventListener` | Extract the handler into a `const` so both calls receive the same reference |

The ref-cleanup trap in code:

```jsx
// ❌ ref.current may have changed by the time cleanup runs
useEffect(() => {
  observer.observe(nodeRef.current);
  return () => observer.unobserve(nodeRef.current);
}, []);
```

```jsx
// ✅ Capture the node at setup time
useEffect(() => {
  const node = nodeRef.current;
  if (!node) return;
  observer.observe(node);
  return () => observer.unobserve(node);
}, []);
```

See [[React Lifecycle - Ref Lifecycle and Cleanup]] for the full ref pattern.

---

## Summary table

| Resource | Cleanup |
|----------|---------|
| Subscription | `return unsub` |
| Timer | `clearInterval` / `clearTimeout` |
| Fetch | `AbortController` (preferred) or ignore flag |
| DOM handle | Imperative teardown (`map.remove()`, `chart.destroy()`) |
| Event listener | `removeEventListener` |

---

## Related

- [[React Hooks - useEffect]] — the effect + cleanup pair
- [[React Lifecycle - StrictMode Double Invoke]] — the stress test that surfaces missing cleanup
- [[React Lifecycle - Effect Ordering]] — child-first cleanup order
- [[React Lifecycle - Suspense Lifecycle]] — Suspense-driven remount
- [[React Lifecycle - Ref Lifecycle and Cleanup]] — ref cleanup patterns
- [[React Lifecycle Guide]]
