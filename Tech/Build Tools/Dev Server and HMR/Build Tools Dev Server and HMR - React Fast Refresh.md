---
tags:
  - build-tools
  - dev-server
  - hmr
  - react
  - fast-refresh
  - tooling
  - frontend
created: 2026-07-16
source: https://github.com/facebook/react/tree/main/packages/react-refresh
---

# Build Tools Dev Server and HMR — React Fast Refresh

> The runtime that makes hot-editing React components preserve state. Written by the React team, integrated by every bundler. Understanding what it preserves — and why it sometimes forces a remount — is what makes dev feel fast. Part of [[Build Tools Dev Server and HMR Guide]].

---

## What it preserves

- **Component state** (`useState`, `useReducer`) — yes, if hooks signature hasn't changed
- **Refs** — yes
- **Context values** — yes (unless provider re-mounts)
- **Effects** — cleanup runs, setup re-runs (as expected on any re-render)
- **Module-level state** — NO (module re-executes)
- **State inside non-component exports** (e.g., a `class UserStore`) — NO

The preservation model is per-component: each function component tracked by Fast Refresh gets its own hot-update boundary. When the file changes, the runtime tries to keep the React fiber tree intact and only replace the component implementation — its hook state stays attached to the fiber.

---

## What it doesn't preserve

- Anything at module scope that's not a component
- Component state when hook signature changes (added/removed a hook, changed hook order)
- Component state when the export identity changes (renamed, added default→named)

Module-scope side effects — `const store = createStore()`, event listeners registered at import time, top-level `fetch()` calls — all re-run on every hot update because the module itself re-executes. Fast Refresh does not sandbox module evaluation; it only swaps component references.

---

## How it works — the transform

Both Babel (`react-refresh/babel`) and SWC (`transform.react.refresh: true`) insert:

```js
var _s = $RefreshSig$();

function Counter() {
  _s();
  const [n, setN] = useState(0);
  const [name] = useState('anon');
  return <div onClick={() => setN(n+1)}>{name}: {n}</div>;
}

_s(Counter, 'useState{n}\nuseState{name}');
$RefreshReg$(Counter, 'Counter');

if (module.hot) {
  module.hot.accept(...);
}
```

The signature is a hash of hook calls in order. If the signature changes between updates, Fast Refresh forces a remount (state reset).

Two things happen at transform time:

1. Every function that looks like a component gets wrapped in a signature call — `_s()` at the top marks the hook boundary; `_s(Counter, '...')` at the bottom records the hook order for later comparison.
2. Every component gets registered with `$RefreshReg$` under a stable file+name key. The bundler emits `module.hot.accept()` at the end so the module opts into HMR.

The signature string is a serialization of hook names and their argument shapes. Custom hooks are tracked transitively — a signature for `useAuth()` gets inlined so the parent's signature reflects nested hook changes too.

---

## Rules for reliable Fast Refresh

1. **Named exports only** — a component must be at a named export or default export named at the file level. Anonymous default exports (`export default () => <div/>`) break state preservation.
2. **One component per file** — mixing multiple components in one file works but confuses the graph. Custom hooks fine.
3. **Component names are PascalCase** — Fast Refresh detects components by name convention.
4. **Hooks in stable order** — adding a `useState` above another changes the signature → remount.
5. **Don't export non-component values from a component file** — a `const CONFIG = {}` alongside a component file forces the whole module to reload, losing state.

```js
❌ export default () => <Counter />;
✅ function App() { return <Counter />; }
   export default App;

❌ export const config = { apiUrl: '...' };
   export function Widget() { ... }
✅ // config.js
   export const config = { apiUrl: '...' };
   // Widget.jsx
   export function Widget() { ... }
```

The "no mixed exports" rule is the one people trip on most. Because the module re-executes on every edit, any non-component export makes the runtime fall back to a full module reload — Fast Refresh can only preserve state for pure component modules.

---

## Component detection

- Function starts with capital letter → treated as component
- Uses hooks → treated as component
- `React.memo(Fn)` or `React.forwardRef(Fn)` → treated as component

```js
✅ function UserList() { ... }
✅ const UserList = React.memo(function UserList() { ... });
✅ const UserList = React.forwardRef((props, ref) => { ... });

❌ function userList() { ... }        // lowercase — treated as util
❌ const userList = () => <div/>;      // lowercase — treated as util
```

The heuristic is intentionally loose so common patterns work. HOCs like `React.memo` and `React.forwardRef` are recognized because they're by far the most common wrappers; other custom HOCs (`connect`, `withRouter`) may need explicit handling depending on the plugin version.

---

## The registration cycle

On HMR update:

1. New module re-executes; new components register with new signatures
2. Runtime compares new signatures against old
3. If signature match → hot-swap component preserving state
4. If signature differs → force remount (state reset)
5. If component removed/added → adjust the graph

The registration key is `<module-id>:<component-name>` — that's why renaming a component or moving it between files always forces a remount. The old registration and new registration are simply different entries; Fast Refresh has no way to correlate them.

