---
tags:
  - ios
  - swiftui
  - architecture
  - clean-architecture
  - mvvm
  - combine
  - mobile
created: 2026-07-01
source: https://nalexn.github.io/clean-architecture-swiftui/
---

# iOS SwiftUI Architecture Guide

> Clean Architecture + MVVM + Combine for SwiftUI apps. Three layers, unidirectional data flow, protocol-driven boundaries. Prefer a step-by-step tutorial? See [[iOS Tutorial Guide]].

---

## Prerequisites

New to SwiftUI? Read these first — they cover the framework itself before architecture layers on top:

- [[iOS SwiftUI Fundamentals Guide]] — mental model, `View` protocol, `some View`, layout, modifiers
- [[iOS SwiftUI - Core Concepts]] — declarative rendering, identity, layout negotiation
- [[iOS SwiftUI - Core Components]] — stacks, lists, controls, navigation, modifier catalog

---

## Contents

**Vault's chosen stack (details):**

| Note | Covers |
|------|--------|
| [[iOS SwiftUI Architecture - Clean Architecture]] | 3-layer overview (Presentation / Domain / Data), data flow, dependency rule |
| [[iOS SwiftUI Architecture - Domain Layer]] | Entities, Use Cases, Repository protocols — pure Swift, no framework deps |
| [[iOS SwiftUI Architecture - Data Layer]] | Repository implementations, DTOs, Combine-based network service |
| [[iOS SwiftUI Architecture - Presentation Layer]] | View + ViewModel responsibilities, state binding |
| [[iOS SwiftUI Architecture - MVVM with Combine]] | `ObservableObject`, `@Published`, `@StateObject` vs `@ObservedObject`, cancellables |
| [[iOS SwiftUI Architecture - Combine Operators]] | `map`, `flatMap`, `sink`, `assign`, `receive(on:)`, `eraseToAnyPublisher` |
| [[iOS SwiftUI Architecture - Dependency Injection]] | Protocol-based DI, DIContainer, constructor injection, mocking |
| [[iOS SwiftUI Architecture - Observation Macro]] | iOS 17+ `@Observable` — the modern replacement for `ObservableObject` |
| [[iOS SwiftUI Architecture - Error Handling]] | Propagating errors through Data → Domain → Presentation, `Result` vs `throws`, Combine error operators, LoadState pattern |

**Other architectures (for comparison & context):**

| Note | Covers |
|------|--------|
| [[iOS SwiftUI Architecture - MVC]] | Apple's classic UIKit pattern — why "Massive View Controller" happens |
| [[iOS SwiftUI Architecture - MVP]] | Model-View-Presenter — the "passive View" variant of MVC |
| [[iOS SwiftUI Architecture - VIPER]] | View-Interactor-Presenter-Entity-Router — strict 5-layer enterprise |
| [[iOS SwiftUI Architecture - TCA]] | The Composable Architecture — Point-Free's Redux-style |
| [[iOS SwiftUI Architecture - Comparison]] | Decision guide: which architecture for which situation |

---

## The Three Layers

```
┌─────────────────────────────────────────────────┐
│  Presentation   View  ⟷  ViewModel              │  UIKit-free, SwiftUI + Combine
├─────────────────────────────────────────────────┤
│  Domain         UseCase  →  RepositoryProtocol  │  Pure Swift, zero deps
├─────────────────────────────────────────────────┤
│  Data           RepositoryImpl  →  Network/DB   │  URLSession, CoreData, Alamofire
└─────────────────────────────────────────────────┘
         ↑ dependencies point INWARD toward Domain
```

**The Dependency Rule:** inner layers never import from outer layers. Domain has no idea Presentation or Data exist. The direction is enforced by protocols living in Domain, with implementations in Data.

---

## Data Flow (Single Request)

