---
tags:
  - react
  - performance
  - frontend
  - memoization
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# Preventing Re-renders with React.memo

> Part 3 of [[React Re-renders Guide]]

---

## What React.memo Does

Wrapping a component in `React.memo` stops the downstream re-render chain triggered upstream — **unless the component's own props have changed**.

```jsx
const MemoizedComponent = React.memo(HeavyComponent);
```

Use it for **heavy components** that are independent of frequent upstream state changes.

---

## Rule: All Non-Primitive Props Must Be Memoized

`React.memo` uses **shallow comparison** on props. Objects, arrays, and functions are compared by *reference* — a new reference = a new value even if content is identical.

```jsx
// ❌ BAD — `data` is a new object on every parent render → memo is useless
const Parent = () => {
  return <MemoizedChild data={{ id: 1 }} />;   // new object ref every render
};

// ✅ GOOD — memoize non-primitive props
const Parent = () => {
  const data = useMemo(() => ({ id: 1 }), []);
  return <MemoizedChild data={data} />;
};
```

> If even **one** prop is non-memoized, `React.memo` won't prevent re-renders.

---

## Rule: memo Must Be Applied to Children/Props Elements Directly

Memoizing a *parent* does **not** protect children passed as props.

```jsx
// ❌ WRONG — memoizing Parent doesn't help; children are objects that change
const MemoizedParent = React.memo(({ children }) => <div>{children}</div>);

const GrandParent = () => (
  <MemoizedParent>
    <HeavyChild />   {/* new React element object on every GrandParent render */}
  </MemoizedParent>
);

// ✅ CORRECT — memo applied to the actual component you want to protect
const MemoizedChild = React.memo(HeavyChild);

const GrandParent = () => (
  <ParentWrapper>
    <MemoizedChild />
  </ParentWrapper>
);
```

---

## When to Use React.memo

| Scenario | Use React.memo? |
|----------|-----------------|
| Heavy component, parent re-renders often | ✅ Yes |
| Component with only primitive props | ✅ Safe and effective |
| Component with object/array/function props (unmemoized) | ❌ Ineffective — memoize props first |
| Light component that re-renders cheaply | ❌ Overhead not worth it |
| Component always receives new props anyway | ❌ No benefit |

---

## How It Connects to Other Patterns

- Before using `React.memo`, try composition patterns: [[React Re-renders - Preventing with Composition]]
- For memoizing non-primitive props to make `React.memo` work: [[React Re-renders - useMemo and useCallback]]
