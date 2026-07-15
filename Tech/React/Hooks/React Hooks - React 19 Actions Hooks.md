---
tags:
  - react
  - hooks
  - react-19
  - actions
  - suspense
  - frontend
created: 2026-07-15
source: https://react.dev/reference/react/use
---

# React Hooks — React 19 Actions Hooks

> Four new hooks that ship with React 19 for **Actions**, **Suspense integration**, and **optimistic UI**. Part of [[React Hooks Guide]].

Covers: `use`, `useActionState`, `useOptimistic`, `useFormStatus`.

---

## `use` — read a Promise or Context

Source: https://react.dev/reference/react/use

### Signature

```ts
function use<T>(resource: Promise<T> | Context<T>): T;
```

Reads a Promise or Context. **Not technically a hook** — can be called inside conditions, loops, and after early returns. Integrates with `<Suspense>` (suspends while pending) and Error Boundaries (catches rejections).

### When to use

- Unwrapping a Promise streamed from a Server Component to a Client Component.
- Reading Context **conditionally** (something [[React Hooks - useContext]] cannot do).
- Consuming cached async resources inside a Suspense boundary.

### When NOT to use

- Creating the Promise **inline during render** — every render produces a new Promise, causing an infinite suspend loop. Cache upstream.
- Wrapping `use(promise)` in `try/catch` — the throw is Suspense signaling; use an Error Boundary.
- Reading Context in a Server Component — Context is client-only.

### Example

```tsx
'use client';
import { use, Suspense } from 'react';

function Message({ messagePromise }: { messagePromise: Promise<string> }) {
  const text = use(messagePromise);
  return <p>{text}</p>;
}

export default function App({ messagePromise }) {
  return (
    <Suspense fallback={<p>Loading...</p>}>
      <Message messagePromise={messagePromise} />
    </Suspense>
  );
}
```

### Anti-pattern

```jsx
// ❌ New Promise every render → infinite suspend
function Albums() {
  const albums = use(fetch('/api/albums').then(r => r.json()));
}

// ✅ Cache the Promise upstream, pass as a prop
function Albums({ albumsPromise }) {
  const albums = use(albumsPromise);
}
```

---

## `useActionState` — action state + pending + errors

Source: https://react.dev/reference/react/useActionState

### Signature

```ts
function useActionState<State, Payload>(
  action: (prev: State, payload: Payload) => State | Promise<State>,
  initialState: State,
  permalink?: string
): [
  state: State,
  dispatchAction: (payload: Payload) => void,
  isPending: boolean
];
```

Manages state for an async action (typically a form submission). Returns the last returned state, a dispatcher wired for `<form action>`, and `isPending`.

Multiple dispatches **queue and run sequentially**, each receiving the prior returned state.

The `permalink` argument is a fallback URL for progressive enhancement — if the form submits before JS loads, the browser navigates there and the Server Function still runs.

### When to use

- Forms calling a Server Function that need to render the result (success message, validation errors) back in place.
- Any async event where you want `isPending` without wiring `useTransition` manually.
- Progressive-enhancement forms in RSC apps.

### When NOT to use

- Pure client UI state → [[React Hooks - useState]].
- Parallel async work → [[React Hooks - useTransition]] directly (`useActionState` serializes calls).
- When throwing errors should abort the queue → instead return `{ error }` as state.

### Example

```tsx
async function subscribe(_prev, formData: FormData) {
  const email = formData.get('email');
  const res = await api.subscribe(email);
  return res.ok ? { ok: true } : { error: res.error };
}

export function Subscribe() {
  const [state, action, isPending] = useActionState(subscribe, { ok: false });
  return (
    <form action={action}>
      <input name="email" type="email" />
      <button disabled={isPending}>{isPending ? 'Sending…' : 'Subscribe'}</button>
      {state.error && <p role="alert">{state.error}</p>}
      {state.ok && <p>Subscribed!</p>}
    </form>
  );
}
```

### Anti-pattern

```jsx
// ❌ Throwing aborts every queued dispatch
async function submit() { throw new Error('boom'); }

// ✅ Return the error as state — queue keeps flowing
async function submit(prev, fd) {
  try { return await api.call(fd); }
  catch (e) { return { ...prev, error: e.message }; }
}
```

**Migration:** replaces `useFormState` from React 18 canary. Same shape, better name.

