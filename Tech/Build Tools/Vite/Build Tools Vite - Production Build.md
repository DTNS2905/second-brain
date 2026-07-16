---
tags:
  - build-tools
  - vite
  - rollup
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/build
---

# Build Tools Vite — Production Build

> Vite build = Rollup + Vite's plugin adapter + post-processing (CSS extraction, asset hashing, HTML rewriting). This note covers what changes vs dev and how to configure the important knobs. Part of [[Build Tools Vite Guide]].

---

## The build engine

`vite build` does **not** use esbuild for bundling — it uses **Rollup**. esbuild is used for transforms (TS → JS, JSX, syntax lowering) and optionally for minification, but the module graph, tree-shaking, and chunk emission are Rollup's job.

The same plugin config runs in dev and build, with the caveat that plugins can gate hooks by `apply: 'build'` or `apply: 'serve'`. See [[Build Tools Vite - Plugin API]] for how the plugin adapter routes hooks.

Vite auto-includes several plugins in build that you'd otherwise wire manually in a raw Rollup config:

- `@rollup/plugin-commonjs` — converts CJS deps to ESM so Rollup can tree-shake them
- `@rollup/plugin-node-resolve` — resolves bare specifiers (`import 'react'`) against `node_modules`
- **CSS extraction plugin** — pulls CSS out of the JS graph into standalone `.css` chunks
- **Dynamic import polyfill** — for targets below native ES2020 dynamic import support
- **Asset plugin** — handles `import logo from './logo.svg'` (emit + rewrite)
- **HTML plugin** — rewrites `<script src>` / `<link href>` in `index.html` to hashed output paths

On top of that, Vite:

1. **Projects config** from `vite.config.ts` `build.*` fields onto Rollup's option shape
2. **Post-processes** the Rollup output — writes `dist/index.html`, `dist/.vite/manifest.json`, rewrites asset URLs in CSS

---

## Config projection

Vite exposes a curated subset of Rollup's options under `build.*`. The mental model: everything you'd typically want lives on `build`; anything exotic goes under `build.rollupOptions`, which is a passthrough.

```ts
import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    target: 'es2020',
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: true,
    minify: 'esbuild',
    cssCodeSplit: true,
    reportCompressedSize: false,
    chunkSizeWarningLimit: 500,
    rollupOptions: {
      input: 'index.html',
      output: {
        manualChunks: {
          react: ['react', 'react-dom'],
        },
      },
    },
  },
});
```

Key projections:

| Vite field | Rollup equivalent |
|---|---|
| `build.outDir` | `output.dir` |
| `build.assetsDir` | assets go into `${outDir}/${assetsDir}/` |
| `build.sourcemap` | `output.sourcemap` |
| `build.rollupOptions.input` | `input` |
| `build.rollupOptions.output` | `output` |
| `build.rollupOptions.external` | `external` |
| `build.target` | esbuild/SWC transform target + polyfill decisions |

`build.rollupOptions` is the escape hatch — everything there passes straight to Rollup. If you find yourself fighting Vite's defaults, that's the door.

---

## Chunking strategy

Rollup emits one chunk per **entry** and one chunk per **dynamic import boundary**. Vite layers extra heuristics on top.

### Default behavior

- One chunk per dynamic-import boundary (`import('./route.tsx')`)
- **Auto vendor split** (Vite 5+): npm dependencies are hoisted into vendor chunks keyed by top-level package
- Assets under `assetsInlineLimit` (4KB) become base64 data URLs and disappear from the chunk graph

Auto vendor-splitting means you generally get cache-friendly chunks without any config. `react` and `react-dom` end up in a chunk that changes only when React changes.

### Manual override

For fine-grained control, use `manualChunks`. It can be a static object or a function `(id: string) => string | void`.

```ts
export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks: (id) => {
          if (id.includes('node_modules/react')) return 'react-vendor';
          if (id.includes('node_modules/lodash')) return 'lodash';
          if (id.includes('node_modules/@sentry')) return 'sentry';
        },
      },
    },
  },
});
```

❌ Over-manual chunking — splitting every vendor into its own file — hurts HTTP/2 waterfalls and defeats gzip locality.
✅ Group by change cadence: rarely-changing libs together (React, Router), volatile app code separate.

See [[Build Tools Bundlers - Chunking and Code Splitting]] for the theory behind chunk sizing and cache boundaries.

---

## Asset pipeline

Files imported by JS/CSS flow through a fixed pipeline:

1. **Type-check by extension** — the asset plugin matches on known extensions (`.svg`, `.png`, `.woff2`, etc.) or on the `assetsInclude` glob
2. **Inline vs emit decision** — if the file is under `build.assetsInlineLimit` (default 4096 bytes), inline as a base64 data URL
3. **Emit with content-hash filename** — otherwise write to `dist/assets/<name>-<hash>.<ext>`, e.g. `dist/assets/logo-a1b2c3d4.svg`
4. **Rewrite the import** — the `import logo from './logo.svg'` expression is replaced with the emitted URL string

