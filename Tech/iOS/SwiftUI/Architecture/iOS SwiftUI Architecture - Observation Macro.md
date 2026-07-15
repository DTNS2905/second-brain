---
tags:
  - ios
  - swiftui
  - observation
  - observable
  - mvvm
  - ios17
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
apple_docs:
  - https://developer.apple.com/documentation/observation
  - https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
  - https://developer.apple.com/documentation/observation/observable()
  - https://developer.apple.com/documentation/swiftui/bindable
---

# iOS SwiftUI Architecture - Observation Macro

> `@Observable` (iOS 17+) is the modern replacement for `ObservableObject` + `@Published`. Fewer property wrappers, better performance, no Combine dependency. Link back to [[iOS SwiftUI Architecture Guide]].

---

## What Changed

Apple introduced the `Observation` framework and the `@Observable` macro in iOS 17. It replaces the `ObservableObject` protocol with a macro that tracks property access **at the read site**, not the write site.

**Result:** SwiftUI re-renders only the views that read the properties that actually changed — not every view observing the object.

---

## Migration Cheat Sheet

| Before (iOS 13–16) | After (iOS 17+) |
|--------------------|-----------------|
| `class VM: ObservableObject` | `@Observable class VM` |
| `@Published var users: [User]` | `var users: [User]` |
| `@StateObject var vm = VM()` | `@State var vm = VM()` |
| `@ObservedObject var vm: VM` | plain `var vm: VM` |
| `@EnvironmentObject var vm: VM` | `@Environment(VM.self) var vm` |
| `.environmentObject(vm)` | `.environment(vm)` |

---

## Before/After Example

### Before (iOS 13–16)

```swift
final class UserListViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
}

struct UserListView: View {
    @StateObject private var viewModel = UserListViewModel(...)
    var body: some View {
        List(viewModel.users) { UserRow(user: $0) }
    }
}
```

### After (iOS 17+)

```swift
@Observable
final class UserListViewModel {
    var users: [User] = []
    var isLoading = false
    var errorMessage: String?
}

struct UserListView: View {
    @State private var viewModel = UserListViewModel(...)
    var body: some View {
        List(viewModel.users) { UserRow(user: $0) }
    }
}
```

**What went away:** `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `objectWillChange`.

---

## Performance: Granular Tracking

`ObservableObject` fires `objectWillChange` when **any** `@Published` property changes. Every view observing the object re-renders.

`@Observable` uses per-property access tracking:

```swift
@Observable class VM {
    var users: [User] = []
    var isLoading = false
}

struct HeaderView: View {
    let vm: VM
    var body: some View {
        Text("Loading: \(vm.isLoading ? "yes" : "no")")  // only reads isLoading
    }
    // ↑ Only re-renders when isLoading changes.
    //   Under ObservableObject it would ALSO re-render when users changed.
}
```

For dashboards with many small views observing one big VM, this is a real perf win.

---

## Two-Way Binding: `@Bindable`

With `@Observable`, you can't use `$` on a plain property. Use `@Bindable` when you need `Binding<T>`:

```swift
struct LoginView: View {
    @Bindable var vm: LoginViewModel   // NEW — for read/write bindings
    var body: some View {
        TextField("Email", text: $vm.email)     // works via @Bindable
    }
}
```

Or inline: `@Bindable var vm = vm` at the top of the body.

| Wrapper | Purpose |
|---------|---------|
| `@State` | Owning declaration of an `@Observable` object in a view |
| `@Bindable` | Producing `Binding<T>` from an `@Observable`'s properties |
| `@Environment(Type.self)` | Reading an ancestor-provided `@Observable` |

---

## Environment Injection

### Old

```swift
struct RootView: View {
    @StateObject var session = Session()
    var body: some View {
        ChildView().environmentObject(session)
    }
}
struct ChildView: View {
    @EnvironmentObject var session: Session
    ...
}
```

### New

```swift
struct RootView: View {
    @State var session = Session()   // @Observable Session
    var body: some View {
        ChildView().environment(session)
    }
}
struct ChildView: View {
    @Environment(Session.self) var session
    ...
}
```

Type-safer than `@EnvironmentObject` — the type is a static parameter, not inferred from the class name.

---

## Combine Still Works — But You Rarely Need `@Published`

`@Observable` doesn't include `@Published`'s publisher-per-property behavior. If you need to observe a property as a Combine `Publisher`, use:

```swift
withObservationTracking {
    _ = viewModel.users    // access to trigger tracking
} onChange: {
    print("users changed")
}
```

Or bridge to `AsyncStream` / SwiftUI's `onChange(of:)`. In practice: for **UI reactivity**, drop Combine; for **async pipelines** (search debouncing, network chains), keep Combine (or move to `async/await`).

See [[iOS SwiftUI Architecture - Combine Operators]] for where Combine still shines.

---

## MVVM with `@Observable`

Clean Architecture + MVVM doesn't change — only the ViewModel's syntax:

```swift
@Observable
@MainActor
final class UserListViewModel {
    private(set) var users: [User] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let fetchUsers: FetchUsersUseCase
    private var task: Task<Void, Never>?

