---
tags:
  - build-tools
  - vite
  - ssr
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/ssr
---

# Build Tools Vite — SSR and Environments

> Vite's SSR pipeline lets frameworks like Nuxt, SvelteKit, Astro, and Remix sit on top of it. The Environment API (v5+) generalizes SSR into a first-class multi-target build. Part of [[Build Tools Vite Guide]].

---

## Why SSR needs a different bundle

Client bundles target the browser: they inline env vars, transform JSX, ship polyfills, and expect `window`, `document`, `fetch`, and DOM APIs to exist. A server bundle runs in Node (or an edge runtime like Cloudflare Workers), which flips almost every assumption.

Server code needs:

- **Externalized Node built-ins** — `fs`, `path`, `crypto`, `stream`, `node:*` specifiers must resolve to the runtime's built-ins, not be bundled or polyfilled.
- **No browser-specific transforms** — no `define: { 'window': ... }` shims, no DOM API assumptions, no CSS-injection helpers that touch `document.head`.
- **Different module resolution** — Node uses `exports` conditions (`node`, `import`, `require`, `default`). SSR builds set `conditions: ['node', 'import', 'default']` instead of the browser's `['browser', 'import', 'default']`.
- **CommonJS-friendly output** — legacy Node targets (or plugins written against CJS) may need `require()`-compatible output; Vite handles this with `ssr.format`.

The dev server also behaves differently — it never ships an SSR module to the browser, and it applies a separate transform pipeline for server code (no `import.meta.hot` client stub, no CSS `link` injection, etc.).

---

## ssrLoadModule

The dev-mode entry point. Frameworks call it from their SSR middleware to load and execute their server entry on every request:

```ts
const { render } = await vite.ssrLoadModule('/src/entry-server.tsx');
const html = await render(url);
```

Vite:

1. Resolves the module using SSR-condition resolution (`node`, `import`, `default`).
2. Transforms with the SSR pipeline — skips browser polyfills, HMR client stubs, and CSS-injection wrappers.
3. Executes in Node's context, returns the evaluated module namespace.

Because the module graph is cached and invalidated on file change, every request gets fresh code without a rebuild — the same [[Build Tools Vite - Dev Server Architecture|on-demand transform model]] as the client, just with different conditions.

A minimal Express middleware:

```ts
app.use('*', async (req, res, next) => {
  try {
    const template = await vite.transformIndexHtml(req.originalUrl, rawHtml);
    const { render } = await vite.ssrLoadModule('/src/entry-server.tsx');
    const appHtml = await render(req.originalUrl);
    const html = template.replace('<!--ssr-outlet-->', appHtml);
    res.status(200).set({ 'Content-Type': 'text/html' }).end(html);
  } catch (e) {
    vite.ssrFixStacktrace(e as Error);
    next(e);
  }
});
```

`vite.ssrFixStacktrace()` rewrites stack traces to source locations — essential because the transformed code has different line numbers.

---

## SSR externals

Dependencies that should stay `require()`-able at runtime (not bundled). Vite auto-externalizes packages that have server-friendly exports — anything in `node_modules` with a valid `exports.node` or `exports.default` gets marked external by default.

```ts
export default {
  ssr: {
    noExternal: ['some-esm-lib', /^@my-org\//],
    external: ['redis'],
  },
};
```

