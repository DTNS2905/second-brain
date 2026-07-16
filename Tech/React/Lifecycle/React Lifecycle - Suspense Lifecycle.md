---
tags:
  - react
  - lifecycle
  - concurrency
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/Suspense
---

# React Lifecycle — Suspense Lifecycle

> Suspense adds a fourth lifecycle state — "suspended" — that sits between rendering and committed. State is preserved across suspend/resume; effects behave as if the suspended tree were still mounted. Part of [[React Lifecycle Guide]].

---

## The Suspense state machine

A component under a `<Suspense>` boundary can move through these states in one render cycle:

```
rendering
  ↓  (child throws a promise, or use(promise) reads pending)
suspended
  ↓  (React commits the fallback tree)
fallback-committed
  ↓  (promise resolves; React schedules re-render)
re-rendering
  ↓  (child now returns a value; boundary re-renders normally)
committed
```

Key properties of this machine:

- The transition into `suspended` is synchronous — throwing a promise unwinds the current render, it does not schedule anything.
- The fallback is a real commit: React runs layout and effects for the fallback subtree.
- The re-render on resume preserves state for the boundary's siblings and for the suspended subtree itself, because React never unmounted them — it just hid the DOM while waiting.

---

## What triggers a suspend

A component "suspends" when it can't finish rendering yet. The mechanism is a thrown Promise, but the ergonomic surface varies:

- A descendant throws a Promise (used to be `React.lazy` internals only; now surfaced via the `use(promise)` API)
- A descendant calls `use()` on a pending Promise
- A descendant reads from a data source that suspends (React Query with `suspense: true`, Relay, Apollo with a Suspense adapter)

```jsx
// React 19: use() a promise directly
function Profile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise);  // suspends until resolved
  return <div>{user.name}</div>;
}
```

`use()` is the first hook that is allowed inside conditions and loops, precisely because it participates in the Suspense machinery rather than the hook-index machinery.

---

## What happens to already-mounted siblings inside the boundary

Critical rule: when a component inside a `<Suspense>` boundary suspends, React re-renders the boundary and shows the fallback. But **already-mounted siblings and unrelated subtrees are NOT unmounted** — React holds their fiber tree in memory, hides the DOM (via `display: none` on the boundary content), and resumes on unsuspend.

The accurate statement of the guarantee:

- **State is preserved** across suspend/resume — component-local `useState`, `useRef`, and context subscriptions survive.
- **Effects on the boundary itself** run based on visibility toggles (the fallback commits, then unmounts; the real content commits when data resolves).
- **Effects inside the suspended subtree** run once the tree finally commits with real content — never during the suspended phase, because the subtree never committed.

That means the boundary itself has a normal mount/unmount lifecycle for its two children (fallback and content), but the *suspended content subtree* is treated as "not yet mounted" until data resolves.

---

## New content vs existing content

Suspense's default behavior differs depending on whether the boundary already has committed real content:

- **New content suspends**: fallback shows immediately.
- **Existing content suspends**: by default the boundary shows the fallback (which unmounts existing DOM). To keep existing content visible while new content loads, wrap the state update in `useTransition` or use `useDeferredValue`.

```jsx
// ❌ Existing content flashes fallback when the user types a new query
function Search() {
  const [q, setQ] = useState('');
  return (
    <>
      <input value={q} onChange={e => setQ(e.target.value)} />
      <Suspense fallback={<Spinner />}>
        <SearchResults q={q} />  {/* suspends on every keystroke */}
      </Suspense>
    </>
  );
}
```

```jsx
// ✅ useTransition marks the update as non-urgent — existing content stays visible
function Search() {
  const [q, setQ] = useState('');
  const [isPending, startTransition] = useTransition();
  function onChange(e) {
    startTransition(() => setQ(e.target.value));
  }
  return (
    <>
      <input defaultValue={q} onChange={onChange} />
      {isPending && <InlineSpinner />}
      <Suspense fallback={<Spinner />}>
        <SearchResults q={q} />
      </Suspense>
    </>
  );
}
```

React tracks the transition and keeps the previous SearchResults committed while the new one resolves in the background. See [[React Lifecycle - Transitions and Interruptible Renders]] for how transitions interact with the scheduler.

---

## Effect timing for suspended trees

Effects **do not run** while a component is inside a suspended subtree — because the component is not committed. The setup runs when the boundary commits with real content. Cleanup runs on unmount as usual.

```jsx
function DataFetcher({ userId }: Props) {
  const user = use(fetchUser(userId));  // suspends
  useEffect(() => {
    // This effect does NOT run while suspended;
    // runs once user resolves and this component commits
    analytics.viewProfile(user.id);
  }, [user.id]);
  return <div>{user.name}</div>;
}
```

The corollary: **do not put data-fetching side effects in `useEffect` and expect Suspense to coordinate them.** If the fetch lives in an effect, the component has already committed by the time the fetch starts — Suspense never sees it. Cross-link [[React Lifecycle - Effect Ordering]] for the general commit-then-effect flow.

