---
tags:
  - build-tools
  - vite
  - config
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/config/
---

# Build Tools Vite — Config Reference

> A terse reference to vite.config.ts — grouped by concern, with commonly-wrong defaults flagged and ✅/❌ anti-patterns called out. Part of [[Build Tools Vite Guide]].

---

## The config file

The entry point for every Vite project is `vite.config.ts` (or `.js`) at the project root. `defineConfig` gives you type inference without an explicit annotation.

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';

export default defineConfig({
  plugins: [react()],
  // ... other options
});
```

Or an async factory when you need to branch on the current command or mode, or read from the filesystem before building the config:

```ts
export default defineConfig(async ({ command, mode }) => ({
  plugins: [...],
}));
```

`command` is `'serve'` (dev) or `'build'`. `mode` is `'development'`/`'production'` by default; override with `--mode staging`.

Vite loads the config with esbuild before evaluating it, so `.ts` works out of the box — no separate build step for the config itself.

---

## Root-level options

The most important top-level fields. Everything else is nested under a namespace (`server`, `build`, `resolve`, etc.).

| Field | Purpose |
|-------|---------|
| `plugins` | Plugin array |
| `root` | Project root (default: cwd) |
| `base` | Public base path (default: '/') |
| `mode` | Build mode |
| `define` | Global constant replacements |
| `publicDir` | Static file root (default: 'public') |
| `cacheDir` | .vite cache (default: 'node_modules/.vite') |
| `envDir` | Where to find .env files |
| `envPrefix` | Prefix for exposed env vars (default: 'VITE_') |
| `clearScreen` | Clear terminal on rebuild (default: true) |

`base` matters when your app is deployed under a sub-path (`/app/`) — it prefixes every asset URL. `define` does a raw text replacement at build time (like Webpack's `DefinePlugin`), so wrap strings in `JSON.stringify`:

```ts
{
  define: {
    __APP_VERSION__: JSON.stringify('1.2.3'),
  },
}
```

---

## `server.*`

Governs the dev server: HMR, proxy, filesystem access, CORS. See [[Build Tools Vite - Dev Server Architecture]] for how these knobs interact with the middleware chain.

```ts
{
  server: {
    host: true,             // listen on 0.0.0.0
    port: 5173,
    strictPort: false,
    open: false,            // auto-open browser
    https: false,           // or { cert, key }
    proxy: { '/api': 'http://localhost:8080' },
    cors: true,
    fs: {
      strict: true,         // restrict serve to project root
      allow: ['..'],        // extra dirs
      deny: ['.env'],       // never serve
    },
    warmup: { clientFiles: ['./src/main.tsx'] },
    hmr: { overlay: true, port: 5174, host: 'localhost' },
  },
}
```

### `server.proxy`

Backed by [`http-proxy`](https://github.com/http-party/node-http-proxy). Object shorthand rewrites the host; use the long form for path rewrites and websocket upgrades:

```ts
{
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
        ws: true,
      },
    },
  },
}
```

### `server.fs`

Vite refuses to serve files outside the project root by default (`strict: true`). In a monorepo you often need to reach up to sibling packages — extend `allow`, don't disable `strict`.

### `server.warmup`

Vite eagerly transforms the listed entries at startup so the first HMR ping doesn't stall. Cheap win for large apps.

---

## `build.*`

Governs the production build (Rollup). See [[Build Tools Vite - Production Build]] for chunking strategy and asset flow.

```ts
{
  build: {
    target: 'es2020',
    outDir: 'dist',
    assetsDir: 'assets',
    assetsInlineLimit: 4096,
    cssCodeSplit: true,
    cssMinify: true,
    sourcemap: false, // or true | 'inline' | 'hidden'
    minify: 'esbuild', // or 'terser' | false
    terserOptions: {},
    chunkSizeWarningLimit: 500, // kB
    manifest: false,
    ssrManifest: false,
    modulePreload: { polyfill: true },
    reportCompressedSize: true,
    emptyOutDir: true,
    copyPublicDir: true,
    rollupOptions: {
      input: 'index.html',
      output: { manualChunks: {} },
      external: [],
    },
    lib: { entry: '', formats: ['es', 'cjs'] },
    ssr: 'src/entry-server.tsx',
  },
}
```

### `build.target`

Lowest ECMAScript version the output must support. `'es2020'` is the modern baseline; `'esnext'` disables transpilation entirely (Rollup will still bundle). Multi-target arrays like `['es2020', 'safari13']` are supported.

### `build.sourcemap`

Four values with different tradeoffs:

| Value | Emits `.map` | Referenced in output | Use when |
|-------|--------------|----------------------|----------|
| `false` | no | — | never in prod |
| `true` | yes | yes (`//# sourceMappingURL`) | internal apps |
| `'inline'` | no (embedded) | yes | tiny outputs |
| `'hidden'` | yes | no | prod + Sentry |

