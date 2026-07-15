---
tags:
  - react
  - component-composition
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-elements-children-parents
---

# React Component Composition - Memoization with Children

> How React.memo and useCallback interact with children props — and why naive memoization often fails. Part of [[React Component Composition Guide]].

---

## Mystery 3: Memoizing the Parent Doesn't Help

**Scenario:** Parent (`SomeOutsideComponent`) has state; intermediate component is memoized.

```jsx
const MovingComponentMemo = React.memo(MovingComponent);

const SomeOutsideComponent = () => {
  const [state, setState] = useState();   // triggers re-render

  return (
    <MovingComponentMemo>
      <ChildComponent />    {/* Does this re-render? */}
    </MovingComponentMemo>
  );
};
```

**Answer: YES, `ChildComponent` re-renders.** Here's why:

```
SomeOutsideComponent re-renders (state change)
  → creates new element: <ChildComponent />  (new object reference)
  → passes it as children prop to MovingComponentMemo
  → React.memo compares old vs new children prop
  → old children !== new children (different object reference!)
  → memo fails → MovingComponent re-renders
  → ChildComponent re-renders
```

`React.memo` does a shallow comparison. A new `<ChildComponent />` element is a new object every render, so memo is bypassed.

---

## ✅ Fix: Memoize the Child Instead

```jsx
const ChildComponentMemo = React.memo(ChildComponent);

const SomeOutsideComponent = () => {
  const [state, setState] = useState();

  return (
    <MovingComponent>          {/* no need to memo the parent */}
      <ChildComponentMemo />   {/* memo on the child works */}
    </MovingComponent>
  );
};
```

Why this works:
```
SomeOutsideComponent re-renders
  → creates new element: <ChildComponentMemo /> (new object)
  → passes as children to MovingComponent
  → MovingComponent re-renders (no memo on it)
  → React processes <ChildComponentMemo />
  → ChildComponentMemo's props haven't changed → skips render ✅
```

Memo on the **rendered** component stops the re-render, regardless of how many wrapper re-renders happened.

---

## Mystery 4: useCallback on Render Function Children

```jsx
const SomeOutsideComponent = () => {
  const [state, setState] = useState();

  const renderChild = useCallback(() => <ChildComponent />, []);

  return (
    <MovingComponent>
      {renderChild}
    </MovingComponent>
  );
};
```

`useCallback` keeps `renderChild` as a stable reference. But:

```
SomeOutsideComponent re-renders
  → renderChild reference is SAME (useCallback worked)
  → passes renderChild as children to MovingComponent
  → MovingComponent.children prop is SAME reference → but MovingComponent still re-renders
     (because SomeOutsideComponent re-rendered and MovingComponent has no memo)
  → MovingComponent calls renderChild()
  → renderChild() creates NEW <ChildComponent /> element
  → ChildComponent re-renders ✅ (still happens)
```

`useCallback` memoizes the function; it doesn't memoize the *result* of calling the function.

---

## Comparison: When Memoization Actually Works

### ✅ Works: useCallback + React.memo on the wrapper

```jsx
const MovingComponentMemo = React.memo(MovingComponent);

const SomeOutsideComponent = () => {
  const [state, setState] = useState();
  const renderChild = useCallback(() => <ChildComponent />, []);

  return (
    <MovingComponentMemo>
      {renderChild}     {/* stable ref → memo passes → wrapper skips → fn never called */}
    </MovingComponentMemo>
  );
};
```

### ✅ Works: React.memo on the child (no useCallback needed)

```jsx
const ChildComponentMemo = React.memo(ChildComponent);

const SomeOutsideComponent = () => {
  const [state, setState] = useState();

  return (
    <MovingComponent>
      {() => <ChildComponentMemo />}   {/* fn creates new element, but memo stops render */}
    </MovingComponent>
  );
};
```

### ❌ Fails: Only useCallback, no memo anywhere

```jsx
const SomeOutsideComponent = () => {
  const renderChild = useCallback(() => <ChildComponent />, []);
  return <MovingComponent>{renderChild}</MovingComponent>;
  // MovingComponent still re-renders → calls renderChild() → new element → ChildComponent re-renders
};
```

### ❌ Fails: Only React.memo on wrapper, no stable children

```jsx
const MovingComponentMemo = React.memo(MovingComponent);

const SomeOutsideComponent = () => {
  const [state, setState] = useState();
  return (
    <MovingComponentMemo>
      <ChildComponent />   {/* new element every render → memo bypassed */}
    </MovingComponentMemo>
  );
};
```

---

## Decision Tree: Which Memoization to Apply

```
Is children a function (render prop)?
├── YES
│   ├── Does the wrapper need to skip its own re-render?
│   │   ├── YES → useCallback(fn) + React.memo(Wrapper)
│   │   └── NO  → React.memo(Child)
└── NO (element children)
    ├── Does the wrapper have its own state that re-renders it?
    │   ├── YES → children are safe (created outside), no memo needed
    │   └── NO  → parent re-renders propagate, consider React.memo(Child)
```

---

## Summary Table

| Strategy | Stops wrapper render? | Stops child render? | Notes |
|----------|----------------------|---------------------|-------|
| `React.memo(Wrapper)` + stable children | ✅ | ✅ | children must not change |
| `React.memo(Wrapper)` + new element children | ❌ | ❌ | new element bypasses memo |
| `React.memo(Child)` | ❌ | ✅ | wrapper still renders |
| `useCallback(fn)` only | ❌ | ❌ | fn ref stable, element isn't |
| `useCallback(fn)` + `React.memo(Wrapper)` | ✅ | ✅ | fn never called |
| Element children (no memo) | ❌ | ✅ | natural composition pattern |

---

## Related Notes

- [[React Component Composition - Children as Props]] — why element children are naturally stable
- [[React Component Composition - Children as Render Functions]] — why render fn children re-render
- [[React Re-renders - Preventing with React.memo]] — React.memo deep dive and pitfalls
- [[React Re-renders - useMemo and useCallback]] — when useCallback/useMemo actually prevent re-renders
- [[React Re-renders - Preventing with Composition]] — composition as alternative to memoization
