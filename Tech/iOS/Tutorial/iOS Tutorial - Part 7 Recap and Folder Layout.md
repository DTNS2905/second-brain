---
tags:
  - ios
  - swiftui
  - tutorial
  - clean-architecture
  - recap
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/swiftui
---

# iOS Tutorial — Part 7: Recap and Folder Layout

> Zoom out. Look at everything you built, why each layer exists, and when to skip layers on smaller apps. Back to index: [[iOS Tutorial Guide]].

---

## No New Keywords Here

This part is a recap — every term has been introduced already. Stuck on any word? Look it up in [[iOS Tutorial Glossary]].

---

## Final Folder Layout

```
CountriesApp/
├── App/
│   └── CountriesAppApp.swift              # @main, composition root wiring
├── Presentation/
│   ├── CountriesListView.swift            # SwiftUI View
│   ├── CountryRow.swift                   # Sub-view
│   └── CountriesViewModel.swift           # @Observable, state + orchestration
├── Domain/
│   ├── Entities/
│   │   └── Country.swift                  # Pure Swift, framework-free
│   ├── UseCases/
│   │   └── FetchCountriesUseCase.swift    # Business rule: alphabetize
│   └── Repositories/
│       └── CountriesRepository.swift      # Protocol only
├── Data/
│   ├── DTOs/
│   │   └── CountryDTO.swift               # Matches server JSON + toDomain()
│   ├── Network/
│   │   ├── APIClient.swift                # Protocol + URLSessionAPIClient
│   │   └── MockAPIClient.swift            # For previews + tests
│   └── Repositories/
│       └── CountriesRepositoryImpl.swift  # CountriesRepository conformance
└── DI/
    └── DIContainer.swift                  # .live and .mock configurations
```

---

## The Dependency Rule (Visual)

```
                    ┌──────────────────────┐
                    │        App           │  wires the graph
                    └──────────┬───────────┘
                               │
             ┌─────────────────┼─────────────────┐
             ▼                                   ▼
  ┌────────────────────┐              ┌────────────────────┐
  │   Presentation     │              │        Data        │
  │  View + ViewModel  │              │  Repo impl + DTO   │
  └─────────┬──────────┘              └─────────┬──────────┘
            │  depends on                       │  depends on
            ▼                                   ▼
                     ┌──────────────────┐
                     │      Domain      │  ← nothing depends on
                     │  Entity + UC +   │    Presentation or Data
                     │  Repo protocol   │
                     └──────────────────┘
```

**Read every arrow as "imports."** Domain imports nothing from outside itself. Presentation and Data both import Domain. Neither Presentation nor Data imports the other.

**Consequence:** you can rip out `URLSessionAPIClient` and replace it with GraphQL, gRPC, or CoreData — the Domain and Presentation layers don't change.

---

## What Each Layer Owns

| Layer | Owns | Doesn't own |
|-------|------|-------------|
| **Domain** | Entities, business rules, Repository protocols | UI, threads, network, persistence, DI |
| **Data** | Repository implementations, DTOs, `URLSession`, mappers | Business rules, screens, ViewModels |
| **Presentation** | Views, ViewModels, loading/error state, formatting | Persistence, network specifics |
| **App / DI** | Composition of the graph, entry point | Any actual logic |

---

## The Journey You Just Made

| Part | Concept introduced | Layer touched |
|------|--------------------|-----------------|
| 1 | View, modifiers, layout, List | Presentation |
| 2 | `@State`, bindings, `.searchable` | Presentation |
| 3 | `@Observable` VM, MVVM boundary | + ViewModel |
| 4 | Entity, UseCase, Repository protocol | + Domain |
| 5 | DTO, `URLSession` publisher, real network | + Data |
| 6 | `DIContainer`, mock configurations, previews as states | Wired together |

Each part introduced *one* concept. That's the discipline. When you learn a new pattern next, isolate it the same way: build the smallest version that shows the pattern, *then* layer on top.

---

## When to Skip Layers

Clean Architecture is a **spectrum**, not a checkbox. Here's a rough guide:

| App size | Skip? | Recommendation |
|----------|-------|----------------|
| Weekend prototype, single screen, no persistence | Skip Domain + Data | Just a View + `@Observable` VM with async fetch inline. |
| Small app, one API, 3-5 screens | Skip UseCase | View → VM → Repository. Business rules trivial. |
| Mid-size app, multiple data sources, shared features | Full Clean | The layout you learned. |
| Feature-flagged monorepo, dozens of features | Full Clean + modularization | Each feature its own Swift Package with the same 3 layers. |

