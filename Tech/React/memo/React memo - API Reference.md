---
tags:
  - react
  - memo
  - frontend
created: 2026-06-08
source: https://react.dev/reference/react/memo
---

# React memo - API Reference

> Full signature, parameters, return value, and caveats for `memo()`. Part of [[React memo Guide]].

---

## Signature

```js
const MemoizedComponent = memo(Component, arePropsEqual?)
```

Import:

```js
import { memo } from 'react';
```

---

## Parameters

### `Component` (required)

Any valid React component — function components, components wrapped with `forwardRef`, etc.

```js
const Greeting = memo(function Greeting({ name }) {
  return <h1>Hello, {name}!</h1>;
});
```

The memoized component has the same signature and props as the original.

### `arePropsEqual` (optional)

A custom function `(oldProps, newProps) => boolean`:
- Return `true` → treat as equal → **skip** re-render
- Return `false` → treat as different → **trigger** re-render

When omitted, React uses **shallow comparison** (`Object.is`) on every prop.

See [[React memo - Custom Comparison]] for details and caveats.

---

## Return Value

A new React component with identical behavior to the original. React skips re-rendering it when its parent re-renders **and** its props haven't changed (per the comparison).

---

## Critical Caveats

### Own state always triggers re-render

`memo` only stops re-renders caused by the *parent*. Internal state changes always re-render the component:

```jsx
const Greeting = memo(function Greeting({ name }) {
  const [greeting, setGreeting] = useState('Hello');  // own state

  return (
    <>
      <h3>{greeting}, {name}!</h3>
      <button onClick={() => setGreeting('Hi')}>Change</button>
    </>
  );
});
// Clicking the button always re-renders, regardless of memo
```

### Context changes always trigger re-render

If a memoized component consumes a context, it **always** re-renders when that context value changes:

```jsx
const ThemeContext = createContext(null);

const Greeting = memo(function Greeting({ name }) {
  const theme = useContext(ThemeContext);  // context subscription
  return <h3 className={theme}>Hello, {name}!</h3>;
});
// Re-renders whenever ThemeContext value changes, even if name is unchanged
```

To prevent this, split the context or use context selectors.

---

## Memo Is a Performance Hint, Not a Guarantee

React may choose to re-render a memoized component even if props haven't changed (e.g., during hydration, or future React internals). **Don't rely on memo for correctness** — use it only as a performance optimization.

---

## Basic Example

```jsx
import { memo, useState } from 'react';

// Greeting only re-renders when `name` prop changes
const Greeting = memo(function Greeting({ name }) {
  console.log('Greeting rendered');
  return <h1>Hello, {name}!</h1>;
});

function App() {
  const [count, setCount] = useState(0);
  const [name, setName] = useState('Taylor');

  return (
    <>
      <button onClick={() => setCount(c => c + 1)}>Count: {count}</button>
      {/* name hasn't changed → Greeting does NOT re-render */}
      <Greeting name={name} />
    </>
  );
}
```

---

## Summary

| Aspect | Behavior |
|--------|----------|
| Parent re-renders, same props | ❌ Skipped |
| Parent re-renders, changed props | ✅ Re-renders |
| Own state update | ✅ Re-renders |
| Context change | ✅ Re-renders |
| Prop comparison | Shallow (`Object.is`) by default |
| Guarantee | None — hint only |

---

## Related Notes

- [[React memo - Stable Props]] — making props pass shallow comparison
- [[React memo - Custom Comparison]] — overriding the comparison function
- [[React Re-renders - Why Components Re-render]] — full re-render trigger rules
