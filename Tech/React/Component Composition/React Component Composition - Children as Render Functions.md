---
tags:
  - react
  - component-composition
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-elements-children-parents
---

# React Component Composition - Children as Render Functions

> Why render-function children (render props pattern) cause re-renders on every parent re-render, unlike element children. Part of [[React Component Composition Guide]].

---

## The Pattern

```jsx
const MovingComponent = ({ children }) => {
  const [pos, setPos] = useState({ x: 100, y: 100 });

  return (
    <div onMouseMove={(e) => setPos({ x: e.clientX, y: e.clientY })}>
      {children({ data: 'something' })}   {/* children is called as a function */}
    </div>
  );
};

const SomeOutsideComponent = () => (
  <MovingComponent>
    {() => <ChildComponent />}   {/* children is a function */}
  </MovingComponent>
);
```

**Does `ChildComponent` re-render on mouse move? YES.**

---

## Why: Element Creation Moves Inside

When `children` is a function, calling it happens **inside `MovingComponent`** on every render:

```
MovingComponent re-renders (state change)
  → calls children()                      ← happens INSIDE MovingComponent
  → children() returns <ChildComponent /> ← new element object created here
  → React sees a new element definition
  → re-renders ChildComponent
```

Contrast with element children (see [[React Component Composition - Children as Props]]):
```
MovingComponent re-renders (state change)
  → children prop already contains element object (created outside)
  → no new element creation
  → React skips ChildComponent re-render
```

The element creation point is the critical difference.

---

## ❌ useCallback Doesn't Fix This

A common but incorrect fix:

```jsx
const SomeOutsideComponent = () => {
  const [state, setState] = useState();

  // Stable function reference between renders
  const renderChild = useCallback(() => <ChildComponent />, []);

  return (
    <MovingComponent>
      {renderChild}
    </MovingComponent>
  );
};
```

`useCallback` memoizes the *function reference*, not its *return value*. `MovingComponent` still calls `renderChild()` on every render, creating a new `<ChildComponent />` element each time.

---

## ✅ Fix Option 1: Memo the child component

```jsx
const ChildComponentMemo = React.memo(ChildComponent);

const SomeOutsideComponent = () => (
  <MovingComponent>
    {() => <ChildComponentMemo />}   {/* new element, but memo skips render */}
  </MovingComponent>
);
```

Even though a new element object is created on each call, `React.memo` prevents the actual component re-render if props haven't changed.

---

## ✅ Fix Option 2: useCallback + memo the parent

```jsx
const MovingComponentMemo = React.memo(MovingComponent);

const SomeOutsideComponent = () => {
  const [state, setState] = useState();

  const renderChild = useCallback(() => <ChildComponent />, []);

  return (
    <MovingComponentMemo>
      {renderChild}
    </MovingComponentMemo>
  );
};
```

`useCallback` keeps the function reference stable → `React.memo` sees `children` prop hasn't changed → `MovingComponent` skips its own re-render entirely → `children()` is never called.

---

## When to Use Render Functions Anyway

Despite the re-render cost, render functions are legitimate when:
- The child **needs data from the parent** that isn't available at the call site
- Implementing headless component patterns (e.g., `<Downshift>{(props) => ...}</Downshift>`)
- Data-driven rendering where parent controls what data is passed down

```jsx
// Legitimate: child needs parent's internal data
<DataProvider>
  {({ isLoading, data }) => isLoading ? <Spinner /> : <Table data={data} />}
</DataProvider>
```

---

## Summary

| Children type | Element created | Re-renders child? |
|--------------|----------------|-------------------|
| `{<Child />}` | Outside (in caller) | ❌ No |
| `{() => <Child />}` | Inside (on each call) | ✅ Yes |
| `{memoFn}` with no parent memo | Inside (on each call) | ✅ Yes |
| `{memoFn}` with `React.memo(Parent)` | Skipped (parent skips) | ❌ No |
| `{() => <MemoChild />}` | Inside (on each call) | ❌ No (memo blocks) |

---

## Related Notes

- [[React Component Composition - Children as Props]] — why element children don't re-render
- [[React Component Composition - Memoization with Children]] — detailed memo patterns
- [[React Re-renders - useMemo and useCallback]] — when useCallback actually helps
- [[React Re-renders - Preventing with React.memo]] — React.memo deep dive
