---
tags:
  - build-tools
  - dev-server
  - hmr
  - vite
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/api-hmr
---

# Build Tools Dev Server and HMR — Vite HMR Protocol

> Vite's HMR is a small WebSocket protocol atop the module graph. This note covers message shapes, the plugin hook (handleHotUpdate), and the interaction with framework runtimes. Part of [[Build Tools Dev Server and HMR Guide]].

---

## The WebSocket connection

When you run `vite dev`, the server exposes an HTTP endpoint (default `http://localhost:5173/`) **and** a WebSocket endpoint on the same port. The `@vite/client` runtime — a small ~5KB module — is injected into every HTML page served in dev.

```html
<script type="module" src="/@vite/client"></script>
```

That client:

1. Opens `ws://localhost:5173/` (or `wss://` behind HTTPS).
2. Listens for `HMRPayload` messages on the socket.
3. Sends `ping` frames every ~30s to keep the connection alive.
4. On disconnect, retries with exponential backoff and reloads once the server is back.

Configuration lives under `server.hmr`:

```ts
export default {
  server: {
    hmr: {
      host: 'localhost',
      port: 5173,          // usually shared with the HTTP port
      protocol: 'ws',      // 'wss' behind TLS proxies
      clientPort: 443,     // useful when a proxy terminates TLS
      overlay: true,       // in-page error overlay
    },
  },
};
```

Cross-link `[[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]]` for the generic client/server dance shared with Webpack.

---

## Message types (server → client)

Every message on the socket is a JSON object with a `type` discriminator. The union in `vite/src/node/server/ws.ts`:

```ts
type HMRPayload =
  | ConnectedPayload        // handshake
  | UpdatePayload           // module update(s)
  | FullReloadPayload
  | PrunePayload            // remove modules from graph
  | ErrorPayload
  | CustomPayload;          // plugin-defined events
```

Concrete shapes on the wire:

```json
{ "type": "connected" }

{ "type": "update", "updates": [
  { "type": "js-update", "path": "/src/App.tsx", "acceptedPath": "/src/App.tsx", "timestamp": 1720000000000 },
  { "type": "css-update", "path": "/src/app.css", "acceptedPath": "/src/app.css", "timestamp": 1720000000000 }
]}

{ "type": "full-reload", "path": "/src/config.ts" }

{ "type": "prune", "paths": ["/src/Old.tsx"] }

{ "type": "error", "err": { "message": "...", "stack": "...", "loc": {"file": "...", "line": 12, "column": 4} } }

{ "type": "custom", "event": "user:foo", "data": { "anything": true } }
```

Semantics of each:

| Type | Meaning |
|------|--------|
| `connected` | Handshake — client can start accepting updates. |
| `update` | One or more modules changed. `updates[i].type` is `js-update` or `css-update`. |
| `full-reload` | The change couldn't be handled — reload the page. `path` is informational. |
| `prune` | Modules removed from the graph (e.g. an import was deleted). Client runs their `dispose` hooks. |
| `error` | Compile error — client shows the overlay. |
| `custom` | User- or plugin-emitted event; consumed via `import.meta.hot.on(event, fn)`. |

---

## Message types (client → server)

The reverse channel is minimal:

```json
{ "type": "custom", "event": "client:hello", "data": {"foo": "bar"} }
{ "type": "ping" }
```

Only two shapes ever come from the browser:

- **`custom`** — the browser fires `import.meta.hot.send('client:hello', {foo: 'bar'})`, which is delivered to any plugin that called `server.ws.on('client:hello', handler)`.
- **`ping`** — liveness. The server responds with a `pong` frame.

Compared to Webpack's HMR (which is almost entirely server-driven), the client → server direction here matters for two-way plugin communication (e.g. a devtools panel talking to Vite).

---

## The handleHotUpdate plugin hook

`handleHotUpdate` is Vite's escape hatch for custom HMR logic. Fires on every file change, before Vite computes the default update.

```ts
{
  name: 'my-plugin',
  handleHotUpdate(ctx) {
    // ctx.file — absolute path of changed file
    // ctx.timestamp — when it changed
    // ctx.modules — modules to be invalidated
    // ctx.read — async fn to read current contents
    // ctx.server — the ViteDevServer

    if (ctx.file.endsWith('.custom')) {
      ctx.server.ws.send({ type: 'custom', event: 'reload-widget' });
      return [];   // skip default HMR
    }
    return ctx.modules;   // let Vite handle
  },
}
```

