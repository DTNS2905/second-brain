---
tags:
  - build-tools
  - vite
  - plugins
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/api-plugin
---

# Build Tools Vite — Plugin API

> Vite plugins are Rollup plugins + Vite-only lifecycle hooks. Learn the shared hooks (resolveId, load, transform) and the Vite-specific ones (configureServer, transformIndexHtml, handleHotUpdate). Part of [[Build Tools Vite Guide]].

---

## The plugin object

A Vite plugin is a plain object (or a factory returning one) with a required `name` and any subset of lifecycle hooks. The same object flows through **dev mode** (where Vite runs hooks per request via its module graph) and **build mode** (where Rollup drives the pipeline).

```ts
import type { Plugin } from 'vite';

const myPlugin = (): Plugin => ({
  name: 'my-plugin',
  enforce: 'pre',
  apply: 'serve', // 'serve' | 'build' | undefined (both)
  // Rollup hooks:
  resolveId(source, importer) { … },
  load(id) { … },
  transform(code, id) { … },
  buildStart() { … },
  generateBundle(_, bundle) { … },
  // Vite-only hooks:
  config(userConfig, env) { … },
  configResolved(resolvedConfig) { … },
  configureServer(server) { … },
  transformIndexHtml(html) { … },
  handleHotUpdate(ctx) { … },
});
```

Key fields:

- `name` — **required**, used in error messages and DEBUG logs.
- `enforce` — `'pre' | 'post'` to bias ordering relative to Vite's built-in plugins.
- `apply` — `'serve' | 'build'` to scope the plugin to one mode, or a predicate `(config, env) => boolean`.

Everything else is a hook — you only implement the ones you need.

---

## Rollup-compatible hooks

Vite reuses the Rollup plugin interface for anything that touches module resolution and code transformation. Because the shape is identical, most Rollup plugins work in Vite unmodified.

| Hook | Purpose |
|------|---------|
| `resolveId(source, importer)` | Custom module resolution — return the resolved id, or `null` to defer |
| `load(id)` | Provide source code for an id — return `string \| { code, map }` or `null` |
| `transform(code, id)` | Rewrite source — return `{ code, map }` or `null` |
| `buildStart(options)` | Fires once when the build/dev graph starts |
| `buildEnd(error?)` | Fires once when the graph is finalized |
| `generateBundle(opts, bundle)` | Inspect/mutate the emitted chunks (build only) |
| `writeBundle(opts, bundle)` | After files are written to disk (build only) |
| `moduleParsed(info)` | After a module is fully parsed |
| `closeBundle()` | Very last hook, once per build |

These hooks all follow Rollup's `null`-to-defer contract — returning `null`/`undefined` passes the input to the next plugin in the chain. See [[Build Tools Bundlers - Rollup Internals]] for the semantics of these hooks in isolation.

**Dev vs build:** in dev, `resolveId`/`load`/`transform` run **per request** through Vite's module graph — not as one big Rollup pass. In build, Rollup itself drives them across the whole graph.

---

## Vite-only hooks

These extend beyond Rollup — they exist because Vite is also a dev server, not just a bundler.

| Hook | Purpose | Runs |
|------|---------|------|
| `config` | Mutate/replace config before merge | Once, pre-resolve |
| `configResolved` | Read final resolved config | Once, post-merge |
| `configureServer` | Attach middleware / ws handlers | On dev server start |
| `configurePreviewServer` | Same for `vite preview` | On preview start |
| `transformIndexHtml` | Rewrite HTML | On each `index.html` request (dev) / bundle emit (build) |
| `handleHotUpdate` | Custom HMR logic | On file change (dev) |

Most non-trivial Vite plugins pair one Rollup hook (usually `transform`) with one Vite-only hook (usually `configureServer` or `transformIndexHtml`).

---

## enforce and apply

By default, a plugin runs **after** Vite's built-in aliasing/CSS/asset plugins but **before** user plugins in the array. Use `enforce`/`apply` to change that.

- `enforce: 'pre'` — run **before** Vite's built-in plugins. Use for aliasing/rewrites that must feed the built-in pipeline.
- `enforce: 'post'` — run **after** the built-in plugins. Use for output-shaping or wrapping.
- (default) — runs between built-in "pre" plugins and built-in "post" plugins.
- `apply: 'serve'` — active in `vite dev` only.
- `apply: 'build'` — active in `vite build` only.
- `apply: (config, env) => boolean` — programmatic scoping.
- (default) — active in both modes.

Order within a single tier is **array order** in the user's `plugins: []`.