---

## The `<Activity>` API (React 19)

`<Activity mode="visible" | "hidden">` lets React keep a tree mounted (state preserved) but hide it (effects unmounted). Different from Suspense: Suspense is triggered by children requesting data; Activity is toggled by the parent.

```jsx
<Activity mode={isVisible ? "visible" : "hidden"}>
  <ExpensiveTree />
</Activity>
```

Behavior:

- When mode flips from **visible to hidden**: effects run cleanup (like unmount), state is preserved.
- When mode flips from **hidden to visible**: effects run setup (like re-mount).

Result: your effect setup/cleanup pair must be idempotent — this is the same idempotence contract StrictMode surfaces. Cross-link [[React Lifecycle - StrictMode Double Invoke]].

Practical uses:

- Tab UIs where you want to keep the tab's scroll position, form state, and network subscriptions dormant.
- Off-screen routes in a router that wants to prewarm without paying effect costs.

Activity is the explicit, parent-controlled version of what Suspense does implicitly during a suspend/resume.

---

## `use(promise)` vs `useEffect` fetching

```jsx
// ❌ Fetch in useEffect: async, no built-in suspend, race conditions, waterfalls
function Profile({ id }: Props) {
  const [user, setUser] = useState<User | null>(null);
  useEffect(() => {
    let ignore = false;
    fetchUser(id).then(u => { if (!ignore) setUser(u); });
    return () => { ignore = true; };
  }, [id]);
  if (!user) return <Spinner />;
  return <div>{user.name}</div>;
}
```

```jsx
// ✅ use(promise): React suspends automatically, Suspense shows fallback, no race
function Profile({ id }: Props) {
  const user = use(fetchUser(id));   // Suspense boundary above handles loading UI
  return <div>{user.name}</div>;
}
```

The `use()` pattern requires:

- A Suspense boundary as an ancestor.
- The promise reference must be **stable across renders** (create it outside the component, hoist it into a parent, or use a data lib that dedupes by cache key). A naked `use(fetch(id))` in the render body creates a new promise every render and will suspend forever.

---

## Refreshing suspended data with `key`

The `key` prop reset trick: change the key on a boundary or on the component that reads data, and React treats it as a new fiber → unmount + remount → refetch.

```jsx
function UserPage({ id }: Props) {
  const [reloadKey, setReloadKey] = useState(0);
  return (
    <>
      <button onClick={() => setReloadKey(k => k + 1)}>Refresh</button>
      <Suspense fallback={<Spinner />}>
        <UserProfile key={reloadKey} id={id} />
      </Suspense>
    </>
  );
}
```

Why this works: a new key means a new fiber identity. The old fiber unmounts (running cleanup), the new one mounts, and since the promise passed to `use()` is derived from the id + reload key, the cache miss triggers a fresh fetch and a fresh suspend. See [[React Reconciliation - Keys]] for the underlying identity semantics.

---

## Streaming SSR and Suspense

With React 18+ streaming SSR, `<Suspense>` boundaries flush independently. The initial HTML includes the fallback; when the data resolves on the server, React streams the real content and swaps it in on the client. This means Suspense is a *build-time and network-time* concept, not just a runtime one.

Consequences for the lifecycle model:

- Server components inside a boundary can suspend without blocking the shell — the shell hydrates immediately and the streamed chunks hydrate as they arrive.
- The client-side lifecycle for a streamed subtree is: hydrate fallback → receive streamed HTML → hydrate real content → run effects. Effects still respect the commit-then-effect rule.

Cross-link `[[Web Rendering Patterns - SSR]]` (if it exists in the vault) and `[[Build Tools Meta-frameworks - RSC and the Bundler]]` (future).

---

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Creating a new promise inline every render (`use(fetchUser(id))`) | Cache the promise: use a data lib, hoist the promise to a parent, or `useMemo` for the same input |
| Expecting effects to run while suspended | Effects run only after commit — pull data via `use()` instead of fetching in `useEffect` |
| Suspense boundary too high — whole page flashes fallback | Add finer-grained boundaries around the specific data-reading subtree |
| Ignoring `useTransition` for existing-content updates | Wrap non-urgent updates in `startTransition` so the previous UI stays visible |
| Assuming state resets on suspend | State is preserved — if you need a reset, change the `key` |
| Firing analytics from a `useEffect` above the suspending child | The parent's effect fires before the child commits — move analytics into the resolved child |

---

## Related

- [[React Lifecycle - Transitions and Interruptible Renders]] — how transitions keep existing content visible (next in reading order)
- [[React Lifecycle - StrictMode Double Invoke]] — the idempotence contract Activity remounts share
- [[React Hooks - useTransition]] — non-blocking updates
- [[React Hooks - React 19 Actions Hooks]] — the `use` API in detail
- [[React Reconciliation - Keys]] — the key reset trick
- [[React Lifecycle Guide]]
