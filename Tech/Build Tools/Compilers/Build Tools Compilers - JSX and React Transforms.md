---
tags:
  - build-tools
  - compilers
  - jsx
  - react
  - tooling
  - frontend
created: 2026-07-16
source: https://legacy.reactjs.org/blog/2020/09/22/introducing-the-new-jsx-transform.html
---

# Build Tools Compilers — JSX and React Transforms

> Every React app runs through at least three transforms: JSX → function calls, TS erasure, and (in dev) Fast Refresh. This note maps each transform to its role, tool, and pitfalls. Part of [[Build Tools Compilers Guide]].

---

## The three transforms every React app runs

1. **JSX** — the `<Foo />` → function-call transform
2. **TS erasure** — strip type annotations
3. **Fast Refresh** (dev only) — insert HMR runtime hooks

The React Compiler (auto-memoization) adds a fourth, opt-in transform. All four are separate passes; a build pipeline may run them in any tool (Babel, SWC, esbuild, tsc) as long as the output is valid JS that React understands at runtime.

---

## Classic JSX runtime

The old default, deprecated in favor of the automatic runtime but still supported.

```jsx
// Source
const el = <div className="x">hi</div>;

// Output (classic)
const el = React.createElement('div', { className: 'x' }, 'hi');
```

Requires `React` in scope in every file. Verbose imports (`import React from 'react'`) even in files that only use JSX and don't otherwise touch the React namespace. The bundle pays for that import in every module.

```jsx
❌ Classic runtime — noise in every file
import React from 'react';
export const Badge = () => <span>new</span>;

✅ Automatic runtime — no React import needed
export const Badge = () => <span>new</span>;
```

---

## Automatic JSX runtime

Default since React 17 (2020+). The compiler injects imports from `react/jsx-runtime` for you.

```jsx
// Source
const el = <div className="x">hi</div>;

// Output (automatic)
import { jsx as _jsx } from 'react/jsx-runtime';
const el = _jsx('div', { className: 'x', children: 'hi' });
```

Key differences from `createElement`:

- No `React` import required
- Children are passed as a `children` prop, not positional args → smaller output for elements with many children
- Splits into `jsx` (single/no children), `jsxs` (static children array), and `jsxDEV` variants — the runtime can skip work in the hot path
- `key` is passed as its own argument to `_jsx`, not mixed with props → fixes the long-standing "spread props overwrites key" footgun

---

## tsconfig for automatic runtime

```json
{
  "compilerOptions": {
    "jsx": "react-jsx",
    "jsxImportSource": "react"
  }
}
```

Options for `jsx`:

| Value | Behavior |
|-------|----------|
| `"preserve"` | Keep JSX as-is; bundler transforms it |
| `"react"` | Classic runtime (`React.createElement`) |
| `"react-jsx"` | Automatic runtime (recommended) |
| `"react-jsxdev"` | Automatic + dev diagnostics (`jsxDEV`) |
| `"react-native"` | RN's own `createElement` transform |

`jsxImportSource` swaps the runtime module — set it to `preact`, `solid-js`, `theme-ui`, etc. to reuse the JSX transform for other libraries. Emotion's `/** @jsxImportSource @emotion/react */` pragma works the same way per-file.

---

## Babel config for automatic runtime

```js
// babel.config.js
module.exports = {
  presets: [
    ['@babel/preset-react', { runtime: 'automatic', importSource: 'react' }],
  ],
};
```

