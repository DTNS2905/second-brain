---
tags:
  - ios
  - swiftui
  - fundamentals
  - navigation
  - mobile
created: 2026-07-10
source: https://developer.apple.com/documentation/swiftui/navigation
---

# iOS SwiftUI - Navigation

> How screens are pushed, popped, and presented in SwiftUI. Value-driven, state-owned, and testable. Link back to [[iOS SwiftUI Fundamentals Guide]].

---

## Definitions

- **`NavigationView`** — the original navigation container (iOS 13-15). **Deprecated in iOS 16+**. Do not use in new code.
- **`NavigationStack`** — modern replacement (iOS 16+). A stack container with a state-driven `path` you can read and mutate.
- **`NavigationLink`** — a tappable view that triggers a push. Modern form uses a `value:`; older form uses `destination:` (view directly).
- **`NavigationPath`** — a type-erased stack of route values. Append to push, remove to pop.
- **`.navigationDestination(for:)`** — declares which view to build when a value of a given type is on the path.
- **`.navigationTitle`** — sets the title shown in the nav bar of the current screen.
- **`.navigationBarTitleDisplayMode`** — `.large`, `.inline`, or `.automatic`.
- **`NavigationSplitView`** — two- or three-column layout for iPad and macOS (sidebar + content + detail).
- **Sheet** — a modally presented view that slides up from the bottom.
- **Full-screen cover** — a modal that covers the entire screen (no swipe-to-dismiss by default).
- **Alert / Confirmation Dialog** — small, focused prompts. Alerts are for confirmation; confirmation dialogs offer multiple actions.
- **`.toolbar`** — declarative API for adding buttons to the nav bar / bottom bar / keyboard bar.
- **`ToolbarItem`** — a single toolbar entry placed with a `placement:` (leading, trailing, principal, etc.).
- **Coordinator pattern** — an object that owns navigation state (`path`, presented sheets) so `View` and `ViewModel` stay free of routing logic.
- **Deep link** — a URL that opens a specific screen in your app, handled via `.onOpenURL` or Universal Links.

---

## Basic Example

```swift
NavigationStack {
    List(users) { user in
        NavigationLink(user.name, value: user)
    }
    .navigationDestination(for: User.self) { user in
        UserDetailView(user: user)
    }
    .navigationTitle("Users")
    .navigationBarTitleDisplayMode(.large)
}
```

`User` must conform to `Hashable`. The stack rebuilds `UserDetailView` from the value when the row is tapped.

---

## Programmatic Navigation

### Using `NavigationPath` (heterogeneous)

```swift
@State private var path = NavigationPath()

NavigationStack(path: $path) {
    HomeView()
        .navigationDestination(for: User.self) { UserDetailView(user: $0) }
        .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
}

path.append(user)      // push
path.removeLast()      // pop
path.removeLast(path.count)  // pop to root
```

`NavigationPath` accepts any `Hashable` value. Trade-off: type-erased, no compile-time exhaustiveness.

### Using a typed `[Route]` (recommended)

```swift
enum Route: Hashable {
    case userDetail(User)
    case postDetail(Post)
    case settings
}

@State private var path: [Route] = []

NavigationStack(path: $path) {
    HomeView()
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .userDetail(let u): UserDetailView(user: u)
            case .postDetail(let p): PostDetailView(post: p)
            case .settings:          SettingsView()
            }
        }
}

path.append(.userDetail(user))
path.removeAll()   // pop to root
```

- ✅ Compile-time exhaustive `switch`
- ✅ Easy to inspect/mutate in tests
- ✅ One `.navigationDestination` handles the whole app

---

## Push, Pop, Pop-to-Root

```swift
func push(_ route: Route)       { path.append(route) }
func pop()                      { if !path.isEmpty { path.removeLast() } }
func popToRoot()                { path.removeAll() }
func replaceStack(_ new: [Route]) { path = new }
```

Assign the array directly for **atomic multi-step navigation** (e.g., deep links).

---

## Sheets, Full-Screen Covers, Alerts

```swift
.sheet(isPresented: $showEditor) {
    EditorView()
}

.sheet(item: $selectedUser) { user in
    UserEditor(user: user)
}

.fullScreenCover(isPresented: $showOnboarding) {
    OnboardingFlow()
}

.alert("Delete this item?", isPresented: $confirmDelete) {
    Button("Delete", role: .destructive, action: delete)
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This cannot be undone.")
}

.confirmationDialog("Choose action", isPresented: $showActions) {
    Button("Share", action: share)
    Button("Archive", action: archive)
    Button("Delete", role: .destructive, action: delete)
}
```

