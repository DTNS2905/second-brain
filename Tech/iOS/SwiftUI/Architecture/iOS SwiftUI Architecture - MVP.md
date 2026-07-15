---
tags:
  - ios
  - architecture
  - mvp
  - mobile
created: 2026-07-10
source: https://martinfowler.com/eaaDev/uiArchs.html
---

# iOS SwiftUI Architecture - MVP

> Model-View-**Presenter** — a variant of MVC where the Presenter actively pushes data into a passive View through a protocol interface. Link back to [[iOS SwiftUI Architecture Guide]].

---

## Definitions

- **Model** — same as in [[iOS SwiftUI Architecture - MVC|MVC]]: data + business rules, no UI dependencies.
- **View** (passive) — **dumb**, exposes methods like `showName(_:)`, `showLoading()`. Never pulls data itself.
- **Presenter** — where all UI logic lives. Holds a reference to the View **via a protocol** and calls methods to update the UI.
- **Passive View** — Martin Fowler's term: the View does nothing on its own, only receives commands from the Presenter.

**Core difference from MVC:** in MVC, the View pulls data from the Model via the Controller. In MVP, the Presenter **pushes** data into the View — the View is completely passive.

---

## Diagram

```
    ┌──────────┐   updates    ┌──────────────┐
    │  Model   │◀────────────▶│  Presenter   │
    └──────────┘              └──────┬───────┘
                                     │  showXxx() / hideXxx()
                                     ▼
                              ┌──────────────┐
                              │     View     │  (protocol-based, passive)
                              └──────────────┘
                                     ▲
                                     │ user events
                                     └────▶ Presenter.didTap...()
```

---

## Code Example

```swift
// Model
struct User { let name: String; let email: String }

// View protocol — the surface the Presenter operates on
protocol UserView: AnyObject {
    func showLoading()
    func hideLoading()
    func show(user: User)
    func showError(_ message: String)
}

// Presenter
final class UserPresenter {
    weak var view: UserView?
    private let service: UserService

    init(service: UserService) { self.service = service }

    func viewDidLoad() {
        view?.showLoading()
        service.fetchUser { [weak self] result in
            DispatchQueue.main.async {
                self?.view?.hideLoading()
                switch result {
                case .success(let user): self?.view?.show(user: user)
                case .failure(let err):  self?.view?.showError(err.localizedDescription)
                }
            }
        }
    }
}

// View — UIKit implementation
final class UserViewController: UIViewController, UserView {
    var presenter: UserPresenter!

    override func viewDidLoad() {
        super.viewDidLoad()
        presenter.viewDidLoad()
    }

    func showLoading()  { /* spinner on */ }
    func hideLoading()  { /* spinner off */ }
    func show(user: User)   { nameLabel.text = user.name }
    func showError(_ m: String) { /* alert */ }
}
```

**Key property:** the Presenter **does not import UIKit**. It only knows the `UserView` protocol → testable without instantiating a `UIViewController`.

---

## MVP vs MVVM (the common question)

| Aspect | MVP | [[iOS SwiftUI Architecture - MVVM with Combine\|MVVM]] |
|---|---|---|
| Who pushes data? | Presenter calls View methods | ViewModel exposes state, View **observes** |
| View knows Presenter? | Yes (usually injected) | No — View just reads `@Published` |
| Binding mechanism | Manual (`view?.show(...)`) | Reactive (Combine / SwiftUI `@State`) |
| Fits SwiftUI? | ❌ SwiftUI leans on observation, incompatible with passive View | ✅ Natural fit |

**TL;DR:** MVP is "MVVM without observation". Once Combine and SwiftUI arrived, MVVM became the natural choice — MVP faded on iOS.

---

## Pros

- ✅ View trivially mockable (just a protocol)
- ✅ Presenter testable without a UI runtime
- ✅ Responsibilities clearer than MVC

## Cons

- ❌ Heavy boilerplate: every View needs a protocol + a method per state
- ❌ Presenter bloats as the UI grows (many `showXxx` methods)
- ❌ Wastes SwiftUI's data binding — writing a passive View in SwiftUI fights the framework
- ❌ Small iOS community today — templates and articles are scarce

---

## When To Use

| Situation | Verdict |
|---|---|
| UIKit app, team already comfortable with MVP (e.g. from Android) | ✅ OK |
| New SwiftUI app | ❌ Pick MVVM |
| Maintaining an existing MVP codebase | ✅ Keep it |

---

## Related

- [[iOS SwiftUI Architecture - MVC]] — the pattern MVP branched from
- [[iOS SwiftUI Architecture - MVVM with Combine]] — inherits MVP's spirit but uses observation
- [[iOS SwiftUI Architecture - Comparison]] — full comparison table
