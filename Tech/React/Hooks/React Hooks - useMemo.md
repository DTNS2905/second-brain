---
tags:
  - react
  - hooks
  - performance
  - memoization
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useMemo
---

# React Hooks — useMemo

> Cache the **result of a calculation** across renders. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useMemo<T>(calculateValue: () => T, dependencies: DependencyList): T;
```

`calculateValue` must be pure and take no arguments. React caches the return value; on subsequent renders it re-invokes only when a dependency changes (`Object.is` compare).

---

## When it actually pays off — only these three cases

### 1. Genuinely expensive calculation

Measure first — don't guess.

```ts
console.time('filter');
const visible = filterTodos(todos, tab);
console.timeEnd('filter');
```

- `< 1ms` → don't memoize.
- Consistently `> 1ms` → memoize.

Test with **CPU throttling** and a **production build**. `useMemo` never speeds up the first render — only subsequent ones.

### 2. Prop passed to a `React.memo` child

Without memoization, `filterTodos(...)` returns a new array reference each render and defeats the `memo` wrapper:

```jsx
const List = memo(function List({ items }) { /* ... */ });

// ✅ Stable reference — memo actually skips re-renders
const visible = useMemo(() => filterTodos(todos, tab), [todos, tab]);
<List items={visible} />
```

See [[React memo - Stable Props]].

### 3. Dependency of another hook

Memoize an object before using it in `useEffect`/`useMemo`/`useCallback` deps to prevent the hook from re-running each render.

```jsx
// ❌ Effect fires every render — new config reference each time
const config = { timeout: 3000 };
useEffect(() => connect(config), [config]);

// ✅ Memoized dep
const config = useMemo(() => ({ timeout: 3000 }), []);
useEffect(() => connect(config), [config]);
```

---

## "Should you add useMemo everywhere?" — No

> From the docs: *"You should only rely on `useMemo` as a performance optimization. If your code doesn't work without it, find the underlying problem and fix it first."*

Downsides of over-memoization:
- Adds noise to every component.
- A single "always new" dependency invalidates the cache anyway.
- Memory overhead grows with the number of memos.

Prefer these strategies **first**:

| Strategy | Note |
|----------|------|
| Pass JSX as `children` | [[React Component Composition - Children as Props]] |
| Keep state local | Don't lift higher than needed |
| Move objects INTO effects | Instead of memoizing them just for deps |
| Fix impure renders | Don't paper over them with memo |
| Enable React Compiler | Auto-memoizes — makes `useMemo` largely unnecessary |

---

## When NOT to use

- Cheap arithmetic, string concatenation, small array ops.
- Values that change every render (defeats the cache).
- Inside loops or conditionals — violates [[React Hooks - Rules of Hooks]].

---

## Minimal correct example

```tsx
function TodoList({ todos, tab, theme }: Props) {
  const visibleTodos = useMemo(
    () => filterTodos(todos, tab),
    [todos, tab]
  );

  return (
    <div className={theme}>
      <List items={visibleTodos} />
    </div>
  );
}
```

---

## Anti-pattern: arrow-body braces without return

```jsx
// ❌ Braces make this a block — returns undefined
const opts = useMemo(() => {
  matchMode: 'whole-word',
  text,
}, [text]);
```

```jsx
// ✅ Parenthesized object literal — implicit return
const opts = useMemo(() => ({ matchMode: 'whole-word', text }), [text]);

// ✅ Or explicit return
const opts = useMemo(() => {
  return { matchMode: 'whole-word', text };
}, [text]);
```

Very easy TypeScript trap — the first form compiles but silently returns undefined.

---

## Anti-pattern: memoizing when there's no memo child

```jsx
// ❌ Child is not memoized — memo does nothing, useCallback overhead wasted
const Child = ({ data }) => <div>{data.name}</div>;
const data = useMemo(() => ({ name }), [name]);
<Child data={data} />
```

```jsx
// ✅ Just compute normally
<Child data={{ name }} />
```

`useMemo` only helps when a downstream check (memo shallow compare, effect dep compare) actually inspects the reference.

---

## Caveats

- Strict Mode calls `calculateValue` **twice in dev** — keep it pure.
- `Object.is` equality on dependencies triggers cache re-computation.
- React may **discard** the cache on its own (e.g., off-screen suspended content). Don't rely on `useMemo` as a data store — it's a hint, not a promise.
- Cannot be called conditionally.

---

## Summary decision tree

```
Do you have a real perf problem?
  ├── Profile first (DevTools → Profiler)
  ├── Yes, calculation > 1ms and runs often
  │     └── useMemo it
  ├── Yes, prop invalidates a React.memo child
  │     └── useMemo it (and memoize all other non-primitive props)
  ├── Yes, dep of another hook that fires too often
  │     └── useMemo it, or move the value inside the hook
  └── No visible problem, just "future-proofing"
        └── Don't. Let React Compiler handle it.
```

---

## Related

- [[React Hooks - useCallback]] — same idea for functions
- [[React memo Guide]] — the pairing that makes useMemo pay off
- [[React Re-renders - useMemo and useCallback]] — usage in re-render prevention
- [[React memo - Stable Props]]
- [[React Hooks - Rules of Hooks]]
