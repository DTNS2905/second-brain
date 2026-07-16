---
tags:
  - build-tools
  - dev-server
  - hmr
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/api/hot-module-replacement/
---

# Build Tools Dev Server and HMR — HMR Protocol Fundamentals

> Every HMR system has the same three parts: a server-side watcher, a transport (WebSocket usually), and a client runtime. Understanding this shape lets you reason about Vite, Webpack, Metro, and Turbopack as variations on the same theme. Part of [[Build Tools Dev Server and HMR Guide]].

---

## The three parts

Every HMR implementation — Vite, Webpack, Metro, Turbopack, Parcel — decomposes into the same three moving parts. Naming and wire format differ; the shape does not.

1. **Server watcher** — detects file changes, invalidates modules, computes the propagation set.
2. **Transport** — usually WebSocket; carries update messages to the browser.
3. **Client runtime** — receives updates, calls user-provided `accept` handlers, or falls back to full reload.

| Part | Runs where | Responsibility |
|---|---|---|
| Watcher | Node process | fs events, transform pipeline, dep graph, message emission |
| Transport | Between processes | Reliable ordered delivery of update messages |
| Client runtime | Browser | Fetch new modules, run accept callbacks, framework glue |

The client runtime is small (a few KB) but load-bearing — it's the piece that makes HMR feel "invisible" when it works.

---

## The lifecycle of a change

The end-to-end sequence from keystroke to updated UI. Every mainstream bundler follows this shape.

1. User saves `src/Button.tsx`.
2. Server watcher receives fs event (chokidar, native fs.watch, or platform-specific).
3. Server re-transforms the changed module (esbuild, SWC, Babel, whatever).
4. Server walks importers UP the graph looking for an accept boundary.
5. If found, server sends an `update` message with the accept boundary URLs.
6. Client re-fetches those modules and re-executes them.
7. `import.meta.hot.accept(cb)` calls fire with the new module.
8. State is preserved because the surrounding scope wasn't reloaded.

If no accept boundary is found → `full-reload`.

```
save file
   │
   ▼
fs event ──► server transforms module
                     │
                     ▼
               walk importers up
                     │
             ┌───────┴────────┐
             ▼                ▼
      accept found       root reached
             │                │
             ▼                ▼
      send `update`   send `full-reload`
             │                │
             ▼                ▼
      client re-execs   window.location.reload()
             │
             ▼
      accept callback runs
             │
             ▼
      state preserved
```

The critical property: **step 4 is where all the interesting design decisions live**. Vite walks the ES module graph on demand; Webpack pre-computes it during compilation; Metro precomputes then diffs. The rest of the pipeline is largely mechanical.

---

## Module boundaries and accept semantics

A module opts into HMR by calling `import.meta.hot.accept()` (Vite / ESM-native) or `module.hot.accept()` (Webpack / CommonJS-style). There are two forms:

- **Self-accept** — `accept()` with no args → this module handles its own updates.
- **Dep-accept** — `accept('./dep', cb)` → this module handles updates to a specific dependency.

Propagation stops at the nearest ancestor that accepts.

```ts
if (import.meta.hot) {
  import.meta.hot.accept()
}
```

```ts
if (import.meta.hot) {
  import.meta.hot.accept('./dep', (newDep) => {
    remountWith(newDep)
  })
}
```

✅ Self-accept in leaf modules where a full re-execution is safe.
✅ Dep-accept when a parent needs to re-wire a specific import.
❌ Don't sprinkle `accept()` in modules with global side effects — you'll re-run them on every edit.

An accept handler receives the new module as its argument (or `undefined` if the update failed). Use the argument, not a re-import — the re-import would be cached.

---

## Propagation up the graph

Given a change, the server walks importers upward until it finds a module that opted in via `accept`. That module — and everything below it in the graph, up to the change — is the update set.

```
src/Button.tsx        ← changed
  ↑
src/Toolbar.tsx        ← no accept — propagate up
  ↑
src/App.tsx            ← self-accept? yes → stop here, re-run App
```

If `App.tsx` also doesn't accept and the graph reaches the root without finding one → full-reload.

The **accept boundary** is the topmost module whose scope will be preserved. Everything strictly above it survives the update. Everything at-or-below it is re-executed.

