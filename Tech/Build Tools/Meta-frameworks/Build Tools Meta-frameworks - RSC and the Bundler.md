---
tags:
  - build-tools
  - meta-frameworks
  - rsc
  - react
  - tooling
  - frontend
created: 2026-07-16
source: https://react.dev/reference/rsc/server-components
---

# Build Tools Meta-frameworks — RSC and the Bundler

> React Server Components split the app into two module graphs: server (renders to serialized output) and client (hydrates). The 'use client' and 'use server' directives are build markers — the bundler's job is to route each module into the right graph. Part of [[Build Tools Meta-frameworks Guide]].

---

## The two-graph mental model

RSC is not a runtime trick — it's a **build-time partitioning** of the source tree into two distinct module graphs. Every module in the app ends up in one graph, the other, or (rarely) both. The bundler is what performs the partition.

```
Server graph                Client graph
─────────────────           ─────────────────
Root RSC (default)          Client boundary component
  ├── DB client              ├── React hooks
  ├── fs.readFile            ├── event handlers
  ├── secrets                ├── window / document
  └── use client boundary → (crosses graph)  ← rendered as a Reference
```

Server modules never ship to the client. Client modules are bundled and shipped.

Key implications:

- **Default is server.** Any file without a directive is a server module. This inverts the pre-RSC world where everything defaulted to client.
- **Client is opt-in.** A `'use client'` directive at the top of a file marks it as a **boundary** between the two graphs.
- **The bundler owns partitioning.** The React runtime doesn't decide what's server vs client — the compiler + bundler does, at build time, based on directives.
- **References cross graphs.** When a server component renders `<ClientComponent />`, it doesn't render the component — it emits a **reference** the client resolves.

---

## `'use client'` as a build marker

At file top:

```tsx
'use client';

import { useState } from 'react';
export default function Counter() {
  const [n, setN] = useState(0);
  return <button onClick={() => setN(n + 1)}>{n}</button>;
}
```

The bundler:

- Sees the directive
- Assigns this module to the **client graph**
- Emits a **client-reference** stub in the server graph — a serialized handle the RSC runtime resolves at request time
- Stops walking imports downward from this module into the server graph

The stub in the server graph looks roughly like:

```js
// what the server graph sees for Counter.tsx
export default {
  $$typeof: Symbol.for('react.client.reference'),
  $$id: 'src_components_Counter_tsx#default',
  $$async: false,
};
```

When the server renders `<Counter />`, it sees this reference object and emits a reference into the flight payload instead of trying to render the actual component. Everything under `Counter.tsx` (its own imports, its children) belongs to the client graph.

### The boundary is the file, not the component

A single `'use client'` directive turns the **entire file** into a client module. Any component exported from that file — and any module imported by it — enters the client graph. This is why splitting components into separate files matters: a `'use client'` at the top of a shared utility file balloons the client bundle unnecessarily.

---

## `'use server'` as a build marker

```tsx
'use server';

export async function saveUser(data: FormData) {
  await db.users.update(data);
}
```

The bundler:

- Assigns this module to the **server graph**
- Emits a **server-reference** in the client graph — a callable that, when invoked, makes an RPC to the server
- The function becomes callable from client code but executes on the server

The client-side stub looks like:

```js
// what the client graph sees for saveUser
export const saveUser = createServerReference('abc123');
// createServerReference returns a function that POSTs to the framework's
// action endpoint with (id, args), receives the return value, returns it.
```

Two flavors:

1. **`'use server'` at file top** — every export from that file is a Server Action.
2. **`'use server'` inside a function body** — that specific function is a Server Action (a Server Function). Works inside RSCs.

Both are compiled into references. The client never sees the function body.

---

## Client-reference manifest

For every client component the server graph needs to know about:

```json
{
  "clientModules": {
    "src/components/Counter.tsx": {
      "id": "src_components_Counter_tsx",
      "chunks": ["chunk-a.js", "chunk-b.css"],
      "name": "Counter"
    }
  }
}
```

Server renders JSX and encounters `<Counter />`; instead of rendering, it emits a reference including chunks the client must fetch.

The manifest is a build artifact — produced by the client bundler pass, consumed by the server renderer. Without it, the server has no way to tell the client "to display this component, load these chunks."

### How the manifest gets built

1. Compiler transform scans every source file for a top-level `'use client'` directive.
2. For each such file, it registers the module as a client entry point.
3. The client bundler treats these as roots and code-splits from there.
4. After bundling, the manifest is emitted mapping each `'use client'` source file to:
   - a stable id (used in references)
   - the chunks needed to load it
   - the export names it provides

### How the manifest gets consumed

At request time, when the server renderer walks the JSX tree and hits a client-reference stub, it looks the reference up in the manifest and emits a **module descriptor** into the flight payload — chunks + id + export name. The client runtime uses that to fetch the chunks (if not already loaded) and mount the real component.

---

## Server-reference manifest