- `.sheet(item:)` is the **safest** pattern — the sheet only presents when the optional is non-nil, and the identity of the value drives re-presentation.
- `.fullScreenCover` blocks swipe-to-dismiss; user must trigger dismissal explicitly.

### Detent-controlled sheets (iOS 16+)

```swift
.sheet(isPresented: $show) {
    FilterView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

---

## Toolbar

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Button("Cancel", action: cancel)
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("Save", action: save).disabled(!canSave)
    }
    ToolbarItem(placement: .principal) {
        Text("Editing").font(.headline)
    }
    ToolbarItemGroup(placement: .bottomBar) {
        Button("Delete", role: .destructive, action: delete)
        Spacer()
        Button("Share", action: share)
    }
}
```

Placements: `.navigationBarLeading`, `.navigationBarTrailing`, `.principal`, `.bottomBar`, `.topBarLeading`, `.topBarTrailing`, `.keyboard`, `.confirmationAction`, `.cancellationAction`.

---

## `NavigationSplitView` (iPad, macOS)

```swift
NavigationSplitView {
    List(categories, selection: $selectedCategory) { c in
        Text(c.name).tag(c)
    }
} content: {
    if let cat = selectedCategory {
        List(cat.items, selection: $selectedItem) { i in
            Text(i.title).tag(i)
        }
    } else {
        Text("Select a category")
    }
} detail: {
    if let item = selectedItem {
        ItemDetailView(item: item)
    } else {
        Text("Select an item")
    }
}
```

- Two-column form: `sidebar` + `detail`.
- Three-column form: `sidebar` + `content` + `detail`.
- Automatically collapses to a `NavigationStack` on iPhone.

---

## Deep Link Handling

```swift
@main
struct MyApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .onOpenURL { url in
                    router.handle(url)
                }
        }
    }
}

final class AppRouter: ObservableObject {
    @Published var path: [Route] = []

    func handle(_ url: URL) {
        guard url.scheme == "myapp" else { return }
        switch url.host {
        case "user":
            if let id = url.pathComponents.dropFirst().first {
                path = [.userDetail(User(id: id))]
            }
        case "settings":
            path = [.settings]
        default: break
        }
    }
}
```

Assigning `path` directly (not appending) gives a clean stack for the deep-link destination.

---

## Coordinator Pattern (keeps ViewModels routing-free)

**Problem:** if a `ViewModel` triggers navigation directly, it becomes hard to test and couples business logic to UI.

**Solution:** a `Coordinator` (or `Router`) owns `path` and presented items. `ViewModel` calls into it via an abstraction.

```swift
protocol UserFlowRouting: AnyObject {
    func showUserDetail(_ user: User)
    func showSettings()
    func dismiss()
}

final class UserFlowCoordinator: ObservableObject, UserFlowRouting {
    @Published var path: [Route] = []
    @Published var presentedSheet: Route?

    func showUserDetail(_ user: User) { path.append(.userDetail(user)) }
    func showSettings()               { presentedSheet = .settings }
    func dismiss()                    { presentedSheet = nil }
}

@MainActor
final class UserListViewModel: ObservableObject {
    private weak var router: UserFlowRouting?
    init(router: UserFlowRouting) { self.router = router }

    func didSelect(_ user: User) { router?.showUserDetail(user) }
}
```

The `View` observes the coordinator's `path`; the `ViewModel` only knows the routing protocol. See [[iOS SwiftUI Architecture - MVVM with Combine]] and [[iOS SwiftUI Architecture - Presentation Layer]].

---

## Anti-Patterns

### 1. Mixing `NavigationLink(destination:)` with programmatic `path`

❌ Before — pushes escape the `path`, breaking pop-to-root:

```swift
NavigationStack(path: $path) {
    List(users) { user in
        NavigationLink(destination: UserDetailView(user: user)) {
            Text(user.name)
        }
    }
}
```

✅ After — everything routed through the `path`:

```swift
NavigationStack(path: $path) {
    List(users) { user in
        NavigationLink(user.name, value: Route.userDetail(user))
    }
    .navigationDestination(for: Route.self) { route in
        RouteView(route: route)
    }
}
```

### 2. Navigating from inside a `ViewModel`

❌ Before — ViewModel owns a `View`:

```swift
final class UserListViewModel: ObservableObject {
    @Published var next: UserDetailView?

    func didSelect(_ u: User) {
        next = UserDetailView(user: u)
    }
}
```