---

## `useOptimistic` — instant optimistic UI

Source: https://react.dev/reference/react/useOptimistic

### Signature

```ts
function useOptimistic<State, Action>(
  state: State,
  updateFn?: (currentState: State, optimisticValue: Action) => State
): [
  optimisticState: State,
  addOptimistic: (action: Action) => void
];
```

Shows a temporary optimistic state while an async Action runs. When the action settles and `state` updates for real, the optimistic layer discards automatically.

**Must be triggered from inside `startTransition` or a Server Action.** Calls outside are warned and revert immediately.

### When to use

- Instant feedback on like/unlike, follow, add-to-cart.
- Rendering a pending list item while its server insert completes.
- Any interaction where a > 100ms round-trip would feel laggy.

### When NOT to use

- When the server may reject and you can't cheaply reconcile UI (multistep forms with side effects).
- When you need the pending flag itself — pair with [[React Hooks - useTransition]].
- Outside `startTransition` / Actions — optimistic value flashes then vanishes.

### Example

```tsx
function Thread({ messages, sendMessage }) {
  const [optimistic, addOptimistic] = useOptimistic(
    messages,
    (curr, text) => [...curr, { text, sending: true }]
  );

  function submit(formData: FormData) {
    const text = formData.get('text') as string;
    startTransition(async () => {
      addOptimistic(text);
      await sendMessage(text);
    });
  }

  return (
    <>
      {optimistic.map((m, i) => (
        <p key={i} style={{ opacity: m.sending ? 0.5 : 1 }}>{m.text}</p>
      ))}
      <form action={submit}><input name="text" /></form>
    </>
  );
}
```

### Anti-pattern

```jsx
// ❌ Updater function may miss concurrent base-state changes
const [opt, setOpt] = useOptimistic(items);
setOpt(prev => [...prev, newItem]);

// ✅ Reducer form re-runs against the latest base state
const [opt, addItem] = useOptimistic(
  items,
  (current, newItem) => [...current, newItem]
);
```

---

## `useFormStatus` — read the parent form's status

Source: https://react.dev/reference/react-dom/hooks/useFormStatus

### Signature

```ts
function useFormStatus(): {
  pending: boolean;
  data: FormData | null;
  method: 'get' | 'post';
  action: ((formData: FormData) => void | Promise<void>) | null;
};
```

**Imported from `react-dom`, not `react`.** Returns the submission status of the **nearest ancestor `<form>`**. Only works from a **child** component — calling it in the same component that renders the `<form>` returns `pending: false` forever, because the form's context isn't yet established for its own component.

### When to use

- Reusable `<SubmitButton>` that shows a spinner and disables itself during submission.
- Reusable field-level components that dim inputs while the parent form is submitting.
- Inspecting `data` to render "Uploading 'file.pdf'…" feedback.

### When NOT to use

- Inside the same component as the `<form>` element — use `useActionState`'s `isPending` there.
- To read a sibling form's status — it only walks up.
- Server-side (client-only DOM hook).

### Example

```tsx
import { useFormStatus } from 'react-dom';

function SubmitButton() {
  const { pending } = useFormStatus();
  return <button disabled={pending}>{pending ? 'Saving…' : 'Save'}</button>;
}

export function ProfileForm({ save }) {
  return (
    <form action={save}>
      <input name="name" />
      <SubmitButton />
    </form>
  );
}
```

### Anti-pattern

```jsx
// ❌ Same component as <form> — pending is always false
function Form() {
  const { pending } = useFormStatus();
  return <form action={submit}><button disabled={pending}>Save</button></form>;
}

// ✅ Move the hook to a child component
```

---

## Package summary

| Hook | Package | Purpose | Key restriction |
|------|---------|---------|-----------------|
| `use` | `react` | Read Promise or Context | Not a hook — Promise must be cached upstream |
| `useActionState` | `react` | Async action state + pending | Serializes calls; return errors as state |
| `useOptimistic` | `react` | Temporary optimistic state | Must run inside `startTransition` / Action |
| `useFormStatus` | `react-dom` | Parent form's submission state | Must be inside a **child** of `<form>` |

---

## Related

- [[React Hooks - useTransition]] — `useOptimistic` requires it
- [[React Hooks - useContext]] — the classic Context reader
- [[React Hooks - useState]] — client-only alternative when Actions aren't involved
