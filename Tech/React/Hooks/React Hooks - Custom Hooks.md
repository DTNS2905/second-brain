---
tags:
  - react
  - hooks
  - custom-hooks
  - patterns
  - frontend
created: 2026-07-15
source: https://react.dev/learn/reusing-logic-with-custom-hooks
---

# React Hooks — Custom Hooks

> Reuse **stateful logic**, not state. Part of [[React Hooks Guide]].

---

## What makes a function a hook

A function is a hook if and only if it **calls other hooks**. That's the entire distinction — hooks are just JS functions with a naming convention that flags them for the linter.

## Naming convention

- Prefix with `use` + a capital letter: `useOnlineStatus`, `useFormInput`, `useChatRoom`.
- If the function does **not** call any hooks, do **not** prefix it with `use` — that would prevent callers from using it conditionally.
- Conversely, if it calls hooks, it **must** be prefixed so the linter enforces [[React Hooks - Rules of Hooks]] at the call site.

```jsx
// ✅ Uses hooks → must start with `use`
function useOnlineStatus() {
  return useSyncExternalStore(subscribe, () => navigator.onLine);
}

// ✅ Pure function → no `use` prefix (callable conditionally)
function getSorted(items) {
  return items.slice().sort();
}
```

---

## Sharing logic, not state

Each call site gets its **own independent state**:

```jsx
function useFormInput(initial: string) {
  const [value, setValue] = useState(initial);
  return { value, onChange: (e) => setValue(e.target.value) };
}

function LoginForm() {
  const username = useFormInput('');
  const password = useFormInput('');
  // username.value and password.value are INDEPENDENT state slots
}
```

If you actually need **shared** state across components, lift it or use [[React Hooks - useContext]] — not a custom hook.

---

## Composition

Custom hooks can call any other hooks, including other custom hooks. Pass reactive values (props, state) in and let the hook manage its own effects:

```tsx
function useChatRoom({ serverUrl, roomId, onReceiveMessage }: Options) {
  const onMessage = useEffectEvent(onReceiveMessage);

  useEffect(() => {
    const conn = createConnection({ serverUrl, roomId });
    conn.on('message', onMessage);
    conn.connect();
    return () => conn.disconnect();
  }, [serverUrl, roomId]);
}
```

`useEffectEvent` lets the effect read fresh callback props without forcing re-runs when the parent re-renders with a new function reference.

---

## When to extract a custom hook

- Duplicated effect logic across two or more components.
- Effects that synchronize with an external system (WebSocket, `resize`, `matchMedia`).
- Complex state transitions that clutter a component.
- Testable stateful logic you want to unit-test in isolation.

## When NOT to extract

- One-off logic used in a single component — extract only when duplication or complexity earns it.
- Pure computation with no hooks — write a plain function (`getSorted`, not `useSorted`).
- Generic "lifecycle" wrappers like `useMount(fn)` — they mask missing dependencies and defeat the linter.

---

## Anti-pattern: generic lifecycle wrappers

```jsx
// ❌ Hides deps from ESLint — nothing tells you `fn` might capture stale state
function useMount(fn: () => void) {
  useEffect(() => { fn(); }, []);
}

function C({ userId }) {
  useMount(() => init(userId)); // stale userId if it changes later
}
```

```jsx
// ✅ Use useEffect directly with real deps
useEffect(() => { init(userId); }, [userId]);
```

The linter can't see through the `useMount` boundary to warn about missing deps.

---

## Anti-pattern: too-abstract "do everything" hook

```jsx
// ❌ Grab-bag interface, unclear when to use it
function useLogic(url, onData, onError, shouldFetch, delay) { /* ... */ }
```

```jsx
// ✅ Focused, high-level purpose
function useData(url: string) {
  const [data, setData] = useState(null);
  useEffect(() => {
    let ignore = false;
    fetch(url).then(r => r.json()).then(d => { if (!ignore) setData(d); });
    return () => { ignore = true; };
  }, [url]);
  return data;
}
```

Rule of thumb: name the hook after **what it does at a high level** (`useChatRoom`, `useOnlineStatus`), not the mechanism (`useEffectWithCleanup`, `useSubscribable`).

---

## Anti-pattern: `use` prefix on a non-hook

```jsx
// ❌ Doesn't call any hooks — linter now blocks conditional calls
function useSorted(items) {
  return items.slice().sort();
}

// You can no longer do this:
if (needSorted) useSorted(items); // ❌ rules-of-hooks violation
```

```jsx
// ✅ Plain function — safe to call anywhere
function getSorted(items) {
  return items.slice().sort();
}
```

Reserve `use*` for functions that genuinely call other hooks.

---

## Structure of a well-designed custom hook

```tsx
function useFeature(reactiveInput: Input, callbackProp?: CallbackProp) {
  // 1. Local state / refs
  const [state, setState] = useState(initial);
  const ref = useRef<Handle>(null);

  // 2. Stable callback via useEffectEvent (or useCallback)
  const stableCallback = useEffectEvent(callbackProp ?? noop);

  // 3. Effects with correct deps
  useEffect(() => {
    // subscribe / connect
    return () => { /* cleanup */ };
  }, [reactiveInput]);

  // 4. Return a stable, minimal API
  return { state, doSomething };
}
```

Return a **small, stable object** — don't leak internal setters unless the caller needs them.

---

## Debugging with `useDebugValue`

For library authors — label the hook in React DevTools. See [[React Hooks - Store and Utility Hooks]].

```jsx
function useOnlineStatus() {
  const online = useSyncExternalStore(subscribe, getSnapshot);
  useDebugValue(online ? 'Online' : 'Offline');
  return online;
}
```

---

## Summary

| Do | Don't |
|----|-------|
| Extract when logic repeats or manages external state | Extract every effect "just in case" |
| Name by high-level purpose | Name by mechanism (`useEffectWithCleanup`) |
| Return a minimal, stable API | Leak every internal setter |
| Use `use*` only when calling other hooks | `use*` prefix on pure functions |
| Pass reactive values as arguments | Read stale closure values inside |

---

## Related

- [[React Hooks - Rules of Hooks]] — every custom hook must follow them
- [[React Hooks - useEffect]] — the most common building block
- [[React Hooks - useMemo]] / [[React Hooks - useCallback]] — for stable returns
- [[React Hooks - Store and Utility Hooks]] — `useDebugValue` for DevTools labels
