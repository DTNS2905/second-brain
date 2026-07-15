---
tags:
  - react
  - performance
  - frontend
  - lists
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# List Performance & the `key` Attribute

> Part 5 of [[React Re-renders Guide]]

---

## How React Uses `key`

React uses the `key` attribute to identify which items in a list changed, were added, or were removed between renders. A stable key = React updates the existing component. An unstable key = React **unmounts and remounts** the component.

---

## Rules for `key` Values

| Rule | Reason |
|------|--------|
| Use a **stable, unique string** per item | Allows React to track identity across renders |
| Prefer **item IDs** from your data | IDs don't change; indices can shift |
| Array index is OK for **static lists** only | Static = never reordered, added, or removed |

---

## Anti-pattern: Random Keys

```jsx
// ❌ NEVER DO THIS — forces unmount/remount on every render
items.map((item) => (
  <Component key={Math.random()} item={item} />
));
```

**Consequences:**
- Severe performance degradation
- State resets on every render
- Input fields lose their values
- Animations/transitions break

---

## Anti-pattern: Index Keys in Dynamic Lists

```jsx
// ❌ Risky for dynamic lists
items.map((item, index) => (
  <Component key={index} item={item} />
));
```

**Problems when items are reordered, added, or removed:**
- State-related bugs (wrong item gets the wrong state)
- Form inputs end up with wrong values
- `React.memo` optimizations break — item at index 0 is "the same" even if it changed

---

## Correct Pattern

```jsx
// ✅ Use stable IDs
items.map((item) => (
  <Component key={item.id} item={item} />
));
```

---

## When Index Keys Are Acceptable

- The list is **purely static** — no additions, removals, or reordering ever
- Items have no internal state
- Items are not memoized with `React.memo`

Example: a static navigation menu rendered from a fixed array.

---

## Related

- [[React Re-renders - Preventing with React.memo]] — key instability defeats memo
- [[React Re-renders Guide]] — back to index
