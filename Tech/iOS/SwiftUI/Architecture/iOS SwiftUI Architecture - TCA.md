---
tags:
  - ios
  - architecture
  - tca
  - swiftui
  - redux
  - mobile
created: 2026-07-10
source: https://pointfreeco.github.io/swift-composable-architecture/
---

# iOS SwiftUI Architecture - TCA

> **The Composable Architecture** — Point-Free's Redux-style architecture for SwiftUI. Unidirectional state, explicit actions, side effects modeled as Effect. Link back to [[iOS SwiftUI Architecture Guide]].

---

## Definitions (every keyword)

- **State** — a single struct holding **all** state for a feature. A value type (`struct`), `Equatable`.
- **Action** — an enum listing **every** possible event in a feature (user tap, response arrived, timer tick).
- **Reducer** — a pure function `(inout State, Action) -> Effect<Action>`. Given the current state + an action → mutates state + returns an Effect (if there is a side effect).
- **Effect** — represents a side effect (network call, timer, database) that returns later as another Action.
- **Store** — object holding the State + Reducer. The View **observes** the Store to re-render.
- **Dependency** — an external resource (API client, database) injected into the Reducer via `@Dependency`.

**Unidirectional data flow:**
```
User action → Store.send(.action) → Reducer(state, action) → new State → View re-render
                                          │
                                          └─▶ Effect → later action → Reducer again
```

---

## Package Setup

TCA is a Swift Package, not an Apple framework:

```swift
// Package.swift
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0")
```

---

## Code Example (TCA 1.x — Reducer macro)

```swift
import ComposableArchitecture

@Reducer
struct UserListFeature {
    @ObservableState
    struct State: Equatable {
        var users: [User] = []
        var isLoading = false
        var errorMessage: String?
    }

    enum Action {
        case onAppear
        case loadResponse(Result<[User], Error>)
    }

    @Dependency(\.userClient) var userClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                return .run { send in
                    await send(.loadResponse(Result { try await userClient.fetch() }))
                }

            case .loadResponse(.success(let users)):
                state.isLoading = false
                state.users = users
                return .none

            case .loadResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none
            }
        }
    }
}

// View
struct UserListView: View {
    let store: StoreOf<UserListFeature>

    var body: some View {
        List(store.users) { user in Text(user.name) }
            .overlay { if store.isLoading { ProgressView() } }
            .onAppear { store.send(.onAppear) }
    }
}

// Wire up
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            UserListView(
                store: Store(initialState: UserListFeature.State()) {
                    UserListFeature()
                }
            )
        }
    }
}
```

---

## Concepts unique to TCA

### 1. Reducer composition
A large feature is many small Reducers composed together. A parent Reducer owns child State + child Action and delegates down to the child Reducer.

### 2. Built-in dependency injection
`@Dependency(\.userClient)` — TCA ships its own DI container, distinct from the [[iOS SwiftUI Architecture - Dependency Injection|constructor injection]] used in Clean Architecture. Overriding a dependency in tests is a one-liner.

### 3. Testable by design
TCA provides `TestStore` — it runs the Reducer step by step, forcing you to assert **every** state change and **every** effect. Miss an assertion → the test fails.

```swift
@Test
func loadUsers() async {
    let store = TestStore(initialState: UserListFeature.State()) {
        UserListFeature()
    } withDependencies: {
        $0.userClient.fetch = { [User(name: "A")] }
    }

    await store.send(.onAppear) { $0.isLoading = true }
    await store.receive(\.loadResponse.success) {
        $0.isLoading = false
        $0.users = [User(name: "A")]
    }
}
```

---

## TCA vs MVVM+Clean Architecture

| Aspect | TCA | [[iOS SwiftUI Architecture - Clean Architecture\|Clean+MVVM]] |
|---|---|---|
| State style | Single struct per feature | Multiple `@Published` on a ViewModel |
| Side effects | `Effect` type (declarative) | Combine publisher + `sink` |
| Async | `async/await` first-class | Combine (or async/await, your choice) |
| DI | `@Dependency` (built-in) | Constructor injection (manual) |
| Test story | `TestStore` — enforces full assertions | Mock protocol in XCTest — more flexible |
| Boilerplate | Many `case` branches in Reducer | Many Use Case protocols |
| Learning curve | **Steep** — need Redux + Point-Free's DSL | Moderate |
| Third-party dep | Yes (swift-composable-architecture) | None |

---

## Pros

- ✅ **Unidirectional data flow** — easy to debug, mutations can be logged or replayed
- ✅ High test coverage naturally (TestStore enforces full assertions)
- ✅ DI, navigation, side effects — a lot built in, no need to hand-roll
- ✅ Point-Free community is very active — steady releases, great docs
- ✅ Time-travel debugging is feasible (state is a value-type struct)

## Cons

- ❌ **Very steep learning curve** — new to iOS + Redux at the same time is overwhelming
- ❌ Large third-party dependency — Apple may ship features that obsolete parts of it (already partially happened with `@Observable`)
- ❌ Reducers bloat as features grow (many action cases)
- ❌ Overkill boilerplate for simple CRUD features
- ❌ **Very different** from traditional Apple/Cocoa style — long-time iOS devs can find it jarring

---

## When To Use

| Situation | Verdict |
|---|---|
| Team with Redux experience (React/Elm/Web) | ✅ TCA will feel familiar |
| App with complex state: undo/redo, offline sync, collaborative | ✅ TCA shines here |
| Team wants extremely high test coverage, tool-enforced | ✅ TestStore is powerful |
| iOS beginner, no prior Redux exposure | ❌ Start with MVVM |
| Solo dev, small app | ❌ Overhead isn't worth it |

---

## Related

- [[iOS SwiftUI Architecture - MVVM with Combine]] — the standard Apple pattern, stylistically opposite of TCA
- [[iOS SwiftUI Architecture - Clean Architecture]] — TCA can be seen as one implementation of Clean Architecture with its own DSL
- [[iOS SwiftUI Architecture - Observation Macro]] — TCA 1.7+ integrated `@ObservableState` using the Observation framework
- [[iOS SwiftUI Architecture - Comparison]] — decision guide

---

## External References (not Apple)

TCA is not an Apple framework. Canonical sources:
- Docs: https://pointfreeco.github.io/swift-composable-architecture/
- GitHub: https://github.com/pointfreeco/swift-composable-architecture
- Video course: https://www.pointfree.co
