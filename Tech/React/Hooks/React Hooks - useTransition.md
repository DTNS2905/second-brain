---
tags:
  - react
  - hooks
  - concurrency
  - performance
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useTransition
---

# React Hooks — useTransition

> Mark a state update as **non-blocking** and keep the UI responsive during expensive re-renders. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useTransition(): [
  isPending: boolean,
  startTransition: (action: () => void | Promise<void>) => void
];
```

Returns:
- `isPending` — `true` while the transition is committing.
- `startTransition` — wraps a setter to mark its updates as transitions. **Stable identity** — safe to omit from effect deps.

---

## Semantics

```jsx
startTransition(() => {
  setTab('posts');       // marked as transition — interruptible, low-priority
  setFilter('recent');   // also marked
});
```

- The wrapped function runs **immediately and synchronously**.
- Updates queued inside are **lower priority** than urgent updates (typing, clicks).
- Transitions can be **interrupted** — if the user types while a heavy chart is transitioning, React discards the in-progress work and restarts.
- With `async` actions, only setters **before the first `await`** are auto-marked. Wrap post-await setters in another `startTransition`.

`isPending` flips to `true` at the first `startTransition(...)` call, stays `true` until every state update queued inside commits.

---

## When to use

- **Tab switching** where the new tab is expensive to render.
- **Router navigation** — keep the current page interactive while the next one renders.
- Any expensive state update triggered by a user action (filtering large lists, chart re-layout).
- Preventing loading spinners from replacing already-visible content.

---

## When NOT to use

- **Controlled input values.** `startTransition(() => setText(e.target.value))` makes the input feel laggy because the visible text lags behind. Instead:
  - Use two state variables (urgent input, deferred derived state), or
  - Reach for [[React Hooks - useDeferredValue]].
- **Outside a component** — use the standalone `startTransition` import (no `isPending`).
- **Non-state work** (network requests) — transitions only affect React state updates. Fetches still fire immediately.

---

## Minimal correct example

```tsx
function TabContainer() {
  const [isPending, startTransition] = useTransition();
  const [tab, setTab] = useState<'about' | 'posts' | 'contact'>('about');

  function selectTab(next: typeof tab) {
    startTransition(() => setTab(next));
  }

  return (
    <>
      <TabButton onClick={() => selectTab('posts')}>Posts</TabButton>
      <div style={{ opacity: isPending ? 0.7 : 1 }}>
        {tab === 'posts' && <SlowPosts />}
      </div>
    </>
  );
}
```

Clicking a tab **doesn't freeze** the UI — the current tab stays interactive while React renders the new one in the background.

---

## Anti-pattern: transitioning a controlled input

```jsx
// ❌ Input feels laggy — the visible text updates AFTER the transition
function Search() {
  const [, startTransition] = useTransition();
  const [text, setText] = useState('');
  return (
    <input
      value={text}
      onChange={(e) => startTransition(() => setText(e.target.value))}
    />
  );
}
```

```jsx
// ✅ Input value updates urgently; the deferred derived state can lag
function Search() {
  const [text, setText] = useState('');
  const deferredText = useDeferredValue(text);
  return (
    <>
      <input value={text} onChange={(e) => setText(e.target.value)} />
      <ExpensiveResults query={deferredText} />
    </>
  );
}
```

---

## useTransition vs useDeferredValue

Both use the same concurrent-rendering priority system. They differ in **which side of the value you control**:

|  | `useTransition` | `useDeferredValue` |
|---|-----------------|--------------------|
| Wraps | The **setter** call | The **value** you receive |
| You own | The state update site | Only how you use the value |
| Gives you | `isPending` flag | Manual staleness check (`v !== deferred`) |
| Best when | You're calling `setX` yourself | Value comes from a prop or hook |

See [[React Hooks - useDeferredValue]] for the paired hook.

---

## Standalone `startTransition`

For calling outside a component (no `isPending`):

```jsx
import { startTransition } from 'react';

function onSelect(next) {
  startTransition(() => setTab(next));
}
```

Same semantics as the returned one, but no pending flag.

---

## Caveats

- Transitions batch multiple `setX` calls that happen synchronously inside the wrapper.
- `isPending` itself is an **urgent** state update — flipping it back to `false` isn't part of the transition.
- If a transition triggers a Suspense boundary that has already committed content, React will render the fallback **only** for new items — existing content stays visible.
- Cannot be called conditionally.

---

## Related

- [[React Hooks - useDeferredValue]] — value-based counterpart
- [[React Hooks - React 19 Actions Hooks]] — `useActionState` / `useOptimistic` build on transitions
- [[React Hooks - useState]] — the underlying setters you wrap
