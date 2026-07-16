---
tags:
  - build-tools
  - vite
  - hmr
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/api-hmr
---

# Build Tools Vite — HMR API

> Vite's HMR contract is exposed via import.meta.hot — a small API for accepting, disposing, and invalidating module updates. This is what React Fast Refresh and Vue's HMR are built on top of. Part of [[Build Tools Vite Guide]].

---

## What HMR is (vs live-reload)

HMR (Hot Module Replacement) swaps a module in-place **without reloading the page**, preserving app state — form inputs, scroll position, open modals, in-memory stores. Live-reload, by contrast, reloads the whole page, blowing away all runtime state.

HMR is opt-in per module. Vite will only hot-swap a module if it (or one of its ancestors in the import graph) calls `import.meta.hot.accept()`. If no accept boundary is found while propagating the update, Vite falls back to a full page reload.

```
✅ HMR: patch the changed module, keep state
❌ Live-reload: throw away state, reparse everything
```

The API surface — `import.meta.hot` — is a Vite-flavored implementation of the [ESM HMR proposal](https://github.com/FredKSchott/esm-hmr). In production, `import.meta.hot` is `undefined` and all guarded blocks are dead-code eliminated.

Cross-link: [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]].

---

## The runtime

At dev startup, Vite injects a client script at the top of `index.html`:

```html
<script type="module" src="/@vite/client"></script>
```

This client script:

- Opens a **WebSocket** to the dev server (port matches `server.hmr.port` or the main dev port)
- Tracks the module graph on the client (which modules imported which)
- Handles inbound messages of type `update` / `full-reload` / `prune` / `error` / `custom`
- Exposes the `import.meta.hot` object per module via transform-time rewriting

The transform inlines a small runtime shim into every module that touches `import.meta.hot`. That shim knows its own module URL and can talk back to the client script.

```
Server (Node)              Client (browser)
  chokidar watcher    →    /@vite/client WebSocket
  module graph        →    module graph mirror
  transform + HMR     →    accept callbacks / dispose / prune
```

---

## `import.meta.hot.accept()`

The simplest form — a self-accepting module:

```ts
if (import.meta.hot) {
  import.meta.hot.accept();
}
```

