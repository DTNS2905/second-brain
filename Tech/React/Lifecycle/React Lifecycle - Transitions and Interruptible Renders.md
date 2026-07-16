---
tags:
  - react
  - lifecycle
  - concurrency
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/useTransition
---

# React Lifecycle — Transitions and Interruptible Renders

> Concurrent rendering shatters the "every render becomes a commit" assumption. A transition may be started, interrupted, and discarded many times before it commits — meaning your render function is a query, not a fact. Part of [[React Lifecycle Guide]].

---

## Priority lanes

React schedules every update onto one of four internal *lanes*. The lane determines whether the render can be interrupted, and by what.

| Lane | Trigger | Interruptible? |
|------|---------|----------------|
| Sync | Discrete input (click, keypress) | No — commits before the browser paints |
| Default | Setstate in a normal event handler | No, but can be superseded |
| Transition | `startTransition(() => setState(…))` | Yes — can be interrupted by higher priority |
| Idle | React internal (Suspense retries, etc.) | Yes |

The lane concept exists precisely so that a user typing in an input (sync) is never blocked by an expensive downstream re-render (transition). Sync always wins. Cross-link `[[React Reconciliation - Virtual DOM and Fiber]]` for how the reconciler maps lanes onto Fiber work.

---

## What "interruptible" actually means

During a transition render, React may:

- **Start** rendering a component tree with new state
- **Pause** to yield to the browser
- **Discard** the WIP tree if a higher-priority update arrives
- **Restart** from scratch with the new state

If the tree is discarded before commit:

- No DOM mutations happen
- No effects run
- No cleanup runs (there was no setup to clean up)
- **The render is as if it never happened** — except for any side effects your component function had (which is why render must be pure)

The WIP (work-in-progress) tree lives entirely in memory. React can build it, throw it away, and start again without any observable DOM change. That's the whole point: the *commit* is the only observable event; renders are speculation.

---

## Render must be pure

Purity is the rule that's unavoidable under concurrency. Your component function may be called:

- Once and committed (normal)
- Twice and committed on the second (StrictMode — see [[React Lifecycle - StrictMode Double Invoke]])
- Many times and never committed (interrupted transitions)
- Then discarded and re-run with different state

Any side effect during render body will fire on every one of those speculative runs.

```jsx
// ❌ Side effect in render body — analytics fires on interrupted renders, doubles in StrictMode
function Search({ query }: Props) {
  analytics.searchAttempt(query);
  return <Results q={query} />;
}
```

```jsx
// ✅ Side effect moved to event handler (source of truth) or effect (commit-gated)
function Search({ query }: Props) {
  useEffect(() => {
    analytics.searchAttempt(query);
  }, [query]);
  return <Results q={query} />;
}
```

The rule of thumb: **if it must happen exactly as many times as the user perceived the event, put it in an event handler. If it must reflect committed state, put it in an effect. Never put it in the render body.**

---

## `isPending` is not part of the transition it reports

Subtle detail. `const [isPending, startTransition] = useTransition();` — `isPending` flips to `true` **urgently** (sync/default lane), while the wrapped update is a transition. This means:

- The frame with `isPending: true` and old content commits *immediately*
- The transition renders in the background
- When the transition commits, `isPending` flips back to `false` and new content shows

```jsx
const [q, setQ] = useState('');
const [isPending, startTransition] = useTransition();

function onChange(e) {
  startTransition(() => setQ(e.target.value));
  // At this point, isPending is being set to true urgently
  // setQ is running in the transition lane
}

return (
  <>
    <input onChange={onChange} />
    {isPending && <span>Updating…</span>}
    <Results q={q} />
  </>
);
```

If `isPending` were itself a transition, the loading indicator would never appear during a fast-scrolling interruption — because the transition it lives inside would keep getting discarded. React deliberately splits it into two updates on two lanes so the spinner is guaranteed to paint.

---

## `useSyncExternalStore` prevents tearing

"Tearing" is when different parts of the UI show different values from the same external store during a concurrent render — some subtrees read the store *before* an update, others read it *after*, and the committed frame shows a mix. React can't guarantee consistency for stores it doesn't know about — hence the `useSyncExternalStore` hook, which reads the store synchronously at a well-defined moment and forces a re-render if the store changed mid-render.

```jsx
// ❌ Reading external store directly in render — subject to tearing under transitions
function Counter() {
  const value = store.getState().count;
  return <span>{value}</span>;
}
```

```jsx
// ✅ Redux, Zustand, and other external stores use this internally
const value = useSyncExternalStore(
  store.subscribe,
  store.getSnapshot,
  store.getServerSnapshot
);
```

