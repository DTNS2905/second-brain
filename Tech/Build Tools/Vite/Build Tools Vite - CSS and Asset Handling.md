---
tags:
  - build-tools
  - vite
  - css
  - assets
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/features
---

# Build Tools Vite — CSS and Asset Handling

> Vite treats CSS and static assets as first-class modules. Import them from JS, use query suffixes to control treatment, and know when to reach for the public dir instead. Part of [[Build Tools Vite Guide]].

---

## CSS as a first-class module

Any `.css` file can be imported directly from a JS/TS module. Vite parses the CSS, tracks it as a node in the module graph, and hands it to the right pipeline for the current mode.

```ts
import './styles.css';
```

- **Dev** — the stylesheet is injected via a `<style>` tag over the HMR channel. Edits patch the DOM without a page reload.
- **Build** — the CSS is extracted, hashed, and emitted to `dist/assets/`. The importing chunk gets a `<link rel="stylesheet">` in the generated HTML.

The import has no runtime value — it's a side-effect import. The stylesheet is applied globally the moment its owning chunk executes.

---

## CSS Modules

Any file matching `*.module.css` is treated as a CSS Module. Class names are locally scoped (hashed), so collisions across files are impossible.

```css
/* Button.module.css */
.primary { color: rebeccapurple; }
```

```tsx
import styles from './Button.module.css';

export function Button() {
  return <button className={styles.primary} />;
}
```

At build time the raw class `primary` becomes something like `_primary_1a2b3c_1`. The default export of a `.module.css` import is a `{ [localName]: hashedName }` map.

The `.module.` suffix works for every supported preprocessor too — `Button.module.scss`, `Button.module.less`, etc.

---

## Preprocessor support

Auto-detected when the preprocessor is a devDep — no plugin, no config, just install.

- `sass` → `.scss`, `.sass`
- `less` → `.less`
- `stylus` → `.styl`, `.stylus`

```
npm install -D sass
```

```ts
import './main.scss';
```

Vite invokes the preprocessor on demand, feeds the output through PostCSS if configured, then either injects (dev) or extracts (build). Preprocessor-specific options go under `css.preprocessorOptions` in `vite.config.ts`.

```ts
export default defineConfig({
  css: {
    preprocessorOptions: {
      scss: { additionalData: `@use "src/styles/vars" as *;` },
    },
  },
});
```

---

## PostCSS

Vite auto-picks up `postcss.config.js` (or the `postcss` field in `package.json`). No wiring — every stylesheet is passed through the configured plugin chain.

```js
// postcss.config.js
module.exports = {
  plugins: [require('autoprefixer'), require('tailwindcss')],
};
```

This is how Tailwind, autoprefixer, `postcss-nested`, and friends plug in. The config is loaded once per Vite process and applied uniformly to preprocessed CSS as well.

---

## CSS in JS libs

CSS-in-JS is **not** a first-class Vite feature — there's no built-in runtime or babel step for template-literal styles. Each ecosystem ships its own Vite plugin:

| Library | Plugin |
|---------|--------|
| Emotion | `@vitejs/plugin-react` with `jsxImportSource: '@emotion/react'` |
| Styled Components | `vite-plugin-styled-components` (for SSR displayNames) |
| vanilla-extract | `@vanilla-extract/vite-plugin` |
| Linaria / Panda / Stitches | Each has its own plugin |

The JSX pragma / Babel transform side of this belongs to the compiler layer — see [[Build Tools Compilers - JSX and React Transforms]].

---

## The four query suffixes

Vite reserves a small set of query strings that mutate how an import is resolved. They're the escape hatch when the default treatment isn't what you want.

```ts
import url from './logo.svg?url';       // → the URL string
import raw from './notes.md?raw';        // → the file contents
import inline from './icon.svg?inline';  // → base64 data URL
import worker from './worker.ts?worker'; // → a Worker constructor
```

- **`?url`** — force asset-URL treatment even for files Vite would otherwise transform (e.g. import a `.ts` file as a URL to a hosted script).
- **`?raw`** — get the file's text content as a string. Handy for shader source, markdown blobs, license text.
- **`?inline`** — always base64 the file, regardless of `assetsInlineLimit`.
- **`?worker`** — bundle the file as a Web Worker; the default export is a constructor.

Combinable variants:

- `?worker&inline` — worker is inlined as a blob URL (no separate file)
- `?worker&url` — get just the URL to the built worker chunk
- `?sharedworker` — same shape, but a `SharedWorker` constructor

---

## Static asset imports

The default treatment for a non-JS, non-CSS file import.

```ts
import logo from './logo.png';
// logo === '/assets/logo-a1b2c3d4.png' at runtime
```

Vite:

- **Inlines** the asset as a base64 data URL when its size is under `build.assetsInlineLimit` (default `4096` bytes / 4 KiB).
- **Otherwise emits** it with the pattern `[name]-[hash].[ext]` into `dist/assets/`.
- **Rewrites** the JS import to reference the emitted path.

The same logic applies to `url()` references inside CSS — Vite rewrites those transparently, so CSS authored in `src/` doesn't need to know the final hash.

```ts
// vite.config.ts — disable inlining entirely
export default defineConfig({
  build: { assetsInlineLimit: 0 },
});
```

---

## Public dir vs imported

Rule of thumb: **prefer imports**. Reach for `public/` only when a file has to be at a stable, un-hashed path.