```json
{
  "serverActions": {
    "abc123": {
      "id": "abc123",
      "name": "saveUser",
      "chunks": ["server-actions.js"]
    }
  }
}
```

Client bundle contains a stub `saveUser` that calls the reference id via fetch.

The id is typically a **content hash** of the module + export name — stable across builds (given the same source) so that if a client caches a reference, it still resolves after redeployment (subject to how the framework handles cache invalidation). The framework mounts an action endpoint (Next: a special POST route, Remix: routes with actions) that:

1. Receives `{ id, args }`
2. Looks up the module + export from the manifest
3. Invokes the function server-side
4. Returns the result — serialized as a flight payload if it includes JSX, JSON otherwise

---

## The RSC payload format

Server renders JSX to a **flight** payload (React's wire format):

```
0:["$L1",[...tree...]]
1:I{"id":"src_components_Counter_tsx","chunks":["chunk-a.js"],"name":"Counter"}
2:["$","div",null,{"children":["$L1",null,{"count":0}]}]
...
```

Client fetches this stream, reconstructs the React tree, and mounts.

Key properties:

- **Streamable.** Rows are emitted as the server renders — no need to render the whole tree before sending. Client can render top-down as chunks arrive.
- **Deduplicated.** A component or value referenced multiple times gets one row and multiple pointers (`$L1`, `$L2` etc.).
- **Includes references.** Client references (`I` rows) tell the client which modules to fetch.
- **Includes suspense boundaries.** Fallbacks stream first, real content streams later, replacing the fallback in place.
- **Not JSON.** It's line-delimited, mixed-type, with escaping conventions for React internals (`$$typeof`, refs, symbols).

The client runtime (`react-server-dom-*`) parses this stream row by row, resolves references, and yields a normal React element tree to `createRoot().render(...)`.

---

## Next.js implementation

- Webpack + custom loader emit client-reference stubs on `'use client'` files
- Both server and client graphs share the same file tree; the directive dictates routing
- Turbopack does the same via its own transform passes

Next runs **three bundler passes** for App Router builds:

1. **Server pass (RSC layer).** Compiles for the server runtime (Node or Edge). Every `'use client'` file is replaced with a stub. Server-only imports (fs, secrets) are allowed.
2. **SSR pass.** Compiles a version that can render client components on the server for the initial HTML. This bundle includes the client component source but runs in Node.
3. **Client pass.** Compiles for the browser. `'use client'` files are the entry points. Server-only code paths are stripped or error.

Each pass has its own module graph and its own manifest output. The three are stitched together at request time.

Cross-link [[Build Tools Meta-frameworks - Next.js Build Pipeline]].

---

## Vite implementation

- `@vitejs/plugin-rsc` (community + growing) implements the two-graph model on Vite
- Environment API used to define two environments — `server` and `client` — each with its own module graph
- Same directive semantics

Vite's Environment API (added in v6) was specifically designed to model this kind of multi-graph build. Each environment has:

- Its own plugin pipeline
- Its own module graph (dependency tracking, HMR state)
- Its own resolver (with different conditions — `react-server` for the server env)
- Its own output bundle

The RSC plugin registers `server` and `client` environments and installs a shared transform that recognizes `'use client'` and `'use server'`, marking modules as boundaries. When the server environment sees a `'use client'` file, it swaps in a client-reference stub. When the client environment sees a `'use server'` file, it swaps in a server-reference stub.

Cross-link [[Build Tools Vite - SSR and Environments]].

---

## Impact on chunking

- Client-referenced modules become **entry points** in the client graph (each `'use client'` file is essentially a client entry, though the framework may merge them)
- Bundler must know about all `'use client'` files at build time — dynamic RSC boundaries are constrained
- Code-splitting across the two graphs is orthogonal — each graph splits internally

Practical consequences:

| Concern | Effect |
|---|---|
| One `'use client'` per component | Best granularity — each becomes a small chunk that loads on demand |
| Shared client component + shared client util | Bundler dedupes; util ends up in a common chunk |
| `import()` of a `'use client'` file from a server component | Works — becomes a lazy client reference; the client fetches the chunk when it hits the boundary |
| `import()` of a server component from a client component | Not valid — server components can't run in the browser |
| Dynamic `'use client'` (computed at request time) | Not possible — directives must be static so the manifest is complete |

---

## Impact on HMR

- Editing a server component → server re-renders + streams new payload → client updates
- Editing a client component → normal Fast Refresh in the client graph
- Adding/removing a `'use client'` directive → full reload (module graph reassignment)

Because the graph a module lives in is baked in at build/dev-transform time, toggling a directive changes graph membership — including which imports get resolved with which conditions, which reference manifests need entries, and what runtime imports the module. Rebuilding both graphs is the safe move.

For pure content edits within a graph, HMR works normally on the client and effectively via re-request on the server. Frameworks (Next, Vite RSC plugin) intercept file changes to the server graph and push a "refetch the RSC payload for this route" signal to the browser.

Cross-link [[Build Tools Dev Server and HMR - React Fast Refresh]].

---

## Common misconceptions

```
❌ "'use client' means the code runs in the client bundle only."
✅ Correct — but the FILE it's declared in is the *boundary*. Client components can be rendered by server components; the crossover happens via references.

❌ "'use server' turns a function into an API endpoint."
✅ It becomes callable from client code via an implicit RPC. Not a REST endpoint you can hit with curl (though the framework may expose one).

❌ "RSC lets me use jQuery on the server."
✅ Server components render on the server. DOM APIs (window, document) still don't exist there.
```

More:

```
❌ "Server components are SSR."
✅ Different. SSR renders React to HTML. RSC renders React to a flight payload (which can be streamed alongside HTML). Every RSC app also does SSR by default.

❌ "'use client' components can only import client code."
✅ They can import server-safe code (utils, types, pure functions). What they can't import is code that only makes sense on the server (fs, db clients).

❌ "The bundler runs at request time."
✅ No — the bundler is a build-time tool. What runs at request time is the RSC renderer, which consumes bundler-produced manifests.
```

---

## Anti-patterns

```
❌ Passing a non-serializable value across a boundary (functions, class instances, Date objects on some framework versions)
✅ Pass primitives, plain objects, or Server Action refs

❌ Importing a server-only lib from a 'use client' file
✅ Bundler will error at build time — either move to a server component or refactor

❌ Marking a whole file 'use client' when only one component is interactive
✅ Split into two files; keep as much as possible on the server
```

### Passing non-serializable props

```tsx
// ❌ Won't work — function isn't serializable
export default function ServerParent() {
  const onSubmit = (data) => { /* ... */ };
  return <ClientForm onSubmit={onSubmit} />;
}
```

```tsx
// ✅ Use a Server Action
export default function ServerParent() {
  async function onSubmit(data: FormData) {
    'use server';
    /* ... */
  }
  return <ClientForm onSubmit={onSubmit} />;
}
```

### Importing server-only into client

```tsx
// ❌ 'use client' file importing fs
'use client';
import { readFileSync } from 'fs';
```

The bundler resolves `fs` in the client environment — it's not available; the build fails. The `server-only` package makes this failure explicit and earlier.

### Over-broad 'use client'

```tsx
// ❌ A whole page marked as client
'use client';
export default function Page() {
  return (
    <div>
      <ExpensiveStaticHeader />
      <StaticProductList />
      <AddToCartButton /> {/* only this needs interactivity */}
    </div>
  );
}
```

```tsx
// ✅ Push the boundary down
export default function Page() {
  return (
    <div>
      <ExpensiveStaticHeader />
      <StaticProductList />
      <AddToCartButton />  {/* this file has 'use client' */}
    </div>
  );
}
```

---

## Where the bundler fits in

Diagram:

```
Source tree
  │
  │  'use client' / 'use server' directives
  ↓
Compiler transform → marks module
  │
  ↓
Bundler
  ├──> Server graph  ─→ Node bundle + server refs manifest
  └──> Client graph  ─→ Client bundle + client refs manifest
  │
  ↓
Runtime
  ├── SSR renders JSX to flight payload
  ├── Sends refs + payload to browser
  └── Client hydrates from refs
```

Layer-by-layer:

| Layer | Responsibility |
|---|---|
| **Compiler transform** | Detect directives, rewrite modules into references, tag graph membership |
| **Bundler** | Traverse each graph independently, resolve with per-graph conditions, code-split, emit manifests |
| **Server runtime** | Render JSX; on client-reference, consult manifest and emit descriptor into flight |
| **Client runtime** | Parse flight, fetch chunks named in descriptors, resolve refs, mount tree |
| **Server Action endpoint** | Look up server-reference id in manifest, invoke, serialize response |

The bundler is the linchpin: without a correct partition and correct manifests, the runtimes have no way to bridge the two graphs.

---

## Summary table

| Concept | Server graph | Client graph |
|---|---|---|
| Default | ✅ | — |
| Marker to enter | (none) | `'use client'` at file top |
| Marker to expose | `'use server'` | — |
| Ships to browser | ❌ | ✅ |
| Can use DOM APIs | ❌ | ✅ |
| Can use fs / db / secrets | ✅ | ❌ |
| React hooks (useState, useEffect) | ❌ | ✅ |
| Async component | ✅ | ❌ (until React Server Actions land more broadly) |
| Represented across boundary | client-reference stub | server-reference stub |

---

## Related

- [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
- [[Build Tools Compilers - JSX and React Transforms]] — directives as build markers
- [[Build Tools Vite - SSR and Environments]] — Vite's two-environment model
- [[Build Tools Webpack - Compiler and Compilation]] — where the transform hooks in
- [[React Component Composition - React Elements]]
- [[Build Tools Meta-frameworks Guide]]