    init(fetchUsers: FetchUsersUseCase) { self.fetchUsers = fetchUsers }

    func load() {
        task?.cancel()
        task = Task {
            isLoading = true
            defer { isLoading = false }
            do {
                users = try await fetchUsers.execute()   // async/await variant of UseCase
            } catch {
                errorMessage = "Something went wrong."
            }
        }
    }
}
```

**Pairs naturally with `async/await`.** The Combine `cancellables` bag is replaced by `Task` cancellation.

---

## When To Migrate

| Situation | Recommendation |
|-----------|----------------|
| iOS 17+ deployment target | ✅ Use `@Observable` from day one |
| Mixed iOS 16 / 17 support | Stick with `ObservableObject` for now — mixing is possible but adds friction |
| Existing large `ObservableObject` codebase | Migrate leaf views first, work upward; the two coexist |
| Perf issue: too many re-renders from a shared VM | ✅ `@Observable` is the fix |

---

## Anti-Patterns / Migration Gotchas

### ❌ Forgetting the `@State` change

```swift
// ❌ Under @Observable, @StateObject fails to compile / behaves oddly
struct View: View {
    @StateObject var vm = MyObservableVM()
}
```

```swift
// ✅ @State is the new owner
struct View: View {
    @State var vm = MyObservableVM()
}
```

### ❌ Trying to use `$vm.property` directly

```swift
// ❌ compile error — no property projection on plain @Observable var
TextField("x", text: $vm.name)
```

```swift
// ✅ Introduce @Bindable
@Bindable var vm: VM
TextField("x", text: $vm.name)
```

### ❌ Adding `@Published` inside `@Observable`

```swift
@Observable class VM {
    @Published var users: [User] = []   // ❌ contradicts the macro
}
```

`@Observable` handles tracking; `@Published` is unnecessary (and technically incompatible with the macro's synthesis).

---

## Summary

| ✅ Do (iOS 17+) | ❌ Don't |
|-----------------|---------|
| `@Observable class VM` | `class VM: ObservableObject` |
| `@State var vm = VM()` | `@StateObject var vm` |
| `@Bindable var vm: VM` for `Binding<T>` | Reach for `$vm.field` on a plain var |
| `@Environment(VM.self)` | `@EnvironmentObject var vm: VM` |
| Combine only for async pipelines | Combine as the required reactivity layer |

---

## Apple Docs (Primary References)

- Observation framework: https://developer.apple.com/documentation/observation
- `@Observable` macro: https://developer.apple.com/documentation/observation/observable()
- **Migration guide (canonical):** https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
- `@Bindable`: https://developer.apple.com/documentation/swiftui/bindable
- WWDC23 "Discover Observation in SwiftUI": https://developer.apple.com/videos/play/wwdc2023/10149/

> Apple, on why to migrate: "Views update based on changes to the observable properties that a view's body reads instead of any property changes that occur to an observable object, which can help improve your app's performance." — this is the granular-tracking claim in the [Performance section](#performance-granular-tracking) above.

**Availability:** iOS 17.0+ / iPadOS 17.0+ / macOS 14.0+ / watchOS 10.0+ / tvOS 17.0+.

---

## Related

- [[iOS SwiftUI Architecture - MVVM with Combine]] — the pre-iOS-17 pattern still valid on older targets
- [[iOS SwiftUI Architecture - Presentation Layer]] — where these wrappers live
- [[iOS SwiftUI Architecture Guide]] — top-level index