| Scenario | Result |
|---|---|
| Leaf self-accepts | Only leaf re-runs; parents keep scope |
| Parent dep-accepts child | Parent's callback fires; parent scope preserved |
| No accept found | Full page reload |
| Accept found but throws | Full page reload |

This is why React Refresh works: every React component file is auto-wrapped with a self-accept, so each component becomes its own boundary.

---

## Invalidation

A module can call `import.meta.hot.invalidate()` (Vite) or `module.hot.invalidate()` (Webpack) inside its accept handler to say "actually I can't handle this — propagate up." Useful when the update changed a module-level thing (an exported hook signature, an enum value).

```ts
if (import.meta.hot) {
  import.meta.hot.accept((newMod) => {
    if (!newMod) return
    if (newMod.SIGNATURE !== SIGNATURE) {
      import.meta.hot.invalidate()
      return
    }
    applyUpdate(newMod)
  })
}
```

The runtime then walks the graph again as if this module never opted in — searching for the next boundary above. If none exists, full-reload.

React Refresh uses this exact mechanism: when a component file's exports change shape (a hook was added or removed at the top level), the refresh runtime invalidates so the parent boundary or a full-reload picks up the change.

---

## State preservation model

What survives an HMR update:

- Application state **in scope of the accept boundary** — because that scope is preserved (only inner modules re-executed).
- Module-level constants in the **accept boundary itself** — no, wait: these re-initialize because the boundary scope re-runs. See below.
- React component state via **framework runtime** (React Refresh) — regardless of accept semantics.

What doesn't:

- Module-level state in the invalidated (below-boundary) module — replaced by the new module.
- State inside a full-reload fallback — everything resets.

| State type | Survives? | Why |
|---|---|---|
| Local var in accept boundary scope | ✅ | Scope not reloaded |
| Module-level const in boundary | ❌ | Boundary re-executes |
| Module-level const below boundary | ❌ | Module re-executes |
| React `useState` (with Fast Refresh) | ✅ | Runtime carries it over by component identity |
| React `useState` (no Fast Refresh) | ❌ | Component tree remounts |
| Redux/Zustand global store | ✅ | Store lives above boundary; reference preserved |
| DOM state (input value, scroll) | ✅ | DOM not touched by HMR itself |

The practical rule: **anything referenced by an object that lives strictly above the boundary survives.** Anything defined inside re-runs.

✅ Put your store, router, and app root above the accept boundary.
❌ Don't put per-component caches at module scope inside a boundary — they reset every edit.

---

## Error overlay contract

On transform error or runtime error during the accept handler, the client runtime shows a full-screen overlay. It's dismissible and disappears on the next successful update. Contents:

- File path
- Line number
- Column number
- Message
- Stack

```json
{
  "type": "error",
  "err": {
    "message": "Unexpected token",
    "stack": "...",
    "loc": { "file": "/src/Button.tsx", "line": 12, "column": 3 }
  }
}
```

The overlay is a `<div>` injected by the client runtime — it lives in a shadow root in Vite, and above the app root in Webpack Dev Server. Dismissing it doesn't retry the update; the next successful message clears it automatically.

✅ Keep the overlay enabled in dev — it catches syntax errors instantly.
❌ Don't run production error boundaries against dev overlay behavior — different contract entirely.

---

## Full-reload fallback

Triggers for the client to call `location.reload()`:

- No accept boundary between changed module and root.
- Framework runtime declines the update (React Refresh detects a hook signature change).
- Update handler throws during execution.
- Manifest / config change (Webpack).
- `vite.config.ts` / `next.config.js` / equivalent edited — dev server restarts.
- HTML file changed — nothing to hot-swap.

| Trigger | Recoverable? |
|---|---|
| No accept boundary | Yes — add `import.meta.hot.accept()` |
| Framework declines | Yes — restructure to keep hook shape stable |
| Update throws | Yes — fix the error |
| Config change | No — full reload is correct |
| HTML change | No — full reload is correct |

The full-reload path is not a failure. It's the graceful fallback that keeps the dev loop tight even when HMR can't apply the change surgically. Bundlers that "always work" do so by falling back cheerfully, not by never falling back.

---

## WebSocket message shape (generic)

The wire format differs between bundlers, but the message categories are universal.

```json
{ "type": "update", "modules": [{ "path": "/src/Button.tsx", "acceptedPath": "/src/App.tsx" }] }
{ "type": "full-reload", "reason": "Config changed" }
{ "type": "prune", "paths": ["/src/OldFoo.tsx"] }
{ "type": "error", "message": "SyntaxError: …" }
```

