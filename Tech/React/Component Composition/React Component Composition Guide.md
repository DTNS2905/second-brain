---
tags:
  - react
  - component-composition
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-elements-children-parents
---

# React Component Composition Guide

> Master guide covering React Elements, children props, render functions, and memoization patterns in component composition.

---

## Contents

| Note | Covers |
|------|--------|
| [[React Component Composition - React Elements]] | What `<Child />` actually is; createElement, immutability |
| [[React Component Composition - Children as Props]] | Why children passed as props don't re-render with the parent |
| [[React Component Composition - Children as Render Functions]] | Why render-function children DO re-render every time |
| [[React Component Composition - Memoization with Children]] | React.memo and useCallback behavior with children |

---

## Quick Reference: The Four Mysteries

| Scenario | Child Re-renders? | Why |
|----------|------------------|-----|
| `<Parent><Child /></Parent>` | ❌ No | Element created outside Parent; props unchanged |
| `<Parent>{() => <Child />}</Parent>` | ✅ Yes | Function called inside Parent on every render |
| `<MemoParent><Child /></MemoParent>` (parent memoized) | ✅ Yes | `children` prop is a new Element object each time |
| `<Parent><MemoChild /></Parent>` (child memoized) | ❌ No | Child's definition never changes between renders |
| `useCallback(() => <Child />, [])` passed as render fn | ✅ Yes | Fn ref stable but return value (element) recreated on call |

---

## Core Mental Model

```
JSX <Child />
    ↓
React.createElement(Child, null)  ← returns a plain JS object
    ↓
{ type: Child, props: {}, ... }  ← an "Element" (description, not instance)
    ↓
Rendered only when returned from a component's render function
```

**Key insight:** An element object is just data. It only causes a render when React sees it in a component's return value. Who *creates* the element object determines whether it gets recreated on re-render.

---

## Composition Performance Pattern

```jsx
// ✅ Heavy state changes in MovingComponent don't affect ChildComponent
const SomeOutsideComponent = () => (
  <MovingComponent>
    <ChildComponent />   {/* Element created here, NOT inside MovingComponent */}
  </MovingComponent>
);
```

Use this to isolate expensive state (mouse position, scroll) from unrelated subtrees. See [[React Re-renders - Preventing with Composition]].

---

## Related Notes

- [[React Re-renders Guide]] — full re-render performance reference
- [[React Re-renders - Why Components Re-render]] — state/props trigger rules
- [[React Re-renders - Preventing with React.memo]] — memo deep dive
- [[React Re-renders - Preventing with Composition]] — composition as perf strategy
- [[React Re-renders - useMemo and useCallback]] — hook memoization
- [[React Reconciliation Guide]] — how React diffs the element tree
