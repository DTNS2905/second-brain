---
tags:
  - ios
  - swift
  - core-tech
  - concurrency
  - combine
  - observation
  - mobile
created: 2026-07-06
source: https://www.swift.org/blog/
apple_docs:
  - https://www.swift.org/blog/
  - https://developer.apple.com/documentation/swift
---

# iOS Swift Core Tech Guide

> Swift's major frameworks and language features, in the order they shipped. Read chronologically to understand *why* the language ended up with today's shape — every new paradigm was solving a real pain point of the one before it. Pairs with [[iOS Swift Fundamentals Guide]] (the language itself) and [[iOS SwiftUI Fundamentals Guide]] (the UI framework).

---

## Why a Chronological View

Every iOS codebase in 2026 is an archaeological dig: view controllers written for GCD, view models rewritten for Combine, screens rebuilt for `@Observable`. If you only learn the newest APIs you can't read the code you're actually maintaining — and you won't see *why* async/await was worth introducing when Combine already existed.

This Guide walks the timeline in order. Each entry has:
- **Year / Swift version / iOS min** — pin the release
- **Problem it solved** — the pain point the previous era created
- **Where it appears in this vault** — deep-dive links

---

## Timeline

### 1. Foundation & GCD — the pre-Swift baseline (2009, Obj-C origin)