### `build.rollupOptions`

The escape hatch. Anything Rollup can do, you can express here — `input` for multiple entry points, `output.manualChunks` for chunking policy, `external` for library builds.

```ts
{
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          react: ['react', 'react-dom'],
          vendor: ['lodash-es', 'date-fns'],
        },
      },
    },
  },
}
```

### `build.lib`

Turns Vite into a library bundler. When present, `rollupOptions.external` should list peer deps so they aren't inlined:

```ts
{
  build: {
    lib: {
      entry: 'src/index.ts',
      name: 'MyLib',
      formats: ['es', 'cjs'],
      fileName: (format) => `mylib.${format}.js`,
    },
    rollupOptions: {
      external: ['react', 'react-dom'],
      output: { globals: { react: 'React' } },
    },
  },
}
```

---

## `resolve.*`

Controls module resolution — aliases, deduplication, conditional exports.

```ts
{
  resolve: {
    alias: {
      '@': '/src',
      '@ui': '/src/components/ui',
    },
    dedupe: ['react', 'react-dom'],
    conditions: ['browser'],
    mainFields: ['browser', 'module', 'main'],
    extensions: ['.ts', '.tsx', '.js', '.jsx', '.json'],
    preserveSymlinks: false,
  },
}
```

### `resolve.alias`

Prefer absolute paths (`/src`) over `path.resolve(__dirname, 'src')` — Vite normalizes them. Keep it in sync with `tsconfig.json`'s `paths` or use `vite-tsconfig-paths`.

### `resolve.dedupe`

Forces a single copy of the listed packages even if multiple versions exist in `node_modules`. Non-negotiable for React (two copies = broken hooks) and for any library relying on module identity (context providers, singletons).

### `resolve.conditions`

Package exports resolution — controls which `exports` field key wins. `['browser']` picks the browser build; SSR uses `['node']`. See [[Build Tools Vite - SSR and Environments]].

---

## `optimizeDeps.*`

Pre-bundling knobs. Cross-link [[Build Tools Vite - Dependency Pre-Bundling]] for the full model.

```ts
{
  optimizeDeps: {
    entries: [],
    include: ['react', 'react-dom/client'],
    exclude: [],
    esbuildOptions: {},
    force: false,
  },
}
```

- `include` — force pre-bundling of deps Vite might miss (dynamic imports, deps of deps).
- `exclude` — opt out; typically for ESM-native packages that don't need it, or workspace packages you're actively editing.
- `force: true` — invalidates the `node_modules/.vite` cache. Equivalent to `--force` on the CLI.
- `entries` — extra scan roots when your entry isn't a plain `index.html` (Storybook, custom HTML shells).

---

## `ssr.*`

SSR options. Cross-link [[Build Tools Vite - SSR and Environments]] for how these compose with `build.ssr`.

```ts
{
  ssr: {
    noExternal: [],
    external: [],
    target: 'node', // or 'webworker'
    optimizeDeps: { include: [] },
    resolve: { conditions: ['node'] },
  },
}
```

- `external` — deps that stay as bare imports in the SSR bundle (the runtime resolves them).
- `noExternal` — force bundling even if Vite would otherwise externalize. Use for CSS-in-JS libraries or ESM-only deps that break under Node's CJS externalization.
- `target: 'webworker'` — for edge runtimes (Cloudflare Workers, Vercel Edge). Disables Node built-ins.

---

## `css.*`

