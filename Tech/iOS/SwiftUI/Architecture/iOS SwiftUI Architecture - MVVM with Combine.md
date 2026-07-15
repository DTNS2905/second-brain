---
tags:
  - ios
  - swiftui
  - mvvm
  - combine
  - observableobject
  - published
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/combine/observableobject
apple_docs:
  - https://developer.apple.com/documentation/combine/observableobject
  - https://developer.apple.com/documentation/combine/published
  - https://developer.apple.com/documentation/swiftui/stateobject
  - https://developer.apple.com/documentation/swiftui/observedobject
  - https://developer.apple.com/documentation/swiftui/environmentobject
  - https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
---

# iOS SwiftUI Architecture - MVVM with Combine

> The mechanics that make MVVM tick in SwiftUI: `ObservableObject`, `@Published`, property wrappers, and Combine plumbing. Link back to [[iOS SwiftUI Architecture Guide]].

**Load-bearing prerequisites:** [[iOS SwiftUI - Concurrency and Threading]] (why `.receive(on: DispatchQueue.main)` is mandatory in every VM) and [[iOS ARC Guide]] (why `[weak self]` inside stored `.sink` closures is mandatory).

---

## The Three Pieces

```
Model      →  Domain Entities (User, Order) + Use Cases       — pure Swift
View       →  SwiftUI struct                                   — describes UI
ViewModel  →  ObservableObject holding @Published state       — glue
```

The **ViewModel** is where MVVM diverges from plain SwiftUI. Instead of `@State` scattered across views, state lives in one testable object.

---

## `ObservableObject` — The Contract

`ObservableObject` is a protocol with a single requirement: an `objectWillChange` publisher SwiftUI subscribes to.

```swift
final class UserListViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
}
```

**You don't write `objectWillChange` yourself.** `@Published` synthesizes it: whenever any `@Published` property is about to change, `objectWillChange.send()` fires automatically. SwiftUI subscribes, invalidates the view body, re-renders.

**Manual signal (rare):**

```swift
final class VM: ObservableObject {
    var users: [User] = [] {
        willSet { objectWillChange.send() }  // ✅ same effect as @Published
    }
}
```

---

## `@Published` — Property Publisher

`@Published` wraps a value type and produces a `Publisher<Value, Never>` accessible via `$`:

```swift
final class SearchViewModel: ObservableObject {
    @Published var query = ""            // value
    @Published var results: [Item] = []

    private var cancellables = Set<AnyCancellable>()

    init(search: SearchUseCase) {
        $query                            // Publisher<String, Never>
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .removeDuplicates()
            .flatMap { search.execute(query: $0) }
            .replaceError(with: [])
            .assign(to: &$results)        // note: assign(to:) with & — no cancellable needed
    }
}
```

**Two ways to bind Publisher → `@Published`:**

| Form | Requires | Ownership |
|------|----------|-----------|
| `.assign(to: \.results, on: self)` | Store `AnyCancellable` yourself; **can leak** with `self` | Manual |
| `.assign(to: &$results)` | Nothing — lifetime tied to the property | Auto (recommended) |

---

## The Cancellable Bag

Every subscription you `sink` needs a `Set<AnyCancellable>` on the ViewModel, or it dies immediately:

```swift
final class VM: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    func load() {
        useCase.execute()
            .sink { _ in } receiveValue: { [weak self] in self?.data = $0 }
            .store(in: &cancellables)     // ✅ subscription lives as long as VM
    }
}
```

**Why `Set` and not `[AnyCancellable]`?** `AnyCancellable` is `Hashable` by identity; a `Set` handles idempotent re-inserts and gives O(1) `insert`.

**Cleanup:** when the ViewModel deinits, `cancellables` deinits, each `AnyCancellable` calls `cancel()` — subscriptions torn down automatically.

---

## `[weak self]` — Preventing Retain Cycles

Combine closures capture `self` strongly by default. If the closure is stored on `self` (via `cancellables`), you get a cycle:

```
VM ──strong──▶ cancellables ──strong──▶ AnyCancellable ──strong──▶ closure ──strong──▶ VM
```

```swift
// ❌ retain cycle — VM never deinits
.sink { value in self.data = value }

// ✅ break the cycle
.sink { [weak self] value in self?.data = value }
```

**Rule of thumb:** if the closure runs inside a subscription stored on `self`, use `[weak self]`.

---

## Property Wrapper Cheat Sheet

| Wrapper | Container | Purpose |
|---------|-----------|---------|
| `@Published` | ViewModel | Value + publisher; drives `objectWillChange` |
| `@StateObject` | View | View creates & owns the VM |
| `@ObservedObject` | View | View observes a VM passed in from a parent |
| `@EnvironmentObject` | View | VM injected from ancestor's `.environmentObject()` |
| `@State` | View | View-local UI state, no VM |
| `@Binding` | View | Two-way tie to a parent's `@State` or `@Published` |

---

## `@StateObject` vs `@ObservedObject` — The Bug That Bites Everyone

