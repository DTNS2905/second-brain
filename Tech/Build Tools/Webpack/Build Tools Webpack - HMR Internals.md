---
tags:
  - build-tools
  - webpack
  - hmr
  - internals
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/concepts/hot-module-replacement/
---

# Build Tools Webpack — HMR Internals

> How Webpack's Hot Module Replacement actually works: the runtime injected into every bundle, the update manifest, the chunk fetch protocol, and the React Refresh wiring. Part of [[Build Tools Webpack Guide]].

---

## Enabling HMR

```js
// webpack.config.js — dev
const webpack = require('webpack');
module.exports = {
  mode: 'development',
  devServer: { hot: true },
  plugins: [new webpack.HotModuleReplacementPlugin()],
};
```

`webpack-dev-server` with `hot: true` auto-adds the plugin — you rarely need to instantiate `HotModuleReplacementPlugin` yourself in the standard SPA setup. In custom servers (SSR, Express-based apps) you add it manually and pair it with `webpack-hot-middleware` to expose the update stream over your own HTTP server.

Three things must be true for HMR to work:

1. `mode` is `development` (or the plugin is explicitly added in production, which is almost never what you want).
2. `HotModuleReplacementPlugin` is present in the compilation.
3. The client bundle contains the HMR runtime entry — dev-server adds this automatically; custom servers do it via `webpack-hot-middleware/client`.

---

## The HMR runtime

When HMR is enabled, Webpack injects a small runtime into every emitted chunk. This runtime:

- Owns the `module.hot` API surface exposed to user code
- Maintains a per-module `hot` object (accept handlers, dispose handlers, data stash)
- Handles update fetching, module factory replacement, and propagation
- Talks to the dev server via WebSocket (or SSE for `webpack-hot-middleware`)
- Tracks a global `status` state machine: `idle → check → prepare → ready → dispose → apply → idle`

The runtime lives inside the same IIFE as the standard Webpack runtime — it isn't a separate script. That means the update chunk executes in the exact same closure as the original bundle, sharing the `__webpack_require__` module cache. Cross-link [[Build Tools Webpack - Compiler and Compilation]] for how this cache is built.

---

## The module.hot API

```js
if (module.hot) {
  module.hot.accept();                            // self-accept
  module.hot.accept('./dep', () => { /* ... */ }); // dep-accept
  module.hot.accept(['./a', './b'], () => { /* ... */ }); // multi-dep
  module.hot.decline();                            // reject
  module.hot.dispose(data => { data.x = state; }); // stash state
  module.hot.data;                                 // read stashed state
  module.hot.invalidate();                         // propagate up
  module.hot.status();                             // 'idle', 'check', 'prepare', 'ready', 'dispose', 'apply'
  module.hot.check();                              // request update manually
  module.hot.apply(options);                       // apply update
  module.hot.addStatusHandler(cb);
}
```

The `if (module.hot)` guard is required — in production `module.hot` is `undefined`, and the whole block is dropped by dead-code elimination as long as `mode: 'production'` sets `NODE_ENV=production`.

| API | Meaning |
|-----|---------|
| `accept()` | This module handles its own updates; when I change, re-execute me |
| `accept(dep, cb)` | I handle updates to `dep`; when `dep` changes, don't propagate — run `cb` |
| `decline()` | I cannot be hot-updated; force full reload if I change |
| `dispose(cb)` | Before I'm replaced, run `cb(data)` — stash side-effect state |
| `data` | The `data` object populated by the previous version's dispose callback |
| `invalidate()` | Mark self dirty and propagate up during the current update cycle |
| `check()` | Manually poll the server for a new update manifest |
| `apply()` | Apply an update prepared by `check()` |

---

## Update flow

1. File saved → Webpack recompiles (incremental — only affected modules re-run through loaders).
2. Compilation emits a new hash (this becomes the "next hash").
3. `HotModuleReplacementPlugin` diffs the module graph against the previous compilation and computes changed modules per chunk.
4. Plugin emits two assets:
   - `<hash>.hot-update.json` — the manifest listing changed/removed chunks and modules
   - `<chunkId>.<hash>.hot-update.js` — one delta file per changed chunk, containing new module factories