---

## Bundler integrations

| Bundler | Integration |
|---------|-------------|
| Vite | `@vitejs/plugin-react` (Babel) or `@vitejs/plugin-react-swc` (SWC) |
| Webpack | `@pmmmwh/react-refresh-webpack-plugin` + `babel-loader`/`swc-loader` + refresh transform |
| Next.js | Built-in (SWC-based transform) |
| Metro (RN) | Built-in (Babel-based transform) |

Each integration is responsible for three things: injecting the `react-refresh/runtime` at the top of the entry, applying the Babel/SWC transform to source files, and wiring `import.meta.hot` / `module.hot` into the runtime's `performReactRefresh()` call. The transform itself is bundler-agnostic — the runtime and the HMR glue are what differ.

Cross-link [[Build Tools Dev Server and HMR - Vite HMR Protocol]] and [[Build Tools Dev Server and HMR - Webpack HMR Protocol]] for the underlying HMR protocols.

---

## Failure modes

```
❌ Editing a component's hook count → forced remount (state lost)
✅ Expected — Fast Refresh can't rehydrate a hook list that changed

❌ Renaming an anonymous default export → forced full reload
✅ Give the component a name: `function Counter() {}; export default Counter;`

❌ Mixing components and utilities in one file → both re-execute on any change
✅ Split utilities into their own module

❌ Component doesn't refresh after edit
✅ Check that the plugin is enabled and the file matches the include pattern
```

Additional pitfalls:

- **Higher-order components** wrapping components with `connect(mapState)(Comp)` sometimes lose identity across edits — the wrapper returns a new function each module eval.
- **Dynamic `import()`** — code-split modules use the same rules; a chunk that mixes components and helpers still reloads fully.
- **Non-React state (Zustand, Redux stores)** at module scope will reset on every edit if the store is created in the same file as a component. Move stores to their own file.

---

## The $RefreshReg$ / $RefreshSig$ globals

These are runtime hooks the transform relies on. Defined in the injected `react-refresh` runtime. In dev, they're globals; in prod, the runtime is not loaded and the transform inserts no-ops.

```js
// Dev only, injected by the bundler:
window.$RefreshReg$ = (type, id) => RefreshRuntime.register(type, moduleId + ':' + id);
window.$RefreshSig$ = () => RefreshRuntime.createSignatureFunctionForTransform();
```

In production builds the transform is disabled entirely — bundlers gate it on `NODE_ENV === 'development'`. The output for prod contains no `$RefreshReg$`/`$RefreshSig$` calls at all, so there's zero runtime cost.

---

## Fast Refresh vs framework-agnostic HMR

Without Fast Refresh, Vite's/Webpack's HMR would need per-component boilerplate:

```js
// Without Fast Refresh (theoretical)
import.meta.hot.accept('./Counter', (m) => {
  // manually re-render tree with the new component…
});
```

Fast Refresh does this automatically — a component export gets its own hot-update logic without user code.

Framework-agnostic HMR (like Vite's default `import.meta.hot.accept`) can only tell the app "this module changed, here's the new exports" — it can't preserve React fiber state across the swap. Fast Refresh sits between the bundler's HMR and React's fiber tree, translating "module changed" into "swap the component type on all matching fibers, keep their hook state."

See [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]] for the general HMR model.

---

## Interaction with StrictMode

StrictMode's double-invoke behavior interacts with Fast Refresh: when a signature changes and Fast Refresh remounts, StrictMode's setup+cleanup+setup pattern applies to the new mount. Cross-link [[React Lifecycle - StrictMode Double Invoke]].

Practically: an edit that changes hook order in a StrictMode tree runs effects setup→cleanup→setup twice (once for remount, once for StrictMode's simulation). This can make debug output look chattier than expected — the effects are firing correctly, just doubled.

---

## Debugging Fast Refresh

```
✅ Enable overlay: server.hmr.overlay: true
✅ In dev, check console for '[HMR] ...' messages
✅ If a component always full-reloads, examine what else is exported from that file
```

Diagnostic checklist when Fast Refresh isn't working:

1. Confirm the plugin is loaded — check the dev server output for `react-refresh` mention.
2. Verify the transform is running — the compiled bundle should contain `$RefreshReg$` calls.
3. Check the file matches the plugin's `include` glob (defaults usually cover `**/*.{js,jsx,ts,tsx}`).
4. Look for non-component exports in the file — they force full reload.
5. Confirm the component is a named export or a named function passed to `export default`.
6. Rule out anonymous HOCs — wrap the inner function with a name before applying the HOC.

---

## Related

- [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]]
- [[Build Tools Dev Server and HMR - Vite HMR Protocol]]
- [[Build Tools Dev Server and HMR - Webpack HMR Protocol]]
- [[Build Tools Compilers - JSX and React Transforms]]
- [[React Lifecycle - StrictMode Double Invoke]]
- [[React Hooks - Rules of Hooks]]
- [[Build Tools Dev Server and HMR Guide]]
