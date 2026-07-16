---
tags:
  - react
  - lifecycle
  - refs
  - frontend
created: 2026-07-16
source: https://react.dev/reference/react/useRef
---

# React Lifecycle — Ref Lifecycle and Cleanup

> Refs have their own lifecycle contract: attach on commit, detach before re-attach, detach on unmount. React 19 adds cleanup returns to callback refs, replacing years of "check if node changed" boilerplate. Part of [[React Lifecycle Guide]].

---

## Two ref shapes

| Shape | Access pattern | Attach timing |
|-------|----------------|---------------|
| Object ref (`useRef`) | `ref.current` | During commit, before layout effects |
| Callback ref (`(node) => …`) | Function called with node | During commit, before layout effects |

Object refs are containers React writes into. Callback refs are functions React invokes with the node — you own where the reference goes and can do side effects at attach/detach time.

---

## Ref lifecycle sequence per commit

Refs run in the commit phase, child-first, **before** any layout effect. The full order:

1. DOM mutations complete
2. **Old ref cleanup** — object refs set to `null`; callback refs re-called with `null` OR their cleanup return runs (React 19)
3. **New ref attach** — object refs assigned the new node; callback refs called with the new node
4. `useLayoutEffect` cleanup → setup
5. Paint
6. `useEffect` cleanup → setup

This means: by the time `useLayoutEffect` runs, every ref in the tree is already pointing at the correct node. See [[React Lifecycle - Effect Ordering]] for the full commit-phase pipeline.

Refs are the earliest hook to see the new DOM. If you need to measure or observe a node before the browser paints, do it in a callback ref or a `useLayoutEffect` — not in `useEffect`.

---

## Object refs

`useRef(init)` creates a mutable container. React assigns `.current` on commit and does not re-create the container across renders. During render, don't read or write `.current` — it violates render purity and, on the first render, the ref hasn't been attached yet.

```jsx
const inputRef = useRef<HTMLInputElement>(null);
return <input ref={inputRef} />;
```

Reading during render:

```jsx
// ❌ .current is stale during first render (null); mutable value during render breaks purity
function Cmp() {
  const ref = useRef(0);
  ref.current += 1;
  return <span>{ref.current}</span>;
}
```

```jsx
// ✅ Mutate refs in event handlers or effects only
function Cmp() {
  const ref = useRef(0);
  useEffect(() => { ref.current += 1; });
  return <span>{ref.current}</span>;
}
```

The pure-render rule is enforced (loudly) by [[React Lifecycle - StrictMode Double Invoke]] — mutations during render will double, revealing the bug.

Cross-link `[[React Hooks - useRef]]`.

---

## Callback refs — before React 19

Callback refs let you run code at attach and detach time. Pre-React 19, detection was manual: React called the same function twice per lifecycle transition — once with the node, then again with `null`.

```jsx
const setNode = useCallback((node: HTMLElement | null) => {
  if (node) {
    observer.observe(node);
  } else {
    observer.disconnect();
  }
}, []);

return <div ref={setNode} />;
```

The problem: two calls per lifecycle transition, hard to read, easy to leak (miss the null branch and the observer stays alive forever). Sharing state between the "attach" and "detach" branch required closures or module-level variables.

---

## Callback refs — React 19 cleanup return

React 19 lets callback refs return a cleanup function, exactly like `useEffect`:

```jsx
const setNode = (node: HTMLElement) => {
  const obs = new IntersectionObserver(onIntersect);
  obs.observe(node);
  return () => obs.disconnect();
};

return <div ref={setNode} />;
```

React calls the cleanup **before** calling `setNode` with the next node (on re-attach) or on unmount. Symmetric with `useEffect` — setup and teardown live in one closure, and the observer instance is captured naturally.

```jsx
// ❌ Pre-19 style still works but is now the wrong shape
const setNode = (node: HTMLElement | null) => {
  if (node) observer.observe(node);
  else observer.disconnect();
};
```

