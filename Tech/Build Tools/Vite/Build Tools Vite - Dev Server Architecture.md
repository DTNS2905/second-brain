---
tags:
  - build-tools
  - vite
  - dev-server
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/features
---

# Build Tools Vite — Dev Server Architecture

> The Vite dev server is a Connect middleware pipeline that intercepts module requests, transforms per-file, and serves native ESM to the browser. This note walks its internals. Part of [[Build Tools Vite Guide]].

---

## Connect middleware pipeline

Vite's dev server is a [Connect](https://github.com/senchalabs/connect) app — the same middleware primitive Express is built on. Each incoming request walks a stack of middlewares until one writes a response.

The stack, in order:

1. **CORS / host check** — validates `Origin` and `Host` headers.
2. **Cached transform middleware** — short-circuits requests that already have a fresh transform result.
3. **Source map middleware** — serves `.map` files for transformed modules.
4. **Public dir middleware** — serves files from `public/` verbatim.
5. **Transform middleware** — the core: resolve → load → transform for JS/TS/JSX/CSS/etc.
6. **Static file middleware** — serves anything else on disk under the project root.
7. **HTML transform middleware** — rewrites `index.html` (injects `@vite/client`, resolves module scripts).
8. **SPA fallback** — rewrites unknown URLs to `/index.html`.
9. **404 middleware** — final fallback.

The HMR WebSocket lives alongside on the same HTTP server via an `upgrade` handler, not inside the middleware chain.

```ts
// Simplified internal shape
const server = connect();
server.use(corsMiddleware);
server.use(cachedTransformMiddleware);
server.use(sourceMapMiddleware);
server.use(publicDirMiddleware);
server.use(transformMiddleware);
server.use(serveStaticMiddleware);
server.use(indexHtmlMiddleware);
server.use(spaFallbackMiddleware);
server.use(notFoundMiddleware);
httpServer.on('upgrade', wsUpgradeHandler);
```

---

## Request flow for a JS module

When the browser requests `/src/App.tsx`, the following happens end-to-end:

1. Browser sends `GET /src/App.tsx` with `Accept: */*` and referrer of the page.
2. **Middleware: resolveId** — every plugin's `resolveId` hook runs in sequence. First non-null wins. Plugins can rewrite the id (e.g., virtual modules).
3. **Middleware: load** — plugins can provide contents via the `load` hook; otherwise Vite reads from disk.
4. **Middleware: transform** — esbuild strips TS/JSX to plain JS; every plugin's `transform` hook then runs.
5. **Middleware: import rewriting** — bare specifiers like `import React from 'react'` are rewritten to `/node_modules/.vite/deps/react.js?v=abc123`. Relative imports get their extensions appended if missing.
6. **Response** — `Content-Type: application/javascript`, ETag set, source map appended inline as base64 data URL.

All of this happens in single-digit milliseconds per file — most of the cost is transform, and esbuild is measured in tens of microseconds for typical files.

```
Browser                Dev Server                Plugins
   │  GET /src/App.tsx     │                        │
   │──────────────────────>│  resolveId(id)         │
   │                       │───────────────────────>│
   │                       │<──────────────────────│
   │                       │  load(id)              │
   │                       │───────────────────────>│
   │                       │<──────────────────────│
   │                       │  transform(code, id)   │
   │                       │───────────────────────>│
   │                       │<──────────────────────│
   │                       │  rewrite imports       │
   │  200 application/js   │                        │
   │<──────────────────────│                        │
```

Cross-link: [[Build Tools Vite - Plugin API]] covers `resolveId` / `load` / `transform` in depth.

---

## The module graph

Vite maintains an in-memory graph of every module the browser has requested. It's the single source of truth for HMR.

- **Nodes** — one per `(url, resolvedId)` pair. Each carries `transformResult`, `importers` (who imports me), `importedModules` (who I import), `acceptedHmrDeps`, `isSelfAccepting`, `lastHMRTimestamp`.
- **Edges** — imports, tracked when the transform pass sees an `import` statement.

On file change, Vite calls `moduleGraph.onFileChange(file)` which invalidates that node and walks importers to find the nearest HMR boundary (a module that called `import.meta.hot.accept`). Everything from the changed file up to that boundary gets re-executed.