✅ After — ViewModel emits an intent; coordinator decides the destination:

```swift
final class UserListViewModel: ObservableObject {
    private let router: UserFlowRouting
    init(router: UserFlowRouting) { self.router = router }
    func didSelect(_ u: User) { router.showUserDetail(u) }
}
```

### 3. `.sheet(isPresented:)` for identity-dependent content

❌ Before — stale data if `selectedUser` changes while sheet is open:

```swift
.sheet(isPresented: $showEditor) {
    UserEditor(user: selectedUser!)
}
```

✅ After — sheet re-presents when the identity changes:

```swift
.sheet(item: $selectedUser) { user in
    UserEditor(user: user)
}
```

### 4. Deep pushes with `append`-per-step

❌ Before — user sees each intermediate screen flash by:

```swift
path.append(.category(c))
path.append(.subcategory(s))
path.append(.item(i))
```

✅ After — atomic assignment:

```swift
path = [.category(c), .subcategory(s), .item(i)]
```

### 5. Multiple `.navigationDestination(for:)` scattered across children

❌ Before — hard to reason about, fragile ordering:

```swift
HomeView()
    .navigationDestination(for: User.self) { ... }
ListView()
    .navigationDestination(for: Post.self) { ... }
```

✅ After — one destination handler at the stack root, single `Route` enum:

```swift
NavigationStack(path: $path) {
    HomeView()
        .navigationDestination(for: Route.self) { RouteView(route: $0) }
}
```

---

## Interaction with Clean Architecture / MVVM

- **View** — declares `NavigationStack(path: $router.path)`, binds `.sheet(item:)`, `.alert`, `.toolbar`. Reads state only.
- **ViewModel** — pure presentation state + intent methods. Calls a `Routing` protocol; never imports SwiftUI navigation types.
- **Coordinator / Router** — owns `path`, `presentedSheet`, `presentedAlert`. Translates intents into route mutations.
- **Domain / Data layers** — never touched by navigation.

This makes ViewModels unit-testable (assert calls on a mock router) and routing swap-friendly for previews and tests.

See [[iOS SwiftUI Architecture - MVVM with Combine]].

---

## Summary Table

| Task | API | Notes |
|------|-----|-------|
| Root container | `NavigationStack { … }` | Replaces `NavigationView` |
| Value-based push | `NavigationLink(_, value:)` + `.navigationDestination(for:)` | Value must be `Hashable` |
| Programmatic path | `@State var path: [Route]` | Prefer typed enum over `NavigationPath` |
| Push | `path.append(route)` | |
| Pop | `path.removeLast()` | Guard for empty |
| Pop to root | `path.removeAll()` | Atomic |
| Deep link | `.onOpenURL { url in … }` | Assign `path` directly |
| Modal (partial) | `.sheet(item:)` / `.sheet(isPresented:)` | Prefer `item:` |
| Modal (full) | `.fullScreenCover` | Blocks swipe-dismiss |
| Confirm | `.alert` | One `role: .destructive` button |
| Multi-action | `.confirmationDialog` | Bottom action sheet |
| Bar buttons | `.toolbar { ToolbarItem(placement:) }` | Multiple placements |
| iPad / macOS layout | `NavigationSplitView` | Collapses on iPhone |
| Title | `.navigationTitle("…")` | On the destination, not the stack |
| Title style | `.navigationBarTitleDisplayMode(.inline / .large)` | Per screen |

---

## Related

- [[iOS SwiftUI Fundamentals Guide]] — top index
- [[iOS SwiftUI - Core Concepts]] — state, view identity, view protocol
- [[iOS SwiftUI - Core Components]] — the components you push and present
- [[iOS SwiftUI - Lifecycle]] — `.onAppear`, `.task`, and when navigation triggers them
- [[iOS SwiftUI - Property Wrappers]] — `@State`, `@Binding`, `@StateObject` powering the router
- [[iOS SwiftUI Architecture - MVVM with Combine]] — where the Coordinator sits
- [[iOS SwiftUI Architecture - Presentation Layer]] — View / ViewModel / Router split

---

## Apple Docs

- https://developer.apple.com/documentation/swiftui/navigation
- https://developer.apple.com/documentation/swiftui/navigationstack
- https://developer.apple.com/documentation/swiftui/navigationlink
- https://developer.apple.com/documentation/swiftui/navigationpath
- https://developer.apple.com/documentation/swiftui/navigationsplitview
- https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)