| Case | Where |
|------|-------|
| Referenced from HTML/JS with a bundler-owned path | Import it from a `src` subdir |
| Referenced from CSS `url()` with no processing | Same — bundler handles url() |
| Robots.txt, favicon, `.well-known/`, sitemap.xml | `public/` |
| Runtime-referenced by a stable, un-hashed URL | `public/` |
| Referenced from a Service Worker at a known path | `public/` |
| Static download link where the URL matters | `public/` |

Files in `public/` are **copied to the output root as-is** — no hashing, no processing, no module-graph tracking. Reference them via absolute path:

```html
<img src="/logo.svg" />
```

```ts
const url = '/robots.txt'; // works in dev and build
```

You get no fingerprinting, so cache-busting is your problem. In exchange, the URL is stable across builds.

---

## SVG-as-component pattern

Vite doesn't turn SVGs into React components by default — it treats `.svg` as a plain asset. Options:

- **`vite-plugin-svgr`** — enables `?react` (and the CRA-style `ReactComponent` named import).
- **Plain URL import** — use `<img src={logo} />`.

```ts
// With vite-plugin-svgr
import Logo from './logo.svg?react';

export function Header() {
  return <Logo width={24} height={24} />;
}
```

```ts
// Plain URL
import logoUrl from './logo.svg';

export function Header() {
  return <img src={logoUrl} width={24} height={24} />;
}
```

The component form gives you `fill`/`stroke`/CSS control over the SVG's paths; the URL form is smaller and cacheable.

---

## CSS code splitting

`build.cssCodeSplit: true` (default) — **each async chunk gets its own CSS file**. When a route is code-split, its stylesheet ships as a sibling asset and is only fetched when that route loads.

`build.cssCodeSplit: false` — combines **all** CSS into one file. Every route pays the cost, but there's only one request.

First-paint tradeoff:

- **Split** — smaller initial CSS, but each new route adds a stylesheet request (potentially blocking paint until it arrives).
- **Combined** — larger initial payload; zero CSS work on route change.

For SPAs with a heavy initial route and cheap subsequent navigation, combined is often faster. For MPAs or when routes have wildly different styling, split is the win.

---

## CSS ordering

CSS is emitted in the order the module graph is traversed. Same rule as any bundler: **later imports win** in the cascade.

Cross-cutting rules — resets, utility CSS, design tokens — should be imported **early**, typically in `main.tsx` before any component imports:

```tsx
// main.tsx
import './styles/reset.css';
import './styles/tokens.css';
import './styles/utilities.css';

import App from './App';
```

If a component's local styles need to override a utility, that ordering guarantees the component CSS is emitted later, so its rules win at equal specificity. Getting the order wrong is the single most common cause of "why is my Tailwind class not applying" bugs.

---

## Web worker imports

```ts
import Worker from './worker.ts?worker';

const worker = new Worker();
worker.postMessage({ msg: 'hi' });
worker.onmessage = (e) => {
  console.log(e.data);
};
```

Vite:

- Bundles `worker.ts` as a **separate chunk** with its own module graph.
- Serves it with the correct `Content-Type` in dev.
- Emits it with the correct MIME type and hashed filename in build.

Variants:

- `?worker&inline` — the worker is a base64 blob URL; no extra HTTP request, at the cost of larger main bundle.
- `?worker&url` — you get the URL string only; construct the `Worker` yourself with custom options.
- `?sharedworker` — same, but for `SharedWorker`.

TypeScript needs the ambient types from `vite/client` to recognize these query suffixes:

```ts
/// <reference types="vite/client" />
```

---

## Common pitfalls

```
❌ Storing an asset in public/ and importing with `import './public/logo.svg'`
✅ Public dir files are served at root; reference as `/logo.svg` string

❌ Expecting SVG to become a React component by default
✅ Add vite-plugin-svgr and use ?react query

❌ CSS Modules classname is undefined at runtime
✅ Ensure filename ends in .module.css

❌ Tailwind classes not applying after adding component-scoped CSS
✅ Import global/utility CSS first in main.tsx — later imports win

❌ Autoprefixer not running
✅ Confirm postcss.config.js exists at project root and lists the plugin

❌ TS error on `import x from './logo.svg?url'`
✅ Add `/// <reference types="vite/client" />` to a src/*.d.ts file

❌ Large image inlined as base64, bloating the JS bundle
✅ Lower build.assetsInlineLimit, or use ?url to force emission
```

---

## Summary

| Feature | Trigger | Output |
|---------|---------|--------|
| Global CSS | `import './x.css'` | Injected (dev) / extracted (build) |
| CSS Modules | `*.module.css` | Locally scoped, hashed class names |
| Preprocessor | Install devDep | Auto-detected, no config |
| PostCSS | `postcss.config.js` | Applied to all CSS |
| Static asset | `import x from './y.png'` | Inline (<4KB) or hashed emit |
| Force URL | `?url` | URL string |
| Raw text | `?raw` | File contents as string |
| Force inline | `?inline` | Base64 data URL |
| Worker | `?worker` | Worker constructor |
| Public dir | `public/foo` | Copied as-is, served at `/foo` |

---

## Related

- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Vite - Production Build]]
- [[Build Tools Foundations - The Dependency Graph]] — assets are graph nodes
- [[Build Tools Vite Guide]]
