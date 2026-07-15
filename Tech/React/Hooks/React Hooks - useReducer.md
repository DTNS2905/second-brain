---
tags:
  - react
  - hooks
  - state
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useReducer
---

# React Hooks — useReducer

> State with centralized transitions. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useReducer<S, A>(
  reducer: (state: S, action: A) => S,
  initialArg: S
): [S, Dispatch<A>];

function useReducer<S, A, I>(
  reducer: (state: S, action: A) => S,
  initialArg: I,
  init: (arg: I) => S
): [S, Dispatch<A>];
```

- `reducer` must be **pure** — `(state, action) => nextState`, no mutation, no side effects.
- Returns `[state, dispatch]`. `dispatch` has a **stable identity** — safe to omit from effect deps.

---

## When to prefer over useState

| Signal | Why reducer wins |
|--------|------------------|
| Multiple related fields updated together | One `dispatch` call vs many `setX` calls |
| Next state depends on previous with non-trivial logic | All transitions live in one pure function |
| Same state mutated from many handlers | Centralize the "what can happen" in the reducer |
| Need to unit-test state transitions | Reducers are trivially testable — no React needed |

## When NOT to use

- One or two independent primitives — `useState` is lighter and clearer.
- State that's really **derived data** — compute during render instead.
- Global state across the tree — combine `useReducer` with [[React Hooks - useContext]], or use a real store.

---

## Minimal example

```tsx
type State = { count: number };
type Action =
  | { type: 'inc' }
  | { type: 'dec' }
  | { type: 'reset'; payload: number };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'inc':   return { count: state.count + 1 };
    case 'dec':   return { count: state.count - 1 };
    case 'reset': return { count: action.payload };
    default:      throw new Error(`Unknown action`);
  }
}

function Counter() {
  const [state, dispatch] = useReducer(reducer, { count: 0 });
  return (
    <>
      <button onClick={() => dispatch({ type: 'inc' })}>+</button>
      <button onClick={() => dispatch({ type: 'dec' })}>-</button>
      <span>{state.count}</span>
    </>
  );
}
```

---

## Anti-pattern: mutating state inside the reducer

React sees the same reference and skips the re-render.

```jsx
// ❌ Mutation — UI does not update
function reducer(state, action) {
  if (action.type === 'add') {
    state.items.push(action.item);
    return state;
  }
}
```

```jsx
// ✅ Return a fresh object
function reducer(state, action) {
  if (action.type === 'add') {
    return { ...state, items: [...state.items, action.item] };
  }
  return state;
}
```

---

## Lazy initialization via `init`

```jsx
function init(userId) {
  return { userId, cart: [], history: [] };
}

const [state, dispatch] = useReducer(reducer, userId, init);
```

`init(userId)` runs once. Useful when the initial state needs computation from a prop.

---

## Caveats

- Reducer and `init` **run twice in Strict Mode dev** — keep them pure.
- `Object.is`-equal next state bails out re-rendering. Returning the same reference on a no-op action is a valid optimization.
- Updates are batched; state read after `dispatch(...)` in the same handler is still previous state.
- `dispatch` identity is stable across renders.

---

## Reducer vs useState — quick heuristic

```
Is your state:
  ├── One primitive that flips based on a single event?
  │     └── useState
  ├── A small object with independent fields?
  │     └── useState (one per field is fine)
  ├── Multiple fields updated together, or many actions?
  │     └── useReducer
  └── Truly global, cross-tree?
        └── useReducer + Context, or a store library
```

---

## Related

- [[React Hooks - useState]] — the lighter alternative
- [[React Hooks - useContext]] — combine with reducer for scoped "app state"
- [[React Hooks - Rules of Hooks]] — why reducer + dispatch identity is stable
