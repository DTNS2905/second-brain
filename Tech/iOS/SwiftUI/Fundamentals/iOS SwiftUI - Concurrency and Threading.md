---
tags:
  - ios
  - swiftui
  - concurrency
  - threading
  - main-actor
  - combine
  - async-await
  - fundamentals
  - mobile
created: 2026-07-06
source: https://developer.apple.com/documentation/swift/concurrency
---

# iOS SwiftUI — Concurrency and Threading

> Why does `.receive(on: DispatchQueue.main)` exist? What does `@MainActor` protect against? Why `[weak self]` inside a `.sink`? This note answers those before you write your first ViewModel. Back to index: [[iOS SwiftUI Fundamentals Guide]].

---

## New Keywords in This Note

Full definitions in [[iOS Tutorial Glossary]].

**Concurrency:** [[iOS Tutorial Glossary#`@MainActor`|@MainActor]], [[iOS Tutorial Glossary#`async` / `await`|async / await]], [[iOS Tutorial Glossary#`Task { … }`|Task]], [[iOS Tutorial Glossary#`Task.isCancelled`|Task.isCancelled]]
**Foundation:** [[iOS Tutorial Glossary#`DispatchQueue`|DispatchQueue]]
**Combine:** [[iOS Tutorial Glossary#`.receive(on:)`|.receive(on:)]], [[iOS Tutorial Glossary#`.store(in:)`|.store(in:)]], [[iOS Tutorial Glossary#`Cancellable` / `AnyCancellable`|Cancellable]]
**Swift:** [[iOS Tutorial Glossary#`[weak self]` — closure capture list|[weak self]]]

---

## The One Rule You Cannot Break

> **UI state may only be read or mutated on the main thread.**

Everything on this page is a consequence of that one rule.

SwiftUI's rendering, `@State`, `@Observable` property tracking, and view-body invalidation all live on the **main thread** (technically the **main actor** — more below). Touch them from a background queue and you get:

- Purple runtime warnings in Xcode ("Publishing changes from background threads is not allowed").
- Corrupted view state (torn reads, dropped updates).
- Occasional crashes on iOS 17+ when SwiftUI catches the violation.

---

## Thread vs. Queue vs. Actor — the Vocabulary

You'll see all three terms. They're related but not interchangeable.

| Concept | What it is | Example |
|---------|-----------|---------|
| **Thread** | An OS-level execution timeline. Preemptively scheduled. | `Thread.main`, `Thread.current` |
| **Queue** (Dispatch queue / GCD) | A serial or concurrent buffer of blocks of work. The OS assigns threads to run them. | `DispatchQueue.main`, `DispatchQueue.global()` |
| **Actor** (Swift Concurrency) | A type that serializes access to its state. Runs on threads borrowed from a cooperative pool. | `@MainActor`, custom `actor MyThing { … }` |

Mental model:

- **You** rarely deal with threads directly.
- **GCD (`DispatchQueue`)** is the pre-Swift-Concurrency world. Still used everywhere, especially in Combine.
- **Actors** are the modern replacement. Same goal — serialize access to shared state — with compiler-checked safety.

They coexist. Old Combine code hops with `DispatchQueue.main`. New async/await code jumps to `@MainActor`. Both routes deliver you to the main thread.

---

## `DispatchQueue` — the GCD World

```swift
import Foundation

// Enqueue work on the main queue (main thread)
DispatchQueue.main.async {
    self.title = "Loaded"     // safe to touch UI here
}

// Enqueue heavy work on a background queue
DispatchQueue.global(qos: .userInitiated).async {
    let result = expensiveWork()
    DispatchQueue.main.async {
        self.title = result   // hop back to main before touching UI
    }
}
```

- `.main` — the one, singular main queue → main thread → UI-safe.
- `.global(qos:)` — a pool of background queues. `qos` = "quality of service" — hints at priority (`.userInteractive`, `.userInitiated`, `.utility`, `.background`).
- `.async { … }` — enqueues; returns immediately.
- `.sync { … }` — enqueues and *blocks* the caller. Rarely correct. **Never** `DispatchQueue.main.sync` from the main queue (deadlock).

Apple docs: https://developer.apple.com/documentation/dispatch/dispatchqueue

---

## `@MainActor` — the Swift Concurrency Way

```swift
@MainActor
final class CountriesViewModel {
    var countries: [Country] = []      // safe to touch — compiler enforces main
}
```

Applying `@MainActor` to a type, function, or property tells the compiler:

> "This code must run with main-thread access. Any caller from off-main has to `await` it, forcing an implicit hop."

Advantages over `DispatchQueue.main.async` sprinkled everywhere:

- **Compile-time checks.** The compiler flags a background call to a `@MainActor` method as an error, not a runtime warning.
- **Cleaner code.** No `DispatchQueue.main.async { … }` scaffolding inside every function.
- **Composability.** `await` naturally suspends and resumes on the correct actor.

### When to apply `@MainActor`

| Target | Apply? |
|--------|--------|
| ViewModel class as a whole | ✅ Recommended for iOS 17+. Makes every property + method main-safe by default. |
| A single method | ✅ When only one function needs main isolation. |
| An entire repository | ❌ Repositories often *do* background work — main-isolating them defeats the purpose. |
| A `View` | ❌ SwiftUI views already run on the main actor (implicit). |

Apple docs: https://developer.apple.com/documentation/swift/mainactor

---

## Why the ViewModel Layer Cares So Much

A ViewModel typically:

1. Kicks off a network request (background work).
2. Waits for the result (arrives on a background queue).
3. Writes it to a `@Published` / `@Observable` property (must be main).

Steps 1-2 must run *off* main so the UI doesn't freeze. Step 3 must run *on* main so SwiftUI's invariants hold. That means **every ViewModel has a thread hop in it, whether you write it or not.**

- With **Combine**, you write the hop explicitly: `.receive(on: DispatchQueue.main)`.
- With **async/await + `@MainActor`**, the compiler inserts the hop for you at the `await`.

If you forget the hop with Combine, you get the purple warning. If you forget with `@MainActor`, you get a compile error. **`@MainActor` is safer.**

---

## Combine + Threading

### Where do Combine operators run?

By default, each operator runs on **whatever thread the previous operator delivered its output on**. There's no "main thread by default."

`URLSession.dataTaskPublisher` delivers on a background URLSession-owned queue. That means `.decode`, `.map`, and the `receiveValue:` closure of `.sink` all run on that background queue — **unless** you insert a hop.

### The hop pattern

```swift
publisher
    .decode(type: [CountryDTO].self, decoder: decoder)    // background
    .map { dtos in dtos.compactMap { $0.toDomain() } }    // background
    .receive(on: DispatchQueue.main)                      // ← hop here
    .sink { [weak self] countries in
        self?.countries = countries                       // main thread ✅
    }
    .store(in: &cancellables)
```

- `.receive(on:)` is the **only** operator that changes the delivery thread for downstream operators. Everything after it runs on the receiver.
- Put it as **late as possible**. Decoding and mapping are CPU work — run them off-main. Only hop back for the final UI-touching sink.
- **`.subscribe(on:)`** exists too, but it's rarer. It changes where the *upstream* work starts. For `URLSession` you don't need it (URLSession already runs off-main).

### The cancellables lifecycle

Every subscription (`.sink`, `.assign`) returns a `Cancellable`. If you drop it, the subscription is cancelled immediately — you get zero values.

```swift
private var cancellables = Set<AnyCancellable>()   // owns subscriptions for VM lifetime

publisher.sink { … }.store(in: &cancellables)      // retained until VM deinits
```

When the VM deallocates, `cancellables` deallocates, which cancels each subscription, which cancels any in-flight network work. Clean.

Deep dive: [[iOS SwiftUI Architecture - Combine Operators]].

---

## Retain Cycles — Why `[weak self]`?

> **Full deep dive:** [[iOS ARC Guide]] and [[iOS ARC - Retain Cycles]]. This section is a summary; the ARC notes cover the reference-graph theory, the "big three" leak sources (Timer, NotificationCenter, Combine sink), and how to debug leaks with the Memory Graph Debugger.

The classic Combine leak:

```swift
publisher.sink { value in
    self.items = value              // ⚠️ closure captures self strongly
}.store(in: &cancellables)
```

The reference graph:

```
self ──> cancellables ──> AnyCancellable ──> closure ──> self ──> ...
```

Neither end drops. Both live forever. The ViewModel never deallocates → the network subscription lives forever → memory leaks.

The fix:

```swift
publisher.sink { [weak self] value in
    self?.items = value             // ✅ weak reference, cycle broken
}.store(in: &cancellables)
```

Now `closure ──> self` is weak. When the last strong owner of the VM releases, `self` becomes `nil`, the closure body no-ops, and cleanup proceeds.

### When to use `[weak self]`

| Situation | Capture |
|-----------|---------|
| Closure stored in `cancellables` (Combine sinks, timer callbacks, notification observers) | `[weak self]` |
| Closure passed to a one-shot `.map` / `.filter` / `.sorted` — not stored | Strong (default) is fine |
| `Task { … }` inside a class method | `[weak self]` if you'll later cancel; safe as-is otherwise (Task holds self only until it finishes) |
| SwiftUI View closures (`Button(action:)`) | Not needed — views are value types |

Rule of thumb: **if the closure is stored longer than the current stack frame, `[weak self]`.**

---

## Async/await — the Modern Path

```swift
@MainActor
final class CountriesViewModel {
    private(set) var countries: [Country] = []

    private let fetch: FetchCountriesUseCase

    init(fetch: FetchCountriesUseCase) { self.fetch = fetch }

    func load() async {
        do {
            countries = try await fetch.execute()   // implicit hop after await
        } catch {
            // handle
        }
    }
}
```

What the compiler does for you here:

1. `fetch.execute()` runs off-main (assuming the repository isn't `@MainActor`).
2. At the `await`, control leaves the main actor.
3. When `execute()` returns, control resumes **back on the main actor** because `CountriesViewModel` is `@MainActor`.
4. `countries = …` is safe.

No `receive(on:)`. No `[weak self]` (Structured Concurrency ties the task's lifetime to the enclosing scope — no dangling closures). No `cancellables` set.

### `Task { … }` — kicking off async from sync

```swift
Button("Reload") {
    Task {
        await viewModel.load()
    }
}
```

`Task { … }` inherits the enclosing actor. Inside a SwiftUI View closure (main actor), it starts on main. Inside a `nonisolated` function, it starts on any thread.

### `.task` view modifier

The one you'll use most in views:

```swift
List(items) { … }
    .task {
        await viewModel.load()
    }
```

- Runs on appear, cancelled on disappear.
- Inherits the main actor (SwiftUI views are main-actor-isolated).
- Structurally cancelled — no manual `AnyCancellable` bookkeeping.

Deep dive: [[iOS SwiftUI - Lifecycle]] (View lifecycle section).

Apple docs: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/

---

## Cheatsheet — Which Tool When

| Situation | Reach for |
|-----------|-----------|
| ViewModel is iOS 17+ only, greenfield | `@MainActor` + async/await |
| ViewModel needs Combine (search debouncing, chained pipelines) | Combine + `.receive(on: DispatchQueue.main)` + `[weak self]` |
| One-off UI update from a completion handler | `DispatchQueue.main.async { … }` |
| Bridging a completion-handler API into async | `withCheckedThrowingContinuation` |
| Long-running background task | `Task.detached { … }` — but usually you don't need this |
| Cancel work on view disappear | `.task { … }` — auto-cancel is free |

---

## Common Gotchas

### "Purple warning: Publishing changes from background threads"

You mutated a `@Published` or `@Observable` property from off-main. Add `.receive(on: DispatchQueue.main)` before the sink (Combine), or mark the class `@MainActor` (async).

### "My VM leaks memory"

Missing `[weak self]` inside a stored `.sink` closure. See the retain-cycle diagram above.

### "My async function ran on the wrong thread"

`await` returns you to the actor of *the current context*, not automatically to main. If a `nonisolated` function awaits, it stays wherever it was resumed. To force main: wrap in a `@MainActor` type, or use `await MainActor.run { … }`.

### "`DispatchQueue.main.sync` from main → deadlock"

`.sync` blocks until the enqueued block runs. If you're already on main, main is blocked waiting for main. Never `.sync` on the same queue you're currently on.

### "My `Task { }` outlived the view"

`Task { … }` inside `.onAppear` starts a task that is *not* auto-cancelled on disappear. Use `.task { … }` instead.

---

## Where This Shows Up in the Tutorial

- [[iOS Tutorial - Part 3 MVVM ViewModel]] introduces `@Observable` (implicitly needs main-thread state mutation).
- [[iOS Tutorial - Part 4 Domain Layer]] introduces `.receive(on: DispatchQueue.main)`, `[weak self]`, and `Set<AnyCancellable>` — **read this note first**.
- [[iOS Tutorial - Part 6 Dependency Injection]] introduces `@MainActor` on the ViewModel factory.
- [[iOS Tutorial - Part 9 From Tutorial to Real App]] tier T4.1 walks you through migrating Combine → async/await, at which point Combine hops disappear.

---

## Apple Docs — Primary References

| Topic | URL |
|-------|-----|
| Swift Concurrency (async/await) | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/ |
| Actors (Swift) | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency#Actors |
| `@MainActor` | https://developer.apple.com/documentation/swift/mainactor |
| Grand Central Dispatch (`DispatchQueue`) | https://developer.apple.com/documentation/dispatch/dispatchqueue |
| Combine `.receive(on:)` | https://developer.apple.com/documentation/combine/publisher/receive(on:options:) |
| Combine `.subscribe(on:)` | https://developer.apple.com/documentation/combine/publisher/subscribe(on:options:) |
| `Task` | https://developer.apple.com/documentation/swift/task |
| `AnyCancellable` | https://developer.apple.com/documentation/combine/anycancellable |

---

## Related Notes

- [[iOS SwiftUI - Lifecycle]] — when views/state/tasks are created and destroyed
- [[iOS SwiftUI - Core Concepts]] — the mental model this all sits on top of
- [[iOS SwiftUI Architecture - MVVM with Combine]] — how threading applies to the VM layer
- [[iOS SwiftUI Architecture - Combine Operators]] — full operator catalog including scheduling
- [[iOS SwiftUI Architecture - Observation Macro]] — how `@Observable` interacts with the main actor
- [[iOS Tutorial Glossary]] — one-line definitions of every term above
