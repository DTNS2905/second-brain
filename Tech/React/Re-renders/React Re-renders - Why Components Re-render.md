---
tags:
  - react
  - performance
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# Why React Components Re-render

> Part 1 of [[React Re-renders Guide]]

---

## The 4 Triggers

### 1. State Changes

When a component's state changes (via event handler or `useEffect`), it re-renders itself. This is the **root source** of all re-renders in an app.

```jsx
const Component = () => {
  const [state, setState] = useState(initialState);
  // triggers re-render of this component
  return <div onClick={() => setState(newState)}>...</div>;
};
```

### 2. Parent Re-renders

When a parent re-renders, **all its children re-render** — regardless of whether their props changed.

```
Parent re-renders
  └── ChildA re-renders  ← even if no props changed
  └── ChildB re-renders  ← even if no props changed
```

> Re-renders go **down** the tree. A child re-render never causes a parent re-render.

### 3. Context Changes

When a Context Provider's value changes, **all components consuming that context re-render** — even if they don't use the changed portion of the data.

```jsx
// Both ComponentA and ComponentB re-render when ctx value changes,
// even if ComponentA only uses ctx.theme and ctx.user changed.
const ComponentA = () => {
  const { theme } = useContext(AppContext);
  return <div style={{ color: theme }} />;
};
```

> These re-renders **cannot be prevented with memoization directly** — only with context splitting workarounds. See [[React Re-renders - Context Re-renders]].

### 4. Hooks Changes

Rules for state and context apply **inside hooks too**:
- A state change inside a custom hook triggers a re-render of the host component
- A context change inside a custom hook triggers a re-render of the host component
- Chained hooks follow the same rules — each hook "belongs" to its host component

```jsx
const useData = () => {
  const [data, setData] = useState(null); // belongs to the component using useData
  return data;
};
```

---

## The Props Myth

> **Props changing does NOT trigger a re-render** on non-memoized components.

Why? Because props can only be updated by a parent re-render. By the time props change, the parent has already re-rendered and caused the child to re-render anyway.

Props only become relevant when using `React.memo` — see [[React Re-renders - Preventing with React.memo]].

```jsx
// ChildComponent re-renders whenever ParentComponent re-renders,
// regardless of whether `value` prop changed.
const ParentComponent = () => {
  const [state, setState] = useState(1);
  return <ChildComponent value="static string" />;
};
```