5. Server pushes `{ type: 'hash', data: '<newHash>' }` then `{ type: 'ok' }` over WebSocket.
6. Client runtime calls `module.hot.check()` — fetches the manifest at `/<oldHash>.hot-update.json`.
7. For each chunk id listed in the manifest, client fetches `<chunkId>.<newHash>.hot-update.js`.
8. Runtime executes those scripts. Each script calls `webpackHotUpdate(chunkId, moreModules)` which stashes the new factories in a pending buffer.
9. Runtime enters `dispose` phase: for every module about to be replaced, run its `dispose` handlers (state stash time).
10. Runtime enters `apply` phase: swap module factories in `__webpack_require__.m`, invalidate the module cache entries for changed modules, run accept callbacks along the propagation chain.
11. If any step throws, or the propagation walk reaches a module with no accept handler → `location.reload()`.

The old-hash → new-hash chain matters: the manifest is fetched with the *previous* hash in the URL, and the update scripts carry the *new* hash. This lets the client apply updates in strict order even when saves happen in rapid succession.

---

## The manifest

```json
// 87a3b2c.hot-update.json
{
  "c": ["main"],
  "r": [],
  "m": []
}
```

- `c` — chunks that have update deltas to fetch
- `r` — chunks that have been fully removed since the previous build
- `m` — modules that have been removed (and should be evicted from the cache without replacement)

The compact single-letter keys keep the manifest tiny — it's fetched on every save, so bytes matter. Everything else — which modules changed inside a chunk, their factory bodies — lives inside the corresponding `<chunkId>.<hash>.hot-update.js`.

---

## The hot-update chunk

Contains module factory functions for the changed modules, wrapped in a call the runtime recognizes:

```js
"use strict";
self["webpackHotUpdatemyApp"]("main", {
  "./src/button.jsx": (module, exports, __webpack_require__) => {
    // new factory body — the recompiled module
  },
});
```

The wrapper name is derived from `output.hotUpdateGlobal` (default `webpackHotUpdate<name>`). The runtime installs a handler on that global before calling `check()`, so the script's execution side-effect *is* the delivery mechanism. Executes in the context of the current runtime — updates the module registry, then triggers propagation.

---

## Propagation algorithm

```
For each changed module M:
  If M is self-accepting → invoke its accept handler → done
  Else:
    Walk importers upward
    For each importer I:
      If I has accept('.../M', cb) → invoke cb → done
      Else continue
      If I is self-accepting → invoke its self-accept handler → done
    If reach root with no accept → full reload
```

The walk is a BFS across the import graph in reverse. A module is only "handled" when *some* ancestor either self-accepts (re-executing itself picks up the fresh transitive `M`) or explicitly accepts a path that includes `M`. If any leaf of the walk reaches an entry module with nothing catching it, the runtime bails to a full page reload.

`module.hot.decline()` short-circuits this — a declined module forces a reload the moment it (or anything downstream) changes, regardless of ancestor accepts.

Cross-link [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]] for the transport-agnostic view of this same flow.

---

## dispose pattern (state stash)

```js
let listener = createListener();

if (module.hot) {
  module.hot.dispose(data => {
    // called just before this module is replaced
    data.listener = listener;
  });

  if (module.hot.data && module.hot.data.listener) {
    // re-inherit state from previous module version
    listener = module.hot.data.listener;
  }

  module.hot.accept();
}
```

`dispose` is the only supported way to survive an HMR swap. The `data` object is scoped to a single generation — it's created empty for each module version, populated by that version's dispose handler, then handed to the *next* version as `module.hot.data`.

Typical uses:

- Unsubscribe/remove event listeners so the new version can re-register cleanly
- Stash long-lived state (WebSocket connections, running timers, cached data)
- Clean up DOM nodes injected imperatively
- Tear down singletons before their next-version replacement runs

Without `dispose`, side effects from the previous version linger — you get duplicate listeners, orphaned intervals, and progressive memory bloat over a long dev session.

---

## React Refresh integration

