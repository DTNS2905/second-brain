---
tags:
  - react
  - memo
  - frontend
created: 2026-06-08
source: https://react.dev/reference/react/memo
---

# React memo - Stable Props

> How to keep props referentially stable so `memo` is not bypassed. Part of [[React memo Guide]].

---

## Why Props Stability Matters

`memo` uses `Object.is` shallow comparison. Primitives compare by value; objects, arrays, and functions compare by **reference**.

```js
Object.is(42, 42)          // true  ✅
Object.is('hi', 'hi')      // true  ✅
Object.is({}, {})          // false ❌ — different references
Object.is([], [])          // false ❌
Object.is(fn, fn)          // true  ✅ (same reference)
() => {} === () => {}      // false ❌ — new function each render
```

Every non-primitive created inside a parent render creates a new reference, defeating memo.

---

## Pattern 1: Pass Primitive Props Directly

The simplest fix — decompose objects into primitives:

```jsx
// ❌ Breaks memo — new object every render
function Page() {
  const [name, setName] = useState('Taylor');
  const [age, setAge] = useState(42);
  return <Profile person={{ name, age }} />;
}

// ✅ Fixes memo — primitives compare by value
function Page() {
  const [name, setName] = useState('Taylor');
  const [age, setAge] = useState(42);
  return <Profile name={name} age={age} />;
}

const Profile = memo(function Profile({ name, age }) { ... });
```

---

## Pattern 2: Memoize Objects with `useMemo`

When you must pass an object (e.g., complex config, derived data):

```jsx
// ❌ Breaks memo — new object on every Page render
function Page() {
  const [name, setName] = useState('Taylor');
  const [age, setAge] = useState(42);
  return <Profile person={{ name, age }} />;
}

// ✅ Fixes memo — same reference unless name or age changes
function Page() {
  const [name, setName] = useState('Taylor');
  const [age, setAge] = useState(42);

  const person = useMemo(() => ({ name, age }), [name, age]);

  return <Profile person={person} />;
}

const Profile = memo(function Profile({ person }) { ... });
```

`person` reference stays stable between renders where neither `name` nor `age` changed.

---

## Pattern 3: Memoize Functions with `useCallback`

Functions created inline in render are new references every time:

```jsx
// ❌ Breaks memo — new function reference on every Parent render
function Parent() {
  const handleClick = () => { doSomething(); };
  return <Child onClick={handleClick} />;
}

// ✅ Fixes memo — stable function reference
function Parent() {
  const handleClick = useCallback(() => {
    doSomething();
  }, []);  // or list actual dependencies

  return <Child onClick={handleClick} />;
}

const Child = memo(function Child({ onClick }) { ... });
```

---

## Pattern 4: Lift Stable Values Out of the Component

For truly constant values (no dependencies), define them outside the component:

```jsx
// ✅ No re-creation — object is defined once at module level
const STYLE = { color: 'red', fontWeight: 'bold' };

function Parent() {
  return <Child style={STYLE} />;
}

const Child = memo(function Child({ style }) { ... });
```

---

## Combined Example

```jsx
const MemoizedExpensiveChart = memo(function ExpensiveChart({ data, onHover, config }) {
  // expensive render...
});

function Dashboard() {
  const [filter, setFilter] = useState('all');

  // Object prop — memoize with useMemo
  const config = useMemo(() => ({
    theme: 'dark',
    showLegend: true,
  }), []);

  // Function prop — memoize with useCallback
  const handleHover = useCallback((point) => {
    console.log(point);
  }, []);

  // Array derived from state — memoize with useMemo
  const filteredData = useMemo(
    () => rawData.filter(d => d.type === filter),
    [filter]
  );

  return (
    <MemoizedExpensiveChart
      data={filteredData}
      onHover={handleHover}
      config={config}
    />
  );
}
```

---

## Diagnostic: Is Memo Being Bypassed?

Add a render counter to confirm:

```jsx
const Child = memo(function Child({ ...props }) {
  const renderCount = useRef(0);
  renderCount.current++;
  console.log(`Child rendered ${renderCount.current} times`);
  // ...
});
```

If renders keep incrementing despite no visible prop changes, one prop is unstable. Use React DevTools Profiler to identify which prop changed.

---

## Summary

| Prop type | Problem | Fix |
|-----------|---------|-----|
| Primitive (`string`, `number`, `boolean`) | None | Pass directly |
| Object/array created inline | New ref every render | `useMemo` |
| Function created inline | New ref every render | `useCallback` |
| Truly constant (no deps) | Module re-evaluation | Define outside component |
| Object/array from props | Depends on parent | Memoize at the source |

---

## Related Notes

- [[React memo - API Reference]] — why shallow comparison requires stable refs
- [[React memo - Custom Comparison]] — when you can't make props stable
- [[React Re-renders - useMemo and useCallback]] — in-depth useMemo/useCallback patterns
- [[React Component Composition - Memoization with Children]] — memo interactions with children props