Cross-link `[[React Hooks - Store and Utility Hooks]]` for the full API. The mechanism: React re-checks the snapshot after the interruptible render finishes and bails out (re-renders) if the store changed while the transition was mid-flight.

---

## Concurrent renders and effects

Effect setup fires **only on committed renders**. Interrupted renders never trigger cleanup because there was no setup. This means:

- A component may run its function 5 times during a transition, but its effects fire once (on the successful commit)
- Cleanup runs once, when the committed effect is superseded or the component unmounts
- There's no "setup for the interrupted render" that leaks

Result: **effects are commit-gated, so effects are safe under concurrency**. Render-body side effects are not.

```jsx
// ✅ Subscription in effect — fires once per commit, regardless of how many WIP renders were discarded
function Live({ channel }: Props) {
  useEffect(() => {
    const sub = channel.subscribe(handler);
    return () => sub.unsubscribe();
  }, [channel]);
  return <Feed />;
}
```

Compare to the render-body version, which would open a subscription for every interrupted render and never clean any of them up because cleanup only pairs with committed setups. See [[React Lifecycle - Effect Ordering]] for how effect scheduling interacts with the commit phase.

---

## The mental model shift

Old model (class components): *"render was called → the DOM changed → `componentDidUpdate` ran."* Every `render()` call implied a commit was coming.

New model (concurrent React): **"render is a query. Commit is a fact."** A render is a hypothetical — *"if this state were committed, what would the DOM look like?"* React uses that answer to decide whether to commit. If a higher-priority update arrives first, the hypothetical is discarded and nothing observable happens.

This is why:

- Render must be pure (React runs it speculatively)
- Effects run after commit (only reflect committed state)
- Refs attach on commit (only reflect committed DOM — see [[React Lifecycle - Ref Lifecycle and Cleanup]])

The same principle explains behavior across the framework — see [[React Lifecycle - Mental Model]] for the fuller treatment.

---

## Anti-patterns under concurrency

Everything in this table is a way of assuming render implies commit — the assumption concurrent React explicitly breaks.

| Anti-pattern | Why it breaks |
|--------------|---------------|
| Mutating a ref during render | Ref mutation is a side effect; runs on interrupted renders too |
| Reading `Date.now()` / `Math.random()` in render and expecting stability | Fine per render, but different renders see different values → tearing |
| Reading an external store directly (`store.getState()`) in render | No sync guarantee; use `useSyncExternalStore` |
| Fetching data in render body | Fetches on every discarded render → thundering herd |
| Assuming component instance identity (via ref-capture) will survive interruption | Component may not commit at all |

```jsx
// ❌ Ref mutation in render — increments once per WIP render, not once per commit
function BadCounter() {
  const renderCount = useRef(0);
  renderCount.current++;
  return <span>{renderCount.current}</span>;
}
```

```jsx
// ✅ Increment in effect — one increment per committed render
function GoodCounter() {
  const renderCount = useRef(0);
  useEffect(() => {
    renderCount.current++;
  });
  return <span>{renderCount.current}</span>;
}
```

---

## When to reach for `useTransition` vs `useDeferredValue`

Both mark updates as non-urgent. The difference is *who owns the setter*.

- `useTransition` wraps a **state update** (you own the setter call)
- `useDeferredValue` wraps a **value** (you receive a value from a parent whose setter you can't touch)

```jsx
// useTransition — you control the setter
const [isPending, startTransition] = useTransition();
function onSearch(q) {
  startTransition(() => setQuery(q));
}
```

```jsx
// useDeferredValue — you receive q from a parent
function Results({ q }: { q: string }) {
  const deferredQ = useDeferredValue(q);
  return <ExpensiveList q={deferredQ} />;
}
```

Rule of thumb: if you can wrap the setter, use `useTransition` — it gives you `isPending` for free. If the value is coming in as a prop or context and you can't reach the setter, use `useDeferredValue`. Cross-link `[[React Hooks - useTransition]]`, `[[React Hooks - useDeferredValue]]`.

---

## Closing thought

**Render is a query. Commit is a fact.**

If you internalize this, everything else falls out: purity of render, why refs and effects wait for commit, why StrictMode is a friend not a foe, why Suspense can suspend without leaking, why transitions can be discarded without corrupting state. The whole concurrent-React lifecycle is a single principle applied consistently — the render function answers a hypothetical, and only commits become part of the world.

---

## Related

- [[React Hooks - useTransition]] — the transition API
- [[React Hooks - useDeferredValue]] — the value-based counterpart
- [[React Hooks - Store and Utility Hooks]] — useSyncExternalStore for external stores
- [[React Reconciliation - Virtual DOM and Fiber]] — lane priorities in the reconciler
- [[React Lifecycle - Suspense Lifecycle]] — the fourth state (previous in reading order)
- [[React Lifecycle Guide]]
