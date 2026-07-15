---
tags:
  - react
  - hooks
  - fundamentals
  - frontend
created: 2026-07-15
source: https://react.dev/reference/rules/rules-of-hooks
---

# React Hooks — Rules of Hooks

> Two rules that make hooks work at all. Part of [[React Hooks Guide]].

---

## Rule 1 — Only call hooks at the top level

Don't call hooks inside:
- Loops
- Conditions
- Nested functions
- `try/catch/finally` blocks
- **After** any early return

Always call them at the top level of a component or custom hook — in the same order every render.

## Rule 2 — Only call hooks from React functions

Call hooks from:
- Function components
- Other custom hooks (functions named `use*`)

Never from:
- Plain JS functions
- Event handlers (the handler runs later, not during render)
- Class components
- Inside `useMemo` / `useEffect` / `useCallback` callbacks

---

## Why these rules exist

React identifies each hook call by its **positional index** in the render — the first `useState` call is state slot 0, the second is slot 1, and so on. **There is no name-based lookup.**

```
Component render:
  useState('a')   ← slot 0
  useEffect(...)  ← slot 1
  useState('b')   ← slot 2
```

If a conditional call **skips** slot 1 on one render but includes it the next, every subsequent slot shifts, and React would:
- Return the wrong state to the wrong hook.
- Call effect cleanup on a hook that no longer exists.
- Attach state to a hook that expects to be an effect.

The top-level rule guarantees the **call sequence is identical** across renders.

Rule 2 exists so all stateful logic is visible from the component's source and React knows which fiber owns the state.

---

## Anti-patterns

### Conditional call

```jsx
// ❌ Slot indices shift when `cond` flips
function C({ cond }) {
  if (cond) {
    const [x, setX] = useState(0);
  }
  const [y, setY] = useState(1); // becomes slot 0 or 1 depending on cond
}
```

```jsx
// ✅ Push the condition INSIDE the hook
function C({ cond }) {
  const [x, setX] = useState(0);
  useEffect(() => {
    if (!cond) return;
    // ...
  }, [cond]);
}
```

### After early return

```jsx
// ❌ Same shifting problem
function C({ hide }) {
  if (hide) return null;
  const [x, setX] = useState(0);
}
```

```jsx
// ✅ Hooks first, THEN conditional render
function C({ hide }) {
  const [x, setX] = useState(0);
  if (hide) return null;
}
```

### Inside a loop with variable length

```jsx
// ❌ items.length varies → different number of hooks per render
for (const item of items) {
  useEffect(() => sync(item), [item]);
}
```

```jsx
// ✅ One hook that syncs all items
useEffect(() => {
  items.forEach(item => sync(item));
}, [items]);

// ✅ Or extract a child component with its own hook
{items.map(item => <ItemSync key={item.id} item={item} />)}
```

### Inside try/catch

```jsx
// ❌ Throw could skip the hook
try {
  const [x] = useState(0);
} catch { /* … */ }
```

```jsx
// ✅ Hook outside; handle errors elsewhere
const [x] = useState(0);
```

### Inside a callback

```jsx
// ❌ Handler runs later, not during render
function handleClick() {
  const [x, setX] = useState(0);
}
```

```jsx
// ✅ Declare state at the top; call the setter in the handler
const [x, setX] = useState(0);
function handleClick() {
  setX(v => v + 1);
}
```

---

## The one exception: `use`

[[React Hooks - React 19 Actions Hooks|use]] (React 19) is a **special function**, not technically a hook — it can be called inside conditions, loops, and after early returns.

```jsx
// ✅ Legal for `use`, illegal for every other hook
function C({ cond, promise }) {
  if (cond) {
    const value = use(promise);
  }
}
```

Everything else must obey the top-level rule.

---

## Enforcement

Install and enable **`eslint-plugin-react-hooks`**:

```json
{
  "plugins": ["react-hooks"],
  "rules": {
    "react-hooks/rules-of-hooks": "error",
    "react-hooks/exhaustive-deps": "warn"
  }
}
```

`rules-of-hooks` catches call-order violations. `exhaustive-deps` catches missing dependencies in `useEffect` / `useMemo` / `useCallback` — do not silence it with `// eslint-disable`; either add the dep or move the code.

React 19 ships an updated linter that also validates the `use` API (allowed conditionally) and Server Components.

---

## Summary

```
Where can I call a hook?
  ├── Top level of a function component?           ✅
  ├── Top level of a custom hook (use* name)?      ✅
  ├── Inside a condition/loop/try/nested function? ❌
  ├── After an early return?                       ❌
  ├── Inside an event handler / useEffect body?    ❌
  ├── Inside a class component?                    ❌
  └── The `use` API (React 19)?                    ✅ everywhere
```

---

## Related

- [[React Hooks - Custom Hooks]] — the second class of allowed callers
- [[React Hooks - useEffect]] — where `exhaustive-deps` matters most
- [[React Hooks Guide]] — top-level index
