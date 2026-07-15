---
tags:
  - react
  - performance
  - frontend
  - memoization
  - hooks
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# useMemo and useCallback for Re-render Prevention

> Part 4 of [[React Re-renders Guide]]

---

## Core Rule

> `useMemo` and `useCallback` **do not prevent re-renders by themselves**.
> They only matter when the component is already wrapped with `React.memo`.

---

## Anti-pattern: Memoizing Props Without React.memo on Child

Memoizing a prop passed to a non-memoized component has **no effect** on re-renders.

```jsx
// ❌ USELESS — ChildComponent is not memoized, so it re-renders anyway
const Parent = () => {
  const onClick = useCallback(() => console.log('click'), []);
  return <ChildComponent onClick={onClick} />;
};
```

The child re-renders whenever the parent re-renders, regardless of prop stability.

---

## When useCallback / useMemo Are Necessary

### 1. As dependencies for other hooks

Non-primitive values used as `useEffect`, `useMemo`, or `useCallback` dependencies must be memoized — otherwise the hook re-runs on every render.

```jsx
// ❌ BAD — `config` is a new object each render → useEffect runs every render
const Component = () => {
  const config = { timeout: 3000 };
  useEffect(() => {
    fetchData(config);
  }, [config]);    // new reference every render!
};

// ✅ GOOD
const Component = () => {
  const config = useMemo(() => ({ timeout: 3000 }), []);
  useEffect(() => {
    fetchData(config);
  }, [config]);
};
```

### 2. As props for React.memo children

All non-primitive props passed to a `React.memo` component **must** be memoized, or the memo is pointless.

```jsx
const MemoizedChild = React.memo(({ data, onClick }) => <div>...</div>);

// ✅ ALL non-primitive props memoized → memo actually works
const Parent = () => {
  const data = useMemo(() => ({ id: 1 }), []);
  const onClick = useCallback(() => {}, []);
  return <MemoizedChild data={data} onClick={onClick} />;
};
```

---

## useMemo for Expensive Calculations

`useMemo` has overhead (memory + computation on mount). Only use it for genuinely expensive operations.

> "In React, mounting and updating components is the most expensive calculation in most cases."

### Primary use case: memoizing React elements

```jsx
// ✅ Useful — expensive element tree from a map
const list = useMemo(
  () => items.map((item) => <HeavyItem key={item.id} item={item} />),
  [items]
);
```

Pure JS operations (sort, filter, map over plain data) are **usually cheap** — don't wrap them in `useMemo` preemptively.

---

## Decision Guide

```
Do you need useCallback/useMemo?
  ├── Is it a dep in useEffect/useMemo/useCallback?
  │     └── YES → memoize it
  └── Is it a prop for a React.memo component?
        ├── YES → memoize it (and ALL other non-primitive props)
        └── NO  → don't bother
```

---

## Related

- [[React Re-renders - Preventing with React.memo]] — requires memoized props to work
- [[React Re-renders - Preventing with Composition]] — prefer this first
