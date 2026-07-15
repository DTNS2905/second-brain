---
tags:
  - react
  - component-composition
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-elements-children-parents
---

# React Component Composition - React Elements

> What `<Child />` actually is under the hood: createElement, plain objects, and immutability. Part of [[React Component Composition Guide]].

---

## JSX is Syntactic Sugar

```jsx
// These are identical:
const el = <Child />;
const el = React.createElement(Child, null);
```

`React.createElement` returns a **plain JavaScript object** — an *Element*:

```js
{
  type: Child,       // the component function/class
  props: {},
  key: null,
  ref: null,
  // ...
}
```

This object is just a *description* of what to render. It is **not** a rendered component instance.

---

## Element vs Component vs Instance

| Term | What it is | Example |
|------|-----------|---------|
| **Element** | Plain JS object (description) | `{ type: Child, props: {} }` |
| **Component** | Function or class definition | `function Child() { ... }` |
| **Instance** | Live DOM node / fiber | What React manages internally |

---

## Elements Are Immutable

Once created, an element object cannot be changed. To update the UI, React creates a *new* element object and compares it to the previous one (reconciliation).

```jsx
// ✅ Every render call creates a fresh object
const el1 = <Child />;
const el2 = <Child />;
// el1 !== el2  (different object references)
```

This is why reference equality matters for memoization — see [[React Component Composition - Memoization with Children]].

---

## When Does an Element Become a Component Render?

An element triggers rendering only when React encounters it **in a component's return value**:

```jsx
// ❌ Not rendered — just an object sitting in a variable
const element = <Child />;

// ✅ Rendered — React processes it when Parent returns
const Parent = () => {
  return <Child />;   // element returned → React renders Child
};
```

This distinction is the foundation for understanding why children-as-props behave differently than inline JSX — see [[React Component Composition - Children as Props]].

---

## Children Are Also Elements

```jsx
<Parent>
  <Child />
</Parent>

// Desugars to:
React.createElement(Parent, { children: React.createElement(Child, null) })
```

`children` is just a prop whose value happens to be another element object. No magic — see [[React Component Composition - Children as Props]].

---

## Related Notes

- [[React Component Composition - Children as Props]] — why element origin determines re-render behavior
- [[React Reconciliation - Virtual DOM and Fiber]] — how React processes element trees
- [[React Reconciliation - Diffing Algorithm]] — how old vs new elements are compared