```ts
// Runs pre, dev-only
{ name: 'x', enforce: 'pre', apply: 'serve', … }

// Runs post, build-only
{ name: 'y', enforce: 'post', apply: 'build', … }
```

The full sort ends up:

```
[built-in alias]
→ user 'pre' plugins
→ vite core plugins
→ user normal plugins
→ vite build plugins
→ user 'post' plugins
```

---

## Virtual modules

A **virtual module** is an id that doesn't exist on disk — the plugin fabricates the source in `load`. This is the canonical way to expose build-time data to app code.

Convention: user-facing id is prefixed `virtual:`, and the resolved id is prefixed with `\0` so other tooling knows to leave it alone.

```ts
const VIRTUAL_ID = 'virtual:my-cfg';
const RESOLVED = '\0' + VIRTUAL_ID;

{
  resolveId(id) { if (id === VIRTUAL_ID) return RESOLVED; },
  load(id) {
    if (id === RESOLVED) return `export const cfg = ${JSON.stringify(cfg)};`;
  },
}
```

Usage in app code:

```ts
import { cfg } from 'virtual:my-cfg';
```

Why the `\0` prefix? Rollup and Vite treat ids starting with `\0` as "not a real filesystem path" — they won't try to read from disk, resolve extensions, or apply node_modules pre-bundling.

Common uses:

- Injecting build metadata (git SHA, build time, feature flags).
- Aggregating file-glob imports into a single manifest.
- Exposing plugin state (e.g., icon sprites, i18n messages).

---

## transformIndexHtml

Rewrite `index.html` — either as a **string** (with search/replace) or by returning a set of tag descriptors to inject.

```ts
transformIndexHtml: {
  order: 'pre',
  handler(html) {
    return html.replace('<!--HEAD-->', '<meta name="x" content="y">');
  },
}
```

Or return an array of tag objects to inject:

```ts
transformIndexHtml(html) {
  return [
    { tag: 'meta', attrs: { name: 'theme-color', content: '#0f172a' }, injectTo: 'head' },
    { tag: 'script', attrs: { src: '/analytics.js', async: true }, injectTo: 'body' },
  ];
}
```

`injectTo` accepts `'head' | 'head-prepend' | 'body' | 'body-prepend'`.

The `order` field on the hook object (`'pre' | 'post'`) controls when it runs relative to Vite's own HTML processing (script injection, CSS injection, HMR client injection).

---

## handleHotUpdate

Take over HMR when Vite's default module-graph invalidation isn't what you want. Return one of:

- `undefined` — defer to Vite's default behavior.
- `[]` — swallow this update (no HMR, no reload).
- `ctx.modules` (or a subset) — invalidate exactly these modules.

```ts
handleHotUpdate(ctx) {
  if (ctx.file.endsWith('.custom')) {
    // full reload
    ctx.server.ws.send({ type: 'full-reload' });
    return [];
  }
  return ctx.modules;
}
```

Return `[]` to skip HMR for this update, return an array of modules to invalidate a specific set.

The context has:

- `ctx.file` — absolute path of the changed file.
- `ctx.timestamp` — mtime as a number, use for HMR payload timestamps.
- `ctx.modules` — the `ModuleNode[]` affected in the graph.
- `ctx.read()` — lazily read the new content.
- `ctx.server` — the dev server, with `ws.send()` for pushing custom events.

For payload details and client-side receivers see [[Build Tools Vite - HMR API]].

---

## config hook

Runs **once**, before any user config is finalized. Can mutate or return a partial config to be **deep-merged** with the user's — never mutate in place if you want to be portable, prefer returning.

```ts
config(userConfig, { command }) {
  if (command === 'serve') {
    return { server: { port: 5173 } };
  }
}
```

The second argument is a `{ command, mode }` env object:

- `command` — `'serve' | 'build'`.
- `mode` — the resolved mode (`'development'`, `'production'`, or a custom string).

Use this to set defaults; use `configResolved` to **read** final values.

---

## configResolved

Fires once after all `config` hooks have run and the config has been fully resolved (paths made absolute, aliases normalized, base/root computed). This is the earliest hook where you can safely **read** the final config.

```ts
let resolved: ResolvedConfig;
{
  configResolved(config) {
    resolved = config;
  },
  transform(code, id) {
    if (resolved.command === 'build') { … }
  },
}
```

Never mutate the config in `configResolved` — it's already been consumed by Vite core.

---

## configureServer — order

Attach Express-style middlewares and websocket handlers to the dev server. The **return value** matters:

