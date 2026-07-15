---
tags:
  - ios
  - architecture
  - viper
  - clean-architecture
  - mobile
created: 2026-07-10
source: https://www.objc.io/issues/13-architecture/viper/
---

# iOS SwiftUI Architecture - VIPER

> **V**iew · **I**nteractor · **P**resenter · **E**ntity · **R**outer — a strict 5-layer architecture for enterprise apps, derived from Uncle Bob's Clean Architecture. Link back to [[iOS SwiftUI Architecture Guide]].

---

## Definitions (each letter in VIPER)

- **View** — SwiftUI `View` or UIKit `UIViewController`. Passive; only renders what the Presenter feeds it.
- **Interactor** — holds the **business logic** for one use case (equivalent to a Use Case in [[iOS SwiftUI Architecture - Clean Architecture|Clean Architecture]]). Calls Data services.
- **Presenter** — formats data for the View, receives user events from the View, invokes the Interactor.
- **Entity** — plain data model (same as "Entity" in Clean Architecture).
- **Router** (also called **Wireframe**) — handles navigation and module assembly (instantiates View + Presenter + Interactor and wires them together).

**Must-remember rule:** each screen/feature = **one VIPER module** with all 5 files (usually 6-8 counting protocols).

---

## Diagram

```
       ┌──────────┐  user event  ┌──────────────┐  execute     ┌──────────────┐
       │   View   │─────────────▶│  Presenter   │─────────────▶│  Interactor  │
       └──────────┘              └──────────────┘              └──────┬───────┘
             ▲                          │                             │
             │ show(viewModel)          │                             ▼
             │                          │                        ┌─────────┐
             └──────────────────────────┘                        │ Entity  │
                                          ┌──────────────┐        └─────────┘
                       navigate ──────────▶│    Router   │
                                          └──────────────┘
```

**Data flow:** View → Presenter → Interactor → (Data) → Interactor → Presenter → View. Router is **only** for navigation, never data.

---

## Module Structure (one feature)

```
UserList/
├── UserListView.swift              # SwiftUI View
├── UserListPresenter.swift         # ObservableObject
├── UserListInteractor.swift        # business logic
├── UserListRouter.swift            # navigation
├── UserListEntity.swift            # data model
└── UserListContract.swift          # all protocols (View/Presenter/Interactor/Router)
```

---

## Code Example (SwiftUI-flavored VIPER)

```swift
// Contract — all protocols declared here
protocol UserListInteractorInput {
    func loadUsers()
}
protocol UserListInteractorOutput: AnyObject {
    func didLoadUsers(_ users: [User])
    func didFailWithError(_ error: Error)
}
protocol UserListRouting {
    func navigateToDetail(user: User)
}

// Interactor
final class UserListInteractor: UserListInteractorInput {
    weak var output: UserListInteractorOutput?
    private let repository: UserRepository

    init(repository: UserRepository) { self.repository = repository }

    func loadUsers() {
        repository.fetchUsers { [weak self] result in
            switch result {
            case .success(let users): self?.output?.didLoadUsers(users)
            case .failure(let err):   self?.output?.didFailWithError(err)
            }
        }
    }
}

// Presenter
final class UserListPresenter: ObservableObject, UserListInteractorOutput {
    @Published var users: [User] = []
    @Published var errorMessage: String?

    private let interactor: UserListInteractorInput
    private let router: UserListRouting

    init(interactor: UserListInteractorInput, router: UserListRouting) {
        self.interactor = interactor
        self.router = router
    }

    func onAppear() { interactor.loadUsers() }
    func didSelect(_ user: User) { router.navigateToDetail(user: user) }

    func didLoadUsers(_ users: [User]) { self.users = users }
    func didFailWithError(_ error: Error) { errorMessage = error.localizedDescription }
}

// Router
final class UserListRouter: UserListRouting {
    weak var viewController: UIViewController?
    func navigateToDetail(user: User) { /* push detail module */ }
}

// View
struct UserListView: View {
    @StateObject var presenter: UserListPresenter

    var body: some View {
        List(presenter.users) { user in
            Text(user.name).onTapGesture { presenter.didSelect(user) }
        }
        .onAppear { presenter.onAppear() }
    }
}
```

---

## VIPER vs Clean Architecture

| Aspect | VIPER | [[iOS SwiftUI Architecture - Clean Architecture\|Clean Architecture]] |
|---|---|---|
| Number of layers | 5 (V-I-P-E-R) | 3 (Presentation / Domain / Data) |
| Organizing unit | Feature module (one bundle per screen) | Layer (grouped across the whole app) |
| Navigation | Router is an **official** layer | Coordinator pattern (optional, not required) |
| Boilerplate | Very high (5-8 files per screen) | Moderate (Domain + Data reused) |
| Test coverage | Extremely high | High |
| iOS community momentum | Declining (peak 2016-2020) | Growing |

**Look closely:** VIPER is essentially **one implementation** of Clean Architecture where "one module = one use case". Clean Architecture does not force you to have a separate Router.

---

## Pros

- ✅ Extremely clear boundaries — a new dev opens the code and knows exactly where to look
- ✅ High test coverage is easy to reach (everything is a protocol)
- ✅ Large teams (5+ iOS devs) can work in parallel without stepping on each other
- ✅ Navigation logic isolated (Router) — easy deep-linking, easy flow swaps

## Cons

- ❌ **Massive boilerplate** — a single "About" screen still needs 5-8 files
- ❌ Steep learning curve for beginners
- ❌ Many passthrough methods (Presenter forwards events straight to Interactor)
- ❌ Router bloats when navigation gets complex (deep links, tab bar, modals)
- ❌ Doesn't leverage SwiftUI's declarative nav (`NavigationStack`) — Router was designed for UIKit

---

## When To Use

| Situation | Verdict |
|---|---|
| >10 iOS devs, enterprise app (banking, insurance) | ✅ Consider |
| Solo dev / small team, <20 screens | ❌ Serious overkill |
| SwiftUI-first project | ⚠️ Possible but wasteful — [[iOS SwiftUI Architecture - Clean Architecture\|Clean Architecture]] is leaner |
| Legacy UIKit codebase already on VIPER | ✅ Keep it |

---

## Related

- [[iOS SwiftUI Architecture - Clean Architecture]] — the theoretical foundation VIPER builds on
- [[iOS SwiftUI Architecture - MVVM with Combine]] — a leaner pattern for SwiftUI
- [[iOS SwiftUI Architecture - Comparison]] — decision guide
