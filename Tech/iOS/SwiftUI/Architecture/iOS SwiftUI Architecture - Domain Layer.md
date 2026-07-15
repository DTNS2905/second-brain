---
tags:
  - ios
  - swift
  - clean-architecture
  - domain-layer
  - mobile
created: 2026-07-01
source: https://medium.com/@arunzzrip/clean-architecture-mvvm-on-ios-38e24896e890
---

# iOS SwiftUI Architecture - Domain Layer

> The innermost layer. Pure Swift, zero framework dependencies (except Combine for return types). Link back to [[iOS SwiftUI Architecture Guide]].

---

## What Lives Here

| Component | Role |
|-----------|------|
| **Entity** | Business object (`struct`, `Codable`-optional, `Identifiable` if listed in UI) |
| **UseCase** | One protocol per user-facing action (`FetchUsersUseCase`, `PlaceOrderUseCase`) |
| **RepositoryProtocol** | Data gateway signature — implementation lives in Data layer |
| **DomainError** | Business-meaningful errors (`.userNotFound`, `.insufficientBalance`) |

---

## Entities

Plain, immutable-by-default `struct`s. No UI, no persistence details, no wire format.

```swift
struct User: Identifiable, Equatable {
    let id: Int
    let name: String
    let email: String
    let role: Role
}

enum Role: String, Equatable {
    case admin, member, guest
}
```

**Rule:** if you find yourself adding `Color`, `Image`, `NSManagedObjectID`, or JSON-shape hacks — that field belongs elsewhere.

---

## Use Cases

One protocol = one business action. The name is a verb phrase.

```swift
protocol FetchUsersUseCase {
    func execute() -> AnyPublisher<[User], Error>
}

protocol RegisterUserUseCase {
    func execute(email: String, password: String) -> AnyPublisher<User, Error>
}
```

The default implementation lives in Domain (or a `UseCases/Impl/` sub-folder), takes a `Repository` protocol via constructor injection, and applies business rules.

```swift
final class RegisterUserUseCaseImpl: RegisterUserUseCase {
    private let repository: UserRepository

    init(repository: UserRepository) {
        self.repository = repository
    }

    func execute(email: String, password: String) -> AnyPublisher<User, Error> {
        guard email.contains("@") else {
            return Fail(error: DomainError.invalidEmail).eraseToAnyPublisher()
        }
        guard password.count >= 8 else {
            return Fail(error: DomainError.weakPassword).eraseToAnyPublisher()
        }
        return repository.register(email: email, password: password)
    }
}
```

**Why a Use Case for a trivial passthrough?**
- Business rules can be added later without touching Views
- ViewModel depends on one small interface (easier to mock)
- Cross-cutting concerns (logging, retry, caching) attach here, not in Views

---

## Repository Protocols

Abstract the data source. Implementation is Data layer's job.

```swift
protocol UserRepository {
    func fetchUsers() -> AnyPublisher<[User], Error>
    func fetchUser(id: Int) -> AnyPublisher<User, Error>
    func register(email: String, password: String) -> AnyPublisher<User, Error>
}
```

**Return type convention:** `AnyPublisher<T, Error>` (Combine) or `async throws -> T` (Swift Concurrency). Pick one per project and stick with it.

---

## Domain Errors

Prefer business-meaningful errors over leaking `URLError` or `DecodingError` upward. The Data layer maps low-level errors into Domain errors.

```swift
enum DomainError: Error, Equatable {
    case userNotFound
    case invalidEmail
    case weakPassword
    case network             // catch-all for any transport failure
    case unauthorized
}
```

The View then pattern-matches on Domain errors for localized copy:

```swift
switch error {
case DomainError.userNotFound: return "No account with that email."
case DomainError.invalidEmail: return "Please enter a valid email."
default: return "Something went wrong. Try again."
}
```

---

## What NOT to Put Here

| ❌ Anti-pattern | Why | Fix |
|-----------------|-----|-----|
| `import SwiftUI` in a Use Case | Presentation leaking inward | Move UI logic to ViewModel |
| `URLSession` inside a Use Case | Data leaking inward | Behind `Repository` protocol |
| `NSManagedObject` field on an Entity | CoreData leaking inward | DTO in Data layer maps to Entity |
| `Codable` conformance on Entity to match JSON shape | Wire format shouldn't dictate business shape | Add a DTO in Data with its own `Codable` |
| `Date` formatted as `String` for display | UI concern | Keep `Date`, format in ViewModel |

---

## Testing the Domain

Because Domain has no framework deps, tests are fast and require no host app:

```swift
final class RegisterUserUseCaseTests: XCTestCase {
    func test_rejectsEmailWithoutAtSign() {
        let repo = MockUserRepository()
        let sut = RegisterUserUseCaseImpl(repository: repo)

        let exp = expectation(description: "invalidEmail")
        var cancellables = Set<AnyCancellable>()
        sut.execute(email: "no-at-sign", password: "longenough")
            .sink(receiveCompletion: {
                if case .failure(let e as DomainError) = $0, e == .invalidEmail {
                    exp.fulfill()
                }
            }, receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 0.1)
        XCTAssertFalse(repo.registerCalled)  // Use Case rejected before hitting repo
    }
}
```

See [[iOS SwiftUI Architecture - Dependency Injection]] for how mocks like `MockUserRepository` are constructed.

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| One Use Case protocol per action | One giant `UserUseCase` with 20 methods |
| Constructor-inject the Repository | Repository as a singleton inside the Use Case |
| Return `AnyPublisher<T, Error>` uniformly | Mix callbacks, Publishers, async in one project |
| Map framework errors to `DomainError` | Leak `URLError` to Views |
| Keep Entities immutable | Mutate Entities in the ViewModel |

---

## Related

- [[iOS SwiftUI Architecture - Data Layer]] — where these protocols get implemented
- [[iOS SwiftUI Architecture - Presentation Layer]] — where these Use Cases get consumed
- [[iOS SwiftUI Architecture - Clean Architecture]] — the enclosing pattern
