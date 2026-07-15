---
tags:
  - react
  - performance
  - frontend
  - reconciliation
  - keys
created: 2026-06-08
source: https://www.developerway.com/posts/reconciliation-in-react
---

# Keys — Overriding Position-Based Identity

> Part 3 of [[React Reconciliation Guide]]

---

## What Keys Do

By default React identifies elements by their **position in the tree**. The `key` attribute lets you override this with an **explicit identity** — independent of position.

> Same key = same component. Different key = different component (unmount + remount).

---

## Keys in Lists (Primary Use Case)

Without keys, React matches list items by index. When you insert an item at the front, React sees every position as changed → re-renders the entire list.

```jsx
// ❌ No keys — inserting at front causes all items to re-render
<ul>
  {items.map((item) => <li>{item.text}</li>)}
</ul>

// ✅ With stable keys — React matches by id, only new item is mounted
<ul>
  {items.map((item) => <li key={item.id}>{item.text}</li>)}
</ul>
```

**Why index keys are bad for dynamic lists:**

```jsx
// Items: [A, B, C] — keys: [0, 1, 2]
// Insert at front: [X, A, B, C] — keys: [0, 1, 2, 3]
// React sees: key=0 changed from A→X, key=1 changed from B→A, etc.
// → Treats every existing item as "changed", not just the new one
// → State bugs: the state that was on A now lives on key=0 (X's position)
```

---

## Keys Outside Lists — Forcing Remount

Keys work anywhere in JSX, not just in lists. Changing a key **forces React to unmount and remount** that component — regardless of type or position.

### Use Case 1: Reset component state when props change

```jsx
// ❌ Without key — UserProfile keeps old state when userId changes
const UserPage = ({ userId }) => {
  return <UserProfile userId={userId} />;
};

// ✅ With key — forces fresh mount for each userId
const UserPage = ({ userId }) => {
  return <UserProfile key={userId} userId={userId} />;
};
```

### Use Case 2: Reset uncontrolled inputs

```jsx
// Uncontrolled input's state lives in the DOM, not React state.
// key forces a new DOM element when userId changes.
const UserForm = ({ userId }) => (
  <input key={userId} name="username" defaultValue="" />
);
```

---

## Keys and the Same-Type Rule

Keys take precedence over position. Even if two elements have the **same type at the same position**, different keys force a remount:

```jsx
// Same type (input), same position, but different keys → new DOM element
{isEditing
  ? <input key="edit" placeholder="Enter name" />
  : <input key="view" placeholder="Enter name" disabled />
}
// → Switching isEditing DOES clear typed text (unlike the no-key version)
```

---

## Moving State Between Positions with Keys

A key can "travel" across positions, carrying state with it:

```jsx
const Component = () => {
  const [isReverse, setIsReverse] = useState(false);

  return (
    <>
      <Input key={isReverse ? 'some-key' : null} />
      <Input key={!isReverse ? 'some-key' : null} />
    </>
  );
};
// When isReverse toggles, 'some-key' moves from Input[0] to Input[1].
// React "moves" the component state to the new position.
```

---

## Static Elements Adjacent to Dynamic Lists

```jsx
<>
  {items.map((item) => <ListItem key={item.id} />)}
  <StaticFooter />   {/* always at the end — position stable regardless of list length */}
</>
// React treats the map output as a single unit in position 0.
// StaticFooter is always at position 1 — never affected by list changes.
```

---

## Key Rules Summary

| Scenario | Best Key |
|----------|---------|
| Static list (no add/remove/reorder) | Index is fine |
| Dynamic list | Stable unique ID from data |
| Reset state on prop change | Use the changing prop as key |
| Force fresh mount on demand | Change the key |
| **Never** | `Math.random()` or anything generated at render time |

---

## Related

- [[React Reconciliation - Diffing Algorithm]] — position-based rules keys override
- [[React Re-renders - List Performance]] — key anti-patterns for performance