Semantically: "This module can be re-executed without reloading the page." Vite will re-fetch and re-execute this module on change. Any importers of this module will see the *new* exports on their next read (via the module graph's version-bumping URL suffix, e.g. `?t=1728000000`).

Self-accepting modules are useful for leaf modules — styles, small helpers, constants — that have no cleanup obligation.

```ts
export const theme = { primary: '#00f' };

if (import.meta.hot) import.meta.hot.accept();
```

---

## Accepting dep updates

A module can accept updates to its **dependencies** instead of (or in addition to) itself:

```ts
if (import.meta.hot) {
  import.meta.hot.accept('./config.ts', (newMod) => {
    if (newMod) applyConfig(newMod.default);
  });
}
```

Semantically: "When `./config.ts` changes, don't reload me — I'll patch myself using the new module."

The callback receives the freshly evaluated dep module (or `undefined` if the update errored). It's the module's responsibility to reconcile — swap references, rewire event handlers, re-render, etc.

This is the pattern that plugin authors most often use, because it lets the *parent* module own the reconciliation logic for its children.

---

## Multi-dep accept

Accept updates from a list of deps:

```ts
if (import.meta.hot) {
  import.meta.hot.accept(['./a.ts', './b.ts'], ([newA, newB]) => {
    // newA and newB are aligned to the paths above
    // either may be undefined if that particular update errored
    if (newA) rewireA(newA);
    if (newB) rewireB(newB);
  });
}
```

The callback receives an array aligned to the paths — index `0` maps to `./a.ts`, index `1` to `./b.ts`. Any entry can be `undefined` if that specific update failed to evaluate.

Only the deps that actually changed will be non-undefined on any given tick — Vite batches multi-file changes, but each accept fires per-boundary.

---

## Dispose

Cleanup before the module is replaced:

```ts
if (import.meta.hot) {
  import.meta.hot.dispose((data) => {
    // stash state on `data` — becomes `import.meta.hot.data` in the new module
    data.subs = subs;
    clearInterval(timer);
    ws.close();
  });
}
```

`dispose` runs on the **old** module instance just before the new one evaluates. The `data` argument is a plain object that persists across module versions — read it back on the new instance via `import.meta.hot.data`:

```ts
const subs = import.meta.hot?.data.subs ?? new Set<() => void>();
```

Use dispose for:

- Clearing timers / intervals
- Removing DOM event listeners
- Closing sockets, database connections, workers
- Persisting subscription lists across reloads

Without a proper dispose, HMR will leak resources on every edit — the classic symptom is "my event handler fires 47 times after ten edits."

---

## Invalidate

Force propagation up to the next accept boundary:

```ts
if (import.meta.hot) {
  import.meta.hot.accept((newMod) => {
    if (!canPatch(newMod)) {
      import.meta.hot.invalidate('Cannot hot-swap: schema changed');
    }
  });
}
```

`invalidate(reason?)` says: "I registered as an accept boundary, but for this particular update I can't actually swap safely — please walk up and find another one." Vite will bubble the update to importers of this module. If no ancestor accepts, it becomes a full-reload.

The optional `reason` string is logged to the browser console — useful for debugging why a hot-swap became a reload.

Typical use: a component library that self-accepts, but on a *breaking* change to props needs the parent to re-render fresh.

---

## Prune

When a module is removed from the graph (no longer imported by anyone reachable from the entry):

```ts
if (import.meta.hot) {
  import.meta.hot.prune(() => {
    // teardown — the module will be dropped from the runtime
    unmount();
    removeStyleTag();
  });
}
```

`prune` fires when Vite detects the module has been orphaned — e.g., you removed the only `import './widget.css'` line. The callback is your last chance to detach side effects the module installed.

`prune` is **not** the same as `dispose`:

| Callback | Fires when | New module after? |
|----------|------------|-------------------|
| `dispose` | Module is about to be replaced | Yes — new version loads |
| `prune`   | Module is removed from graph   | No — gone entirely |

---

## The propagation algorithm

On a file change, Vite runs this algorithm on its **server-side module graph**:

1. Vite invalidates the changed module in its graph (bumps its version)
2. Walks up importers, marking each until it hits one with `import.meta.hot.accept` registered for the incoming edge
3. Sends an `update` message to the client with the accept-boundary URLs
4. If it can't find an accept boundary before reaching an entry point, sends `full-reload`
5. On the client, the accept-boundary module is re-fetched (via a versioned URL like `/src/foo.ts?t=...&import`), evaluated, and its accept callback fires with the new module

If any intermediate module has `hmr: false` (via `server.hmr` config or plugin metadata), propagation short-circuits to full-reload immediately.

```
change: ./utils/format.ts
  ↑ imported by ./components/Row.tsx           (no accept)
    ↑ imported by ./components/Table.tsx       (accepts './Row.tsx'? No, accepts self via React Refresh)
      → boundary found — send update for Table.tsx
```

If the boundary itself throws during evaluation, Vite sends an `error` message and the overlay appears.

Cross-link: [[Build Tools Dev Server and HMR - Vite HMR Protocol]].

---

## React Fast Refresh integration

`@vitejs/plugin-react` (and `@vitejs/plugin-react-swc`) inserts Fast Refresh boilerplate at transform time. For every module that exports React components, the plugin appends:

- A `RefreshRuntime.register(Component, id)` call per exported component
- A synthetic `import.meta.hot.accept` that hands the new module to the React Refresh runtime
- A guard that falls back to `invalidate()` if the module exports non-component values (which can't be safely hot-swapped)

```ts
// what the plugin injects at the bottom of MyComponent.tsx (roughly)
if (import.meta.hot) {
  RefreshReg(MyComponent, 'MyComponent');
  import.meta.hot.accept((newMod) => {
    if (!newMod) return;
    RefreshRuntime.performReactRefresh();
  });
}
```

This is why hot-editing a React component preserves state (`useState`, `useReducer`, context values) without any user-written HMR code — the React Refresh runtime patches the component's fiber tree in place.

Rules of thumb the plugin enforces:

- Only files exporting **only components** get Fast Refresh — mixing a `useMyHook` export next to a component in the same file forces a full-reload
- Anonymous default exports (`export default () => <div/>`) don't get Fast Refresh — Refresh needs a stable identity
- Named function/class components work; arrow functions assigned to a `const` also work

Cross-link: [[Build Tools Dev Server and HMR - React Fast Refresh]] and [[Build Tools Compilers - JSX and React Transforms]].

---

## Custom events

`import.meta.hot` doubles as a **typed pub-sub channel** between plugins (server) and browser modules (client). Useful for out-of-band signaling — "the graphql schema changed, re-fetch introspection" — without shoehorning it into module updates.

### Server → client

```ts
// vite plugin
export default {
  name: 'user-sync',
  configureServer(server) {
    watchUsers().on('change', (users) => {
      server.ws.send({ type: 'custom', event: 'user:sync', data: users });
    });
  },
};
```

```ts
// client module
if (import.meta.hot) {
  import.meta.hot.on('user:sync', (data) => {
    /* update local state, refresh queries, etc. */
    userStore.replaceAll(data);
  });
}
```

### Client → server

```ts
// client module
if (import.meta.hot) {
  import.meta.hot.send('client:hello', { greet: 'yo' });
}
```

```ts
// vite plugin
configureServer(server) {
  server.ws.on('client:hello', (data, client) => {
    /* respond — you can send back via client.send() */
    client.send('server:ack', { echoed: data.greet });
  });
}
```

Event names should be namespaced (`myplugin:eventname`) to avoid collisions with Vite's built-in events (`vite:beforeUpdate`, `vite:afterUpdate`, `vite:error`, `vite:ws:connect`, `vite:ws:disconnect`).

You can also `off()` a handler:

```ts
const handler = (data) => { /* ... */ };
import.meta.hot.on('user:sync', handler);
// later
import.meta.hot.off('user:sync', handler);
```

---

## HMR error overlay

Any syntax error, transform error, or unhandled exception in an HMR update callback renders a **full-screen error overlay** in dev, backed by a `<vite-error-overlay>` custom element. It shows:

- The error message
- File path with line/column
- A code frame
- The plugin that reported the error (if applicable)

The overlay is dismissible with Esc or by clicking outside — but it will re-appear on the next failed update. On a successful update, the overlay disappears automatically.

Disable it in `vite.config.ts` if you prefer console errors only:

```ts
export default {
  server: {
    hmr: { overlay: false },
  },
};
```

The overlay is styled as a Shadow DOM element, so it can't be broken by your app's CSS.

---

## HMR-unfriendly patterns

Not all code hot-reloads cleanly. Common footguns:

```
❌ Module-level state that can't survive re-run
✅ Store state in a ref or global map keyed by module id

❌ Side effects in module body that mutate globals
✅ Guard with import.meta.hot for HMR-safe teardown

❌ Anonymous default exports of React components
✅ Named function components (needed for Fast Refresh)

❌ Mixing component + non-component exports in one file
✅ Split hooks/utils into sibling files

❌ Assuming top-level code runs once
✅ Idempotent init — check for existing instance first
```

### Example: module-level singleton done wrong

```ts
// ❌ new socket every time the module reloads → leaks
const socket = new WebSocket('/api/live');
socket.onmessage = handleMessage;
```

### Same singleton done HMR-safely

```ts
// ✅ reuse across reloads, tear down on prune
const socket =
  import.meta.hot?.data.socket ?? new WebSocket('/api/live');
socket.onmessage = handleMessage;

if (import.meta.hot) {
  import.meta.hot.data.socket = socket;
  import.meta.hot.dispose(() => {
    socket.onmessage = null; // detach current handler; keep socket
  });
  import.meta.hot.prune(() => {
    socket.close();
  });
}
```

The pattern: stash long-lived resources on `import.meta.hot.data`, detach handlers in `dispose`, fully tear down in `prune`.

---

## API summary

| Method | Purpose | Fires on |
|--------|---------|----------|
| `accept()` | Self-accept — module can re-run in place | Own file change |
| `accept(dep, cb)` | Accept a single dep's updates | Dep change |
| `accept([...deps], cb)` | Accept multiple deps' updates | Any listed dep change |
| `dispose(cb)` | Cleanup before replacement | Own file change |
| `prune(cb)` | Cleanup when removed from graph | Import path removed |
| `invalidate(reason?)` | Bubble update to next boundary | Called from accept cb |
| `on(event, cb)` | Listen to server-sent custom events | Server `ws.send` |
| `off(event, cb)` | Detach a custom event listener | Manual |
| `send(event, data)` | Send a custom event to server | Manual |
| `data` | Persistent object across reloads | Read on new instance |

---

## Related

- [[Build Tools Dev Server and HMR - Vite HMR Protocol]]
- [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]]
- [[Build Tools Dev Server and HMR - React Fast Refresh]]
- [[Build Tools Vite - Plugin API]]
- [[Build Tools Vite Guide]]
