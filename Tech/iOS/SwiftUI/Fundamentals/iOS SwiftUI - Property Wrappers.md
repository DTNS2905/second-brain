---
tags:
  - ios
  - swiftui
  - fundamentals
  - property-wrappers
  - state-management
  - mobile
created: 2026-07-10
source: https://developer.apple.com/documentation/swiftui/state-and-data-flow
---

# iOS SwiftUI - Property Wrappers

> The complete reference for every SwiftUI state and data-flow property wrapper — what each one does, when to use it, and the pitfalls that bite everyone. Link back to [[iOS SwiftUI Fundamentals Guide]].

---

## Prerequisites

This note is the **SwiftUI-specific** catalog. Before reading, understand the underlying Swift language feature:

- [[iOS Swift - Property Wrappers]] — the `@propertyWrapper` mechanic, `wrappedValue`, `projectedValue`, and the `$` sigil.

**Quick refresher:** a property wrapper is a struct annotated `@propertyWrapper` that intercepts read/write of a property. In SwiftUI, these wrappers connect a View (a value type, ephemeral) to storage that survives across re-renders (heap-allocated buckets managed by SwiftUI itself). The wrapper is the bridge.

---

## The `$` Sigil — Projected Value

Every SwiftUI state wrapper exposes two things:

- `foo` — the **wrapped value** (the actual `String`, `Int`, VM, etc.)
- `$foo` — the **projected value** (usually a `Binding<T>` or a `Publisher`)

```swift
@State private var name = ""

TextField("Name", text: $name)   // TextField needs a Binding — $ produces it
Text(name)                        // read the value directly
```

| Wrapper | `$foo` produces |
|---------|-----------------|
| `@State` | `Binding<Value>` |
| `@Binding` | `Binding<Value>` (rebound) |
| `@StateObject` / `@ObservedObject` | `ObservedObject<T>.Wrapper` (subscript for per-property `Binding`) |
| `@Published` | `Publisher<Value, Never>` (Combine) |
| `@Bindable` | Same as `@ObservedObject` — subscript for per-property `Binding` |
| `@FocusState` | `Binding<Value>` |
| `@AppStorage` / `@SceneStorage` | `Binding<Value>` |

**Rule:** whenever a child needs to *mutate* the parent's state, the child takes a `Binding` and the parent passes `$state`.

---

## The Wrappers

### 1. `@State`

**Definition:** view-local storage for a **value type** (Int, String, Bool, struct). Owned by the view. Persists across re-renders as long as the view's identity is stable. Marked `private` by convention because nobody outside the view should reach into it.

**Syntax:**

```swift
@State private var count: Int = 0
```

**Minimal example:**

```swift
struct CounterView: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("\(count)")
            Button("+1") { count += 1 }
        }
    }
}
```

**When to use:**
- Simple UI-only state (toggles, text field text, sheet-presented flags)
- Value types (`Int`, `String`, `Bool`, small `struct`s)
- State that belongs to *this* view and nowhere else

**Pitfalls:**
- ❌ Do not use `@State` for reference types (classes). It stores the reference once and never notices mutations. Use `@StateObject` (or `@State` with `@Observable` on iOS 17+).
- ❌ Do not make `@State` `public` or `internal` — hiding it behind `private` prevents accidental parent access.
- ❌ Do not initialize `@State` from an `init` parameter and expect updates when the parent passes a new value — `@State` is initialized **once per view identity** and ignores later parent-provided initial values. Use `@Binding` or `.id(...)` to reset.

---

### 2. `@Binding`