**Anti-pattern to avoid:** copying the 3-layer folder skeleton into a new project and putting `class UserProfileViewModel` in it that just holds two `@Published` strings. If the VM is trivial, it's fine — but don't invent a `GetUserNameUseCase` that returns `user.name`. That's ceremony, not architecture. See [[iOS SwiftUI Architecture - Clean Architecture]] on when the layers pay for themselves.

---

## When to Reach for What (Cheat Sheet)

| Need | Reach for |
|------|-----------|
| Local UI state (toggle, text field, tab index) | `@State` |
| Two-way link to a child view | `$` binding, `@Binding` in the child |
| ViewModel state (iOS 17+) | `@Observable` class + `@State` at the view root |
| ViewModel state (iOS 16 and below) | `ObservableObject` + `@Published` + `@StateObject`  — [[iOS SwiftUI Architecture - MVVM with Combine]] |
| Global/shared state across screens | `@Environment` — see [[iOS SwiftUI Architecture - Observation Macro]] |
| Network fetch | `URLSession.dataTaskPublisher` inside a Repository impl |
| JSON → app model | `Decodable` DTO + `toDomain()` mapper |
| Business rule reused by multiple VMs | Use Case |
| Mocking in previews / tests | `DIContainer.mock` factory |

---

## Where to Go Next

Suggested next topics — each opens a new note or a new area of the vault:

1. **Navigation** — `NavigationStack` with typed destinations, deep links. Not covered here.
2. **Persistence** — SwiftData (iOS 17+) or Core Data. Slots into the Data layer as another Repository backing.
3. **Async/await migration** — replace Combine `AnyPublisher` with `async throws` and see how the layers stay identical.
4. **Modularization** — split Domain, Data, Presentation into Swift Packages; the Dependency Rule becomes a **compile-time** guarantee.
5. **Testing depth** — snapshot tests for Views, contract tests for Repository protocols.
6. **@Environment for DI** — an alternative to `DIContainer` factories that avoids passing VMs through inits.

Each of these is worth its own tutorial track. The current track has given you the foundation to absorb any of them.

---

## Apple Docs — Consolidated

| Topic | URL |
|-------|-----|
| SwiftUI framework | https://developer.apple.com/documentation/swiftui |
| SwiftUI tutorials | https://developer.apple.com/tutorials/swiftui |
| Observation | https://developer.apple.com/documentation/observation |
| `@Observable` | https://developer.apple.com/documentation/observation/observable() |
| Migrating `ObservableObject` → `@Observable` | https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro |
| Managing model data | https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app |
| Combine | https://developer.apple.com/documentation/combine |
| `URLSession.DataTaskPublisher` | https://developer.apple.com/documentation/foundation/urlsession/datataskpublisher |
| Swift language guide | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/ |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines/ |

---

## Cross-References Inside the Vault

- Foundations: [[iOS SwiftUI Fundamentals Guide]] → [[iOS SwiftUI - Core Concepts]], [[iOS SwiftUI - Core Components]]
- Architecture reference: [[iOS SwiftUI Architecture Guide]] → [[iOS SwiftUI Architecture - Clean Architecture]], [[iOS SwiftUI Architecture - Domain Layer]], [[iOS SwiftUI Architecture - Data Layer]], [[iOS SwiftUI Architecture - Presentation Layer]]
- Reactive: [[iOS SwiftUI Architecture - MVVM with Combine]], [[iOS SwiftUI Architecture - Combine Operators]], [[iOS SwiftUI Architecture - Observation Macro]]
- Wiring: [[iOS SwiftUI Architecture - Dependency Injection]]

---

**Done.** You built a Clean Architecture SwiftUI app from a blank Xcode project — layer by layer, one concept at a time. Come back to this tutorial when you start a new app and want to remember the *order of operations*: UI → State → VM → Domain → Data → DI. That's the shape.

---

**Ready to keep going?** [[iOS Tutorial - Part 8 Deceptive Tasks]] is a set of "looks easy, becomes hard" exercises that stress-test your architectural instincts. Then [[iOS Tutorial - Part 9 From Tutorial to Real App]] is a 6-tier feature backlog that turns this tutorial code into a shippable app — detail screens, persistence, real business rules, tests, and TestFlight.
