---
tags:
  - react
  - hooks
  - refs
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/useRef
---
/
# React Hooks — useRef

> Mutable value that persists across renders **without** triggering a re-render. Part of [[React Hooks Guide]].

---

## Signature

```ts
function useRef<T>(initialValue: T): { current: T };
function useRef<T>(initialValue: T | null): { current: T | null };
function useRef<T = undefined>(): { current: T | undefined };
```

Returns a **stable object** `{ current }`. The same object is returned across renders. `initialValue` is used only on the first render. **Mutating `current` does not trigger a re-render.**

---

## Two use cases

### 1. DOM refs

Pass the ref to a JSX `ref` attribute; React sets `ref.current` to the DOM node after commit.

Use for imperative APIs the declarative model can't express:
- Focus, blur, text selection
- Media playback (`play`, `pause`, `currentTime`)
- Scroll position (`scrollTo`, `scrollIntoView`)
- Measuring layout (see [[React Hooks - useLayoutEffect]])
- Integrating non-React libraries (Leaflet, D3, jQuery plugins)

### 2. Mutable instance values that must NOT re-render

- Timer IDs (`setInterval`, `setTimeout`)
- `AbortController` for in-flight fetch cancellation
- Previous-value tracking (`prevValue`)
- Cached calculations that don't affect UI
- WebSocket instances, subscription handles

---

## When NOT to use

**Rule of thumb:** *"If it affects what the user sees, it belongs in [[React Hooks - useState]]."*

Do **not** read or write `ref.current` **during rendering**. React can call components multiple times (Strict Mode double-invoke, concurrent rendering) so mid-render mutation is a purity violation. Access refs **inside event handlers or effects only**.

---

## Minimal correct example — DOM ref

```tsx
function TextInput() {
  const inputRef = useRef<HTMLInputElement>(null);

  return (
    <>
      <input ref={inputRef} />
      <button onClick={() => inputRef.current?.focus()}>Focus</button>
    </>
  );
}
```

Ref is `null` before the first commit — always guard with optional chaining.

---

## Minimal correct example — mutable value

```tsx
function Stopwatch() {
  const [startTime, setStartTime] = useState<number | null>(null);
  const intervalRef = useRef<number | null>(null);

  function start() {
    setStartTime(Date.now());
    intervalRef.current = window.setInterval(tick, 100);
  }

  function stop() {
    if (intervalRef.current !== null) clearInterval(intervalRef.current);
    intervalRef.current = null;
  }
}
```

`intervalRef` survives across renders without causing them.

---

## Anti-pattern: ref used as state

```jsx
// ❌ Value updates but the UI does not — ref writes don't re-render
function Counter() {
  const count = useRef(0);
  return <button onClick={() => count.current++}>{count.current}</button>;
}
```

```jsx
// ✅ useState — the button re-renders with the new count
function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={() => setCount(c => c + 1)}>{count}</button>;
}
```

---

## useImperativeHandle — customize what the parent sees via ref

Signature:

```ts
useImperativeHandle<T, R extends T>(
  ref: Ref<T>,
  createHandle: () => R,
  dependencies?: DependencyList
): void;
```

Lets a component expose an **imperative API** to its parent instead of the raw DOM node.

React's docs actively discourage it: *"If you can express something as a prop, you should not use a ref."*

Justified only for:
- Focus / scroll / animate on demand from parent
- Wrapping multiple internal refs behind one composite handle
- Restricting the surface (`{ focus, scrollIntoView }`) so callers can't reach into internals

### React 19 — ref as a prop

```tsx
function MyInput({ ref }: { ref: Ref<{ focus: () => void }> }) {
  const inputRef = useRef<HTMLInputElement>(null);
  useImperativeHandle(ref, () => ({
    focus: () => inputRef.current?.focus(),
  }), []);
  return <input ref={inputRef} />;
}
```

### React 18 and earlier — with forwardRef

```tsx
const MyInput = forwardRef<{ focus: () => void }>((_, ref) => {
  const inputRef = useRef<HTMLInputElement>(null);
  useImperativeHandle(ref, () => ({
    focus: () => inputRef.current?.focus(),
  }), []);
  return <input ref={inputRef} />;
});
```

### Anti-pattern: imperative handle for declarative state

```jsx
// ❌ Parent manages refs and effects just to open/close a modal
useImperativeHandle(ref, () => ({
  open: () => setOpen(true),
  close: () => setOpen(false),
}));
modalRef.current?.open();

// ✅ Prop-driven — declarative, testable, no ref plumbing
<Modal isOpen={isOpen} onClose={() => setIsOpen(false)} />
```

---

## Caveats

- Under Strict Mode, refs are created twice in dev; one copy is discarded — don't put side effects in `useRef(() => setup())`.
- Refs are `null` before the first commit — always guard.
- Don't mutate objects held in a ref if any component reads them during render — cross-boundary tearing.
- `useRef` returns the same object every render — don't check `ref === prevRef`, it always is.

---

## Summary

| Need | Hook |
|------|------|
| Value that drives UI | [[React Hooks - useState]] |
| DOM node access | `useRef` + JSX `ref` attribute |
| Mutable instance value (timer, controller, prev) | `useRef` |
| Expose imperative API to parent | `useImperativeHandle` (rare — prefer props) |

---

## Related

- [[React Hooks - useState]] — when the value should re-render
- [[React Hooks - useLayoutEffect]] — measuring the DOM node from the ref
- [[React Hooks - Rules of Hooks]]
