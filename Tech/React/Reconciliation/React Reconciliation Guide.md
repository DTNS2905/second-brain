---
tags:
  - react
  - performance
  - frontend
  - reconciliation
created: 2026-06-08
source: https://www.developerway.com/posts/reconciliation-in-react
---

# React Reconciliation Guide

> How React decides what to update in the DOM — the algorithm behind every render, re-render, mount, and unmount.

## What is Reconciliation?

Reconciliation is React's process of comparing the **new element tree** (from a re-render) against the **previous tree**, then computing the minimal set of DOM mutations needed to sync them.

React follows 3 steps every render:
1. Create a new element tree by calling your components
2. Diff the new tree against the previous tree
3. Apply only the necessary DOM operations

---

## Contents

1. [[React Reconciliation - Virtual DOM and Fiber]]
2. [[React Reconciliation - Diffing Algorithm]]
3. [[React Reconciliation - Keys]]
4. [[React Reconciliation - Practical Patterns]]

---

## Core Mental Model

```
JSX → React.createElement() → Element Object Tree
                                      ↓
                              Fiber Tree (internal)
                                      ↓
                         Diff old vs new Fiber Tree
                                      ↓
                          Commit minimal DOM changes
```

### JSX is just objects

```js
<div><h1>Hello</h1></div>
// becomes:
{ type: 'div', props: { children: { type: 'h1', props: { children: 'Hello' } } } }
```

For custom components, `type` is the **function reference itself**.

---

## The Two Golden Rules

| Rule | What happens |
|------|-------------|
| **Same position + Same type** | React *reuses* the existing component instance, updates props only |
| **Same position + Different type** | React *unmounts* the old subtree entirely and *mounts* a fresh one |

> These rules are why defining components inside render functions is an anti-pattern — the function reference is new every render, so React sees a "different type" every time.

---

## Related Notes

- [[React Re-renders Guide]] — what triggers re-renders
- [[React Re-renders - Preventing with Composition]] — patterns that leverage reconciliation rules
- [[React Re-renders - List Performance]] — key attribute basics