**Definition:** a **two-way reference** to a source of truth owned somewhere else (usually a parent's `@State`). No storage of its own — reads and writes forward to the source.

**Syntax:**

```swift
@Binding var isOn: Bool
```

**Minimal example:**

```swift
struct ToggleRow: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("Enabled", isOn: $isOn)
    }
}

struct SettingsView: View {
    @State private var enabled = false
    var body: some View {
        ToggleRow(isOn: $enabled)   // pass the projected Binding
    }
}
```

**When to use:**
- A child view needs to mutate the parent's state
- Extracting subviews that both read and write shared state

**Pitfalls:**
- ❌ Do not create a `@Binding` with `.constant(...)` in production code except in Previews — it's non-writable and hides bugs.
- ❌ Passing a raw value instead of `$value` gives a compile error — the type mismatch is your reminder.
- ❌ Do not wrap a `Binding` around a computed property with side effects — SwiftUI will re-evaluate the getter aggressively.

---

### 3. `@StateObject`

**Definition:** view-local storage for a **reference type** conforming to `ObservableObject`. The object is created **once per view identity** and kept alive across parent re-renders. Use this when the view *creates and owns* the object (typically a ViewModel).

**Syntax:**

```swift
@StateObject private var viewModel = UserViewModel()
```

**Minimal example:**

```swift
final class CounterVM: ObservableObject {
    @Published var count = 0
    func increment() { count += 1 }
}

struct CounterView: View {
    @StateObject private var vm = CounterVM()
    var body: some View {
        VStack {
            Text("\(vm.count)")
            Button("+1") { vm.increment() }
        }
    }
}
```

**When to use:**
- The view creates the VM (or any `ObservableObject`)
- The VM must survive across re-renders of the parent
- iOS 13–16, or when interop with `ObservableObject` is required

**Pitfalls:**
- ❌ Do **not** use `@ObservedObject` here — see the dedicated section below.
- ❌ Do not construct expensive dependencies inline every render — use an autoclosure or DI. See [[iOS SwiftUI Architecture - Dependency Injection]].
- ⚠️ On iOS 17+, prefer `@Observable` + `@State` (not `@StateObject`). See the iOS 17+ section below.

---

### 4. `@ObservedObject`

**Definition:** the view **observes** a reference-type `ObservableObject` **passed in from outside**. Does not own it. Does not create it. Simply subscribes to `objectWillChange` and re-renders when it fires.

**Syntax:**

```swift
@ObservedObject var viewModel: UserViewModel
```

**Minimal example:**

```swift
struct UserRow: View {
    @ObservedObject var viewModel: UserRowViewModel   // passed in
    var body: some View {
        Text(viewModel.displayName)
    }
}

struct UserList: View {
    @StateObject private var listVM = UserListViewModel()
    var body: some View {
        ForEach(listVM.rowViewModels) { rowVM in
            UserRow(viewModel: rowVM)                  // parent owns, child observes
        }
    }
}
```

**When to use:**
- Child view receives a VM from a parent
- The child does **not** create the VM

**Pitfalls:**
- ❌ **Never** initialize the VM directly at the declaration site (`@ObservedObject var vm = MyVM()`). Each parent re-render reconstructs the child, recreating the VM, wiping state, cancelling requests. This is the #1 SwiftUI bug — see the dedicated section below.

---

### 5. `@EnvironmentObject`

**Definition:** an `ObservableObject` injected into the view tree by an ancestor via `.environmentObject(...)`. Any descendant can read it without explicit prop-drilling. **Crashes at runtime** if no ancestor provides one.

**Syntax:**

```swift
@EnvironmentObject var session: AuthSession
```

**Minimal example:**

```swift
final class AuthSession: ObservableObject {
    @Published var user: User?
}

@main
struct MyApp: App {
    @StateObject private var session = AuthSession()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(session)
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var session: AuthSession
    var body: some View {
        Text(session.user?.name ?? "Guest")
    }
}
```

**When to use:**
- Truly global-ish state consumed by many deep descendants (auth session, theme, feature flags)
- Avoiding prop-drilling through many layers

**Pitfalls:**
- ❌ Forgetting `.environmentObject(...)` on an ancestor → runtime crash: *"No ObservableObject of type X found."*
- ❌ Using it as a lazy alternative to explicit dependency injection — it hides dependencies and makes tests harder.
- ⚠️ Previews must re-inject: `.environmentObject(AuthSession())` inside `#Preview`.

---

### 6. `@Environment`

**Definition:** read a **value from SwiftUI's environment** — either a built-in system value (color scheme, locale, dismiss action) or a custom `EnvironmentKey`.

**Syntax:**

```swift
@Environment(\.colorScheme) var colorScheme
@Environment(\.dismiss) var dismiss
```

**Minimal example:**

```swift
struct DetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Text(scheme == .dark ? "Dark" : "Light")
            Button("Close") { dismiss() }
        }
    }
}
```

**Custom EnvironmentKey:**

```swift
private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient = LiveAPIClient()
}

extension EnvironmentValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

// Consume
struct MyView: View {
    @Environment(\.apiClient) var api: APIClient
}

// Provide
ContentView().environment(\.apiClient, MockAPIClient())
```

**When to use:**
- Read `dismiss`, `colorScheme`, `locale`, `sizeCategory`, `openURL`, etc.
- Inject value-type dependencies (DI containers, clients) without polluting initializers

**Pitfalls:**
- ❌ Do not use `@Environment` for reference-type observable state — use `@EnvironmentObject` (iOS 13–16) or `@Environment(MyObservable.self)` (iOS 17+).
- ⚠️ Every view that reads an environment value re-renders when that value changes.

---

### 7. `@AppStorage`

**Definition:** a **UserDefaults-backed** persistent value. Reads and writes go through `UserDefaults`. Survives app launches.

**Syntax:**

```swift
@AppStorage("username") var username: String = ""
@AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
```

**Minimal example:**

```swift
struct SettingsView: View {
    @AppStorage("theme") private var theme: String = "system"

    var body: some View {
        Picker("Theme", selection: $theme) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
    }
}
```

**Supported types:** `Bool`, `Int`, `Double`, `String`, `URL`, `Data`, and `RawRepresentable` enums whose raw is one of the above.

**When to use:**
- Small user preferences (theme, opt-ins, last-opened tab)
- One-time flags (has-seen-onboarding)

**Pitfalls:**
- ❌ Do not store secrets — `UserDefaults` is plaintext on disk. Use Keychain via a wrapper.
- ❌ Do not store large blobs or arrays of structs — `UserDefaults` is not a database. Use SwiftData or CoreData.
- ❌ Do not store custom `Codable` structs directly — only the supported primitives work. Encode to `Data` yourself if you must.

---

### 8. `@SceneStorage`

**Definition:** **per-scene state restoration**. Like `@AppStorage` but scoped to the current `Scene` (window on iPad/Mac, single scene on iPhone). Used by the system to restore UI state after termination or across multi-window setups.

**Syntax:**

```swift
@SceneStorage("selectedTab") var selectedTab: Int = 0
```

**Minimal example:**

```swift
struct RootTabView: View {
    @SceneStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView().tag(0)
            ProfileView().tag(1)
        }
    }
}
```

**When to use:**
- Restore transient UI state (selected tab, scroll position, expanded section) after a scene relaunches
- iPad multi-window where each window needs its own state

**Pitfalls:**
- ❌ Do not use for user data — this is UI restoration, not persistence.
- ⚠️ Storage is not guaranteed forever; treat as opportunistic.

---

### 9. `@Bindable` (iOS 17+)

**Definition:** creates `Binding`s to properties of an **`@Observable` class instance** (the new Observation framework macro). Fills the role `@ObservedObject` played for `ObservableObject`.

**Syntax:**

```swift
@Bindable var viewModel: UserViewModel   // where UserViewModel is @Observable
```

**Minimal example:**

```swift
@Observable final class UserViewModel {
    var name: String = ""
    var age: Int = 0
}

struct UserForm: View {
    @Bindable var vm: UserViewModel   // passed in from parent

    var body: some View {
        Form {
            TextField("Name", text: $vm.name)
            Stepper("Age: \(vm.age)", value: $vm.age)
        }
    }
}

struct ParentView: View {
    @State private var vm = UserViewModel()   // @State owns an @Observable class
    var body: some View { UserForm(vm: vm) }
}
```

**When to use:**
- Child views that need `Binding` into an `@Observable` class passed from a parent
- iOS 17+ replacement for `@ObservedObject`

**Pitfalls:**
- ❌ Only works with classes annotated `@Observable`. On `ObservableObject`, use `@ObservedObject`.
- ⚠️ You can also use `@Bindable` inline inside a function body: `@Bindable var vm = vm` to create bindings from a passed-in `@Observable` instance without adding a stored property.

See [[iOS SwiftUI Architecture - Observation Macro]] for the full migration story.

---

### 10. `@FocusState`

**Definition:** tracks which control (usually a `TextField`) currently has **keyboard focus**. Bind fields to focus states with `.focused(...)` and read/write to programmatically move focus.

**Syntax:**

```swift
@FocusState private var focusedField: Field?

enum Field { case email, password }
```

**Minimal example:**

```swift
struct LoginForm: View {
    enum Field { case email, password }

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .focused($focus, equals: .email)
            SecureField("Password", text: $password)
                .focused($focus, equals: .password)
            Button("Sign in") { focus = nil }        // dismiss keyboard
        }
        .onAppear { focus = .email }                  // autofocus
        .onSubmit {
            if focus == .email { focus = .password }
        }
    }
}
```

**Two flavors:**

```swift
@FocusState private var isFocused: Bool                  // single field
@FocusState private var focusedField: Field?             // multiple fields via enum
```

**When to use:**
- Autofocus a field on appear
- "Next" behavior across form fields
- Programmatically dismiss the keyboard (`focus = nil`)

**Pitfalls:**
- ❌ Do not read `@FocusState` from outside the view — it's local. If a VM needs to control focus, pass a `Binding` or use a value the VM owns and a `.onChange` hop.
- ⚠️ Available iOS 15+.

---

### 11. `@FetchRequest`

**Definition:** declaratively fetches results from a **Core Data** managed object context and re-runs on any relevant change.

**Syntax:**

```swift
@FetchRequest(
    sortDescriptors: [SortDescriptor(\Item.timestamp, order: .reverse)]
) private var items: FetchedResults<Item>
```

**Minimal example:**

```swift
struct ItemsList: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\.timestamp)])
    private var items: FetchedResults<Item>

    var body: some View {
        List(items) { item in Text(item.title ?? "") }
    }
}
```

**When to use:**
- Legacy Core Data apps
- Need mature migration tooling and `NSPersistentCloudKitContainer`

**Pitfalls:**
- ❌ Requires a `\.managedObjectContext` injected into the environment.
- ⚠️ On iOS 17+, new code should prefer SwiftData and `@Query`. See [[iOS SwiftUI - SwiftData]].

---

### 12. `@Query` (iOS 17+)

**Definition:** the SwiftData analogue of `@FetchRequest`. Declaratively queries a `ModelContext` for `@Model`-annotated types and re-runs on change.

**Syntax:**

```swift
@Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
```

**Minimal example:**

```swift
@Model final class Item {
    var title: String
    var timestamp: Date
    init(title: String, timestamp: Date = .now) {
        self.title = title
        self.timestamp = timestamp
    }
}

struct ItemsList: View {
    @Query(sort: \Item.timestamp) private var items: [Item]
    var body: some View {
        List(items) { Text($0.title) }
    }
}
```

**When to use:**
- iOS 17+ apps starting fresh with SwiftData
- Any view that needs a live-updating collection of persisted models

**Pitfalls:**
- ❌ Requires a `ModelContainer` set on an ancestor via `.modelContainer(for: Item.self)`.
- ⚠️ Predicate syntax is powerful but has sharp edges — see [[iOS SwiftUI - SwiftData]].

---

## Decision Table

| I want to... | Use this wrapper |
|--------------|------------------|
| Store a `Bool`/`Int`/`String` local to one view | `@State` |
| Let a child view mutate my `@State` | Pass `$state`, child uses `@Binding` |
| Own a ViewModel (`ObservableObject`) in a view | `@StateObject` (iOS 13–16) |
| Own a VM (`@Observable`) in a view | `@State` + `@Observable` class (iOS 17+) |
| Receive a VM from a parent (`ObservableObject`) | `@ObservedObject` |
| Receive a VM from a parent (`@Observable`) | `@Bindable` (iOS 17+) |
| Access a VM anywhere in the tree without prop-drilling | `@EnvironmentObject` / `@Environment(MyType.self)` |
| Read `colorScheme` / `dismiss` / `locale` | `@Environment(\.keyPath)` |
| Inject a value-type dependency (client, config) | `@Environment` + custom `EnvironmentKey` |
| Persist a small user preference across launches | `@AppStorage` |
| Restore UI state per scene / per window | `@SceneStorage` |
| Track / control keyboard focus | `@FocusState` |
| Query Core Data | `@FetchRequest` |
| Query SwiftData | `@Query` (iOS 17+) |

---

## `@StateObject` vs `@ObservedObject` Pitfall

**The classic bug.** Every SwiftUI developer hits this once.

```swift
// ❌ BROKEN
struct CounterView: View {
    @ObservedObject var vm = CounterVM()

    var body: some View {
        VStack {
            Text("\(vm.count)")
            Button("+1") { vm.count += 1 }
        }
    }
}
```

**Why it's broken:** `@ObservedObject` **does not own** the object. `CounterView` is a `struct` — when its parent re-renders, it is reconstructed, which re-runs `CounterVM()` in the property initializer. A **brand new** VM instance is created. The old one (with your count) is discarded. Any in-flight network requests are cancelled. State appears to "reset" seemingly at random.

The bug is silent until something triggers a parent re-render — a `@State` toggle upstream, an `@EnvironmentObject` change, anything.

```swift
// ✅ CORRECT
struct CounterView: View {
    @StateObject private var vm = CounterVM()

    var body: some View {
        VStack {
            Text("\(vm.count)")
            Button("+1") { vm.count += 1 }
        }
    }
}
```

`@StateObject` initializes the VM **once per view identity** and holds it alive across parent re-renders. The initializer expression is only evaluated the first time.

### The Rule

| The VM was... | Use |
|---------------|-----|
| Created by *this* view | `@StateObject` |
| Passed in from a parent | `@ObservedObject` (or `@Bindable` on iOS 17+) |
| Injected from far up the tree | `@EnvironmentObject` |

**Mnemonic:** *"State owns, Observed borrows, Environment steals from the ancestors."*

---

## iOS 17+ Modern Style

Apple introduced the **Observation framework** in iOS 17. Prefer it over `ObservableObject` for all new code.

### Before (iOS 13–16)

```swift
final class ProfileVM: ObservableObject {
    @Published var name: String = ""
    @Published var age: Int = 0
    @Published private(set) var isLoading = false
}

struct ProfileView: View {
    @StateObject private var vm = ProfileVM()
    var body: some View {
        Form {
            TextField("Name", text: $vm.name)
            Stepper("Age: \(vm.age)", value: $vm.age)
        }
    }
}
```

### After (iOS 17+)

```swift
@Observable final class ProfileVM {
    var name: String = ""
    var age: Int = 0
    private(set) var isLoading = false
}

struct ProfileView: View {
    @State private var vm = ProfileVM()          // @State, not @StateObject
    var body: some View {
        @Bindable var vm = vm                     // create bindings inline
        Form {
            TextField("Name", text: $vm.name)
            Stepper("Age: \(vm.age)", value: $vm.age)
        }
    }
}
```

**What changed:**

| Legacy (iOS 13–16) | Modern (iOS 17+) |
|--------------------|------------------|
| `class Foo: ObservableObject` | `@Observable final class Foo` |
| `@Published var name` | `var name` (no attribute) |
| `@StateObject var vm` | `@State var vm` |
| `@ObservedObject var vm` | `@Bindable var vm` (when bindings needed) or just `var vm` |
| `@EnvironmentObject var vm` | `@Environment(Foo.self) var vm` |

**Why it's better:**
- **Granular invalidation** — SwiftUI re-renders only views that read the specific property that changed, not every observer of the whole object.
- **Fewer wrappers to remember** — `@State` covers both value and reference types (paired with `@Observable`).
- **No `@Published`** — every stored property is observable by default.

**When to stick with `ObservableObject`:**
- Deployment target still includes iOS 13–16
- Interop with Combine pipelines you already have (see [[iOS SwiftUI Architecture - MVVM with Combine]])

See [[iOS SwiftUI Architecture - Observation Macro]] for the full migration walkthrough.

---

## Summary

| Wrapper | Storage | Owner | Value or Reference | Use For |
|---------|---------|-------|--------------------|---------|
| `@State` | View-local | View | Value | Local UI state |
| `@Binding` | Parent | Parent (borrowed) | Value | Child mutates parent state |
| `@StateObject` | View-local | View | Reference (`ObservableObject`) | View owns VM (iOS 13–16) |
| `@ObservedObject` | External | Parent | Reference (`ObservableObject`) | Child observes parent VM |
| `@EnvironmentObject` | Ancestor | Ancestor | Reference (`ObservableObject`) | Deep-tree shared VM |
| `@Environment` | Environment | System / ancestor | Any | System values, DI |
| `@AppStorage` | UserDefaults | System | Value | Persistent prefs |
| `@SceneStorage` | Scene | System | Value | Per-scene UI restoration |
| `@Bindable` | External | Parent | Reference (`@Observable`) | Child bindings (iOS 17+) |
| `@FocusState` | View-local | View | Value | Keyboard focus |
| `@FetchRequest` | Core Data | System | Reference | Core Data query |
| `@Query` | SwiftData | System | Reference | SwiftData query (iOS 17+) |

### Golden Rules

| ✅ Do | ❌ Don't |
|------|---------|
| `@State private var` for value types owned by the view | `@State` for classes (use `@StateObject` or `@Observable` + `@State`) |
| `@StateObject` when the view creates the VM | `@ObservedObject var vm = MyVM()` (recreated every render) |
| `@ObservedObject` (or `@Bindable`) only for VMs passed in | Prop-drill VMs 4+ levels — use `@EnvironmentObject` |
| Pass `$state` to give a child a `Binding` | Read `.constant(...)` outside of Previews |
| Prefer `@Observable` + `@State` on iOS 17+ | Reach for `ObservableObject` by default on new code |
| Use `@AppStorage` for small preferences | Store secrets in `@AppStorage` (plaintext) |
| Use custom `EnvironmentKey` for value-type DI | Use `@EnvironmentObject` as a hidden singleton |

---

## Related

- [[iOS SwiftUI Fundamentals Guide]] — the topic index
- [[iOS SwiftUI - Core Concepts]] — declarative model, view identity, environment
- [[iOS SwiftUI - Core Components]] — the building blocks (`Text`, `List`, `TabView`, ...)
- [[iOS SwiftUI - Lifecycle]] — `.task`, `.onAppear`, `.onChange`
- [[iOS SwiftUI Architecture - MVVM with Combine]] — how these wrappers glue MVVM together
- [[iOS SwiftUI Architecture - Observation Macro]] — the iOS 17+ replacement for `ObservableObject`
- [[iOS Swift - Property Wrappers]] — the underlying language mechanic
- [[iOS SwiftUI - SwiftData]] — `@Query` in depth

---

## Apple Docs

- State and data flow overview: https://developer.apple.com/documentation/swiftui/state-and-data-flow
- `@State`: https://developer.apple.com/documentation/swiftui/state
- `@Binding`: https://developer.apple.com/documentation/swiftui/binding
- `@StateObject`: https://developer.apple.com/documentation/swiftui/stateobject
- `@ObservedObject`: https://developer.apple.com/documentation/swiftui/observedobject
- `@EnvironmentObject`: https://developer.apple.com/documentation/swiftui/environmentobject
- `@Environment`: https://developer.apple.com/documentation/swiftui/environment
- `@AppStorage`: https://developer.apple.com/documentation/swiftui/appstorage
- `@Bindable`: https://developer.apple.com/documentation/swiftui/bindable
- `@FocusState`: https://developer.apple.com/documentation/swiftui/focusstate