```
View.onAppear
    ↓ calls
ViewModel.load()
    ↓ calls
UseCase.execute() -> AnyPublisher<[Entity], Error>
    ↓ calls
RepositoryProtocol.fetch() -> AnyPublisher<[Entity], Error>
    ↓ implemented by
RepositoryImpl -> APIService.request() -> URLSession.dataTaskPublisher
    ↓ decodes DTO -> maps to Entity
    ↑ Publisher emits
ViewModel.sink { self.items = $0 }   // @Published property
    ↑ SwiftUI observes objectWillChange
View re-renders
```

---

## Folder Structure (Recommended)

```
MyApp/
├── Domain/
│   ├── Entities/           # User.swift, Country.swift
│   ├── UseCases/           # FetchUsersUseCase.swift
│   └── Repositories/       # UserRepository.swift (protocol)
├── Data/
│   ├── Network/            # APIService.swift, Endpoint.swift
│   ├── DTOs/               # UserDTO.swift
│   └── Repositories/       # UserRepositoryImpl.swift
├── Presentation/
│   ├── Users/
│   │   ├── UserListView.swift
│   │   └── UserListViewModel.swift
│   └── Common/             # LoadableView, ErrorView
├── DI/
│   └── DIContainer.swift
└── App/
    └── MyApp.swift         # @main
```

---

## Stack Choice Summary

| Concern | Choice | Why |
|---------|--------|-----|
| UI framework | SwiftUI | Declarative, state-driven, less boilerplate than UIKit |
| Reactive layer | Combine | First-party, integrates natively with SwiftUI's `@Published` |
| Pattern | MVVM | Clean View/logic split, ViewModel is trivially unit-testable |
| Architecture | Clean Architecture | Domain isolated → business rules survive framework changes |
| DI | Protocol + constructor injection | No third-party container needed; mockable |
| Async style | `AnyPublisher<T, Error>` | Works with SwiftUI bindings; `async/await` is the alternative |

---

## When To Reach For What

- **Simple view with local state** → just `@State`. No ViewModel needed.
- **Shared/networked state** → ViewModel + `@Published`.
- **State reused across views** → hoist to `AppState` (root `ObservableObject`) or `@Environment`.
- **iOS 17+ only** → use [[iOS SwiftUI Architecture - Observation Macro|@Observable]] instead of `ObservableObject`.

---

## Apple Official Docs (Primary References)

Prefer these over third-party posts when they conflict:

| Topic | Apple URL |
|-------|-----------|
| SwiftUI framework | https://developer.apple.com/documentation/swiftui |
| Managing model data | https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app |
| Migrating `ObservableObject` → `@Observable` | https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro |
| Observation framework | https://developer.apple.com/documentation/observation |
| `@Observable` macro | https://developer.apple.com/documentation/observation/observable() |
| Combine framework | https://developer.apple.com/documentation/combine |
| `Publisher` protocol | https://developer.apple.com/documentation/combine/publisher |
| `ObservableObject` | https://developer.apple.com/documentation/combine/observableobject |
| `Published` | https://developer.apple.com/documentation/combine/published |
| `AnyCancellable` | https://developer.apple.com/documentation/combine/anycancellable |
| `receive(on:)` | https://developer.apple.com/documentation/combine/publisher/receive(on:options:) |
| Handling events with Combine (tutorial) | https://developer.apple.com/documentation/combine/receiving-and-handling-events-with-combine |
| `URLSession.DataTaskPublisher` | https://developer.apple.com/documentation/foundation/urlsession/datataskpublisher |
| Swift language guide | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/ |

**Apple's stance on Combine vs Observation:** Apple positions `@Observable` (iOS 17+) as the successor for **UI reactivity**; Combine remains supported for async pipelines (search, debouncing, chained network requests). See [[iOS SwiftUI Architecture - Observation Macro]] for the migration path.

---

## Related

- Reactive parallel in React: [[React memo Guide]] — memoization mirrors Combine's `share()` in spirit (avoid recomputation).
- View-as-a-function-of-state is the same mental model as React: props/state in → UI out.