```ts
export default defineConfig({
  build: {
    assetsInlineLimit: 4096,
    assetsDir: 'assets',
    rollupOptions: {
      output: {
        assetFileNames: 'assets/[name]-[hash][extname]',
        chunkFileNames: 'assets/[name]-[hash].js',
        entryFileNames: 'assets/[name]-[hash].js',
      },
    },
  },
});
```

CSS `url(...)` references are rewritten the same way — the CSS goes through PostCSS, then a Vite pass rewrites URLs to point at emitted assets. Cross-link [[Build Tools Vite - CSS and Asset Handling]].

---

## CSS extraction

In dev, CSS is injected via `<style>` tags for instant HMR. In build, CSS is **extracted** into standalone `.css` files that ship with `<link rel="stylesheet">`.

- `build.cssCodeSplit: true` (default) — one CSS chunk per async JS chunk that imports CSS. Routes get their own CSS, loaded on demand.
- `build.cssCodeSplit: false` — all CSS is concatenated into a single `style.css` at the root. Simpler waterfall, worse first-paint for large apps.

```ts
export default defineConfig({
  build: {
    cssCodeSplit: true,
    cssMinify: 'esbuild', // or 'lightningcss' | false
  },
});
```

For library builds (`build.lib`), CSS extraction defaults change — see the library mode section.

Cross-link [[Build Tools Vite - CSS and Asset Handling]].

---

## Minification

`build.minify` controls JS minification:

- `'esbuild'` (default) — fast (~10x faster than Terser), slightly larger output, no config knobs beyond what esbuild exposes
- `'terser'` — smaller output (~5–10% typical), significantly slower, requires `terser` as a devDependency
- `false` — no minification

```ts
export default defineConfig({
  build: {
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
      },
      mangle: {
        safari10: true,
      },
    },
  },
});
```

Guidance:

- **App builds** — `'esbuild'` is fine. The size difference rarely justifies 5x slower builds.
- **Library builds** — often `false` is right. Let consumers minify with their own settings.
- **Size-sensitive prod** — `'terser'` + `drop_console: true` if every KB matters.

❌ `minify: false` on a regular app build without a reason — you're shipping unminified code to users.
✅ Default `'esbuild'` unless output size matters more than build speed.

---

## Source maps in build

`build.sourcemap` controls output:

| Value | External file | `sourceMappingURL` in JS | Notes |
|---|---|---|---|
| `false` | no | no | bad for debugging prod errors |
| `true` | yes | yes | standard prod choice |
| `'inline'` | no | base64 comment | huge bundle; dev only |
| `'hidden'` | yes | no | for Sentry/Datadog uploads |

```ts
export default defineConfig({
  build: {
    sourcemap: 'hidden',
  },
});
```

Use `'hidden'` when uploading maps to an error monitor — the maps exist on disk, get uploaded, but browsers can't fetch them directly (no leak of un-minified source to users).

Cross-link [[Build Tools Foundations - Source Maps]].

---

## Target and browser support

`build.target` sets the syntax level for the output. Accepts a single target or an array (the lowest wins per feature).

```ts
export default defineConfig({
  build: {
    target: ['es2020', 'chrome80', 'firefox78', 'safari14'],
  },
});
```

This drives:

- **esbuild/SWC transform target** — arrow functions, async/await, optional chaining, etc. are downleveled as needed
- **Dynamic import polyfill** — if the target lacks native `import()`, Vite injects a polyfill
- **`import.meta` handling** — down-transformed where required

Recommendations:

