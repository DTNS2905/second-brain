---
tags:
  - build-tools
  - dev-server
  - hmr
  - webpack
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/api/hot-module-replacement/
---

# Build Tools Dev Server and HMR — Webpack HMR Protocol

> Webpack HMR is older, more elaborate, and works via chunked "hot-update" fetches rather than re-fetching the module as ESM. Understanding it clarifies why Vite's approach is simpler and faster. Part of [[Build Tools Dev Server and HMR Guide]].

---

## The moving parts

Webpack's HMR system is a coordinated dance between five distinct pieces. Unlike [[Build Tools Dev Server and HMR - Vite HMR Protocol|Vite]], which leans on the browser's native ESM loader, Webpack ships its own runtime that impersonates a module system inside the browser.

- **`HotModuleReplacementPlugin`** — bundler-side plugin enabling HMR. Rewrites the module graph to emit deltas rather than a full bundle. Adds hooks for accept/dispose. Automatically enabled when you pass `--hot` to `webpack-dev-server`.
- **`webpack-dev-server`** (or **`webpack-hot-middleware`**) — HTTP + WebSocket server. Serves the initial bundle, watches source files, and pushes `hash` messages to connected clients when a rebuild finishes.
- **Runtime injected into every bundle** — a small JavaScript module (part of `webpack/hot/`) that lives in the client and orchestrates fetches, module replacement, and accept-handler execution.
- **`.hot-update.json` manifest** — lists changed chunks. One manifest per rebuild, keyed by the previous compilation's hash.
- **`.hot-update.js` chunk files** — one per invalidated chunk. Contains updated module factories.

The key insight: Webpack does not re-fetch the module by URL. It fetches **delta chunks** that patch the running bundle in place.

---

## Update flow

The canonical HMR round-trip:

1. **File changes** — a source file (or one of its transitive dependencies via loaders) changes on disk.
2. **Webpack recompiles** — incremental compilation triggers. The persistent cache and module graph diffing keep this to the milliseconds range for small changes.
3. **Server emits new manifest + new hot-update chunks** — written to memory (or disk under `webpack-dev-middleware`) and served over HTTP.
4. **Server sends `hash` message over WS** — a compact JSON message with the new compilation hash pushed to every connected client.
5. **Client's HMR runtime fetches `<hash>.hot-update.json`** — sees the list of changed chunks (`c`), removed chunks (`r`), and removed modules (`m`).
6. **Client fetches each `<chunkId>.<hash>.hot-update.js`** — in parallel where possible.
7. **Each hot-update chunk contains updated module factories** — the runtime evaluates them, replacing the corresponding factories in the module cache.
8. **Client re-runs affected accept handlers** — walking outward from the changed modules until it finds a boundary. Full reload if none is found.

The critical difference from [[Build Tools Dev Server and HMR - Vite HMR Protocol|Vite]]: **the browser is not asked to import the changed module by URL.** Webpack's runtime dictates evaluation order.

---

## The manifest

The `.hot-update.json` file is the map that tells the client what to fetch next:

```json
// 87a3b2c.hot-update.json
{
  "c": ["main"],
  "r": [],
  "m": []
}
```

- **`c`** — array of chunk IDs that have updated hot-update files available.
- **`r`** — chunk IDs removed since the previous compilation.
- **`m`** — module IDs removed since the previous compilation. The runtime purges these from its module cache.

The hash in the filename (`87a3b2c`) is the **previous** compilation hash, not the new one. This lets the client — which knows only its current hash — request "the update from where I am now."

---

## The client API: module.hot

Every module gets a `module.hot` object when HMR is enabled. This is the user-facing surface:

```js
if (module.hot) {
  module.hot.accept();                  // self-accept
  module.hot.accept('./dep', () => {}); // dep-accept
  module.hot.decline();                 // reject updates → full reload
  module.hot.dispose((data) => {});     // teardown, stash state
  module.hot.data;                      // stashed data from prev dispose
  module.hot.invalidate();              // give up, propagate
}
```

Method semantics:

| Method | Behavior |
|---|---|
| `accept()` | This module handles its own updates. Boundary stops here. |
| `accept(deps, cb)` | This module handles updates to `deps`. `cb` runs after each replacement. |
| `decline()` | This module refuses HMR — any update triggers a full reload. |
| `decline(deps)` | Same, but only for updates coming through `deps`. |
| `dispose(cb)` | Registers a teardown callback. `cb` receives a `data` object; anything attached to it survives to the next module's `module.hot.data`. |
| `data` | The `data` object stashed by the previous module instance's `dispose`. `undefined` on first load. |
| `invalidate()` | Marks this module as un-hot-updatable for this cycle; propagates to parents. |
| `removeDisposeHandler(cb)` | Unregister a previously added dispose handler. |