React Refresh sits on top of `module.hot` and rewrites component modules so a re-execution preserves component *state* (not just re-renders). Wire it via `@pmmmwh/react-refresh-webpack-plugin`:

```js
const ReactRefreshPlugin = require('@pmmmwh/react-refresh-webpack-plugin');

module.exports = {
  mode: 'development',
  devServer: { hot: true },
  plugins: [
    new ReactRefreshPlugin({
      overlay: { sockIntegration: 'wds' },
    }),
  ],
  module: {
    rules: [{
      test: /\.[jt]sx?$/,
      exclude: /node_modules/,
      use: [{
        loader: 'swc-loader',
        options: { jsc: { transform: { react: { refresh: true } } } },
      }],
    }],
  },
};
```

What the transform does:

- Wraps every component in a signature registration
- Adds `module.hot.accept()` to files that export only components
- Registers each component with the Refresh runtime so hook state can be reconciled across replacements

`overlay: { sockIntegration: 'wds' }` tells the error overlay to piggyback on the dev-server WebSocket rather than opening its own. Cross-link [[Build Tools Dev Server and HMR - React Fast Refresh]] for the runtime side.

---

## webpack-dev-server vs webpack-hot-middleware

|  | webpack-dev-server | webpack-hot-middleware |
|---|---|---|
| Runs | Standalone HTTP server | Middleware in your Express server |
| HMR transport | WS + SSE fallback | SSE (over the same server) |
| Use case | Simple SPAs | Custom SSR servers, complex routing |
| Setup | `devServer: { hot: true }` | Manually add middleware + plugin |
| Static serving | Built-in (`static`, `historyApiFallback`) | You wire it yourself |
| Compatibility | React, Vue, everything vanilla | Anything you can bolt onto Express/Koa |

Rule of thumb: if you don't have your own server, use `webpack-dev-server`. The moment you need real backend routes, SSR, or custom middleware, `webpack-hot-middleware` + `webpack-dev-middleware` is the pair.

---

## Common failure modes

```
❌ Full reload every save
✅ Missing `module.hot.accept` somewhere in the chain — or (with Refresh) mixed exports in one file

❌ State lost across HMR
✅ Add module.hot.dispose to stash + restore

❌ HMR runtime not injected
✅ Ensure HotModuleReplacementPlugin is in plugins + mode is development

❌ WS keeps disconnecting
✅ Check firewall, proxy, and devServer.hmr.port config
```

A few extra traps worth knowing:

- **Mixed exports break Refresh** — if a file exports a component *and* a non-component (a hook, a constant), Refresh can't safely swap the component alone and falls back to full reload. Split the file.
- **Circular imports break propagation** — the upward walk can loop; the runtime detects this and bails.
- **CSS-in-JS libraries** often skip HMR because they mutate global stylesheets outside the module system — check for a library-specific integration or Babel plugin.
- **CommonJS `require` inside dynamic branches** — the graph only sees statically analyzable edges; dynamic requires may not appear in the update.

---

## Diagnostics

```
DEBUG=hmr webpack serve
stats: { hmr: true }
Browser console: [HMR] Waiting for update signal from WDS...
```

Useful signals when debugging:

- Browser Network tab → filter `hot-update` — you should see the manifest fetch, then N chunk deltas, then nothing.
- Browser console → `[HMR] Updated modules:` lists exactly what got swapped. If it's `[]` after a save, the compilation didn't detect a change (loader cache issue, symlinked file, etc.).
- `webpack-dev-server`'s `--client-logging verbose` prints every WS message.
- `--stats hot-only` in the CLI, or `stats: { hmr: true, chunks: true }` in config, dumps HMR-specific compilation info.

If a save produces a manifest but no accept fires, insert a `module.hot.addStatusHandler(s => console.log(s))` at the entry — you'll see the state machine transitions and can pinpoint which phase throws.

---

## Related

- [[Build Tools Dev Server and HMR - Webpack HMR Protocol]] — protocol-level details
- [[Build Tools Dev Server and HMR - React Fast Refresh]]
- [[Build Tools Webpack - Compiler and Compilation]]
- [[Build Tools Webpack Guide]]