```ts
// server.moduleGraph API surface
server.moduleGraph.getModuleById(id);
server.moduleGraph.getModulesByFile(file);
server.moduleGraph.invalidateModule(mod);
server.moduleGraph.invalidateAll();
```

Cross-link: [[Build Tools Vite - HMR API]] for the boundary-walking algorithm.

---

## import.meta.env

At transform time, Vite performs static replacement on `import.meta.env.*` references. This isn't a runtime object lookup — it's a text substitution done during the transform pass, which means dead-code elimination can strip unused branches.

Built-in vars:

| Variable | Type | Value |
|----------|------|-------|
| `import.meta.env.MODE` | string | `development` or `production` (or custom) |
| `import.meta.env.PROD` | boolean | `true` in prod build |
| `import.meta.env.DEV` | boolean | `true` in dev server |
| `import.meta.env.SSR` | boolean | `true` during SSR transform |
| `import.meta.env.BASE_URL` | string | `config.base` |

User-defined vars: any env var prefixed `VITE_` in `.env` files gets injected.

```ts
// Source
if (import.meta.env.DEV) console.log('dev');
if (import.meta.env.PROD) sendAnalytics();
console.log(import.meta.env.VITE_API_URL);

// Transformed (dev)
if (true) console.log('dev');
if (false) sendAnalytics();
console.log("http://localhost:8080");

// Transformed (prod) — after minification the `if (false)` branch is stripped
console.log('dev'); // ❌ this stays if not properly guarded
sendAnalytics();
console.log("https://api.example.com");
```

The static-replacement approach is why `import.meta.env[dynamicKey]` **does not work** — there's no runtime object to index into.

```ts
❌ const key = 'VITE_API_URL';
   const url = import.meta.env[key]; // undefined at runtime

✅ const url = import.meta.env.VITE_API_URL; // static access works
```

---

## Custom middleware

Plugins can inject express-style middleware via the `configureServer` hook. This is how tools like `vite-plugin-mock`, dev-only auth stubs, and health endpoints work.

```ts
// vite.config.ts
import type { Plugin } from 'vite';

function apiMockPlugin(): Plugin {
  return {
    name: 'my-api-mock',
    configureServer(server) {
      server.middlewares.use('/api/echo', (req, res) => {
        let body = '';
        req.on('data', chunk => (body += chunk));
        req.on('end', () => {
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify({ received: body }));
        });
      });
    },
  };
}

export default {
  plugins: [apiMockPlugin()],
};
```

The `configureServer` hook can return a function that runs *after* Vite's internal middlewares are installed — use this to override Vite's built-in behavior:

```ts
configureServer(server) {
  // Runs BEFORE internal middlewares
  server.middlewares.use('/before', beforeHandler);

  return () => {
    // Runs AFTER internal middlewares (post-hooks)
    server.middlewares.use('/after', afterHandler);
  };
}
```

The order matters when your middleware needs to override the SPA fallback or serve something the transform middleware would otherwise 404.

---

## Proxy configuration