`development: true` flips to `jsxDEV` for source-location info. Frameworks (Next.js, Vite's Babel path) set this based on `NODE_ENV`.

---

## SWC config for automatic runtime

```json
{
  "jsc": {
    "transform": {
      "react": {
        "runtime": "automatic",
        "importSource": "react",
        "development": false,
        "refresh": false
      }
    }
  }
}
```

Same options mapped 1:1 from Babel. `refresh: true` layers Fast Refresh on top (see below). Cross-link [[Build Tools Compilers - SWC Internals]].

---

## esbuild config for automatic runtime

```js
// esbuild flags
{
  jsx: 'automatic',
  jsxImportSource: 'react',
  jsxDev: false,
}
```

esbuild only does the JSX transform — no Fast Refresh, no React Compiler. Fine for prod bundles, but dev needs another tool layered on (Vite pairs esbuild's transform with its own Fast Refresh plugin).

---

## React Compiler

Ships as `babel-plugin-react-compiler` (stable 2026). Analyzes each function component and inserts memoization automatically — no `useMemo`, `useCallback`, or `React.memo` calls by hand.

```jsx
// Source
function Chart({ data, filter }) {
  const filtered = data.filter(filter);
  const sum = filtered.reduce((a, b) => a + b, 0);
  return <div>{sum}</div>;
}

// Output (conceptually)
function Chart({ data, filter }) {
  const $memo = useMemoCache(3);
  const filtered =
    $memo[0] === data && $memo[1] === filter
      ? $memo[2]
      : ($memo[0] = data, $memo[1] = filter, $memo[2] = data.filter(filter));
  const sum =
    $memo[3] === filtered
      ? $memo[4]
      : ($memo[3] = filtered, $memo[4] = filtered.reduce((a, b) => a + b, 0));
  return <div>{sum}</div>;
}
```

```js
// Babel config
module.exports = {
  plugins: [['babel-plugin-react-compiler', {}]],
  presets: [['@babel/preset-react', { runtime: 'automatic' }]],
};
```

The plugin must run **before** `@babel/preset-react` — it works on JSX, not on `createElement` calls.

Cross-link [[React Re-renders Guide]] and [[React memo Guide]] — the Compiler subsumes most manual memoization. Once enabled, most `useMemo`/`useCallback`/`React.memo` calls in a codebase become dead weight.

---

## Fast Refresh transform

Both Babel (`react-refresh/babel`) and SWC (`transform.react.refresh: true`) insert two families of calls:

- `$RefreshSig$()` — signature hash of the component's hooks; forces remount if the hook signature changes
- `$RefreshReg$(Component, 'name')` — registers each component export with the refresh runtime

```js
// Source
export function App(props) {
  const [count, setCount] = useState(0);
  return <div>{count}</div>;
}

// Compiled output (simplified)
var _s = $RefreshSig$();
export function App(props) {
  _s();
  const [count, setCount] = useState(0);
  return <div>{count}</div>;
}
_s(App, 'useState{count}');
$RefreshReg$(App, 'App');
```

The React Refresh runtime (bundled in dev) reads these registrations and, on HMR, replaces the component implementation while preserving state. If the hook signature changed (order, count, or custom hook identity), it remounts instead — silently swapping would corrupt hook state.

Cross-link [[Build Tools Dev Server and HMR - React Fast Refresh]].

---

## Server/client boundary directives

RSC introduces `'use client'` and `'use server'` string directives at file tops. These are consumed by the **bundler**, not the JS runtime:

```jsx
'use client';

import { useState } from 'react';
export default function Counter() {
  const [n, setN] = useState(0);
  return <button onClick={() => setN(n + 1)}>{n}</button>;
}
```

Bundlers treat `'use client'` as a signal to:

- Emit a client-reference (a placeholder that the RSC runtime resolves at request time)
- Move this module into the client bundle graph
- Stop tree-walking into it from the server graph

```jsx
'use server';

export async function addTodo(text: string) {
  await db.todo.create({ data: { text } });
}
```

`'use server'` marks a module (or a single function) as a callable RPC endpoint. The bundler replaces the export with a client-side stub that posts to the server. Cross-link [[Build Tools Meta-frameworks - RSC and the Bundler]].

---

## Development helpers

Both runtimes attach source-location metadata for DevTools stack traces:

| Field | Runtime | Purpose |
|-------|---------|---------|
| `__source` | Classic (`@babel/plugin-transform-react-jsx-source`) | `{ fileName, lineNumber, columnNumber }` |
| `__self` | Classic (`@babel/plugin-transform-react-jsx-self`) | `this` at JSX site — for warnings |
| `jsxDEV(type, props, key, isStatic, source, self)` | Automatic | Same info, single call |

Enable via `"jsx": "react-jsxdev"` (tsc) or `development: true` (Babel/SWC). Prod builds should drop these — they're noise in the output and leak file paths.

---

## Common pitfalls

```
❌ Using classic runtime in a new project → verbose React imports
✅ Set "jsx": "react-jsx" in tsconfig

❌ Adding React.memo everywhere with React Compiler enabled
✅ Trust the compiler; use React.memo only when profiling shows it's needed

❌ 'use client'; at the top of a file that uses server-only APIs (fs, db)
✅ 'use client' marks a client boundary; keep server APIs in a server module

❌ Fast Refresh not working → mixing named exports of hooks and components
✅ One component per file; keep hook exports in dedicated files

❌ React Compiler after preset-react in Babel plugin order → sees createElement, bails out
✅ Order plugins so react-compiler runs before the JSX transform

❌ Setting jsxImportSource but forgetting the runtime is installed
✅ npm install the source package (react, preact, etc.) — the transform emits an import
```

---

## Summary table — which tool does which transform

| Transform | Babel | SWC | esbuild | tsc |
|-----------|-------|-----|---------|-----|
| JSX → `jsx()` | ✅ `@babel/preset-react` | ✅ `jsc.transform.react` | ✅ `jsx: 'automatic'` | ✅ (with `preserve` off) |
| TS erasure | ✅ `@babel/preset-typescript` | ✅ `parser.syntax: 'typescript'` | ✅ built-in | ✅ (source of truth) |
| Fast Refresh | ✅ `react-refresh/babel` | ✅ `transform.react.refresh` | ❌ | ❌ |
| React Compiler | ✅ `babel-plugin-react-compiler` | ⚠️ planned | ❌ | ❌ |
| RSC boundary directives | Handled at **bundler** level (Turbopack, Webpack RSC loader, Vite RSC), not compiler | | | |

Takeaway: **Babel is still the only tool that runs every React transform**. SWC covers the common path (JSX + TS + Fast Refresh); esbuild and tsc handle only the two syntactic transforms. Most stacks converge on SWC for speed and bolt Babel back on solely for the React Compiler until SWC's port lands.

---

## Related

- [[Build Tools Compilers - Babel Internals]]
- [[Build Tools Compilers - SWC Internals]]
- [[Build Tools Dev Server and HMR - React Fast Refresh]]
- [[Build Tools Meta-frameworks - RSC and the Bundler]]
- [[React Re-renders Guide]] — where React Compiler fits
- [[Build Tools Compilers Guide]]