The `if (module.hot)` guard is critical — in production builds, `module.hot` is `undefined`, and the entire block gets dead-code-eliminated.

---

## dispose data

The `dispose → data` handoff is how Webpack's HMR preserves runtime state across module replacements — subscriptions, timers, connection handles, whatever is expensive or externally observable.

```js
let subs = createSubs();
if (module.hot) {
  module.hot.dispose(data => { data.subs = subs; });
  if (module.hot.data && module.hot.data.subs) {
    subs = module.hot.data.subs;
  }
  module.hot.accept();
}
```

Flow when this module hot-updates:

1. The old instance's `dispose` callback fires. `subs` is placed on `data`.
2. Webpack tears down the old module.
3. The new module code executes. On startup, it reads `module.hot.data.subs` — the same reference that was stashed.
4. `subs` is restored without recreating the underlying subscription.

Without this, every save would leak an unclosed subscription — a classic HMR footgun. See [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]] for the general pattern.

---

## decline

Explicitly declines HMR — updates cause full reload. Rarely used directly (most non-accepting modules just propagate updates upward until something accepts, or hit the root and trigger a full reload naturally).

```js
if (module.hot) {
  module.hot.decline();
}
```

Reasonable uses:

- Global side-effect modules (e.g. polyfills) where hot-swapping would leave the runtime in an inconsistent state.
- Modules that mutate `window` or install DOM listeners that can't be cleanly torn down.

Most codebases never call `decline()`. The propagation model handles the fallback case automatically.

---

## HotModuleReplacementPlugin

Auto-enabled by `webpack-dev-server --hot`. In older versions you had to add it manually to `plugins`; modern configurations get it for free. It emits:

- **The HMR runtime into every bundle** — small (~5 KB gzipped) JavaScript module that hooks into `__webpack_require__` and manages the module cache.
- **The hot-update manifest on each rebuild** — the JSON described above.
- **The per-chunk update files** — one per invalidated chunk.

Manually if needed:

```js
const webpack = require('webpack');

module.exports = {
  mode: 'development',
  plugins: [
    new webpack.HotModuleReplacementPlugin(),
  ],
  devServer: {
    hot: true,
  },
};
```

Note: `devServer.hot: true` implies the plugin — double-adding causes warnings.

---

## webpack-dev-server vs webpack-hot-middleware

Two ways to actually serve the bundle + push updates:

