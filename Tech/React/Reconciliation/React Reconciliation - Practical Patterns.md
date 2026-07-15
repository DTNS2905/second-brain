---
tags:
  - react
  - performance
  - frontend
  - reconciliation
  - patterns
created: 2026-06-08
source: https://www.developerway.com/posts/reconciliation-in-react
---

# Practical Patterns from Reconciliation Rules

> Part 4 of [[React Reconciliation Guide]]

---

## Anti-pattern: Defining Components Inside Render

The most impactful anti-pattern revealed by reconciliation rules.

```jsx
// ❌ NEVER — SlowList is a new function reference every render
const Parent = () => {
  const SlowList = ({ items }) => (
    <ul>{items.map(i => <li key={i.id}>{i.text}</li>)}</ul>
  );

  return <SlowList items={data} />;
};
```

**What happens:**
- On every `Parent` re-render, `SlowList` is a new function
- React sees a **different type** at that position
- `SlowList` is **unmounted and remounted** — not updated
- All child state resets, all effects re-run, inputs lose focus

```jsx
// ✅ CORRECT — define outside, stable function reference
const SlowList = ({ items }) => (
  <ul>{items.map(i => <li key={i.id}>{i.text}</li>)}</ul>
);

const Parent = () => <SlowList items={data} />;
```

---

## Pattern: Use key to Reset State on Data Change

When a component has internal state that should reset when its "identity" changes, add a `key` tied to that identity.

```jsx
// ❌ Problem — UserProfile keeps old state (e.g. active tab) when user changes
const UserPage = ({ userId }) => <UserProfile userId={userId} />;

// ✅ Fix — key forces full remount, state starts fresh
const UserPage = ({ userId }) => <UserProfile key={userId} userId={userId} />;
```

Common cases: user switching, document switching, wizard steps.

---

## Pattern: State Colocation (Leverage Reconciliation Boundaries)

Moving state down to the component that owns it prevents re-renders from crossing reconciliation boundaries.

```jsx
// ❌ Filter state in App causes ExpensiveComponent to re-render
const App = () => {
  const [filter, setFilter] = useState('');
  return (
    <>
      <SearchBox filter={filter} onChange={setFilter} />
      <UserList filter={filter} />
      <ExpensiveComponent />   {/* ← unnecessary re-render */}
    </>
  );
};

// ✅ Filter state colocated — ExpensiveComponent never re-renders
const UserSection = () => {
  const [filter, setFilter] = useState('');
  return (
    <>
      <SearchBox filter={filter} onChange={setFilter} />
      <UserList filter={filter} />
    </>
  );
};

const App = () => (
  <>
    <UserSection />
    <ExpensiveComponent />
  </>
);
```

---

## Pattern: Conditional Rendering — Control Type Stability

If you want state to **persist** across a conditional toggle, keep the same element type at the same position.

```jsx
// ✅ State preserved — both branches are <input>, same type, same position
{isEditing
  ? <input placeholder="Enter name" />
  : <input placeholder="Enter name" disabled />
}

// ❌ State lost — type changes from input to div
{isEditing
  ? <input placeholder="Enter name" />
  : <div>Name will appear here</div>
}
```

If you **want** a reset, use different types or different keys.

---

## Pattern: Conditional Rendering — Avoid Changing Component Type

```jsx
// ❌ Changing wrapper type destroys all children state
return condition
  ? <div><HeavyForm /></div>
  : <section><HeavyForm /></section>;
// → HeavyForm remounts on every condition toggle

// ✅ Keep the same wrapper, only change the attribute
return (
  <div className={condition ? 'style-a' : 'style-b'}>
    <HeavyForm />
  </div>
);
```

---

## Debugging Checklist

| Symptom | Likely Cause |
|---------|-------------|
| Input loses focus on every keystroke | Component defined inside render (new type each render) |
| Form state resets unexpectedly | Parent type changed at that position |
| List items flash/reset state | Index keys on dynamic list, or random keys |
| `useEffect` fires too often | Component remounting due to unstable key or type |
| Memoization has no effect | Component defined inside render (new function ref) |

---

## Related

- [[React Reconciliation - Diffing Algorithm]] — the rules behind these patterns
- [[React Reconciliation - Keys]] — key-based patterns
- [[React Re-renders - Preventing with Composition]] — composition patterns
- [[React Re-renders Guide]] — re-renders overview