- **`noExternal`** — bundle these into the SSR bundle. Use when a package ships only ESM and the target Node version can't `import()` it, or when it needs Vite's transforms (CSS, assets).
- **`external`** — leave as `require()` (bundler doesn't process). Use for native modules (`sharp`, `sqlite3`), or when the package must load its own copy at runtime.

The auto-externalization heuristic:

| Case | Result |
|------|--------|
| Package in `node_modules` with `main`/`exports.node` | External |
| Package in `node_modules`, ESM-only, no `node` condition | External (best effort) |
| Package listed in `noExternal` | Bundled |
| Package listed in `external` | External (forced) |
| Local source (relative or aliased) | Bundled |

CSS imports from `node_modules` are always bundled — CSS can't be `require()`d.

---

## SSR build

For production, generate a Node-runnable bundle:

```bash
vite build --ssr src/entry-server.tsx
```

Or in config:

```ts
export default {
  build: {
    ssr: 'src/entry-server.tsx',
  },
};
```

Emits a Node-runnable file to `dist/`. By default:

- Format: ESM (unless `ssr.format: 'cjs'`)
- Externals: everything in `node_modules` that matches the heuristic
- Minification: **off** by default (server code doesn't need to be small; readable stack traces matter more)
- Source maps: on

Output shape:

```
dist/
├── entry-server.js        # your SSR entry
└── chunks/
    └── [hash].js          # split chunks (if any)
```

You run this with `node dist/entry-server.js` in production.

---

## The classic two-build pattern

The canonical setup: two independent builds, one for the browser and one for Node.

```bash
vite build                            # client bundle to dist/client
vite build --ssr src/entry-server.tsx # server bundle to dist/server
```

Server render:

```ts
import { render } from './dist/server/entry-server.js';
import manifest from './dist/client/.vite/ssr-manifest.json';

const html = await render(url, manifest);
```

The manifest tells the server which client chunks to preload for the current route — critical for avoiding waterfalls when the browser starts hydrating.

Typical `package.json`:

```json
{
  "scripts": {
    "dev": "node server.js",
    "build:client": "vite build --outDir dist/client --ssrManifest",
    "build:server": "vite build --outDir dist/server --ssr src/entry-server.tsx",
    "build": "npm run build:client && npm run build:server",
    "start": "NODE_ENV=production node server.js"
  }
}
```

`--ssrManifest` on the client build emits `.vite/ssr-manifest.json` — a mapping from module ID to the chunks and CSS files that must be preloaded when that module renders.

---

## import.meta.env.SSR

At transform time, `import.meta.env.SSR` is replaced with the literal `true` in the server bundle and `false` in the client bundle. This enables conditional code that's fully tree-shaken:

```ts
if (import.meta.env.SSR) {
  const { readFileSync } = await import('node:fs');
  const data = readFileSync('./config.json', 'utf-8');
  return JSON.parse(data);
}
```

In the client bundle, this becomes:

```ts
if (false) {
  const { readFileSync } = await import('node:fs');
  // ...
}
```

Which Terser / esbuild's dead-code elimination strips entirely — the `node:fs` import never ends up in the client graph.

Common patterns:

```ts
export const storage = import.meta.env.SSR
  ? await import('./storage.node.ts')
  : await import('./storage.browser.ts');
```

```ts
export function getSecret() {
  if (!import.meta.env.SSR) {
    throw new Error('getSecret is server-only');
  }
  return process.env.API_SECRET;
}
```

Server-only code is tree-shaken from the client bundle, and imports referenced only inside the `SSR` branch are never resolved by the client transform.

---

## The Environment API (Vite 5+)

Generalizes SSR to any number of "environments" — client, server, edge, worker, mobile, etc. Each environment has:

- Its own **module graph** (independent dependency tree)
- Its own **resolver conditions** (`browser` vs `node` vs `edge`)
- Its own **plugin set** — plugins declare `apply: 'client' | 'ssr' | 'worker'` or a custom name
- Its own **build target** (browser bundle, Node ESM, Worker script)

```ts
export default {
  environments: {
    client: {
      build: {
        outDir: 'dist/client',
        manifest: true,
      },
    },
    ssr: {
      build: {
        outDir: 'dist/server',
        ssr: 'src/entry-server.tsx',
      },
      resolve: {
        conditions: ['node', 'import', 'default'],
      },
    },
    edge: {
      build: {
        outDir: 'dist/edge',
        ssr: 'src/entry-edge.tsx',
      },
      resolve: {
        conditions: ['edge', 'worker', 'import', 'default'],
      },
    },
  },
};
```

This unifies what used to be ad-hoc per-framework logic. Instead of "there's a client build and an SSR build, and if you want an edge target you write a custom Rollup config", every target is a first-class environment with the same API surface.

Plugins can opt into specific environments:

```ts
{
  name: 'my-plugin',
  applyToEnvironment(env) {
    return env.name === 'ssr' || env.name === 'edge';
  },
  transform(code, id) {
    // ...
  }
}
```

The dev server maintains a separate module graph per environment, and `ssrLoadModule` becomes `environment.runner.import()` — each environment has its own runner with its own resolution and transform pipeline. See [[Build Tools Vite - Architecture Overview]] for how this fits into the larger picture.

---

## How meta-frameworks use Vite SSR

Almost every modern React/Vue/Svelte meta-framework builds on top of Vite's SSR primitives:

| Framework | Role of Vite | Server runtime |
|-----------|-------------|----------------|
| **Nuxt 3** | Dev server + client build | Nitro engine (universal Node/edge) |
| **SvelteKit** | Dev + client + server build | Adapters (Node, Vercel, Cloudflare, static) |
| **Astro** | Dev + build; `.astro` compiler plugin | Node, edge, or static per-route |
| **Remix (in React Router 7)** | Vite plugin, replaces esbuild | Any Node-compatible runtime |
| **TanStack Start** | Vite plugin (Vinxi/Nitro under the hood) | Any Nitro target |
| **Qwik City** | Vite plugin | Any Node/edge adapter |
| **SolidStart** | Vite plugin | Any Nitro target |

They all share the same pattern:

1. Register a Vite plugin that adds file-based routing + entry generation.
2. In dev, mount Vite as middleware and use `ssrLoadModule` for the server entry.
3. In build, produce a client bundle + one or more server bundles (Node, edge, static).
4. Provide an adapter layer that wraps the server bundle for the target runtime.

Cross-link [[Build Tools Meta-frameworks Guide]].

---

## Manifest for SSR asset injection

When SSR renders HTML, it needs to inject `<script>` and `<link rel="stylesheet">` tags for the client chunks that the current route uses. Without this, the hydrating client has to discover assets via a waterfall of dynamic imports — visible as CLS and slow LCP.

The `build.manifest: true` output provides this mapping. Structure:

```json
{
  "src/entry-client.tsx": {
    "file": "assets/entry-client-a1b2c3.js",
    "isEntry": true,
    "imports": ["_shared-d4e5f6.js"],
    "css": ["assets/entry-client-g7h8i9.css"]
  },
  "src/routes/dashboard.tsx": {
    "file": "assets/dashboard-j0k1l2.js",
    "imports": ["_shared-d4e5f6.js"],
    "dynamicImports": ["src/routes/dashboard/widgets.tsx"]
  }
}
```

Reading it at render time:

```ts
import fs from 'node:fs';
const manifest = JSON.parse(
  fs.readFileSync('./dist/client/.vite/manifest.json', 'utf-8')
);

function collectAssets(manifest, entryId) {
  const scripts = new Set<string>();
  const styles = new Set<string>();

  function walk(id: string) {
    const entry = manifest[id];
    if (!entry) return;
    scripts.add(entry.file);
    entry.css?.forEach((c: string) => styles.add(c));
    entry.imports?.forEach(walk);
  }
  walk(entryId);
  return { scripts: [...scripts], styles: [...styles] };
}

const routeAssets = collectAssets(manifest, 'src/routes/dashboard.tsx');
```

Then inject:

```html
${routeAssets.styles.map(s => `<link rel="stylesheet" href="/${s}">`).join('')}
${routeAssets.scripts.map(s => `<link rel="modulepreload" href="/${s}">`).join('')}
```

The `ssr-manifest.json` variant (emitted with `--ssrManifest`) uses a slightly different shape optimized for SSR-render-time lookup by module ID.

---

## Edge runtime considerations

Edge runtimes (Cloudflare Workers, Vercel Edge, Deno Deploy, Fastly Compute) lack most Node built-ins. No `fs`, no `path`, no `net`. Instead you get Web APIs — `fetch`, `Request`, `Response`, `ReadableStream`, `crypto.subtle`.

Config for an edge SSR build:

```ts
export default {
  ssr: {
    target: 'webworker',
    noExternal: true,
  },
  resolve: {
    conditions: ['workerd', 'worker', 'edge-light', 'browser'],
  },
  build: {
    ssr: 'src/entry-edge.tsx',
    rollupOptions: {
      output: { format: 'esm' },
    },
  },
};
```

Key differences from Node SSR:

- **`target: 'webworker'`** — tells Vite to avoid Node-only externalization; bundle everything.
- **`noExternal: true`** — Workers can't `require()` from `node_modules` at runtime, so bundle it all in.
- **Conditions** — pick `workerd` (Cloudflare), `edge-light` (Vercel Edge), or `worker`; packages that ship edge-safe entries use these.
- **Bundle size matters** — Workers have a script-size limit (1 MB compressed on Cloudflare's free tier). Compare against Node SSR where size is largely irrelevant.

Vite emits a single-file bundle that avoids `fs`, `path`, etc. — if any dependency tries to import a Node built-in, the build fails loudly (or warns, depending on plugin config).

---

## SSR streaming

For React Suspense, use `renderToPipeableStream` (Node) or `renderToReadableStream` (edge). Vite doesn't do the streaming — the framework layer does — but the SSR bundle output must support these Node APIs.

Node streaming:

```ts
import { renderToPipeableStream } from 'react-dom/server';

app.get('*', (req, res) => {
  const { pipe, abort } = renderToPipeableStream(<App url={req.url} />, {
    bootstrapModules: ['/assets/entry-client.js'],
    onShellReady() {
      res.setHeader('Content-Type', 'text/html');
      pipe(res);
    },
    onError(err) {
      console.error(err);
    },
  });
  setTimeout(abort, 10_000);
});
```

Edge streaming:

```ts
import { renderToReadableStream } from 'react-dom/server';

export default {
  async fetch(req: Request) {
    const stream = await renderToReadableStream(<App url={req.url} />, {
      bootstrapModules: ['/assets/entry-client.js'],
    });
    return new Response(stream, {
      headers: { 'Content-Type': 'text/html' },
    });
  },
};
```

Vite's job: produce an SSR bundle where `react-dom/server` resolves to the version compatible with the target runtime (`react-dom/server.node` for Node, `react-dom/server.edge` for Workers). The `conditions` config handles this.

Cross-link [[React Lifecycle - Suspense Lifecycle]].

---

## Common pitfalls

```
❌ Importing a browser-only lib in an SSR module
✅ Wrap in `if (!import.meta.env.SSR)` or `noExternal` the client-safe fork
```

Symptoms: `ReferenceError: window is not defined` at server render, or `Document is not defined` when the module loads. Fix by gating the import behind the SSR flag, or by finding the package's `/node` or `/server` subpath entry.

```
❌ Forgetting to build both client and server bundles
✅ Two-build pattern; framework abstractions handle this
```

Symptoms: production start-up fails because `dist/server/entry-server.js` doesn't exist, or the HTML has no `<script>` tags because there's no manifest to read from.

```
❌ Loading assets from server without reading manifest
✅ Use manifest to inject correct <script> URLs
```

Symptoms: 404s for `/assets/entry-client.js` (hashed name in prod doesn't match the un-hashed dev URL), or hydration works but styles flash in late.

```
❌ Assuming `process.env` works in edge SSR
✅ Use `import.meta.env` (or the runtime's env binding, e.g. Cloudflare's `env.MY_VAR`)
```

Symptoms: `process is not defined` at edge runtime. Vite's `import.meta.env.*` works everywhere; `process.env` only works in Node.

```
❌ Externalizing a package that Vite needs to transform
✅ Add to `noExternal` so Vite can process its CSS / assets / TS
```

Symptoms: UI library ships with un-transformed CSS imports; server bundle crashes on `import './styles.css'`.

```
❌ Using `__dirname` / `__filename` in ESM SSR bundle
✅ Use `import.meta.url` + `fileURLToPath`
```

Symptoms: `ReferenceError: __dirname is not defined` because ESM doesn't have those globals.

---

## Summary table

| Concept | Client | SSR (Node) | Edge |
|---------|--------|------------|------|
| Conditions | `browser`, `import` | `node`, `import` | `workerd`, `worker`, `edge-light` |
| Node built-ins | Polyfilled/error | Available | Unavailable |
| Externals | N/A (all bundled) | Auto-external `node_modules` | Bundle everything (`noExternal: true`) |
| `import.meta.env.SSR` | `false` | `true` | `true` |
| Output format | ESM (chunked) | ESM (or CJS via `ssr.format`) | ESM (single file) |
| Manifest role | Emit for SSR | Consume for asset injection | Consume for asset injection |
| Streaming API | N/A | `renderToPipeableStream` | `renderToReadableStream` |
| Bundle size | Matters (LCP) | Doesn't matter | Matters (script-size limits) |
| Dev entry | `import` in HTML | `ssrLoadModule` | `ssrLoadModule` (worker mode) |

---

## Related

- [[Build Tools Meta-frameworks Guide]]
- [[Build Tools Meta-frameworks - RSC and the Bundler]]
- [[Build Tools Vite - Production Build]]
- [[Build Tools Vite Guide]]
