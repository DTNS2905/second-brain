---
tags:
  - react
  - component-composition
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-elements-children-parents
---

# React Component Composition - Children as Props

> Why components passed as children don't re-render when the parent re-renders — the key to composition-based performance. Part of [[React Component Composition Guide]].

---

## The Core Mystery

```jsx
const MovingComponent = ({ children }) => {
  // This state updates on every mouse move → triggers re-render
  const [pos, setPos] = useState({ x: 100, y: 100 });

  return (
    <div
      onMouseMove={(e) => setPos({ x: e.clientX, y: e.clientY })}
      style={{ left: pos.x, top: pos.y, position: 'fixed' }}
    >
      {children}
    </div>
  );
};

const SomeOutsideComponent = () => (
  <MovingComponent>
    <ChildComponent />   {/* Does this re-render on mouse move? */}
  </MovingComponent>
);
```

**Answer: NO.** `ChildComponent` does not re-render when `MovingComponent` re-renders.

---

## Why: Who Creates the Element?

The `<ChildComponent />` element object is created inside `SomeOutsideComponent`, not inside `MovingComponent`.

```
SomeOutsideComponent renders
  → creates element: { type: ChildComponent, props: {} }
  → passes it as children prop to MovingComponent

MovingComponent re-renders (state change)
  → receives its props (including children) unchanged
  → children prop still points to the same element object
  → React sees no change in children → skips re-rendering ChildComponent
```

**Props don't get recreated when a component re-renders — they come from the outside.** The element was already created by the parent (`SomeOutsideComponent`) and passed in.

---

## ✅ Correct Mental Model

```jsx
// children is just a prop — same as any other prop
<MovingComponent>
  <ChildComponent />
</MovingComponent>

// Equivalent to:
<MovingComponent children={<ChildComponent />} />
```

When `MovingComponent` re-renders, its `children` prop value hasn't changed (same object reference from `SomeOutsideComponent`'s last render), so React skips re-rendering `ChildComponent`.

---

## ❌ Incorrect Mental Model (Common Mistake)

```
MovingComponent
  └── ChildComponent  ← "child in the DOM tree" = "child component that re-renders with parent"
```

This is wrong. "Child in DOM/JSX tree" ≠ "component that always re-renders with parent". Re-renders follow *where the element was created*, not the visual nesting.

---

## Practical Performance Pattern

Use this to isolate expensive state from unrelated subtrees:

```jsx
// ❌ Problem: HeavyComponent re-renders on every scroll event
const ScrollTracker = () => {
  const [scrollY, setScrollY] = useState(0);
  // scroll handler...
  return (
    <div onScroll={(e) => setScrollY(e.target.scrollTop)}>
      <HeavyComponent />   {/* re-renders every scroll */}
    </div>
  );
};

// ✅ Solution: pass HeavyComponent as children
const ScrollTracker = ({ children }) => {
  const [scrollY, setScrollY] = useState(0);
  return (
    <div onScroll={(e) => setScrollY(e.target.scrollTop)}>
      {children}           {/* does NOT re-render on scroll */}
    </div>
  );
};

const App = () => (
  <ScrollTracker>
    <HeavyComponent />
  </ScrollTracker>
);
```

---

## Caveat: This Only Works for JSX Children

This behavior holds when children are **element objects** passed as props. If children is a **function** (render prop), the behavior is different — see [[React Component Composition - Children as Render Functions]].

---

## Summary

| Where element is created | Re-renders when intermediate component re-renders? |
|--------------------------|---------------------------------------------------|
| Inside the intermediate component (inline JSX) | ✅ Yes |
| Outside, passed as `children` prop | ❌ No |
| Outside, passed as any other element prop | ❌ No |

---

## Related Notes

- [[React Component Composition - React Elements]] — what an element object actually is
- [[React Component Composition - Children as Render Functions]] — when children DO re-render
- [[React Component Composition - Memoization with Children]] — React.memo interactions
- [[React Re-renders - Preventing with Composition]] — this pattern in the re-renders guide
- [[React Re-renders - Why Components Re-render]] — full re-render trigger rules
