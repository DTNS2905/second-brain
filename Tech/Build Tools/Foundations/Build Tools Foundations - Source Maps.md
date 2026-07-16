---
tags:
  - build-tools
  - foundations
  - source-maps
  - tooling
  - frontend
created: 2026-07-16
source: https://tc39.es/source-map/
---

# Build Tools Foundations — Source Maps

> A source map turns your bundled, minified line-1-column-40000 stack trace back into a readable line in your original source. Without them, error trackers and debuggers are useless. Part of [[Build Tools Foundations Guide]].

---

## What a source map is

A JSON file that maps positions in generated code back to positions in the original source. Consumed by:

- Browsers' DevTools (Sources panel, stack traces, breakpoints)
- Node.js (`--enable-source-maps`)
- Error trackers — Sentry, Datadog RUM, Bugsnag
- IDE debuggers (VS Code, WebStorm)

Without a source map, a production stack trace lands you on `bundle.min.js:1:40289` — useless. With one, it lands on `src/checkout/PaymentForm.tsx:82:14`.

---

## The v3 format

The format is standardized as **Source Map v3** (TC39 Ecma-426 draft).

```json
{
  "version": 3,
  "file": "bundle.js",
  "sourceRoot": "",
  "sources": ["src/index.tsx", "src/App.tsx"],
  "sourcesContent": ["import React ...", "export function App ..."],
  "names": ["App", "Header", "handleClick"],
  "mappings": "AAAA,SAAS,GAAG..."
}
```

Key fields:

- `sources` — original files, relative to `sourceRoot`
- `sourcesContent` — the original source (embedded); optional but essential for tools that don't have file access (e.g., Sentry after a deploy, DevTools when the file is gone)
- `names` — original identifier names, referenced by index from `mappings`
- `mappings` — VLQ-encoded position mappings; the compact bulk of the file

---

## VLQ mappings (roughly how they work)

Each mapping is a segment of up to 5 numbers, VLQ-encoded (Variable-Length Quantity, base64):

1. Generated column
2. Source file index (into `sources`)
3. Source line
4. Source column
5. Name index (into `names`), optional

Semicolons separate lines in the generated output. Commas separate segments within a line. Each number is a **delta** from the previous segment — this is what makes the encoding compact.

```
AAAA,SAAS,GAAG;AAAA...
│        │    │
│        │    └── new generated line
│        └────── second segment on the first line
└─────────────── first segment: col 0 → sources[0], line 0, col 0
```

Practical takeaway: **never hand-edit `mappings`**. Tools generate and consume it. If you see `mappings: ""` in a `.map` file, the map is empty and every position falls back to the compiled code.

---

## Two ways to attach a source map

The generated file references its map via a magic comment on the last line:

```js
// Inline (base64) — appended to the generated file
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLC...

// External URL — separate .map file
//# sourceMappingURL=bundle.js.map
```

Inline is fine for **dev** (fast, no extra HTTP request, self-contained). External is standard for **prod** (smaller JS shipped to users, map loaded on demand by DevTools).

For CSS, the equivalent is `/*# sourceMappingURL=... */`.

---

## Source map modes (the config vocabulary)

Webpack's `devtool` option is the canonical set of modes. Every bundler has an equivalent name for each tradeoff:

| Mode | What ships | Use case |
|------|-----------|----------|
| `eval` | Inline maps per module, wrapped in `eval()` | Fastest dev rebuild |
| `eval-cheap-source-map` | Line-level maps in eval | Fast dev, columns approximate |
| `source-map` | Full external `.map` files | Production (default good choice) |
| `hidden-source-map` | External `.map` but no `sourceMappingURL` in JS | Upload maps to error tracker, don't expose in browser |
| `nosources-source-map` | External `.map` without `sourcesContent` | Column mapping only, no source contents leak |

Related config on the bundler side: [[Build Tools Webpack - Core Concepts]].

The two axes to think about:

- **Inline vs external** — build speed and payload size
- **Cheap (line-only) vs full (line+column)** — precision at breakpoints

---

## The chain: transform → transform → bundle → minify

Every step in your pipeline must produce a source map. The final map delivered to the browser is a **composition** of every intermediate map:

```
src/App.tsx
  └── swc (TS → JS) → App.js + App.js.map
        └── Rollup bundle → bundle.js + bundle.js.map (chained)
              └── Terser minify → bundle.min.js + bundle.min.js.map (chained)
```