```ts
configureServer(server) {
  server.middlewares.use('/api', apiHandler);

  // Post-middleware — after Vite's built-in
  return () => {
    server.middlewares.use('/fallback', fallbackHandler);
  };
}
```

Return a function to defer registration until after Vite's internal middlewares. This matters because Vite's own middlewares handle module transforms, HMR ping, and `index.html` — if you want your handler to be a **fallback** (e.g., 404 page, SPA fallback), you must register it in the returned callback.

The `server` object exposes:

- `server.middlewares` — the connect instance.
- `server.ws` — the HMR websocket server (`ws.send(payload)`).
- `server.moduleGraph` — the module graph, for lookups/invalidation.
- `server.watcher` — the chokidar file watcher.
- `server.httpServer` — the underlying Node http server.

`configurePreviewServer` mirrors this API for `vite preview` (production static server), minus HMR.

---

## Plugin hook execution order

The lifecycle is well-defined; keep this reference handy while writing plugins.

```
Server hooks:
  config → configResolved → configureServer → buildStart
Per-request:
  resolveId → load → transform
On file change:
  handleHotUpdate
Build hooks (extra):
  buildEnd → generateBundle → writeBundle → closeBundle
```

Notes:

- **Per-request** hooks (`resolveId`/`load`/`transform`) run *many* times per session in dev — once per module per request.
- `handleHotUpdate` runs *before* the module-graph invalidation kicks in, so you can veto or replace it.
- Build adds the extra tail (`buildEnd`, `generateBundle`, `writeBundle`, `closeBundle`) — these do **not** fire in dev.
- `transformIndexHtml` fires on each HTML request in dev, and once per HTML file at emit time in build.

---

## A real-world example — auto-import

A minimal plugin that injects `import React from 'react'` into `.tsx` files that use JSX or hooks but haven't imported React themselves.

```ts
export default (): Plugin => ({
  name: 'auto-import-react',
  transform(code, id) {
    if (!id.endsWith('.tsx')) return null;
    if (code.includes("from 'react'")) return null;
    if (!/use[A-Z]|<[A-Z]/.test(code)) return null;
    return { code: `import React from 'react';\n${code}`, map: null };
  },
});
```

(Illustrative; `@vitejs/plugin-react` already does automatic runtime, so this is educational.)

What to notice:

- **Early returns** at the top of `transform` — cheaper than full parsing when the module isn't relevant.
- Return `null` when not transforming so the chain isn't broken.
- Returning `{ code, map: null }` — no source map is still better than lying about column positions. See [[Build Tools Foundations - AST and Transform Pipelines]] for what a proper map should contain.

A production version would parse an AST once (`this.parse(code)` from Rollup) rather than string-scanning, and generate a real source map with `magic-string`.

---

## Debugging plugins

Vite emits detailed logs of plugin execution when the `vite:*` DEBUG namespaces are enabled.

```
DEBUG=vite:* vite dev
```

Useful namespaces:

- `vite:resolve` — module resolution decisions.
- `vite:load` — which plugin loaded which id.
- `vite:transform` — transform timings per module.
- `vite:hmr` — HMR events (file change → invalidation → payload).
- `vite:deps` — dep pre-bundling.

Enable one at a time — `vite:*` is very chatty on a real project. Combine with `--force` to bust the dep cache when debugging resolution.

Vite emits detailed logs of plugin execution.

---

## Common pitfalls

```
❌ Forgetting to return `null` from resolveId/load when not handling → chain broken
✅ Return null (or undefined) to defer to other plugins

❌ Returning transformed code without source map
✅ Return { code, map } — even a null map is better than none
```

More traps:

- **Mutating `userConfig` in `config`** — mutations aren't merged the way return values are. Prefer returning a partial.
- **Registering middleware synchronously in `configureServer`** — runs *before* Vite's built-ins. Return a callback for post-middleware.
- **Emitting synthetic ids without `\0` prefix** — other plugins (and Vite's own filesystem checks) will try to `stat()` your virtual id and fail.
- **Heavy work in `transform` without early-exit** — dev runs this per module per request; guard with `id.endsWith(…)` before doing anything expensive.
- **Assuming Node globals in transformed code** — `transform` runs at build time in the plugin, but the *output* runs in the browser. Don't accidentally leak `process.env.X` into shipped bundles unless you actually want that.

---

## Related

- [[Build Tools Bundlers - Rollup Internals]] — shared hook shape
- [[Build Tools Vite - HMR API]]
- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Foundations - AST and Transform Pipelines]]
- [[Build Tools Vite Guide]]
