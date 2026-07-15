---
tags:
  - react
  - hooks
  - state
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useState
---

# React Hooks — useState

> Local reactive state for a component. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useState<S>(
  initialState: S | (() => S)
): [S, Dispatch<SetStateAction<S>>];

type SetStateAction<S> = S | ((prevState: S) => S);
```

Returns `[currentState, setState]`. `setState` has a **stable identity** across renders — safe to omit from effect dependency arrays.

---

## When to use

- Local component state that drives rendering — form inputs, toggles, counters, selected IDs.
- State that should be **independent per component instance**.
- Simple, unrelated pieces of state — declare each as its own `useState` call.

## When NOT to use

| Case | Use instead |
|------|-------------|
| Value derivable from props or other state | Compute during render (or [[React Hooks - useMemo]] if expensive) |
| State shared with siblings | Lift to common parent, or [[React Hooks - useContext]] |
| Many transitions driven by different actions | [[React Hooks - useReducer]] |
| Value shouldn't trigger a re-render | [[React Hooks - useRef]] |

---

## Batching and stale reads

`setState` **queues** an update for the next render. Reading state right after calling `setState` in the same handler still returns the **old** value.

```jsx
// ❌ All three see the same age — only +1 total
function handleClick() {
  setAge(age + 1);
  setAge(age + 1);
  setAge(age + 1);
}
```

```jsx
// ✅ Updater form receives the pending state — +3 total
function handleClick() {
  setAge(a => a + 1);
  setAge(a => a + 1);
  setAge(a => a + 1);
}
```

**Rule:** whenever the next state depends on the previous, use the updater form.

---

## Never mutate — always replace

React uses `Object.is` to bail out. Mutating an object then passing the same reference skips the re-render.

```jsx
// ❌ Same reference — React bails out, UI does not update
const [user, setUser] = useState({ name: 'A', age: 30 });
user.age = 31;
setUser(user);

// ✅ New reference
setUser({ ...user, age: 31 });
```

---

## Lazy initialization

`useState(fn)` treats a function as a **lazy initializer** — called once on mount.

```jsx
// ❌ createInitialTodos() runs on EVERY render (result discarded)
const [todos, setTodos] = useState(createInitialTodos());

// ✅ Function reference — called once
const [todos, setTodos] = useState(createInitialTodos);
```

Use this when the initial value is expensive to compute (parse localStorage, seed a large array, etc.).

---

## Storing a function in state

`useState(fn)` treats `fn` as an initializer. To store a function itself, wrap it:

```jsx
const [handler, setHandler] = useState(() => defaultHandler);
setHandler(() => nextHandler);
```

---

## Caveats

- Strict Mode calls **initializers and updaters twice** in dev — keep both pure.
- `Object.is`-equal updates skip re-rendering.
- `setState` identity is stable — you don't need to include it in dependency arrays.
- Updates are batched inside event handlers, effects, and (since React 18) all async contexts.

---

## Summary

| Pattern | Use |
|---------|-----|
| `setCount(n + 1)` | Only when the value is independent of previous state |
| `setCount(n => n + 1)` | When next depends on previous (or you're calling `set` multiple times in one handler) |
| `useState(expensiveFn)` | ❌ — runs every render |
| `useState(expensiveFn)` with function reference | ✅ — lazy init, runs once |
| Mutating then `setX(x)` | ❌ — same reference, no re-render |
| `setX({ ...x, field: v })` | ✅ — new reference |

---

## Related

- [[React Hooks - useReducer]] — better fit for complex or coordinated state
- [[React Hooks - useRef]] — for mutable values that should NOT re-render
- [[React Re-renders - Why Components Re-render]] — how state changes propagate
- [[React Hooks - Rules of Hooks]] — call-order invariant that makes state slots work