| Message | Meaning | Client action |
|---|---|---|
| `update` | Re-execute these modules within their accept boundaries | Fetch, run, call accept cb |
| `full-reload` | Cannot patch — reset the page | `location.reload()` |
| `prune` | Module removed from graph; drop its `dispose` handlers | Call dispose, unregister |
| `error` | Compilation failed | Show overlay |
| `connected` | Handshake complete | Nothing; log |
| `ping` | Liveness check | Reply `pong` |

Vite adds `custom` events for `hot.send()` / `hot.on()` — a general pub/sub channel between server plugins and client code. Useful for plugin-driven live updates (e.g., a CSS-in-JS runtime notifying the browser of a theme change).

---

## Why WebSockets and not SSE

WebSocket is bidirectional (client → server for custom events, ping-pong, etc.). Server-Sent Events are one-way (server → client). Webpack Dev Server historically supported SSE and now defaults to WS. Vite is WS-only.

| Property | WebSocket | SSE |
|---|---|---|
| Direction | Duplex | Server → client |
| Reconnect | Manual | Automatic (built-in) |
| Framing | Message-based | Line-based text |
| Binary | Yes | No |
| Custom events client → server | ✅ | ❌ |
| Firewall friendliness | Sometimes blocked | HTTP-friendly |

The bidirectional channel is what makes custom events (Vite's `hot.send()`), interactive prompts (dev-time RPC), and ping-pong liveness checks possible over a single connection. SSE would need a separate `fetch` for each client → server message.

---

## Cross-origin and dev proxy

HMR WebSocket usually uses the same host:port as the dev server. In dev-with-proxy setups (Docker, corporate proxy, HTTPS-terminating reverse proxy), you may need to configure the HMR client host/port so the browser knows where to actually connect the WebSocket.

```ts
{
  server: {
    hmr: {
      host: 'localhost',
      port: 5174,
    },
  },
}
```

Common symptoms of a broken HMR socket:

- Page loads fine but edits don't hot-reload.
- Console shows `WebSocket connection to 'wss://…' failed`.
- Client runtime falls back to polling reload.

| Setup | Fix |
|---|---|
| Docker with port mapping | Set `hmr.host` to the host-visible address |
| HTTPS terminated by proxy | Set `hmr.protocol: 'wss'`, `hmr.clientPort` |
| Behind path-based proxy | Set `hmr.path` to the proxied path |
| WSL / VM | Set `hmr.host` to the host-side IP |

See [[Build Tools Dev Server and HMR - Vite HMR Protocol]] for Vite-specific configuration and [[Build Tools Dev Server and HMR - Webpack HMR Protocol]] for the `webpack-dev-server` equivalents.

---

## Common misconceptions

```
❌ "HMR magically preserves all state."
✅ Preservation depends on where the accept boundary is. Module-level state in the
   invalidated module resets. Only scope above the boundary is truly preserved.

❌ "React Fast Refresh is separate from Vite HMR."
✅ Fast Refresh is a framework runtime that USES the bundler's HMR client. It
   doesn't replace it. See [[Build Tools Dev Server and HMR - React Fast Refresh]].
```

More:

```
❌ "If HMR does a full reload, it's broken."
✅ Full reload is the graceful fallback. It fires when the update genuinely can't
   be applied surgically (config change, no accept boundary, framework declines).

❌ "You should call accept() in every module."
✅ Only where re-executing that module is safe and cheap. In a large tree, one or
   two well-placed boundaries beat sprinkling accept() everywhere.

❌ "WebSocket vs SSE is a performance question."
✅ It's a capability question. SSE literally can't do client → server custom events
   without a second channel. WS gives you a single bidirectional pipe.

❌ "HMR and live-reload are the same."
✅ Live-reload = full page reload on any change. HMR = patch the running app in
   place. HMR falls back to live-reload; live-reload has no fallback path because
   it's already the fallback.
```

---

## Related

- [[Build Tools Dev Server and HMR - Vite HMR Protocol]]
- [[Build Tools Dev Server and HMR - Webpack HMR Protocol]]
- [[Build Tools Dev Server and HMR - React Fast Refresh]]
- [[Build Tools Dev Server and HMR Guide]]
