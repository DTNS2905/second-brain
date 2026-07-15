---
tags:
  - ios
  - swiftui
  - mvvm
  - presentation-layer
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
apple_docs:
  - https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
  - https://developer.apple.com/documentation/swiftui/state
  - https://developer.apple.com/documentation/swiftui/binding
  - https://developer.apple.com/documentation/swiftui/stateobject
  - https://developer.apple.com/documentation/swiftui/observedobject
  - https://developer.apple.com/documentation/swiftui/environmentobject
---

# iOS SwiftUI Architecture - Presentation Layer

> Views + ViewModels. UI state, user input, and reactively rendered output. Link back to [[iOS SwiftUI Architecture Guide]].

---

## The Split

```
┌──────────────────────────────────────────────┐
│  View                                        │
│    • SwiftUI struct                          │
│    • Reads @Published from ViewModel         │
│    • Sends user actions to ViewModel         │
│    • Zero business logic                     │
├──────────────────────────────────────────────┤
│  ViewModel  (ObservableObject)               │
│    • @Published state (users, isLoading, …)  │
│    • Calls UseCases                          │
│    • Owns Combine cancellables               │
│    • Maps Domain → display-ready values      │
└──────────────────────────────────────────────┘
```

---

## Minimal ViewModel Template

```swift
@MainActor
final class UserListViewModel: ObservableObject {
    // MARK: - State
    @Published private(set) var users: [User] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies
    private let fetchUsers: FetchUsersUseCase
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init(fetchUsers: FetchUsersUseCase) {
        self.fetchUsers = fetchUsers
    }

    // MARK: - Intents (called from View)
    func load() {
        isLoading = true
        errorMessage = nil

        fetchUsers.execute()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = Self.userMessage(for: error)
                    }
                },
                receiveValue: { [weak self] users in
                    self?.users = users
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Private
    private static func userMessage(for error: Error) -> String {
        switch error {
        case DomainError.unauthorized: return "Please sign in again."
        case DomainError.network:      return "Can't connect. Check your internet."
        default:                       return "Something went wrong."
        }
    }
}
```

**Notes:**
- `private(set)` on published state → View can read but cannot mutate.
- `[weak self]` in closures → prevents retain cycles ([[iOS SwiftUI Architecture - MVVM with Combine]]).
- `@MainActor` guarantees UI updates run on the main thread (Swift 5.5+).

---

## Minimal View

```swift
struct UserListView: View {
    @StateObject private var viewModel: UserListViewModel

    init(viewModel: UserListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error, retry: viewModel.load)
            } else {
                List(viewModel.users) { user in
                    UserRow(user: user)
                }
            }
        }
        .task { viewModel.load() }
    }
}
```

---

## `@StateObject` vs `@ObservedObject` vs `@EnvironmentObject`

| Wrapper | Ownership | When to use |
|---------|-----------|-------------|
| `@StateObject` | View **creates and owns** the ViewModel | The view is where the ViewModel first appears |
| `@ObservedObject` | View **receives** an existing ViewModel from a parent | Reusable subviews that don't own their VM |
| `@EnvironmentObject` | Injected from an ancestor's `.environmentObject(...)` | App-wide state like `AppState`, current user |

### ❌ Common bug: `@ObservedObject` in a screen root

```swift
struct UserListView: View {
    @ObservedObject var viewModel = UserListViewModel(...)  // ❌
    // Every parent re-render creates a NEW ViewModel → state lost
}
```

```swift
struct UserListView: View {
    @StateObject private var viewModel: UserListViewModel   // ✅
    init(viewModel: UserListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
}
```

`@StateObject` lets SwiftUI allocate the VM **once** and keep it alive across parent re-renders.

---

## Passing ViewModel Down

```swift
// Owner
struct UserListView: View {
    @StateObject var viewModel: UserListViewModel
    var body: some View {
        List(viewModel.users) { UserRow(user: $0, actions: viewModel) }
    }
}

// Consumer — takes @ObservedObject because it doesn't own it
struct UserRow: View {
    let user: User
    @ObservedObject var actions: UserListViewModel
    var body: some View { /* … */ }
}
```

---

## Composing State: Loadable Enum

Common pattern — a single `enum` covers all four states, making the View a `switch`:

```swift
enum Loadable<T> {
    case notRequested
    case isLoading
    case loaded(T)
    case failed(Error)
}

// ViewModel
@Published var users: Loadable<[User]> = .notRequested

// View
switch viewModel.users {
case .notRequested:  Color.clear.task { viewModel.load() }
case .isLoading:     ProgressView()
case .loaded(let u): List(u) { UserRow(user: $0) }
case .failed(let e): ErrorView(error: e, retry: viewModel.load)
}
```

Cleaner than juggling three `@Published` booleans (`isLoading`, `error`, `data`).

---

## Two-Way Binding to ViewModel

For form input, expose `@Published` as `var` (drop `private(set)`) and bind with `$`:

```swift
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false

    func submit() { /* … */ }
}

struct LoginView: View {
    @StateObject var vm: LoginViewModel
    var body: some View {
        Form {
            TextField("Email", text: $vm.email)          // two-way binding
            SecureField("Password", text: $vm.password)
            Button("Sign In", action: vm.submit)
                .disabled(vm.isSubmitting)
        }
    }
}
```

---

## What NOT to Put in a View

| ❌ | Move to | Why |
|---|---------|-----|
| `URLSession.shared.dataTask(...)` | ViewModel + UseCase | View has no business talking to the network |
| Complex date formatting | ViewModel computed property | Deterministic testable derivation |
| Business rule (`if user.role == .admin`) | UseCase | The rule belongs in Domain |
| Persisting user preferences | Repository | Storage concern |

---

## What NOT to Put in a ViewModel

| ❌ | Move to | Why |
|---|---------|-----|
| `URLSession` directly | Data layer via UseCase | Untestable, tight coupling |
| SwiftUI `View` / `Color` / `Image` | View | ViewModel must run in unit tests without UI |
| Navigation via `UINavigationController` | View + `NavigationStack` binding | UIKit doesn't belong here |

**Test:** ViewModel should compile & run in a command-line target that doesn't link SwiftUI. If it doesn't, something UI-shaped is inside.

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| `@StateObject` in the owning view | `@ObservedObject` for owned VM (recreated on re-render) |
| `@MainActor` on the ViewModel class | Manually dispatch every property mutation |
| `private(set)` on `@Published` state | Let Views mutate state directly (except for form input) |
| Depend on Use Case protocols | Depend on concrete APIService |
| Own `Set<AnyCancellable>` per VM | Global static cancellable set |

---

## Apple Docs (Primary References)

- Managing model data (canonical guide): https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
- `@State`: https://developer.apple.com/documentation/swiftui/state
- `@Binding`: https://developer.apple.com/documentation/swiftui/binding
- `@StateObject`: https://developer.apple.com/documentation/swiftui/stateobject
- `@ObservedObject`: https://developer.apple.com/documentation/swiftui/observedobject
- `@EnvironmentObject`: https://developer.apple.com/documentation/swiftui/environmentobject

---

## Related

- [[iOS SwiftUI Architecture - MVVM with Combine]] — deep dive on `@Published`, `ObservableObject`, cancellables
- [[iOS SwiftUI Architecture - Observation Macro]] — iOS 17+ replacement for `ObservableObject`
- [[iOS SwiftUI Architecture - Domain Layer]] — the Use Cases consumed here
