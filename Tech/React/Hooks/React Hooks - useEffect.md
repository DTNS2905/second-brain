---
tags:
  - react
  - hooks
  - effects
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useEffect
---

# React Hooks — useEffect

> Synchronize a component with an **external system**. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useEffect(
  setup: () => void | (() => void),
  dependencies?: ReadonlyArray<unknown>
): void;
```

The setup function may return a **cleanup** function. Both may run multiple times.

---

## Dependency array behavior

| Form | Runs setup |
|------|-----------|
| `useEffect(fn)` — omitted | After every commit |
| `useEffect(fn, [])` — empty | After the initial commit only (cleanup on unmount) |
| `useEffect(fn, [a, b])` — deps | Initial commit + whenever `a` or `b` changes (`Object.is`) |

---

## Cleanup contract

Cleanup runs:
1. **Before the next setup**, whenever deps change.
2. **On unmount.**
3. In Strict Mode dev, one **extra setup + cleanup cycle** runs before the first real setup — a stress test to verify cleanup mirrors setup.

If Strict Mode double-fires break your effect, your cleanup is incomplete — fix the effect, don't disable Strict Mode.

---

## When to use — external system sync

- Connecting to a chat / WebSocket / socket.io server.
- Subscribing to browser APIs: `resize`, `online`, `storage`, `IntersectionObserver`.
- Controlling a non-React widget (jQuery plugin, `<video>`, Leaflet map).
- Setting up timers (`setInterval`) — with cleanup.

The mental model: *"my component reflects some external state; the effect keeps them in sync."*

---

## When NOT to use — "You Might Not Need an Effect"

React's docs list a full page of anti-patterns. The core question: **"Why does this code need to run?"** If the answer is *"because the user did X"*, put it in an event handler, not an effect.

Common misuse and fixes:

| Anti-pattern | Fix |
|--------------|-----|
| Derive state from props/state in an effect | Compute during render |
| Cache expensive computation via effect + state | [[React Hooks - useMemo]] |
| Reset state when a prop changes | Pass `key={id}` to the child |
| Chain of effects: `A → setB → effect on B → setC` | Compute all next state in one event handler |
| Send POST on click via effect | Put fetch in the click handler |
| Notify parent of change via effect | Call parent callback in the same handler |
| Subscribe to external store manually | [[React Hooks - useSyncExternalStore]] |
| Initialize app (analytics, i18n) in effect | Do at module top level, or a guarded `didInit` flag |
| Fetch data | Add `ignore` flag cleanup — or use a framework loader / data lib |

Source: https://react.dev/learn/you-might-not-need-an-effect

---

## Minimal correct example

```tsx
useEffect(() => {
  const connection = createConnection(serverUrl, roomId);
  connection.connect();
  return () => connection.disconnect();
}, [serverUrl, roomId]);
```

Setup connects; cleanup disconnects. React re-runs both when `serverUrl` or `roomId` changes.

---

## Anti-pattern: fetch without a race guard

```jsx
// ❌ Rapid input changes let old responses overwrite new ones
useEffect(() => {
  fetchResults(query).then(json => setResults(json));
}, [query]);
```

```jsx
// ✅ Ignore stale responses
useEffect(() => {
  let ignore = false;
  fetchResults(query).then(json => {
    if (!ignore) setResults(json);
  });
  return () => { ignore = true; };
}, [query]);
```

---

## Object / function dependencies

Inline objects and functions get a **new reference every render** — they invalidate the effect every time.

```jsx
// ❌ Effect runs every render
const config = { timeout: 3000 };
useEffect(() => fetchWith(config), [config]);
```

```jsx
// ✅ Move inside the effect, or memoize
useEffect(() => {
  const config = { timeout: 3000 };
  fetchWith(config);
}, []);
```

See [[React Re-renders - useMemo and useCallback]] for the memoized version.

---

## Caveats

- **Client only.** Effects never run during SSR.
- Non-interaction effects may run **after** paint — good, they don't block visible frames.
- `setState` identity from `useState` / `useReducer` is stable — never needs to be in the deps.
- If linter complains about missing deps, don't silence it — either add the dep or move code out of the effect.

---

## Timing map

| Phase | What runs |
|-------|-----------|
| Render (pure) | Your component function |
| Commit | DOM updated, refs attached |
| `useInsertionEffect` | (library-only) inject styles |
| `useLayoutEffect` | Sync DOM read/write before paint |
| **Browser paints** | User sees the frame |
| **`useEffect`** | Non-blocking external-system sync |

See [[React Hooks - useLayoutEffect]] when you need to block paint.

---

## Related

- [[React Hooks - useLayoutEffect]] — same shape, blocks paint, use only for sync DOM measurement
- [[React Hooks - useSyncExternalStore]] — the correct hook for external stores
- [[React Hooks - useState]] — how state updates from effects flow
- [[React Hooks - Rules of Hooks]]