The oldest concurrency primitive Swift developers still touch. `DispatchQueue.main.async { … }` is the raw way of hopping to the main thread. Every modern layer (Combine's `.receive(on:)`, `@MainActor`) ultimately sits on top of it.

- Where in vault: [[iOS SwiftUI - Concurrency and Threading]] (main-thread rule, `DispatchQueue` primer)
- Apple docs: https://developer.apple.com/documentation/dispatch

---

### 2. Swift 1.0 — ARC, structs, protocols (2014, iOS 8)

Swift ships. Key concepts introduced from day one and still load-bearing:

- **ARC** — automatic memory management, replacing manual `retain`/`release`. Deep dive: [[iOS ARC Guide]].
- **Value types** — `struct`/`enum` as first-class citizens. Copy-by-value semantics that make SwiftUI's diffing possible.
- **Optionals** — nullability in the type system.
- **Protocols with default implementations** (extensions) — the seed of Protocol-Oriented Programming.

Fundamentals notes: [[iOS Swift Fundamentals Guide]].

---

### 3. Swift 2 – 4 — POP, error handling, Codable (2015 – 2017, iOS 9 – 11)

Iterative language polish. The two paradigm-level additions:

- **Protocol-Oriented Programming** (Swift 2, WWDC 2015) — "prefer protocols to classes." Set up the pattern for later Clean Architecture where Domain declares protocols and Data implements them.
- **`Codable`** (Swift 4, 2017) — declarative JSON encode/decode. What every DTO in the tutorial rides on. See [[iOS Tutorial - Part 5 Data Layer]].

---

### 4. Swift 5.0 — ABI stability (2019)

The runtime becomes stable. Not a paradigm shift, but the reason Swift is now safe to ship as system frameworks — and the reason SwiftUI, Combine, and Observation could later be added *as system frameworks* rather than embedded per-app.

---

### 5. Combine (Swift 5.1, 2019, iOS 13) — declarative reactive streams

The first "framework" era of Swift concurrency. Publishers, subscribers, operators (`map`, `filter`, `debounce`, `combineLatest`). Enables MVVM-with-streams — the ViewModel exposes an `AnyPublisher<[Country], Error>` that the View subscribes to.

**Problem solved:** callback hell from nested completion handlers; imperative state syncing between multiple async sources.

**Where in vault:**
- [[iOS SwiftUI Architecture - MVVM with Combine]]
- [[iOS SwiftUI Architecture - Combine Operators]]
- [[iOS Tutorial - Part 5 Data Layer]] — the tutorial's data pipeline is Combine.

**Still current?** Yes, but partially superseded by async/await for one-shot operations. Combine remains best for continuous streams (search-as-you-type, `@Published`).

---

### 6. SwiftUI (Swift 5.1, 2019, iOS 13) — declarative UI

Shipped alongside Combine. Views are structs; UI is a function of state. Replaces UIKit's imperative view-controller world.

**Where in vault:** [[iOS SwiftUI Fundamentals Guide]].

---

### 7. async / await + Structured Concurrency + Actors (Swift 5.5, 2021, iOS 15)

Swift grows a real concurrency model. Instead of Combine pipelines or dispatch queues, you write straight-line code that suspends at `await` points.

- **`async` / `await`** — the syntactic replacement for completion handlers.
- **Structured concurrency** — `Task`, `TaskGroup`, cancellation that follows scope.
- **Actors** — reference types with automatic data-race protection.
- **`@MainActor`** — compile-time guarantee code runs on the main thread. Safer than remembering to `.receive(on: DispatchQueue.main)`.

**Problem solved:** Combine's ceremony and steep operator learning curve for what's often a single `let x = await fetch()`.

**Where in vault:**
- [[iOS SwiftUI - Concurrency and Threading]] (async/await + `@MainActor` sections)
- [[iOS Tutorial - Part 9 From Tutorial to Real App]] T4.1 — the exercise that migrates the tutorial's Combine pipeline to async/await.

---

### 8. Swift 5.7 — Generics polish, Regex, `any`/`some` (2022, iOS 16)

Language-quality-of-life release. Two items you'll see often:

- **`any` keyword** — required in front of existential protocol types. `var repo: any CountriesRepository` instead of the pre-5.7 bare `CountriesRepository`.
- **Native `Regex`** — first-class regular expressions, no `NSRegularExpression` gymnastics.

---

### 9. Macros + Observation (Swift 5.9, 2023, iOS 17) — the third state-management era

Two features shipped together, and they're joined at the hip:

- **Macros** — compile-time metaprogramming. `@Observable`, `#Preview`, `@Model` (SwiftData) are all macros.
- **Observation framework** — replaces `ObservableObject` + `@Published`. Any property access from a View auto-subscribes; no more manual `@Published` on every field.

**Problem solved:** `ObservableObject` over-notified (any `@Published` change re-rendered every View watching the object, even Views that only read *one* other property). Observation notifies only what was actually read.

**Where in vault:**
- [[iOS SwiftUI Architecture - Observation Macro]]
- [[iOS Tutorial - Part 3 MVVM ViewModel]] — the tutorial's VM is `@Observable`.

---

### 10. SwiftData (Swift 5.9, 2023, iOS 17) — modern persistence

Replaces Core Data with Swift-native macros. `@Model` classes persist automatically.

**Status in this vault:** not yet covered — the tutorial persists nothing yet. See [[iOS Tutorial - Part 9 From Tutorial to Real App]] T2 (persistence tier) for future coverage.

Apple docs: https://developer.apple.com/documentation/swiftdata

---

### 11. Swift 6.0 — Strict Concurrency by default (2024, iOS 18)

The biggest breaking change since Swift 3. The compiler now enforces `Sendable` conformance across concurrency boundaries — data-race bugs become compile errors instead of runtime crashes.

**Problem solved:** async code compiled and ran but was subtly racy. Now the type system catches it.

**Migration reality:** most code needs `@MainActor` sprinkled around, plus `Sendable` conformances added to shared types. See [[iOS SwiftUI - Concurrency and Threading]].

---

### 12. Swift 6.1+ — ongoing evolution (2025 – 2026)

Continuing themes:

- **Non-copyable types (`~Copyable`)** — value types that can't be duplicated. Useful for resources, file handles, cryptographic keys.
- **Embedded Swift** — Swift for microcontrollers.
- **Foundation rewrite in Swift** — the C-based Foundation is being ported.
- **Typed throws** — `throws(SomeError)` for compile-checked error contracts.

Follow: https://www.swift.org/blog/ and https://github.com/apple/swift-evolution.

---

## Where This Tutorial Sits

The [[iOS Tutorial Guide]] uses a **mixed-era stack** intentionally:

| Layer | Uses | Era |
|-------|------|-----|
| ViewModel state | `@Observable` | iOS 17 (2023) |
| Async pipeline | Combine (`AnyPublisher`) | iOS 13 (2019) |
| Memory model | ARC | Swift 1.0 (2014) |
| Data transport | `Codable` + `URLSession.dataTaskPublisher` | Swift 4 + iOS 13 |

Why? Combine is still the most-documented pattern and reveals *why* async/await was worth introducing. Once you've felt the ceremony, the async/await migration exercise ([[iOS Tutorial - Part 9 From Tutorial to Real App]] T4.1) lands harder.

---

## Related

- [[iOS Swift Fundamentals Guide]] — the language itself, era-independent
- [[iOS ARC Guide]] — memory model (part of the Swift 1.0 baseline)
- [[iOS SwiftUI Fundamentals Guide]] — UI framework (era 6)
- [[iOS SwiftUI Architecture Guide]] — how the eras compose into Clean Architecture
- [[iOS Tutorial Guide]] — hands-on 8-part path that uses eras 5, 6, 7, 9
