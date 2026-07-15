---
tags:
  - ios
  - swift
  - dependency-injection
  - testing
  - clean-architecture
  - mobile
created: 2026-07-01
source: https://swdevnotes.com/swift/2022/use-dependency-injection-to-unit-test-a-viewmodel-in-swift/
---

# iOS SwiftUI Architecture - Dependency Injection

> Protocol-based DI wires the layers together without hard-coded singletons — the mechanism that makes Clean Architecture testable. Link back to [[iOS SwiftUI Architecture Guide]].

---

## Why DI at All?

Without DI, ViewModels reach for singletons: `APIService.shared.fetch()`. That's untestable — you can't stub the network, so unit tests hit the internet (slow, flaky, offline-broken).

With DI:

```
DIContainer creates concrete objects
    ↓ injects protocols
UserRepositoryImpl ← APIService
FetchUsersUseCaseImpl ← UserRepository (protocol)
UserListViewModel ← FetchUsersUseCase (protocol)
```

Every arrow above is a **constructor parameter** typed as a **protocol**. Swap real → mock in tests by changing one line.

---

## Constructor Injection (Default)

The layer above provides dependencies via `init`:

```swift
final class FetchUsersUseCaseImpl: FetchUsersUseCase {
    private let repository: UserRepository       // protocol, not concrete

    init(repository: UserRepository) {
        self.repository = repository
    }

    func execute() -> AnyPublisher<[User], Error> {
        repository.fetchUsers()
    }
}
```

**Why constructor, not property injection?**
- Dependencies are visible in the type signature → discoverable
- No optional stored dependencies to unwrap
- Objects are always valid after `init` — no half-constructed state

---

## The DIContainer

One place to compose everything. Not a framework — usually just a struct:

```swift
final class DIContainer {
    // MARK: - Data layer
    private lazy var apiService = APIService(baseURL: URL(string: "https://api.example.com")!)

    // MARK: - Repositories
    private lazy var userRepository: UserRepository = UserRepositoryImpl(api: apiService)

    // MARK: - Use Cases
    lazy var fetchUsers: FetchUsersUseCase = FetchUsersUseCaseImpl(repository: userRepository)
    lazy var registerUser: RegisterUserUseCase = RegisterUserUseCaseImpl(repository: userRepository)

    // MARK: - ViewModel factories
    func makeUserListViewModel() -> UserListViewModel {
        UserListViewModel(fetchUsers: fetchUsers)
    }

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(registerUser: registerUser)
    }
}
```

`lazy var` ensures shared instances are created once (singletons within the container, not globally).

---

## Wiring in the App Entry Point

```swift
@main
struct MyApp: App {
    private let container = DIContainer()

    var body: some Scene {
        WindowGroup {
            UserListView(viewModel: container.makeUserListViewModel())
        }
    }
}
```

The `View` receives its ViewModel already wired up. It has no knowledge of `APIService`, `UserRepositoryImpl`, or the DIContainer itself.

---

## Passing the Container Down the Tree

For deep hierarchies, pass the container via `@Environment` — but expose factory methods, not raw dependencies:

```swift
struct ContainerKey: EnvironmentKey {
    static let defaultValue = DIContainer()
}

extension EnvironmentValues {
    var diContainer: DIContainer {
        get { self[ContainerKey.self] }
        set { self[ContainerKey.self] = newValue }
    }
}

// Usage
struct RootView: View {
    @Environment(\.diContainer) var container
    var body: some View {
        UserListView(viewModel: container.makeUserListViewModel())
    }
}
```

**Warning:** `@Environment` on `DIContainer` is convenient but weakens the type contract — any view can grab anything. Prefer explicit constructor injection for ViewModels; use environment only when passing through many layers of pass-through views is impractical.

---

## Mocking for Tests

Because every dependency is a protocol, mocks are one-liners:

```swift
final class MockUserRepository: UserRepository {
    var fetchUsersStub: AnyPublisher<[User], Error> =
        Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    var fetchUsersCallCount = 0

    func fetchUsers() -> AnyPublisher<[User], Error> {
        fetchUsersCallCount += 1
        return fetchUsersStub
    }

    func register(email: String, password: String) -> AnyPublisher<User, Error> {
        fatalError("not stubbed")
    }
}
```

Then in tests:

```swift
func test_loadCallsRepositoryOnce() {
    let mockRepo = MockUserRepository()
    let useCase = FetchUsersUseCaseImpl(repository: mockRepo)
    let sut = UserListViewModel(fetchUsers: useCase)

    sut.load()

    XCTAssertEqual(mockRepo.fetchUsersCallCount, 1)
}
```

No network. No file system. No SwiftUI runtime. Runs in milliseconds.

---

## Property Injection (Rare, for `@Environment` Overrides)

```swift
final class UserListViewModel: ObservableObject {
    @Injected var fetchUsers: FetchUsersUseCase   // custom @propertyWrapper
}
```

This resolves at runtime from a global registry. **Avoid unless the top-down constructor injection would require 6+ layers of pass-through.** Property injection hides dependencies from the type system.

---

## Third-Party Containers — Swinject, Factory

For very large apps, a container framework can reduce boilerplate:

```swift
// Swinject
let container = Container()
container.register(UserRepository.self) { r in
    UserRepositoryImpl(api: r.resolve(APIService.self)!)
}
```

**Verdict for most projects:** the hand-rolled `DIContainer` struct above is enough. Skip frameworks until you feel the pain.

---

## Fixtures for Test Data

Alongside mocks, add `.fixture()` static factories on Entities to keep tests readable:

```swift
extension User {
    static func fixture(id: Int = 1, name: String = "Test",
                       email: String = "t@t.com", role: Role = .member) -> User {
        User(id: id, name: name, email: email, role: role)
    }
}

// Use in tests
mockRepo.fetchUsersStub = Just([User.fixture(), User.fixture(id: 2)])
    .setFailureType(to: Error.self).eraseToAnyPublisher()
```

---

## Anti-Patterns

### ❌ Singleton reach-out inside the class

```swift
// ❌ Untestable — cannot swap APIService for a mock
final class UserRepositoryImpl: UserRepository {
    func fetchUsers() -> AnyPublisher<[User], Error> {
        APIService.shared.request(.users)   // hard-coded dependency
    }
}
```

```swift
// ✅ Constructor injection
final class UserRepositoryImpl: UserRepository {
    private let api: APIService
    init(api: APIService) { self.api = api }
}
```

### ❌ ViewModel constructs its own Use Case

```swift
// ❌ Chain of hard-coded dependencies inside the VM
final class UserListViewModel: ObservableObject {
    private let useCase = FetchUsersUseCaseImpl(repository: UserRepositoryImpl(api: APIService.shared))
}
```

```swift
// ✅ Accept the smallest interface — one Use Case
final class UserListViewModel: ObservableObject {
    private let fetchUsers: FetchUsersUseCase
    init(fetchUsers: FetchUsersUseCase) { self.fetchUsers = fetchUsers }
}
```

### ❌ Concrete type in the constructor

```swift
init(repository: UserRepositoryImpl) { ... }   // ❌ can't mock
init(repository: UserRepository)     { ... }   // ✅ protocol
```

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| Constructor-inject protocols | Access `.shared` singletons inside classes |
| Type the parameter as the **protocol** | Type it as the concrete class |
| `lazy var` in DIContainer for shared instances | Static globals |
| ViewModel accepts UseCase, not Repository | ViewModel accepts everything (fat init) |
| `.fixture()` factories for test data | Hand-crafted mock data in every test |

---

## Related

- [[iOS SwiftUI Architecture - Domain Layer]] — protocols get defined here
- [[iOS SwiftUI Architecture - Data Layer]] — protocols get implemented here
- [[iOS SwiftUI Architecture - Presentation Layer]] — protocols get consumed here
- [[iOS SwiftUI Architecture - MVVM with Combine]] — testing pattern for VMs