- **Modern-only** — `target: 'es2020'` or `'esnext'`. Smallest output, no polyfill overhead.
- **Broad support** — `target: 'es2015'` + `@vitejs/plugin-legacy` for actual old browsers
- **Default** — `'modules'` (Vite's default) targets browsers with native ESM (~95% of global usage)

---

## Legacy browser plugin

`@vitejs/plugin-legacy` produces a **second bundle** for old browsers, with core-js polyfills and syntax down-leveling to ES5. Modern browsers get the ESM bundle via `<script type="module">`; old browsers get the legacy bundle via `<script nomodule>`.

```ts
import legacy from '@vitejs/plugin-legacy';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    legacy({
      targets: ['defaults', 'not IE 11'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      renderLegacyChunks: true,
      modernPolyfills: true,
    }),
  ],
});
```

Cost: build time roughly doubles (two full Rollup passes) and dist size grows. Only turn it on if analytics show meaningful traffic from old browsers.

---

## Library mode

For publishing an npm package, `build.lib` reconfigures the output for library consumption — no HTML entry, externalized peer deps, multiple format outputs.

```ts
import { defineConfig } from 'vite';
import { resolve } from 'node:path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'MyLib',
      formats: ['es', 'cjs', 'umd'],
      fileName: (format) => `my-lib.${format}.js`,
    },
    rollupOptions: {
      external: ['react', 'react-dom'],
      output: {
        globals: {
          react: 'React',
          'react-dom': 'ReactDOM',
        },
      },
    },
    sourcemap: true,
    minify: false,
    cssCodeSplit: false,
  },
});
```

What library mode changes:

- **No `index.html` entry** — the entry is `build.lib.entry`
- **CSS extraction** defaults to single-file (`style.css` next to JS)
- **`formats`** — `'es'`, `'cjs'`, `'umd'`, `'iife'`. UMD/IIFE need `name` set.
- **Externals** — peer deps go in `rollupOptions.external` so they aren't bundled
- **Globals** — for UMD/IIFE, map externals to their global names

Pair with `package.json` conditional exports:

```json
{
  "main": "./dist/my-lib.cjs.js",
  "module": "./dist/my-lib.es.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/my-lib.es.js",
      "require": "./dist/my-lib.cjs.js",
      "types": "./dist/index.d.ts"
    }
  },
  "peerDependencies": {
    "react": "^18.0.0",
    "react-dom": "^18.0.0"
  }
}
```

❌ Bundling `react` into a library — every consumer ships their own copy alongside yours; hooks break due to multiple React instances.
✅ `external: ['react', 'react-dom']` + peer dep declaration.

---

## Build manifest

`build.manifest: true` emits `dist/.vite/manifest.json` — a mapping from source paths to output chunk paths, with import graph metadata.

```ts
export default defineConfig({
  build: {
    manifest: true,
    rollupOptions: {
      input: {
        main: 'src/main.ts',
        admin: 'src/admin.ts',
      },
    },
  },
});
```

Sample output:

```json
{
  "src/main.ts": {
    "file": "assets/main-a1b2c3.js",
    "src": "src/main.ts",
    "isEntry": true,
    "imports": ["_react-vendor-d4e5f6.js"],
    "css": ["assets/main-9z8y7x.css"]
  },
  "_react-vendor-d4e5f6.js": {
    "file": "assets/react-vendor-d4e5f6.js"
  }
}
```

Server frameworks (Rails, Laravel, Django, Rack, custom Node SSR) read this file to inject the correct hashed `<script>` and `<link>` tags into rendered HTML — Vite is the bundler, the framework owns the HTML.

`build.ssrManifest: true` emits a separate SSR manifest keyed by module ID → assets, used for preloading during SSR.

---

## SSR build

`vite build --ssr src/entry-server.ts` produces a Node-runnable build with different defaults:

- `ssr` set in Rollup — dependencies are externalized by default (Node resolves them at runtime)
- No CSS extraction (CSS goes to a separate client build)
- Target defaults to `node18` (or your configured Node target)

```ts
export default defineConfig({
  build: {
    ssr: 'src/entry-server.ts',
    outDir: 'dist/server',
    rollupOptions: {
      output: {
        format: 'esm',
      },
    },
  },
});
```

Modern setups use the **Environment API** (Vite 6+) to declare `client` and `ssr` environments explicitly and build both in one command. Cross-link [[Build Tools Vite - SSR and Environments]].

---

## Preview server

`vite preview` boots a local static server that serves the `dist/` output. It's a **smoke-test tool**, not a production server:

- No compression tuning
- No caching headers
- No SPA fallback config beyond a basic rewrite
- Single-process, single-threaded Node

```bash
pnpm vite build
pnpm vite preview --port 4173 --host
```

Use it to verify the build works end-to-end before deploying. For real production, put the `dist/` behind nginx, a CDN, or a Node server with proper caching.

❌ Running `vite preview` in production behind a reverse proxy.
✅ Static hosting (Netlify, Vercel, S3+CloudFront) or nginx `try_files` for SPA fallback.

---

## Common pitfalls

```
❌ Setting build.minify: false without knowing why
✅ Default 'esbuild' is fine unless output size matters more than build speed

❌ Forgetting to add production dependencies to package.json
✅ Vite bundles them; if in devDependencies, prod install may not include them at build time in CI

❌ Manual-chunking every vendor into its own file
✅ Group by change cadence — HTTP/2 helps but tiny chunks still waste bytes on framing + poor gzip locality

❌ sourcemap: 'inline' in production
✅ 'hidden' + upload to Sentry, or plain true with an assets CDN

❌ Bundling peer deps in library mode
✅ rollupOptions.external + peerDependencies

❌ Using `vite preview` as the production server
✅ nginx / CDN / dedicated Node server

❌ Assuming build uses esbuild for bundling
✅ It uses Rollup; esbuild is just for transforms and (optional) minification
```

CI-specific gotchas:

- **`NODE_ENV=production`** during install skips devDependencies. If your build depends on `terser` or `@vitejs/plugin-legacy` being present, they must be in `dependencies` — or install with `NODE_ENV` unset and set it only for the build step.
- **Frozen lockfile** — always `pnpm install --frozen-lockfile` (or `npm ci`) in CI so the build is reproducible.
- **Missing `type: "module"`** — some plugins expect the project to be ESM; Vite itself works either way but plugin ecosystems increasingly assume ESM.

---

## Related

- [[Build Tools Bundlers - Rollup Internals]]
- [[Build Tools Bundlers - Chunking and Code Splitting]]
- [[Build Tools Foundations - Source Maps]]
- [[Build Tools Vite - CSS and Asset Handling]]
- [[Build Tools Vite - SSR and Environments]]
- [[Build Tools Vite Guide]]