CSS modules, PostCSS, and preprocessor options. See [[Build Tools Vite - CSS and Asset Handling]] for how these interact with the graph.

```ts
{
  css: {
    modules: {
      localsConvention: 'camelCase', // or 'dashes', 'camelCaseOnly'
      generateScopedName: '[name]__[local]___[hash:base64:5]',
    },
    postcss: {},
    preprocessorOptions: {
      scss: { additionalData: `@import "src/styles/vars.scss";` },
    },
    devSourcemap: false,
  },
}
```

- `modules.localsConvention: 'camelCase'` lets you write `styles.myClass` in JS while keeping `.my-class` in the source.
- `preprocessorOptions.scss.additionalData` prepends to every SCSS file — handy for shared variables without an explicit `@import` in each file.
- `devSourcemap: true` is worth turning on when debugging CSS-in-JS or PostCSS transforms.

---

## Environment variables

Files loaded in order (later overrides earlier):

1. `.env` — always loaded
2. `.env.local` — always loaded, gitignored
3. `.env.[mode]` — loaded for the current mode
4. `.env.[mode].local` — loaded for the current mode, gitignored

Only `VITE_*` (or your `envPrefix`) are exposed to client code. Everything else stays server-side and is available via `loadEnv()` in the config.

Access from client code:

```ts
const url = import.meta.env.VITE_API_URL;
```

Built-in fields on `import.meta.env`:

| Field | Value |
|-------|-------|
| `MODE` | current mode string |
| `BASE_URL` | resolved `base` |
| `PROD` | `true` in production |
| `DEV` | `true` in dev |
| `SSR` | `true` when SSR |

Loading env in the config itself:

```ts
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    define: {
      __SENTRY_DSN__: JSON.stringify(env.SENTRY_DSN),
    },
  };
});
```

---

## Merging configs

For monorepos or multi-target setups (web + SSR + electron off the same base):

```ts
import { defineConfig, mergeConfig } from 'vite';
import base from './vite.config.base';
export default mergeConfig(base, defineConfig({
  server: { port: 4000 },
}));
```

`mergeConfig` deep-merges — plugin arrays concatenate, objects merge, primitives override. Prefer this over spread (`...base`) which flattens nested objects.

---

## Commonly wrong defaults

```
❌ Leaving build.sourcemap: false in prod
✅ Use 'hidden' — enables Sentry symbolication without exposing sources

❌ Not setting resolve.dedupe for React
✅ dedupe: ['react', 'react-dom'] — critical in monorepos

❌ Ignoring build.chunkSizeWarningLimit warnings
✅ Investigate — either raise the limit intentionally or split the chunk

❌ Setting envPrefix: '' to expose everything
✅ Never — leaks server secrets into client bundle
```

Additional footguns worth knowing:

- `build.emptyOutDir: true` is safe when `outDir` is inside the project root; Vite refuses to empty a dir outside it unless you override the confirmation.
- `build.reportCompressedSize: false` shaves seconds off large builds in CI where you don't need the gzip size printout.
- `server.host: true` is a `0.0.0.0` bind — never in production dev environments exposed to the internet.

---

## ✅ / ❌ config anti-patterns

```
❌ Modifying build.rollupOptions.output.format to 'cjs' for an app
✅ Apps target browsers; ESM is the format. Only libraries use CJS.

❌ Using publicDir for hashed assets
✅ Public dir is for un-hashed, root-relative files (favicons, robots.txt)

❌ resolve.alias to reach outside the project root without server.fs.allow
✅ Vite blocks fs access outside root by default; add to allow list
```

More patterns to avoid:

```
❌ Adding process.env.NODE_ENV to define
✅ Vite already replaces it — double-defining causes esbuild warnings

❌ Setting optimizeDeps.include for every workspace package
✅ Use exclude instead; workspace packages should stay in the source graph

❌ Configuring both css.postcss and a postcss.config.js
✅ Pick one — inline config wins and silently ignores the file
```

---

## Related

- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Vite - Production Build]]
- [[Build Tools Vite - Dependency Pre-Bundling]]
- [[Build Tools Vite - SSR and Environments]]
- [[Build Tools Vite Guide]]