- **webpack-dev-server** (`WDS`) — standalone HTTP + WS server; opinionated. Handles static assets, HMR, live reload, HTTPS, proxying. Configured via `devServer` in `webpack.config.js`. The default for `create-react-app`-style setups.
- **webpack-hot-middleware** — Express-compatible middleware; use in custom servers (SSR frameworks like Next.js's legacy `custom-server` pattern, or any Express-based dev workflow). Ships events via Server-Sent Events by default rather than WebSockets, but the wire format is otherwise identical.

Both consume the same manifest + chunk format. The client runtime doesn't care which server pushed the `hash` message.

| Concern | webpack-dev-server | webpack-hot-middleware |
|---|---|---|
| Transport | WebSocket | SSE (or custom) |
| Server | Standalone | Middleware in your Express app |
| SSR-friendly | Awkward | Natural |
| Config surface | `devServer` field | Programmatic |

---

## React Fast Refresh wiring

Via `@pmmmwh/react-refresh-webpack-plugin`:

```js
const ReactRefreshPlugin = require('@pmmmwh/react-refresh-webpack-plugin');

module.exports = {
  plugins: [
    process.env.NODE_ENV !== 'production' && new ReactRefreshPlugin(),
  ].filter(Boolean),
  module: {
    rules: [
      {
        test: /\.[jt]sx?$/,
        use: [
          { loader: 'swc-loader', options: { jsc: { transform: { react: { refresh: true } } } } },
        ],
      },
    ],
  },
};
```

Two parts:

- **The loader transform** — `swc-loader` (or `babel-loader` with `react-refresh/babel`) wraps every component export with registration calls so Fast Refresh can track them.
- **The Webpack plugin** — injects the React Refresh runtime + wires it into HMR accept handlers per component. Component modules become self-accepting automatically; non-component modules propagate as usual.

Cross-link [[Build Tools Dev Server and HMR - React Fast Refresh]] for the full runtime story — how signatures are computed, what triggers a "hard" refresh vs a state-preserving one, and how hooks are re-linked.

---

## Full-reload fallback

Triggers that force a full page reload rather than a hot patch:

- **Update handler throws** — if any `accept` callback throws, the runtime bails out and does `location.reload()`.
- **No accept boundary in the chain** — propagation reaches the entry module with nobody willing to accept.
- **Module signature changed** — with Fast Refresh, changing component export names, adding/removing hooks in ways that shift the identity, or converting a class to a function component causes a hard refresh.
- **Config file changed** — Webpack has no watch on `webpack.config.js` by default; changes to the config typically require a manual restart. Some setups use `nodemon` around the dev server to work around this.
- **A `decline()`d module is in the propagation path**.
- **Removed modules (`m` list) still referenced by live code** — inconsistent state; safer to reload.

---

## HMR-safe patterns

The mental model: **modules will be re-executed, possibly many times, in the same page load.**

```
❌ Module-level side effects on load (register event listener globally)
✅ Wrap in module.hot.dispose to clean up

❌ Assuming module identity persists across updates
✅ Modules are re-executed; identity does not persist
```

Concrete example — a global listener registration:

```js
const handler = (e) => console.log(e);
window.addEventListener('resize', handler);

if (module.hot) {
  module.hot.dispose(() => {
    window.removeEventListener('resize', handler);
  });
  module.hot.accept();
}
```

Without the `dispose`, every save adds another listener, and after ten saves you have ten `console.log` calls per resize.

Another anti-pattern — caching module references:

```js
// ❌ Bad — stale after HMR
import * as api from './api';
const savedApi = api;

// ✅ Good — re-read on each call, or re-wire in accept
import * as api from './api';
if (module.hot) {
  module.hot.accept('./api', () => {
    // rebind anything holding onto api
  });
}
```

---

## Diagnostics

Tools for debugging why HMR isn't working:

- **`stats: { hmr: true }`** — logs HMR events during compilation. Adds `chunkModules` and `moduleTrace` info about which modules were emitted in the update.
- **`webpack-dev-server` output** — the terminal prints `webpack compiled successfully` + a compilation hash on every rebuild. Client-side, `webpackHotUpdate` calls appear in the DevTools console with `[HMR]` prefixes when `client.logging: 'info'` is set.
- **`HMR_UPDATE` message in WS payload** — inspect via DevTools → Network → WS tab → Messages. You'll see JSON messages like `{"type":"hash","data":"87a3b2c..."}` and `{"type":"ok"}`.

If updates are missing:

1. Confirm the WS connection is alive — the DevTools Network tab should show `ws://localhost:<port>/ws` in "pending" state.
2. Confirm the manifest fetches are 200 — a 404 on `<hash>.hot-update.json` means the server discarded the previous compilation before the client requested the update (usually a race with rapid saves).
3. Confirm accept boundaries — `module.hot.accept()` calls should appear in the modules along the propagation path.

---

## Comparison to Vite

Vite refetches modules by URL with a `?t=` timestamp query; the browser's ESM loader handles the update:

```
GET /src/App.tsx?t=1731000000000
```

The browser's module graph sees a new URL and evaluates it fresh. Vite's client runtime then walks the accept boundaries similarly to Webpack — but the module _loading_ is native.

Webpack ships hot-update chunk files that contain module factories — more machinery, slower iteration, but works with any output format (not just ESM). Which matters because:

- Webpack can HMR CommonJS, AMD, and legacy targets that Vite can't touch.
- Webpack's HMR works even when the output is IIFE'd for old browsers.
- The client runtime is bundler-controlled, so Webpack can enforce evaluation order regardless of what the browser's ESM loader would prefer.

The cost: bigger runtime, more HTTP requests per update (manifest + chunks vs a single module refetch), and slower incremental compilation compared to esbuild-backed [[Build Tools Vite Guide|Vite]].

| Concern | Webpack HMR | Vite HMR |
|---|---|---|
| Transport | WS `hash` message + HTTP fetches | WS `update` payload + native ESM refetch |
| Wire format | `.hot-update.json` + `.hot-update.js` chunks | JSON message describing modules to reload |
| Requires ESM output | No | Yes |
| Client runtime size | ~5 KB | ~2 KB |
| Requests per update | 1 manifest + N chunks | 0 (payload carries hints) + M module fetches |
| Compilation model | Bundle-graph rebuild | Per-module transform on demand |
| Typical iteration | 100 ms – few seconds | ~50 ms |

For the underlying protocol concepts that both share (accept boundaries, propagation, dispose data), see [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]].

---

## Related

- [[Build Tools Webpack - HMR Internals]] — the internals from Webpack's perspective
- [[Build Tools Dev Server and HMR - Vite HMR Protocol]]
- [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]]
- [[Build Tools Dev Server and HMR - React Fast Refresh]]
- [[Build Tools Webpack Guide]]
- [[Build Tools Dev Server and HMR Guide]]