For a decoupled backend, `server.proxy` is a thin wrapper around [http-proxy](https://github.com/http-party/node-http-proxy).

```ts
// vite.config.ts
export default {
  server: {
    proxy: {
      // String shorthand: /api/foo → http://localhost:8080/api/foo
      '/api': 'http://localhost:8080',

      // Object form with options
      '/graphql': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: path => path.replace(/^\/graphql/, '/api/graphql'),
      },

      // Regex prefix (must start with ^)
      '^/socket': {
        target: 'ws://localhost:8080',
        ws: true,
      },

      // With custom error handling and event hooks
      '/auth': {
        target: 'http://localhost:9000',
        changeOrigin: true,
        secure: false,
        configure: (proxy, options) => {
          proxy.on('proxyReq', (proxyReq, req) => {
            proxyReq.setHeader('X-Forwarded-For', req.socket.remoteAddress ?? '');
          });
          proxy.on('error', (err, req, res) => {
            console.error('[proxy]', err.message);
          });
        },
      },
    },
  },
};
```

Key options:

| Option | Purpose |
|--------|---------|
| `target` | Origin to forward to |
| `changeOrigin` | Rewrites `Host` header to target — needed for virtual-host backends |
| `ws` | Enables WebSocket proxying |
| `rewrite` | Path transform function |
| `secure` | If `false`, accepts self-signed certs on target |
| `configure` | Callback for direct access to the underlying proxy instance |

---

## SPA fallback vs MPA

By default the dev server assumes single-page-app routing: any URL that doesn't match a real file resolves to `/index.html`, letting client-side routers (React Router, Vue Router) take over.

For multi-page apps, disable the fallback implicitly by declaring multiple HTML entries in `build.rollupOptions.input`:

```ts
// vite.config.ts
import { resolve } from 'node:path';

export default {
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        admin: resolve(__dirname, 'admin/index.html'),
        marketing: resolve(__dirname, 'marketing/index.html'),
      },
    },
  },
  appType: 'mpa', // disables SPA fallback in dev
};
```

Set `appType: 'custom'` if you're handling all HTML serving yourself (e.g., SSR framework integrations).

| `appType` | SPA fallback | HTML middleware |
|-----------|--------------|-----------------|
| `'spa'` (default) | ✅ | ✅ |
| `'mpa'` | ❌ | ✅ |
| `'custom'` | ❌ | ❌ |

---

## Static assets and public dir

Two distinct paths for asset handling in dev:

**`public/`** — served as-is at root. `public/favicon.svg` becomes `/favicon.svg`. No transforms, no hashing, no import graph. Use for files referenced by literal URL (favicons, robots.txt, `og:image` targets).

**JS/CSS-imported files** — go through the transform pipeline. `import logo from './logo.svg'` returns a resolved URL string; the file gets served through the transform middleware and, in prod, hashed and copied to `dist/assets/`.

Query-suffix modifiers on imports:

```ts
import url from './icon.svg?url';        // Force URL import (default for images)
import raw from './shader.glsl?raw';     // Import as string
import inline from './icon.svg?inline';  // Force inline as data URL
import worker from './job.ts?worker';    // Import as Worker constructor
import wasm from './lib.wasm?init';      // WebAssembly init function
```

The `?raw` and `?inline` suffixes bypass the normal loader and go straight through the transform middleware with special handling.

Cross-link: [[Build Tools Vite - CSS and Asset Handling]] for the full asset pipeline.

---

## Module preload / warmup

Cold-start latency in dev comes from lazy transformation — the browser has to request each module before Vite transforms it. For big apps this creates a request waterfall on first load.

The `server.warmup` option pre-transforms declared entry points on server start:

```ts
// vite.config.ts
export default {
  server: {
    warmup: {
      clientFiles: [
        './src/main.tsx',
        './src/App.tsx',
        './src/routes/**/*.tsx',
      ],
      ssrFiles: [
        './src/entry-server.tsx',
      ],
    },
  },
};
```

Vite walks each glob, transforms the files, and populates the module graph before the first browser request arrives. Combined with dep pre-bundling (see [[Build Tools Vite - Dependency Pre-Bundling]]), initial page load becomes near-instant.

---

## HTTPS in dev

Some browser APIs (`crypto.subtle`, `getUserMedia`, service workers on non-localhost) require secure context. Vite supports HTTPS in dev:

```ts
// vite.config.ts
import { readFileSync } from 'node:fs';

export default {
  server: {
    https: {
      cert: readFileSync('./certs/cert.pem'),
      key: readFileSync('./certs/key.pem'),
    },
    host: 'dev.example.local',
    port: 443,
  },
};
```

For a zero-config option, use [`@vitejs/plugin-basic-ssl`](https://github.com/vitejs/vite-plugin-basic-ssl) which generates a self-signed cert automatically — accept the browser warning once and you're set.

```ts
import basicSsl from '@vitejs/plugin-basic-ssl';

export default {
  plugins: [basicSsl()],
  server: { https: true },
};
```

HTTP/2 is enabled automatically when HTTPS is on, which mitigates the many-small-modules problem that plain HTTPS would otherwise worsen.

---

## WebSocket for HMR

The same HTTP server upgrades to WS for HMR traffic. The client connects to `/@vite/client` (or a configured path), and messages flow in both directions:

| Direction | Message type | Purpose |
|-----------|--------------|---------|
| Server → Client | `update` | Modules to reload |
| Server → Client | `full-reload` | Fall back to page refresh |
| Server → Client | `error` | Compile/transform error → overlay |
| Server → Client | `prune` | Modules removed from graph |
| Server → Client | `custom` | User events from plugins |
| Client → Server | `custom` | User events from `import.meta.hot.send` |

WS server config:

```ts
export default {
  server: {
    hmr: {
      protocol: 'wss',
      host: 'localhost',
      port: 24678,           // Separate port for HMR (useful behind reverse proxies)
      clientPort: 443,       // What the browser connects to
      overlay: true,         // In-browser error overlay
    },
  },
};
```

Cross-link: [[Build Tools Vite - HMR API]] for the full HMR protocol and boundary semantics.

---

## The @vite/client runtime

Vite injects `<script type="module" src="/@vite/client"></script>` at the top of `index.html` in dev. This ~6KB script is the browser-side HMR client. It:

- Opens the HMR WebSocket connection.
- Registers `import.meta.hot` on each module via `createHotContext(url)`.
- Applies incoming `update` messages by re-importing the changed module with a cache-busting `?t=<timestamp>` query.
- Renders the compile-error overlay when the server sends `error` messages.
- Handles style-tag injection for hot-reloaded CSS.

Not present in prod builds — production HTML has none of this. That's why `import.meta.hot` is guarded by `if (import.meta.hot)` in library code:

```ts
if (import.meta.hot) {
  import.meta.hot.accept(newModule => {
    // handle update
  });
}
```

The check compiles to `if (undefined)` in prod, which minifiers strip completely.

---

## Custom event system

Plugins can send arbitrary events to the client, and the client can send events back — a full-duplex channel over the HMR WebSocket.

**Server → Client (from a plugin):**

```ts
// vite.config.ts
export default {
  plugins: [
    {
      name: 'db-schema-watcher',
      configureServer(server) {
        watchDbSchema(newSchema => {
          server.ws.send({
            type: 'custom',
            event: 'schema:updated',
            data: { schema: newSchema, at: Date.now() },
          });
        });
      },
    },
  ],
};
```

**Client listener:**

```ts
// src/main.ts
if (import.meta.hot) {
  import.meta.hot.on('schema:updated', ({ schema, at }) => {
    console.log('schema changed at', at);
    refetchQueries(schema);
  });
}
```

**Client → Server:**

```ts
// Client
if (import.meta.hot) {
  import.meta.hot.send('client:ready', { userId: 42 });
}

// Server (plugin)
configureServer(server) {
  server.ws.on('client:ready', (data, client) => {
    console.log('client says hi', data);
    client.send('server:ack', { ok: true });
  });
}
```

Cross-link: [[Build Tools Vite - HMR API]] for the underlying protocol.

---

## Common debugging

```
❌ "My import isn't resolving in dev but works in prod"
✅ Missing pre-bundle → force with optimizeDeps.include:
   { optimizeDeps: { include: ['lodash-es/debounce'] } }
   The dep didn't get discovered during the initial scan.
```

```
❌ "Middleware runs twice"
✅ Pre / post middleware ordering — check configureServer return value.
   Middlewares registered inside the hook run PRE-internal;
   middlewares in the returned function run POST-internal.
```

```
❌ "Env vars are undefined at runtime"
✅ Only VITE_-prefixed vars are exposed. Other names are silently dropped
   for security. Rename FOO=bar → VITE_FOO=bar.
```

```
❌ "HMR WebSocket keeps disconnecting behind my reverse proxy"
✅ Configure server.hmr.clientPort to the public port,
   and ensure your proxy forwards Upgrade / Connection headers.
```

```
❌ "index.html transform doesn't inject my script"
✅ You're using appType: 'custom' — the HTML middleware is disabled.
   Either switch to 'spa'/'mpa' or transform HTML manually via
   server.transformIndexHtml(url, html).
```

```
❌ "Static file in public/ 404s"
✅ Reference it by absolute path, not relative:
   ❌ <img src="./favicon.svg">
   ✅ <img src="/favicon.svg">
   public/ is served at the root, not resolved relative to importing files.
```

```
❌ "CORS error hitting my dev server from another origin"
✅ server.cors is true by default but restrictive.
   Set server.cors = { origin: 'https://myapp.local' } explicitly.
```

---

## Related

- [[Build Tools Vite - HMR API]]
- [[Build Tools Vite - Plugin API]]
- [[Build Tools Vite - Dependency Pre-Bundling]]
- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Vite Guide]]
