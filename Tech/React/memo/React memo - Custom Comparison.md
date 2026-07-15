---
tags:
  - react
  - memo
  - frontend
created: 2026-06-08
source: https://react.dev/reference/react/memo
---

# React memo - Custom Comparison

> The `arePropsEqual` second argument to `memo()` — when and how to override shallow comparison. Part of [[React memo Guide]].

---

## Signature

```js
const MemoizedComponent = memo(Component, arePropsEqual);

function arePropsEqual(oldProps, newProps) {
  // return true  → props "equal" → SKIP re-render
  // return false → props differ  → TRIGGER re-render
}
```

The return value is the **opposite** of what you'd expect from a `shouldUpdate` function — returning `true` means "no update needed."

---

## When to Use

Use `arePropsEqual` when:
- Props contain large arrays or objects where shallow comparison gives false negatives (always "different" even when semantically equal)
- You can do a cheaper domain-specific comparison than full deep equality
- You need to intentionally **ignore** certain prop changes (e.g., a callback that changes identity but is functionally identical)

---

## Example: Large Array of Points

```jsx
const Chart = memo(function Chart({ dataPoints }) {
  // expensive rendering...
}, arePropsEqual);

function arePropsEqual(oldProps, newProps) {
  if (oldProps.dataPoints.length !== newProps.dataPoints.length) {
    return false;
  }
  return oldProps.dataPoints.every((oldPoint, index) => {
    const newPoint = newProps.dataPoints[index];
    return oldPoint.x === newPoint.x && oldPoint.y === newPoint.y;
  });
}
```

This avoids re-renders when the array reference changes but all data values are the same.

---

## ⚠️ Critical Warnings

### Must compare ALL props

```jsx
// ❌ Dangerous — ignores the onClick prop entirely
function arePropsEqual(oldProps, newProps) {
  return oldProps.value === newProps.value;
  // onClick changes are silently ignored → stale closures
}

// ✅ Correct — compare every prop
function arePropsEqual(oldProps, newProps) {
  return (
    oldProps.value === newProps.value &&
    oldProps.onClick === newProps.onClick
  );
}
```

Forgetting a prop — especially a function — causes **stale closure bugs**: the component renders with outdated handler references.

### Don't use deep equality libraries naively

```jsx
// ❌ Slow — O(n) deep comparison on every render check
import isEqual from 'lodash/isEqual';
const MemoComp = memo(Component, isEqual);

// Prefer: make props stable upstream (useMemo/useCallback) instead
```

Deep comparison can be slower than just re-rendering. Prefer fixing prop stability at the source — see [[React memo - Stable Props]].

### Don't use to implement incorrect behavior

```jsx
// ❌ Wrong use — hiding a legitimate re-render
function arePropsEqual(oldProps, newProps) {
  return true;  // never re-render — breaks the component
}
```

`arePropsEqual` is a performance optimization, not a way to suppress functionally necessary re-renders.

---

## Correct Custom Comparison Template

```jsx
function arePropsEqual(oldProps, newProps) {
  // 1. Check counts / fast-path first
  if (oldProps.items.length !== newProps.items.length) return false;

  // 2. Check all other props first (including callbacks)
  if (oldProps.onSelect !== newProps.onSelect) return false;
  if (oldProps.label !== newProps.label) return false;

  // 3. Deep-check only what's necessary
  return oldProps.items.every(
    (item, i) => item.id === newProps.items[i].id
  );
}
```

---

## Custom Comparison vs. Making Props Stable

| Approach | Best when |
|----------|-----------|
| `arePropsEqual` | Can't control how props are created upstream; domain equality differs from reference equality |
| `useMemo` / `useCallback` upstream | You control the parent; simpler and more maintainable |
| Primitive decomposition | Object props can be split into primitives |

Prefer upstream stabilization — it's less error-prone than a custom comparison that must track all props manually.

---

## Summary

| Rule | Detail |
|------|--------|
| Return `true` | Props "equal" → skip re-render |
| Return `false` | Props differ → trigger re-render |
| Compare ALL props | Missing one prop = stale closure risk |
| Avoid deep equality libs | Slower than re-rendering for most cases |
| Not a guarantee | React may still re-render regardless |

---

## Related Notes

- [[React memo - API Reference]] — default shallow comparison behavior
- [[React memo - Stable Props]] — preferred alternative to custom comparison
- [[React Re-renders - useMemo and useCallback]] — stabilizing props at the source
