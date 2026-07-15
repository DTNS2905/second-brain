---
tags:
  - ios
  - swiftui
  - tutorial
  - mvvm
  - clean-architecture
  - mobile
created: 2026-07-02
source: https://developer.apple.com/tutorials/swiftui
---

# iOS Tutorial Guide — From First Screen to Clean Architecture

> A hands-on 7-part path. You build one small app (a **Countries** list) and grow it layer by layer. Each part is runnable on its own — the code compiles at the end of every part. Pairs with [[iOS SwiftUI Fundamentals Guide]] (reference) and [[iOS SwiftUI Architecture Guide]] (reference).

---

## The App You're Building

A single-screen list of countries. By Part 7 it has:

- A `List` view with rows (flag, name, capital)
- Search filtering
- Real data from `https://api.restcountries.com/countries/v5` (Bearer-authenticated)
- Clean Architecture: Presentation → Domain → Data
- MVVM with the iOS 17+ `@Observable` macro
- DI container so previews use mocks, production uses real network

---

## Stuck on a Word?

Every keyword the tutorial uses — `struct`, `@State`, `Publisher`, `DTO`, and 100+ others — is defined plainly in [[iOS Tutorial Glossary]]. Each tutorial part links its new keywords back to the glossary. Skim the glossary first if you're new to Swift.

## Foundational Deep Dives

Read these Fundamentals notes *before* the implementation-heavy parts (3, 4, 5) — the code makes far more sense once you have the mental model:

- [[iOS SwiftUI - Core Concepts]] — `View` protocol, identity, `body` as function of state
- [[iOS SwiftUI - Lifecycle]] — App → Scene → View, `.task` vs `.onAppear`, state-wrapper lifetimes
- [[iOS SwiftUI - Concurrency and Threading]] — main-thread rule, `DispatchQueue` vs `@MainActor`, retain cycles
- [[iOS ARC Guide]] — how Swift manages memory, why `[weak self]` exists

---

## Path

| Part | Focus | Result at end of part |
|------|-------|-----------------------|
| [[iOS Tutorial - Part 1 First SwiftUI Screen]] | UI only — static list, modifiers | Hard-coded countries render in a `List` |
| [[iOS Tutorial - Part 2 Local State]] | `@State`, `TextField`, `.searchable` | Search filters the local array |
| [[iOS Tutorial - Part 3 MVVM ViewModel]] | Extract logic into an `@Observable` ViewModel | View is dumb; VM owns state |
| [[iOS Tutorial - Part 4 Domain Layer]] | Entity + UseCase + Repository protocol | Business rules live in pure Swift, framework-free |
| [[iOS Tutorial - Part 5 Data Layer]] | `URLSession`, DTO, Combine `Publisher` | Real countries fetched from the network |
| [[iOS Tutorial - Part 6 Dependency Injection]] | `DIContainer`, constructor injection, mocks in previews | Prod app + previews wired independently |
| [[iOS Tutorial - Part 7 Recap and Folder Layout]] | Full folder structure + dependency rule visual | You can start a new Clean Architecture app from scratch |
| [[iOS Tutorial - Part 8 Deceptive Tasks]] | 8 "looks easy, becomes hard" tasks — optimistic UI, pagination × search, undo windows, rate limits | You can spot layer-leak temptations and design correct state machines |
| [[iOS Tutorial - Part 9 From Tutorial to Real App]] | Feature-by-feature backlog to ship the app | A 6-tier roadmap: polish → persistence → richer domain → architecture stretch → tests → TestFlight |

---

## Why This Order

Most tutorials start with Clean Architecture folders on day 1 — you drown in layers before you've written a `Text("Hello")`. This tutorial does the reverse:

1. **UI first.** You can't reason about "where does data go?" until you know what a `View` is.
2. **Local state first.** Feel the pain of a fat View before extracting a ViewModel.
3. **Real network last.** Every earlier part uses hard-coded data, so you focus on *layer boundaries*, not JSON parsing.

Each part introduces **one** new concept. If a part feels obvious — skip it. If it feels hard — the earlier parts will fill the gap.

---

## Prerequisites

- **Xcode 15+** — the `@Observable` macro requires it.
- **iOS 17+ deployment target** — for `@Observable`, `.searchable`, and modern list styles. Older-OS notes are called out where relevant.
- **Swift basics** — struct vs class, `let` vs `var`, closures, protocols. If any of these are new, read the [Swift Language Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/) chapters up to Protocols first.

You do **not** need prior UIKit or Combine knowledge.

---

## How To Use

- Type the code by hand. Copy-pasting skips the muscle memory.
- After each part, run the app in the simulator (`Cmd+R`). If it doesn't build, re-read the diff at the top of that part.
- The final code lives in your Xcode project — no separate repo. Each part just shows the diff from the previous.

---

## Reference (When You Need Depth)

- [[iOS SwiftUI - Core Concepts]] — `View` protocol, `some View`, `@ViewBuilder`, identity
- [[iOS SwiftUI - Core Components]] — full catalog of built-in views
- [[iOS SwiftUI Architecture - Observation Macro]] — `@Observable` deep-dive
- [[iOS SwiftUI Architecture - Clean Architecture]] — layer theory
- [[iOS SwiftUI Architecture - Combine Operators]] — `map`, `flatMap`, `receive(on:)`, etc.
- [[iOS SwiftUI Architecture - Dependency Injection]] — DI variants beyond the constructor style used here

---

## Apple Docs (Primary Source)

| Topic | URL |
|-------|-----|
| SwiftUI tutorials (official) | https://developer.apple.com/tutorials/swiftui |
| SwiftUI framework | https://developer.apple.com/documentation/swiftui |
| Observation framework (`@Observable`) | https://developer.apple.com/documentation/observation |
| Combine framework | https://developer.apple.com/documentation/combine |
| `URLSession` | https://developer.apple.com/documentation/foundation/urlsession |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines/ |

---

**Start here → [[iOS Tutorial - Part 1 First SwiftUI Screen]]**
