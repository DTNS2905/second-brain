---
tags:
  - react
  - performance
  - frontend
  - reconciliation
  - diffing
created: 2026-06-08
source: https://www.developerway.com/posts/reconciliation-in-react
---

# The Diffing Algorithm

> Part 2 of [[React Reconciliation Guide]]

---

## O(n) Heuristic Diffing

A naïve tree diff is O(n³). React uses two heuristic assumptions to achieve **O(n)**:

1. Elements of **different types** produce different trees
2. The `key` attribute hints at stable identity across renders

---

## Rule 1: Different Type at Same Position → Full Remount

When the element **type** at a position changes between renders, React:
- Destroys the **entire old subtree** (unmounts all children, fires cleanups)
- Builds a **fresh new subtree** from scratch

```jsx
// Render 1
<div>
  <Counter />
</div>

// Render 2 — div changed to span
<span>
  <Counter />   {/* ← this Counter is a brand new instance, state is GONE */}
</span>
```

> This is why wrapping with different tags or toggling container types loses all child state.

### Applies to Component Types Too

```jsx
// Render 1: ComponentA at position 0
{isA ? <ComponentA /> : <ComponentB />}

// When isA flips: ComponentB at position 0
// → ComponentA unmounts (state lost), ComponentB mounts fresh
```

---

## Rule 2: Same Type at Same Position → Update in Place

When the element type **stays the same**, React reuses the existing DOM node or component instance and only updates changed props/attributes.

```jsx
// Render 1
<input type="text" placeholder="Enter name" disabled />

// Render 2 — same type (input), just a different prop
<input type="text" placeholder="Enter name" />
// → React updates the `disabled` attribute, does NOT recreate the element
// → Any typed text in the input is preserved!
```

### State Preservation Example

```jsx
const UserInfoForm = () => {
  const [isEditing, setIsEditing] = useState(false);

  return (
    <div>
      <button onClick={() => setIsEditing(!isEditing)}>
        {isEditing ? 'Cancel' : 'Edit'}
      </button>

      {isEditing
        ? <input placeholder="Enter your name" className="edit-input" />
        : <input placeholder="Enter your name" disabled className="view-input" />
      }
    </div>
  );
};
// Toggling isEditing does NOT clear the typed text —
// both branches are <input>, same type, same position.
```

---

## Rule 3: Same Type, Different Component Function Reference → Full Remount

For custom components, `type` is the **function reference**. If the reference changes between renders, React treats it as a different type.

```jsx
// ❌ ANTI-PATTERN — new function reference every render
const Parent = () => {
  const Child = () => <input />;   // new function on every Parent render
  return <Child />;
  // → Child unmounts and remounts every time Parent re-renders
  // → Input loses focus, state resets, effects re-run
};

// ✅ CORRECT — stable reference, defined outside
const Child = () => <input />;

const Parent = () => {
  return <Child />;   // same reference every render → React reuses instance
};
```

---

## Props Diffing (Shallow Comparison)

Once React decides to update (same type), it **shallow-compares** the old and new props:
- Primitive values: compared by value
- Objects / arrays / functions: compared by **reference**

Only changed props trigger DOM attribute updates or component re-renders.

---

## How React Walks the Tree

Fiber traversal order (depth-first):

```
1. Begin work on parent
2. Recurse into first child
3. Process siblings left to right
4. Return to parent
```

Each node is diffed against its counterpart in the previous tree **at the same position**.

---

## Summary Decision Tree

```
Same position between renders?
  └── Same element type?
        ├── YES → update props in place, preserve state
        └── NO  → unmount old subtree, mount new one from scratch
```

---

## Related

- [[React Reconciliation - Keys]] — how keys override position-based identity
- [[React Reconciliation - Virtual DOM and Fiber]] — the engine behind the diff
- [[React Re-renders - Preventing with Composition]] — patterns that exploit these rules