Return-value contract:

- `undefined` / `ctx.modules` — Vite runs its default propagation.
- `[]` — skip HMR entirely for this change (you've handled it via a custom event).
- A filtered `ModuleNode[]` — only invalidate those modules.
- A new `ModuleNode[]` that includes modules **outside** the default set — force propagation to more modules (e.g. re-run all consumers of a virtual module).

✅ Use this for:

- Custom file types (`.mdx`, `.graphql`, `.custom`) where the default JS/CSS handling doesn't fit.
- Server-driven notifications ("your data query is stale, refetch").
- Filtering out unwanted reloads (e.g. edits to a comment-only file).

❌ Don't use it to hack around missing `import.meta.hot.accept` calls — do the accepting properly in user code.

---

## Module graph on the server

Vite maintains an in-memory graph in `server.moduleGraph`. Every module it's seen has a `ModuleNode`:

- **URL** — `/src/App.tsx` (as the browser requests it).
- **Resolved ID** — absolute path on disk, or a virtual id like `\0virtual:foo`.
- **Importers** — `Set<ModuleNode>` — modules that `import` this one.
- **Imported modules** — `Set<ModuleNode>` — what this module imports.
- **Accepted deps** — `Set<ModuleNode>` — populated when the module calls `import.meta.hot.accept([...])`.
- **Last HMR timestamp** — the `?t=` query string appended on the next fetch.
- **isSelfAccepting** — did the module call `import.meta.hot.accept(cb)` with no deps?

The graph is bidirectional (importers + imported), which is what makes the invalidation walk cheap.

---

## Invalidation algorithm

On every file change, Vite walks **upward** from the changed module through `importers` looking for the nearest HMR boundary. Simplified:

```
function invalidate(mod, seen = Set()):
  if seen has mod: return
  seen.add(mod)
  if mod.acceptedHmr:
    return { boundary: mod, seen }
  for importer of mod.importers:
    result = invalidate(importer, seen)
    if result: return result
  return null  // no boundary → full reload
```

The `seen` set prevents infinite loops in circular graphs. If the walk reaches a module with no importers (an entry point) and none of them accept, the result is a `full-reload`.

Concrete example:

```
main.tsx  →  App.tsx  →  Button.tsx
```

- Edit `Button.tsx`: no acceptance → walk to `App.tsx` → `App.tsx` accepts (React Fast Refresh injects this) → boundary is `App.tsx` → HMR update payload sent.
- Edit `main.tsx`: no importers, doesn't self-accept → `full-reload`.

---

## CSS updates

CSS updates are distinct from JS updates and travel as `type: 'css-update'` inside an `update` payload. The client:

1. Finds the existing `<style data-vite-dev-id="…">` (or `<link>`) for that path.
2. Replaces its `textContent` with the new CSS (or bumps the `?t=` on the `href`).
3. Never re-executes the JS module that imported the CSS.

Behavior notes:

- CSS is **always** self-accepting — the client never falls back to full reload.
- CSS Modules (`.module.css`) generate a JS module (the class name map). When the map changes, that JS module *is* invalidated and propagates upward normally.
- `<style>` blocks in `.vue`/`.svelte`/`.astro` are handled by the framework plugin, which turns them into virtual CSS modules.

---

## Timestamps and query strings

Every `js-update` payload includes a `timestamp`. The client uses it to bust the browser cache:

```ts
import(`/@fs/Users/me/proj/src/App.tsx?t=1234567890`);
```

Why:

- Native `import()` is cached by URL. Without a distinct URL, the browser serves the stale module from its module map.
- Adding `?t=<ms>` guarantees a fresh network request.
- The server's transform pipeline treats `?t=` as a no-op query and returns the current transformed source.

The timestamp also flows to every **downstream** import: when `App.tsx` re-fetches, its `import './Button.tsx'` becomes `import './Button.tsx?t=<ms>'` too, so the whole subtree gets fresh copies.

---

## React Fast Refresh wiring

`@vitejs/plugin-react` (or `@vitejs/plugin-react-swc`) injects HMR glue into every JSX/TSX file at transform time:

```ts
// Simplified
if (import.meta.hot) {
  import.meta.hot.accept(withReactRefresh);
}
```

Where `withReactRefresh` is a wrapper that:

1. Calls `RefreshRuntime.performReactRefresh()` to swap in the new component.
2. Checks whether the module exports only React components (i.e. is "refresh-safe"). If not, it triggers a full reload via `import.meta.hot.invalidate()`.
3. Preserves `useState`/`useReducer` state across the swap by keying on component identity.

The key insight: Vite delegates **the update semantics** to the React Refresh runtime. Vite just says "here's a new module version" — React Refresh decides whether state survives.

Cross-link `[[Build Tools Dev Server and HMR - React Fast Refresh]]` for the deeper mechanics.

---

## Custom events — full example

Plugins and user code can exchange arbitrary events over the HMR channel. Server side:

```ts
// vite.config.ts
export default {
  plugins: [{
    name: 'notify-plugin',
    configureServer(server) {
      setInterval(() => {
        server.ws.send({ type: 'custom', event: 'tick', data: Date.now() });
      }, 10000);
    },
  }],
};
```

Client side:

```ts
// client
if (import.meta.hot) {
  import.meta.hot.on('tick', (ts) => {
    console.log('tick', ts);
  });
}
```

Two-way (client → server) via `import.meta.hot.send`:

```ts
// client
import.meta.hot.send('user:refetch', { id: 42 });
```

```ts
// plugin
configureServer(server) {
  server.ws.on('user:refetch', (data, client) => {
    console.log('client asked for refetch', data);
    client.send('user:refetch-ack', { ok: true });
  });
},
```

Namespace convention: prefix custom events with `plugin-name:` or `user:` to avoid collisions with Vite's built-in types.

---

## Error overlay

When a transform or plugin throws, Vite emits an `error` payload. The client injects an HTML overlay:

- Full stack trace, syntax-highlighted source frame, and file path (click-to-open in the editor via `server.launchEditor`).
- Persists until either a successful update arrives (auto-dismiss) or the user clicks it.
- Disable with `server.hmr.overlay: false` if you prefer console-only errors.

Runtime errors thrown by user code at import time also surface here, because the client wraps dynamic imports in a try/catch and forwards failures.

---

## Debugging

Vite uses the `debug` package for structured logging. To see every HMR decision:

```
DEBUG=vite:hmr vite dev
```

Useful namespaces:

| Namespace | What it shows |
|-----------|---------------|
| `vite:hmr` | Every file change → propagation → update payload sent |
| `vite:ws` | WebSocket connections and raw messages |
| `vite:transform` | Every module transform (verbose) |
| `vite:resolve` | Module resolution decisions |
| `vite:deps` | Dep pre-bundling / re-bundling |

In the browser, `localStorage.setItem('vite:hmr', 'true')` (via devtools console) enables verbose client logging — you'll see every accepted boundary, every pruned module, every `?t=` re-fetch.

---

## Vite vs Webpack HMR — diff at a glance

| | Vite | Webpack |
|---|------|---------|
| Client API | `import.meta.hot` | `module.hot` |
| Transport | WebSocket only | WS default, SSE fallback |
| Update mechanism | Re-fetch as ESM with new timestamp | Fetch `.hot-update.js` chunks + manifest |
| Framework integration | Via plugin hooks | Via loader + plugin |

Deeper contrast:

- **Vite** exploits the browser's native ES module loader. An update is literally `import('/src/App.tsx?t=<new>')` — no bundle rebuild.
- **Webpack** rebuilds the affected chunks and ships a JSON manifest listing which modules to swap; the runtime patches them into the existing bundle in place.
- **Cold start**: Vite is O(1) — no bundling. Webpack must bundle before the first byte.
- **Hot update latency**: comparable on small changes; Vite wins big on large graphs because it never re-bundles unaffected code.

Cross-link `[[Build Tools Dev Server and HMR - Webpack HMR Protocol]]` for the Webpack side of this diff.

---

## Related

- [[Build Tools Vite - HMR API]]
- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]]
- [[Build Tools Dev Server and HMR - React Fast Refresh]]
- [[Build Tools Dev Server and HMR Guide]]
