---
tags:
  - react
  - performance
  - frontend
  - composition
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# Preventing Re-renders with Composition

> Part 2 of [[React Re-renders Guide]]
> Composition patterns are the **most effective** way to prevent re-renders — prefer these over memoization.

---

## Anti-pattern: Creating Components Inside Render

**Never define a component inside another component's render function.**

```jsx
// ❌ BAD — SlowComponent is re-created on every parent re-render
const ParentComponent = () => {
  const SlowComponent = () => <div>...</div>; // new function ref every render
  return <SlowComponent />;
};
```

**Why it's bad:**
- React treats it as a *new* component on every render → **unmounts and remounts** instead of updating
- Causes: content flashes, state resets, `useEffect` re-triggering, lost focus

---

## Pattern 1: Moving State Down

Extract state (and the components that use it) into a smaller child component, isolating re-renders from the rest of the tree.

```jsx
// ❌ BEFORE — state in parent causes full parent re-render (including HeavyComponent)
const ParentComponent = () => {
  const [isOpen, setIsOpen] = useState(false);
  return (
    <div>
      <HeavyComponent />          {/* re-renders unnecessarily */}
      <button onClick={() => setIsOpen(!isOpen)}>Open</button>
      {isOpen && <Modal />}
    </div>
  );
};

// ✅ AFTER — state extracted, HeavyComponent is unaffected
const ModalController = () => {
  const [isOpen, setIsOpen] = useState(false);
  return (
    <>
      <button onClick={() => setIsOpen(!isOpen)}>Open</button>
      {isOpen && <Modal />}
    </>
  );
};

const ParentComponent = () => (
  <div>
    <HeavyComponent />   {/* never re-renders due to modal state */}
    <ModalController />
  </div>
);
```

**When to use:** The state is only needed by a small portion of the render tree.

---

## Pattern 2: Children as Props (Wrap State Around Children)

When state wraps a portion of the tree that can't easily be moved, pass the slow components as `children`. Children are just props — they won't re-render when the wrapper's state changes.

```jsx
// ❌ BEFORE — scroll state causes HeavyComponent to re-render
const ParentComponent = () => {
  const [scrollY, setScrollY] = useState(0);
  return (
    <div onScroll={(e) => setScrollY(e.target.scrollTop)}>
      <HeavyComponent />    {/* re-renders on every scroll */}
    </div>
  );
};

// ✅ AFTER — HeavyComponent is passed as children, unaffected by scroll state
const ScrollTracker = ({ children }) => {
  const [scrollY, setScrollY] = useState(0);
  return (
    <div onScroll={(e) => setScrollY(e.target.scrollTop)}>
      {children}   {/* just a prop — doesn't re-render when scrollY changes */}
    </div>
  );
};

const ParentComponent = () => (
  <ScrollTracker>
    <HeavyComponent />
  </ScrollTracker>
);
```

**Why it works:** `children` is resolved *before* `ScrollTracker` renders. React sees it as a stable prop reference.

---

## Pattern 3: Components as Props

The same concept as children as props, but passing heavy components as **named props** instead of `children`. Useful when you have multiple independent heavy components that need isolation.

```jsx
// ✅ Heavy components passed as props — isolated from state changes inside Wrapper
const Wrapper = ({ left, right }) => {
  const [state, setState] = useState(false);
  return (
    <div>
      <button onClick={() => setState(!state)}>Toggle</button>
      <div>{left}</div>     {/* doesn't re-render on state change */}
      <div>{right}</div>    {/* doesn't re-render on state change */}
    </div>
  );
};

const ParentComponent = () => (
  <Wrapper
    left={<HeavyLeftComponent />}
    right={<HeavyRightComponent />}
  />
);
```

---

## Summary

| Pattern | Use When |
|---------|----------|
| **Move state down** | State only used in a small subtree |
| **Children as props** | State wraps a portion that can't be split out |
| **Components as props** | Multiple independent heavy components need isolation |

> Always try composition patterns **before** reaching for `React.memo` or `useMemo`.
> See: [[React Re-renders - Preventing with React.memo]]
