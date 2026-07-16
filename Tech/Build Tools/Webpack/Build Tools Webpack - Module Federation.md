---
tags:
  - build-tools
  - webpack
  - module-federation
  - micro-frontends
  - tooling
  - frontend
created: 2026-07-16
source: https://module-federation.io/
---

# Build Tools Webpack — Module Federation

> Runtime cross-app module sharing — load a component built by another team's Webpack build, from another URL, into your running app. The bones of micro-frontends. Part of [[Build Tools Webpack Guide]].

---

## The idea

At runtime, one app (**host**) loads modules from another app (**remote**) as if they were local. Both apps build independently, deploy independently, and share React (or any singleton dependency) so there's only **one copy in memory** at runtime.

Contrast with traditional approaches:

| Approach | When shared | Cost |
|----------|-------------|------|
| npm package | Build time | Every consumer rebuilds/redeploys on update |
| iframe | Runtime | Full isolation, no shared state, awkward UX |
| **Module Federation** | Runtime | Shared singletons, native UX, independent deploys |

The killer feature: `app1` can render a `<Button>` compiled by `app2`, hosted at `app2.example.com`, using the **same React instance** that `app1` uses for its own components. Hooks work. Context works. It looks and behaves like a local import.

---

## Host vs remote

- **Host** — consumes remote modules. Configured with `remotes: { app2: 'app2@http://.../remoteEntry.js' }`.
- **Remote** — exposes modules. Configured with `exposes: { './Button': './src/Button' }` and `filename: 'remoteEntry.js'`.
- An app can be **both** — bidirectional federation, where app1 exposes some modules and consumes others from app2.

Naming convention:

```
<container-name>@<url-to-remoteEntry.js>
```

The container name (`app2`) becomes the import prefix in host code (`import(...'app2/Button')`).

---

## Minimal remote config

```js
// app2/webpack.config.js
const { ModuleFederationPlugin } = require('webpack').container;

module.exports = {
  plugins: [
    new ModuleFederationPlugin({
      name: 'app2',
      filename: 'remoteEntry.js',
      exposes: {
        './Button': './src/Button',
        './Header': './src/Header',
      },
      shared: {
        react: { singleton: true, requiredVersion: '^18.0.0' },
        'react-dom': { singleton: true, requiredVersion: '^18.0.0' },
      },
    }),
  ],
};
```

Key fields:

- `name` — the container's global identifier
- `filename` — the manifest file emitted (conventionally `remoteEntry.js`)
- `exposes` — map of public export paths → source files
- `shared` — deps that should be deduplicated with the host

---

## Minimal host config

```js
// app1/webpack.config.js
plugins: [
  new ModuleFederationPlugin({
    name: 'app1',
    remotes: {
      app2: 'app2@http://localhost:3002/remoteEntry.js',
    },
    shared: {
      react: { singleton: true, requiredVersion: '^18.0.0' },
      'react-dom': { singleton: true, requiredVersion: '^18.0.0' },
    },
  }),
]
```

Then in host code:

```tsx
const Button = React.lazy(() => import('app2/Button'));

<Suspense fallback={<Spinner />}>
  <Button />
</Suspense>
```

Notes:

- `import('app2/Button')` is treated by Webpack as a **remote import** — it resolves to the container's `get('./Button')` at runtime.
- Wrap in `React.lazy` + `Suspense` because the network fetch is asynchronous.
- The `shared` block must appear on **both sides** with compatible versions.

---

## remoteEntry.js

A small manifest file that a remote emits. Includes:

- **Container name** — global variable exposing `init()` and `get()`
- **Map of exposed modules** to chunk URLs (e.g. `./Button → src_Button_tsx.js`)
- **Shared module descriptors** — version, singleton flag, eagerness

When the host loads a remote module:

1. `<script src="http://.../remoteEntry.js">` — fetched once, cached
2. `window.app2.init(sharedScope)` — remote registers its shared deps
3. `window.app2.get('./Button')` — returns a factory
4. Factory resolves the underlying chunk (e.g. `src_Button_tsx.js`)
5. Chunk is executed → module returned

Only step 1 is guaranteed at bootstrap. The rest is lazy — you only pay for what you use.

---

## Shared modules — singletons

```js
shared: {
  react: {
    singleton: true,                  // one copy across all federated apps
    requiredVersion: '^18.0.0',
    strictVersion: false,
    eager: false,                     // load lazily
  },
}
```

Without `singleton: true`, two React copies can coexist → **hooks break silently** (`Invalid hook call`, or worse: two competing render trees). React uses module identity to store internal state; two React modules = two separate stores.

**Rule of thumb:** anything that uses module-level singletons (React, react-dom, react-router, redux store, i18n instance) must be marked `singleton: true`.

`shared` field options:

| Field | Purpose |
|-------|---------|
| `singleton` | Enforce a single instance across all federated apps |
| `requiredVersion` | Semver range this app expects |
| `strictVersion` | Error on version mismatch instead of warning |
| `eager` | Load in initial chunk instead of async |
| `import` | Fallback module path if no other app provides it (default: the dep name) |
| `shareKey` | Custom share-scope key (advanced) |

---

## Version negotiation

When host and remote declare different `requiredVersion` ranges:

- **Highest compatible wins** — Webpack picks the highest version that satisfies *both* semver ranges
- **If incompatible + `strictVersion: true`** → runtime error
- **If incompatible + `strictVersion: false`** → console warning + fallback to highest available

Example:

```
host declares:   react ^18.0.0, provides 18.2.0
remote declares: react ^18.1.0, provides 18.3.0
→ Both use 18.3.0 (highest compatible with both ranges)
```

Incompatible:

```
host declares:   react ^17.0.0
remote declares: react ^18.0.0
→ strictVersion: true  → throw
→ strictVersion: false → warn, load remote's 18.x (hooks may break in host)
```

**Don't rely on `strictVersion: false`** to save you — plan for compatible ranges across teams.

---

## Eager loading

```js
shared: { react: { singleton: true, eager: true } }
```

- `eager: true` — includes React in the **initial chunk** (no `import()` deferral)
- `eager: false` — React loads asynchronously, alongside remote fetches

Trade-offs:

| Mode | Initial bundle | First remote load | Complexity |
|------|----------------|-------------------|------------|
| `eager: true` | Larger (includes React) | Fast (React already resident) | Simpler |
| `eager: false` | Smaller | Slower first paint of remote | Requires async bootstrap |

If eager mode fails with `Shared module is not available for eager consumption`, you need an **async bootstrap**:

```ts
// src/index.ts
import('./bootstrap');
```

```ts
// src/bootstrap.ts
import ReactDOM from 'react-dom/client';
import App from './App';
ReactDOM.createRoot(document.getElementById('root')!).render(<App />);
```

The extra `import()` gives Webpack a chance to initialize the share scope before app code runs.

---

## Dynamic remotes

At runtime, decide which remote URL to load — useful for env-specific URLs, plugin systems, or A/B testing:

```ts
// Utility to load a remote container manually
async function loadRemote(url: string, scope: string, module: string) {
  await __webpack_init_sharing__('default');
  await __webpack_require__.l(url, (resolve: any) => resolve, scope);
  const container = (window as any)[scope];
  await container.init(__webpack_share_scopes__.default);
  const factory = await container.get(module);
  return factory();
}
```

Usage:

```ts
const { Button } = await loadRemote(
  'https://cdn.example.com/plugins/checkout/remoteEntry.js',
  'checkoutPlugin',
  './Button',
);
```

MF 2.0 wraps this into a simpler `loadRemote()` helper — see below.

---

## MF 2.0 improvements

The `@module-federation/enhanced` package (MF 2.0) sits on top of the Webpack plugin with:

