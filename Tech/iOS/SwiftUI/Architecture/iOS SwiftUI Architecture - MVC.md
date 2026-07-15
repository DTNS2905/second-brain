---
tags:
  - ios
  - architecture
  - mvc
  - uikit
  - mobile
created: 2026-07-10
source: https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/MVC.html
---

# iOS SwiftUI Architecture - MVC

> Model-View-Controller — Apple's classic UIKit pattern. Understand MVC to know why SwiftUI had to move on. Link back to [[iOS SwiftUI Architecture Guide]].

---

## Definitions (every keyword)

- **Model** — pure data + business rules (Swift `struct` / `class`, no UI framework imports).
- **View** — the UI components the user sees. In UIKit: `UIView`, `UILabel`, `UIButton`.
- **Controller** — mediator between Model and View. In UIKit, a subclass of **`UIViewController`** — the class that manages a screen's lifecycle (`viewDidLoad`, `viewWillAppear`, …).
- **Delegate / Target-Action** — the two UIKit mechanisms Views use to send events up to the Controller (tap button, select row).
- **KVO** (Key-Value Observing) — legacy mechanism letting a Controller "observe" Model changes without the Model knowing who is watching.

**Apple's original definition:** *"Model objects represent knowledge and expertise, view objects present that knowledge, controller objects act as the intermediary between them."*

---

## Cocoa MVC Diagram

```
        ┌──────────┐                    ┌──────────┐
        │  Model   │                    │   View   │
        └────┬─────┘                    └────┬─────┘
             │  KVO / notify                 │ delegate / target-action
             ▼                               ▼
        ┌────────────────────────────────────────┐
        │             Controller                 │
        │       (UIViewController subclass)      │
        └────────────────────────────────────────┘
```

**Core rule:** Model and View never talk directly — everything routes through the Controller.

---

## Code Example (UIKit)

```swift
// Model
struct User {
    let name: String
    let email: String
}

// View — configured in Storyboard, wired via IBOutlets
final class UserView: UIView {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var emailLabel: UILabel!
}

// Controller
final class UserViewController: UIViewController {
    @IBOutlet weak var userView: UserView!

    var user: User? {
        didSet { updateUI() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadUser()
    }

    private func loadUser() {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let user = try? JSONDecoder().decode(User.self, from: data) else { return }
            DispatchQueue.main.async { self.user = user }
        }.resume()
    }

    private func updateUI() {
        userView.nameLabel.text = user?.name
        userView.emailLabel.text = user?.email
    }
}
```

---

## Why MVC Fails in Practice: "Massive View Controller"

In real UIKit apps, Controllers end up owning:
- Networking calls
- JSON parsing (Model construction)
- Business rules ("if the user isn't verified, disable this button")
- Navigation logic (`performSegue`, `pushViewController`)
- UI layout tweaks
- `UITableViewDataSource` / `Delegate` implementations

Result: `UserViewController.swift` with **1500+ lines** is common. Testing is painful because the Controller depends on `UIViewController` lifecycle — hard to instantiate in a unit test without a `UIWindow`.

---

## Pros

- ✅ Built into UIKit — no new pattern to learn
- ✅ Fast for small prototypes (1-2 screens)
- ✅ Every iOS dev knows it — onboarding is trivial

## Cons

- ❌ Controllers become **god objects**
- ❌ Business logic tangled with UI lifecycle → untestable
- ❌ No enforced layer boundary — anyone can stuff a network call into a VC
- ❌ Doesn't fit SwiftUI: SwiftUI has **no** `UIViewController`

---

## MVC vs SwiftUI's Default

SwiftUI effectively keeps **MV**: Model + View. There is no Controller — the SwiftUI runtime handles state → UI diffing automatically. That's why [[iOS SwiftUI Architecture - MVVM with Combine|MVVM]] fits SwiftUI better: the **ViewModel** takes the Controller's spot but drops the lifecycle baggage.

---

## Anti-Pattern

### ❌ Networking inside the Controller

```swift
final class UserViewController: UIViewController {
    override func viewDidLoad() {
        URLSession.shared.dataTask(with: url) { ... }.resume()
        // 200 lines of parsing, business logic, UI updates below
    }
}
```

```swift
// ✅ Move networking to a dedicated service; the Controller only holds state
final class UserViewController: UIViewController {
    private let userService: UserService  // injected
    override func viewDidLoad() {
        userService.fetchUser { [weak self] user in self?.user = user }
    }
}
```

---

## When To Use MVC Today

| Situation | Verdict |
|---|---|
| Maintaining legacy UIKit codebase | ✅ Required |
| Single-screen UIKit prototype | ✅ OK |
| New SwiftUI app | ❌ Use [[iOS SwiftUI Architecture - MVVM with Combine\|MVVM]] or [[iOS SwiftUI Architecture - Clean Architecture\|Clean Architecture]] |

---

## Related

- [[iOS SwiftUI Architecture - MVVM with Combine]] — the natural evolution from MVC
- [[iOS SwiftUI Architecture - MVP]] — the "active Controller" variant of MVC
- [[iOS SwiftUI Architecture - Comparison]] — side-by-side with every other pattern
- [[iOS SwiftUI Architecture Guide]] — vault stack rationale
