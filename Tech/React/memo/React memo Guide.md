---
tags:
  - react
  - memo
  - frontend
created: 2026-06-08
source: https://react.dev/reference/react/memo
---

# React memo Guide

> Complete API reference for `React.memo` — skip re-renders when props are unchanged.

---

## Contents

| Note | Covers |
|------|--------|
| [[React memo - API Reference]] | Signature, parameters, return value, state/context caveats |
| [[React memo - Stable Props]] | useMemo + useCallback to prevent memo from being bypassed |
| [[React memo - Custom Comparison]] | `arePropsEqual` function for non-shallow comparisons |

---

## Quick Reference

```js
import { memo } from 'react';

const MemoizedComponent = memo(SomeComponent, arePropsEqual?);
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Component` | React component | ✅ | The component to memoize |
| `arePropsEqual` | `(oldProps, newProps) => boolean` | ❌ | Custom comparison; default is shallow (`Object.is`) |

**Returns:** A new component identical to the original but skips re-renders when props haven't changed.

---

## What Memo Does NOT Prevent

| Trigger | Memo stops it? |
|---------|---------------|
| Parent re-render (same props) | ✅ Yes |
| Parent re-render (changed props) | ❌ No |
| Component's own `useState` change | ❌ No |
| `useContext` value change | ❌ No |

---

## The Core Requirement: Stable Props

`memo` uses **shallow comparison** (`Object.is`). Every non-primitive prop must be referentially stable between renders:

```jsx
// ❌ Breaks memo — new object every render
<MemoComponent config={{ theme: 'dark' }} />

// ✅ Fixes memo — stable reference
const config = useMemo(() => ({ theme: 'dark' }), []);
<MemoComponent config={config} />
```

See [[React memo - Stable Props]] for the full patterns.

---

## React Compiler Makes This Optional

With **React Compiler** enabled, the compiler automatically applies memo-equivalent optimization to all components — manual `memo()` calls become unnecessary.

---

## Related Notes

- [[React Re-renders - Preventing with React.memo]] — memo in the context of re-render patterns
- [[React Re-renders - useMemo and useCallback]] — memoizing values and functions
- [[React Component Composition - Memoization with Children]] — memo interactions with children props
- [[React Re-renders - Preventing with Composition]] — composition as an alternative to memo