```swift
// ❌ BROKEN
struct UserListView: View {
    @ObservedObject var viewModel = UserListViewModel(...)
}
```

`@ObservedObject` **does not own** the VM. Every time the parent re-renders and reconstructs `UserListView`, a new `UserListViewModel` is created — all in-flight requests are cancelled, all state is lost.

```swift
// ✅ CORRECT
struct UserListView: View {
    @StateObject private var viewModel = UserListViewModel(...)
}
```

`@StateObject` allocates the VM **once per view identity** and keeps it alive across parent re-renders.

**Passing a VM to a child** — the child uses `@ObservedObject` (or `@Bindable` on iOS 17):

```swift
UserListView(viewModel: viewModel)   // parent creates once
    // ↓
struct UserRow: View {
    @ObservedObject var viewModel: UserListViewModel  // consumes
}
```

---

## Common Combine Pipelines in ViewModels

### Search with debounce

```swift
$query
    .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
    .removeDuplicates()
    .flatMap { [service] q -> AnyPublisher<[Item], Never> in
        service.search(q).replaceError(with: []).eraseToAnyPublisher()
    }
    .assign(to: &$results)
```

### Combine two publishers into one derived state

```swift
Publishers.CombineLatest($email, $password)
    .map { email, pw in email.contains("@") && pw.count >= 8 }
    .assign(to: &$isFormValid)
```

### Trigger action once when a value first becomes true

```swift
$isAuthenticated
    .first(where: { $0 })
    .sink { [weak self] _ in self?.loadProfile() }
    .store(in: &cancellables)
```

See [[iOS SwiftUI Architecture - Combine Operators]] for the full operator catalog.

---

## Threading — `receive(on: DispatchQueue.main)`

`URLSession.dataTaskPublisher` emits on a background queue. Assigning to `@Published` from a background thread crashes on iOS 15+ (`Publishing changes from background threads is not allowed`).

```swift
useCase.execute()
    .receive(on: DispatchQueue.main)   // ✅ hop to main before publishing
    .assign(to: &$users)
```

With `@MainActor` on the ViewModel class this is enforced by the compiler, but `receive(on:)` is still the operator that does the hop.

---

## Testing MVVM ViewModels

```swift
final class MockFetchUsersUseCase: FetchUsersUseCase {
    var stub: AnyPublisher<[User], Error> = Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    func execute() -> AnyPublisher<[User], Error> { stub }
}

func test_load_populatesUsers() {
    let mock = MockFetchUsersUseCase()
    mock.stub = Just([User.fixture()]).setFailureType(to: Error.self).eraseToAnyPublisher()
    let sut = UserListViewModel(fetchUsers: mock)

    sut.load()

    let exp = expectation(description: "users populated")
    sut.$users
        .dropFirst()  // skip initial []
        .sink { users in
            XCTAssertEqual(users.count, 1)
            exp.fulfill()
        }
        .store(in: &cancellables)
    wait(for: [exp], timeout: 0.1)
}
```

See [[iOS SwiftUI Architecture - Dependency Injection]] for how mocks slot into ViewModels.

---

## `ObservableObject` Is Being Retired — What About iOS 17+?

Apple's new [[iOS SwiftUI Architecture - Observation Macro|@Observable macro]] replaces `ObservableObject` + `@Published`:

```swift
// Before (iOS 13-16)
final class VM: ObservableObject {
    @Published var users: [User] = []
}

// After (iOS 17+)
@Observable final class VM {
    var users: [User] = []
}
```

Benefit: SwiftUI only re-renders views that read `users`, not every view observing the VM. See [[iOS SwiftUI Architecture - Observation Macro]] for the full migration.

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| `@StateObject` when the View owns the VM | `@ObservedObject` on an owned VM (recreated each render) |
| `[weak self]` in `sink` closures | Strong `self` capture stored in `cancellables` |
| `.receive(on: DispatchQueue.main)` before publishing | Assign to `@Published` from background thread |
| `.assign(to: &$prop)` for VM's own properties | `.assign(to: \.x, on: self)` (needs manual cancellable, easy to leak) |
| `private(set)` on `@Published` display state | Views mutating VM state directly |

---

## Apple Docs (Primary References)

- `ObservableObject`: https://developer.apple.com/documentation/combine/observableobject
- `@Published`: https://developer.apple.com/documentation/combine/published
- `@StateObject`: https://developer.apple.com/documentation/swiftui/stateobject
- `@ObservedObject`: https://developer.apple.com/documentation/swiftui/observedobject
- `@EnvironmentObject`: https://developer.apple.com/documentation/swiftui/environmentobject
- Managing model data in your app: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app

**Reminder:** on iOS 17+, prefer [[iOS SwiftUI Architecture - Observation Macro|@Observable]] over `ObservableObject`. The patterns in this note are the correct choice only when supporting iOS 13–16.

---

## Related

- [[iOS SwiftUI Architecture - Presentation Layer]] — how View + VM fit together
- [[iOS SwiftUI Architecture - Combine Operators]] — the operators used above
- [[iOS SwiftUI Architecture - Observation Macro]] — the modern replacement
