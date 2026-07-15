---
tags:
  - ios
  - swiftui
  - clean-architecture
  - mobile
created: 2026-07-01
source: https://nalexn.github.io/clean-architecture-swiftui/
---

# iOS SwiftUI Architecture - Clean Architecture

> The 3-layer variant of Uncle Bob's Clean Architecture adapted for SwiftUI: Presentation, Domain, Data. Link back to [[iOS SwiftUI Architecture Guide]].

---

## The Dependency Rule (Non-Negotiable)

**Source code dependencies point inward.** Domain is the innermost layer and imports nothing app-specific — no UIKit, no SwiftUI, no URLSession, no CoreData.

```
Presentation  →  Domain  ←  Data
    (outer)     (inner)    (outer)
```

Presentation and Data both **depend on Domain**. Domain depends on neither. This is what makes Domain portable — you could swap SwiftUI for UIKit or URLSession for GraphQL without touching Use Cases.

---

## Layer Responsibilities

### Presentation Layer
- SwiftUI `View`s (dumb, declarative)
- `ViewModel`s (`ObservableObject`, hold UI state, invoke Use Cases)
- Navigation state (routing enum, `NavigationStack` path)
- Contains **no business rules** — only UI logic (formatting, validation for display)

See [[iOS SwiftUI Architecture - Presentation Layer]].

### Domain Layer
- **Entities**: plain Swift `struct`s modeling business objects (`User`, `Order`)
- **Use Cases** (a.k.a. Interactors): single-responsibility protocols like `FetchUsersUseCase`
- **Repository protocols**: abstract data gateways (`UserRepository` protocol only)
- Zero framework imports. Pure Swift + Foundation + Combine (Combine is arguably allowed since `AnyPublisher` is used as a return type).

See [[iOS SwiftUI Architecture - Domain Layer]].

### Data Layer
- **Repository implementations** conforming to Domain protocols
- **DTOs** (Data Transfer Objects) — the wire format, `Codable`
- **Network client** (URLSession + Combine, or Alamofire, or async/await)
- **Persistence** (CoreData, SQLite, UserDefaults)
- Maps DTOs → Entities before returning to Domain.

See [[iOS SwiftUI Architecture - Data Layer]].

---

## Concrete Flow: "Load Users"

```swift
// Domain — the interface
protocol UserRepository {
    func fetchUsers() -> AnyPublisher<[User], Error>
}

protocol FetchUsersUseCase {
    func execute() -> AnyPublisher<[User], Error>
}

// Data — the implementation
final class UserRepositoryImpl: UserRepository {
    private let api: APIService
    init(api: APIService) { self.api = api }

    func fetchUsers() -> AnyPublisher<[User], Error> {
        api.request("users")                              // returns [UserDTO]
            .map { (dtos: [UserDTO]) in dtos.map(\.toDomain) }
            .eraseToAnyPublisher()
    }
}

// Presentation — the consumer
final class UserListViewModel: ObservableObject {
    @Published var users: [User] = []
    private let useCase: FetchUsersUseCase
    private var cancellables = Set<AnyCancellable>()

    init(useCase: FetchUsersUseCase) { self.useCase = useCase }

    func load() {
        useCase.execute()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] in self?.users = $0 })
            .store(in: &cancellables)
    }
}
```

---

## What Belongs Where

| Concern | Layer | Why |
|---------|-------|-----|
| `User` struct | Domain | Business entity, framework-free |
| `UserDTO` (Codable, matches JSON) | Data | Wire format, may differ from Entity |
| `URLSession` calls | Data | Framework detail |
| "A verified user can place orders" rule | Domain (Use Case) | Business rule |
| Loading spinner state | Presentation | UI concern |
| Date formatting for display | Presentation | UI concern |
| Password hashing before storage | Data | Storage concern |
| Password validation (length, chars) | Domain | Business rule |

---

## Anti-Patterns

### ❌ ViewModel calls URLSession directly

```swift
// ❌ ViewModel now depends on URLSession — untestable without hitting network
final class UserListViewModel: ObservableObject {
    func load() {
        URLSession.shared.dataTaskPublisher(for: url)...
    }
}
```

```swift
// ✅ ViewModel depends on a Use Case protocol — trivially mockable
final class UserListViewModel: ObservableObject {
    private let useCase: FetchUsersUseCase
    init(useCase: FetchUsersUseCase) { self.useCase = useCase }
}
```

### ❌ Domain imports SwiftUI or UIKit

```swift
// ❌ Domain entity should not know about UI
import SwiftUI
struct User {
    let id: Int
    let displayColor: Color  // UI concern in Domain
}
```

```swift
// ✅ Keep Domain pure. Compute display color in the View or ViewModel.
struct User {
    let id: Int
    let role: Role
}
```

### ❌ View calls Repository directly (skipping Use Case)

For simple CRUD this is tempting but blurs the layer boundary. Even a passthrough Use Case is worth it — it gives you a place to add business rules later without touching the View.

---

## Data Flow Diagram

```
   ┌────────┐  action    ┌──────────┐  execute()  ┌──────────┐  fetch()  ┌──────────┐
   │  View  │───────────▶│ViewModel │────────────▶│ UseCase  │──────────▶│Repository│
   └────────┘            └──────────┘             └──────────┘           │(protocol)│
      ▲                       │                                          └────┬─────┘
      │ SwiftUI               │ @Published                                    │ impl
      │ re-render             ▼                                               ▼
      │                  ┌──────────┐   Publisher   ┌──────────┐        ┌──────────┐
      └──────────────────│  state   │◀──────────────│  UseCase │◀───────│  Data    │
                         └──────────┘               └──────────┘        │ (network,│
                                                                        │  DB, …)  │
                                                                        └──────────┘
```

---

## Related

- [[iOS SwiftUI Architecture - Domain Layer]] — build the innermost layer first
- [[iOS SwiftUI Architecture - Data Layer]] — implement the protocols
- [[iOS SwiftUI Architecture - Dependency Injection]] — wire everything together