At each stage, the tool reads the input file's `.map` (or the input's own `sourceMappingURL`), applies its transform, and emits a new map that composes the incoming map with its own line/column changes. If any step **drops** the map, the chain breaks and stack traces point to compiled positions rather than to `App.tsx`.

```js
// ❌ Wrote a Rollup plugin, forgot to return `map` — chain broken
transform(code) {
  return { code: transformed };   // missing map — Rollup will guess or give up
}
```

```js
// ✅ Return both — Rollup composes it with the incoming map
transform(code, id) {
  const result = doTransform(code);
  return { code: result.code, map: result.map };
}
```

Related: [[Build Tools Foundations - AST and Transform Pipelines]] — every transform in the pipeline must emit its own map.

---

## Uploading source maps to error trackers

Sentry, Datadog RUM, and Bugsnag need the maps to **symbolicate** production errors. Standard workflow:

1. Build with `hidden-source-map` (map exists on disk, but not linked from the JS)
2. Upload the maps as part of your release step:
   ```bash
   sentry-cli releases files "$RELEASE" upload-sourcemaps ./dist
   ```
3. **Don't** ship the `.map` files to CDN — the error tracker keeps them

Why hidden: exposed maps let anyone read your original source (including `sourcesContent`). Sometimes fine (open source), often not (proprietary business logic, embedded secrets that shouldn't have been there in the first place but often are).

Sentry matches minified filename + `Release` header + a debug ID (recent versions of the spec include a `debugId` field for reliable lookup independent of filename).

---

## Common breakage patterns

```
❌ "My stack trace points to line 47298 of bundle.js"
→ No sourceMappingURL comment (or wrong path); DevTools didn't fetch the map.
  Check the last line of the JS. Check the .map is served with correct
  Content-Type and CORS.

❌ "Trace points to compiled JS with type annotations stripped, not my TS source"
→ Chain broken at the TS → JS step. Some upstream tool dropped the input
  map. Verify each transform emits a map and the next tool reads it.

❌ "Sentry shows minified names in stack"
→ Map missing sourcesContent, or wasn't uploaded to Sentry. Check the
  release step logs; check the .map contains sourcesContent.

❌ "DevTools shows the compiled code even with map present"
→ sourcesContent absent AND browser can't fetch the original file (CORS,
  auth, file no longer exists). Enable sourcesContent in your bundler
  config.

❌ "Breakpoint on line 20 pauses on line 22"
→ You're on eval-cheap-source-map or similar line-only mode. Switch to
  a full source-map for accurate column info.
```

---

## Development-only footguns

- **Fast dev modes trade fidelity for speed.** `eval-cheap-source-map` maps lines, not columns. When you set a breakpoint mid-line, it may jump to a nearby statement.
- **Source maps aren't free.** In dev, `source-map` mode can be significantly slower than `eval`. Use `eval` for the tightest inner-loop feedback and switch up only when you need accurate DevTools.
- **HMR + source maps interact.** Some HMR-injected code isn't in your source map at all; stepping through it looks weird. Expected.
- **Vite dev is always mapped.** You don't opt in; `build.sourcemap` only controls production.

---

## Bundler-specific source-map surfaces

Every tool exposes roughly the same tradeoffs under a different config name:

| Tool | Config |
|------|--------|
| Webpack | `devtool` option (many modes) |
| Rollup | `output.sourcemap: true \| 'inline' \| 'hidden'` |
| Vite | `build.sourcemap: true \| 'inline' \| 'hidden'` (build) — dev is always on |
| esbuild | `sourcemap: true \| 'inline' \| 'external' \| 'both' \| 'linked'` |
| SWC | `sourceMaps: true \| 'inline'` |
| Babel | `sourceMaps: true \| 'inline' \| 'both'` |
| TypeScript (`tsc`) | `"sourceMap": true` + `"inlineSources": true` for `sourcesContent` |
| Terser | `sourceMap: { content: inputMap, url: 'bundle.min.js.map' }` (must pass input map) |

The rule across all of them: whatever tool runs **last** in the pipeline is responsible for the final map. Every tool **before** it must feed its map forward.

---

## Related

- [[Build Tools Foundations - AST and Transform Pipelines]] — how source maps are produced by each transform
- [[Build Tools Foundations - Bundlers vs Compilers]] — both layers must produce maps
- [[Build Tools Webpack - Core Concepts]] — devtool option
- [[Build Tools Foundations Guide]]