```jsx
// ✅ 19-style
const setNode = (node: HTMLElement) => {
  observer.observe(node);
  return () => observer.disconnect();
};
```

If a callback ref returns a cleanup, React will **not** call it with `null` anymore for that transition — the cleanup return replaces the null-callback signal.

---

## When ref cleanup runs

| Trigger | What runs |
|---------|-----------|
| Component unmounts | Cleanup runs; object refs are NOT nulled by React (host component refs are; user-set refs on custom components aren't in the same way — check react.dev for specifics) |
| Ref target changes (different DOM node next commit) | Cleanup runs → new node passed to setter |
| Callback ref reference changes (new function each render) | Cleanup runs with old node → new callback called with same node → cleanup runs when unmount |

Key gotcha: if you inline the callback ref (`ref={n => …}`), it's a new function every render → React thinks the ref changed → detach + reattach every render. That's an observer torn down and rebuilt on every state change, a `MutationObserver` that misses records, a focus that gets stolen on every keystroke.

Fix with `useCallback` or a stable module-level function.

```jsx
// ❌ Inline callback ref — detach + reattach every render
<div ref={n => { if (n) obs.observe(n); }} />
```

```jsx
// ✅ Stable identity
const attach = useCallback((n: HTMLDivElement) => {
  obs.observe(n);
  return () => obs.disconnect();
}, [obs]);
return <div ref={attach} />;
```

The same trap applies to inline object refs: `ref={{ current: null }}` is a new object every render and defeats the whole point.

---

## `forwardRef` is deprecated in React 19

In React 19, `ref` is a regular prop for function components. `forwardRef` still works but is no longer needed — and the type ergonomics are dramatically better (no generic argument order to memorize).

```jsx
// ❌ Pre-19: forwardRef required to accept a ref
const Btn = forwardRef<HTMLButtonElement, Props>((props, ref) => (
  <button ref={ref} {...props} />
));
```

```jsx
// ✅ React 19: ref is a prop
function Btn({ ref, ...props }: Props & { ref?: Ref<HTMLButtonElement> }) {
  return <button ref={ref} {...props} />;
}
```

Codemod available: `npx types-react-codemod@latest preset-19 ./src`.

Class components still use `forwardRef` if you want to expose their instance — but class components themselves are legacy. For new code, function components with `ref` as a prop is the target.

---

## `useImperativeHandle` timing

`useImperativeHandle(ref, () => methods, deps)` sets `ref.current` to the returned object. It runs during the commit phase (alongside layout effects), so parent code accessing `ref.current` in `useLayoutEffect` will see the imperative handle.

```jsx
const InputWithFocus = ({ ref }: { ref?: Ref<{ focus: () => void }> }) => {
  const inputRef = useRef<HTMLInputElement>(null);
  useImperativeHandle(ref, () => ({
    focus: () => inputRef.current?.focus(),
  }), []);
  return <input ref={inputRef} />;
};
```

The handle is (re)created whenever `deps` change. Between renders, `ref.current` from the parent's perspective is stable until deps change — so parents can safely close over the handle in effects with the ref in the dep array.

Use sparingly. Imperative handles are an escape hatch — most parent/child communication should go through props and state. Reach for `useImperativeHandle` for genuinely imperative APIs: `focus`, `scrollIntoView`, `play`, `open`.

---

## Summary table

| Pattern | Use |
|---------|-----|
| `useRef(init)` + assign to `ref={}` | DOM node access from handlers/effects |
| Callback ref (React 19) with cleanup return | Observers, third-party libs, per-node lifecycle |
| `useImperativeHandle` | Expose a controlled API from a leaf to its parent |
| `useRef` for mutable non-DOM value | Instance value that doesn't trigger re-render |

---

## Related

- [[React Hooks - useRef]] — the object-ref API in detail
- [[React Lifecycle - Effect Ordering]] — where refs fit in the commit pipeline
- [[React Lifecycle - Unmount and Cleanup Patterns]] — teardown patterns that use ref cleanup
- [[React Lifecycle Guide]]
