---
tags:
  - react
  - performance
  - frontend
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# React Re-renders Guide

> Complete reference from Nadia Makarevich's guide on React re-renders — what causes them, what doesn't, and how to prevent unnecessary ones.

## What is a Re-render?

- **First render** — component appears on screen for the first time
- **Re-render** — second and any consecutive render of a component already on screen
- Triggered by: user interaction or async data (state update, context change, etc.)

### Necessary vs Unnecessary

| Type | Description |
|------|-------------|
| **Necessary** | Component is the *source* of a change, or directly uses new data |
| **Unnecessary** | Propagated via re-render mechanisms due to mistake or bad architecture |

> Unnecessary re-renders are **not inherently bad** — React is fast. They become a problem only when they happen too frequently on **heavy components**.

---

## Contents

1. [[React Re-renders - Why Components Re-render]]
2. [[React Re-renders - Preventing with Composition]]
3. [[React Re-renders - Preventing with React.memo]]
4. [[React Re-renders - useMemo and useCallback]]
5. [[React Re-renders - List Performance]]
6. [[React Re-renders - Context Re-renders]]

---

## Quick Reference

### The 4 Triggers of Re-renders
1. **State change** — root of all re-renders
2. **Parent re-render** — re-renders flow *down*, never up
3. **Context change** — all consumers re-render, even if they don't use the changed part
4. **Hook change** — hooks "belong" to their host component

### The Props Myth
> Props changing **does not** cause a re-render on its own for non-memoized components.
> Props only matter when using `React.memo`.

### Prevention Priority (use in order)
1. **Composition** — move state down, children/components as props
2. **React.memo** — wrap stable components
3. **useMemo / useCallback** — last resort, requires all props memoized