- **Manifest schema** for automatic remote discovery (`mf-manifest.json`)
- **Dev tools** — Chrome extension shows loaded remotes, shared scopes, version negotiation
- **TypeScript support** — auto-generate `.d.ts` from remote's `exposes`
- **Faster runtime** — smaller share-scope resolution overhead
- **Rspack + Vite** compatibility with the same API
- **Same conceptual model** — host, remote, shared, singleton

Adoption is drop-in for most projects:

```js
const { ModuleFederationPlugin } = require('@module-federation/enhanced/webpack');
```

---

## Micro-frontend caveats

- **Shared runtime cost** — React must be a singleton; version drift across teams silently breaks hooks
- **CSS collisions** — federated apps must namespace styles (CSS Modules, utility-first CSS, or Shadow DOM). Global styles from remote can leak into host
- **Debugging** — sourcemaps across origins can be finicky (CORS + `strict-origin` headers block them)
- **Auth / cookies** — each remote is a separate origin unless proxied; `SameSite` cookies won't flow
- **Deploy coupling** — semver contracts between teams; breaking a remote's exposed API breaks every host
- **Bundle bloat** — if teams don't share deps, three copies of `date-fns` may ship (one per remote)
- **Waterfalls** — host → remoteEntry → shared scope init → module chunk = multiple round trips
- **SSR difficulty** — server-side federation exists but is significantly harder than client-side
- **Testing** — E2E tests must spin up multiple dev servers; unit tests need mocks for remote imports

Mitigations:

| Problem | Fix |
|---------|-----|
| CSS leaks | CSS Modules, Tailwind, or Shadow DOM per remote |
| Version drift | CI check on shared deps across teams |
| Sourcemap CORS | Add `Access-Control-Allow-Origin` to CDN + `SourceMap` header |
| Waterfall latency | Preload `remoteEntry.js` with `<link rel="preload">` |
| Deploy coupling | Contract tests + semver on exposed APIs |

---

## When to use MF

✅ Multiple teams shipping into one shell app with independent deploys
✅ Progressive migration between apps (host loads pages from old + new codebases)
✅ Runtime plugin/extension architectures (host loads third-party plugins)
✅ Large orgs where build times or repo size make monorepos painful
✅ White-label products where clients bring their own components

❌ Small teams — the operational complexity outweighs benefits
❌ Single-team apps — code splitting via `import()` is enough
❌ Static sites — pre-rendering + islands architecture is simpler
❌ Apps where deploy cadence is aligned — you don't need runtime decoupling

---

## Alternatives

- **iframes** — simplest isolation, no shared state, ugly UX. Good for truly hostile third-party content
- **Web Components** — DOM-level encapsulation without federation. Works cross-framework but doesn't share React
- **Bit / single-spa** — different orchestration models. `single-spa` composes at the router level; Bit ships versioned components
- **RSC** — different problem (server-driven composition), some overlap for progressive rendering. See [[Web Rendering Patterns Guide]]
- **Rspack federation** — same MF API, Rust-fast; drop-in for existing MF configs. Cross-link `[[Build Tools Bundlers - Turbopack and Rspack]]`
- **Import maps + ESM** — native browser mechanism for runtime module resolution. Simpler than MF but no shared-scope negotiation

Decision matrix:

| Need | Best fit |
|------|----------|
| Runtime module loading + shared React | Module Federation |
| Framework-agnostic composition | Web Components or single-spa |
| Full isolation (untrusted code) | iframes |
| Server-driven composition | RSC or edge middleware |
| Simple lazy loading (same team) | Native `import()` code splitting |

---

## Related

- [[Build Tools Webpack - Code Splitting and SplitChunks]]
- [[Build Tools Webpack - Compiler and Compilation]]
- [[Build Tools Bundlers - Turbopack and Rspack]]
- [[Build Tools Meta-frameworks - Comparison and Decision Guide]]
- [[Build Tools Webpack Guide]]
