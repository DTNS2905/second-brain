---
tags:
  - ios
  - swiftui
  - lifecycle
  - fundamentals
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/swiftui/app
---

# iOS SwiftUI — Lifecycle

> Three nested layers — **App → Scene → View** — plus the state-wrapper lifetimes woven through them. Back to index: [[iOS SwiftUI Fundamentals Guide]].

---

## The Three Nested Layers

```
┌───────────────────────────────────────────────────┐
│  App          @main struct MyApp: App             │  process-lifetime, one instance
│  ┌─────────────────────────────────────────────┐  │
│  │  Scene    WindowGroup / DocumentGroup / …   │  │  one per window/session
│  │  ┌───────────────────────────────────────┐  │  │
│  │  │  View   body → body → body → …        │  │  │  identity-scoped, re-runs often
│  │  │         @State, @Observable, .task    │  │  │
│  │  └───────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

Each layer has its **own** lifecycle rules. Confusing them is the #1 SwiftUI beginner trap.

---

## 1. App Lifecycle

```swift
@main
struct CountriesAppApp: App {
    init() {
        print("App init — process just started")
    }

    var body: some Scene {
        WindowGroup {
            CountriesListView(viewModel: DIContainer.live.makeCountriesViewModel())
        }
    }
}
```

- `App` is instantiated **once per process launch**. `init()` runs before any UI is drawn.
- The `body` returns a `Scene` (or a composition of scenes). Scenes are the top-level containers the system schedules.
- `@main` is the entry point — replaces UIKit's `AppDelegate` + `main.swift` pair.

### App-level dependencies

`init()` is the natural place to build your DI container, register logging, load feature flags, or configure `URLSession`. Anything you'd have done in `application(_:didFinishLaunchingWithOptions:)` in UIKit lives here or in an `.onAppear` on the root scene.

### Bridge to UIKit `AppDelegate`

If you need `AppDelegate` callbacks (push notification tokens, Firebase config), use `@UIApplicationDelegateAdaptor`:

```swift
@main
struct CountriesAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene { … }
}
```

Apple docs: https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor

---

## 2. Scene Lifecycle

A **Scene** is a self-contained UI unit the system can present, hide, or dispose of independently. On iPhone the app has one visible scene at a time. On iPad, multiple. On Mac, each window is a scene.

### Built-in scene types

| Type | Use for |
|------|---------|
| `WindowGroup` | Standard app content; the default choice |
| `DocumentGroup` | Document-based apps (iOS/macOS `.txt`, `.pdf`, etc.) |
| `Settings` | macOS Settings window (auto-hooked to `⌘,`) |
| `MenuBarExtra` | macOS menu bar apps |
| `Window` | macOS single-instance secondary windows |

### `ScenePhase` — the *runtime* state of a scene

```swift
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Text("Hello")
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:     print("Visible and interactive")
                case .inactive:   print("Visible but not receiving input (multitasking preview, incoming call)")
                case .background: print("No longer visible; save state now")
                @unknown default: break
                }
            }
    }
}
```

**When to use each phase:**

| Phase | Use for |
|-------|---------|
| `.active` | Resume timers, restart streams, unblur sensitive content |
| `.inactive` | Blur content in the app switcher (privacy), pause games |
| `.background` | Persist unsaved state, cancel network work, snapshot data |

Apple docs: https://developer.apple.com/documentation/swiftui/scenephase

---

## 3. View Lifecycle

This is where SwiftUI differs most from UIKit — and where most people trip.

> **Views are not long-lived objects. They're lightweight value descriptions that SwiftUI creates, compares, and discards constantly. What persists is the *identity* SwiftUI assigns to a view position, and the state boxes tied to that identity.**

Read [[iOS SwiftUI - Core Concepts]] on identity if that sentence is fuzzy.

### The `body` recomputation cycle

```
State changes → View invalidated → body re-runs → new tree
                                          │
                                          ▼
                        SwiftUI diffs against previous tree
                                          │
                                          ▼
                                 Applies minimal updates
                                 to the render layer
```

`body` runs **many, many times** during an app session. Do not:

- Print / log inside `body` (you'll flood the console).
- Do heavy work in `body` (network, decoding, expensive computation).
- Start timers, subscribe to publishers, or fire side effects in `body`.

Side effects belong in `.task`, `.onAppear`, or `.onChange` — see below.

### `.onAppear` and `.onDisappear`

```swift
Text("Hi")
    .onAppear { print("Attached to screen") }
    .onDisappear { print("Detached from screen") }
```

- **`.onAppear`** fires when the view is added to the hierarchy.
- **`.onDisappear`** fires when it's removed.

Caveats:

- Neither is guaranteed to be exactly-once per user-visible appearance. A view in a `TabView` that's off-screen but *already loaded* may not fire `.onAppear` again when you tab back.
- They fire **synchronously** on the main actor. Don't block them.

### `.task` — the modern replacement

```swift
Text("Loading…")
    .task {
        await viewModel.load()   // async work here
    }
```

- Runs an `async` closure when the view appears, on the main actor by default.
- **Cancelled automatically** when the view disappears — Swift Structured Concurrency propagates the cancellation.
- Prefer over `.onAppear { Task { … } }` — the `Task { }` variant leaks work if the view disappears mid-flight.

### `.task(id:)` — re-fires on ID change

```swift
Text(user.name)
    .task(id: user.id) {
        await loadDetails(for: user.id)
    }
```

Runs on appear **and** whenever `id` changes. The old task is cancelled first. Use for parameterized fetches (detail screens keyed by an ID).

Apple docs:
- `.onAppear`: https://developer.apple.com/documentation/swiftui/view/onappear(perform:)
- `.task`: https://developer.apple.com/documentation/swiftui/view/task(priority:_:)
- `.task(id:)`: https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:)

### `.onChange` — react to any value change

```swift
Text(input)
    .onChange(of: input) { oldValue, newValue in
        print("Changed from \(oldValue) to \(newValue)")
    }
```

- iOS 17+ signature has both old and new value. Pre-17 has only new.
- Fires **after** `body` completes, so you can safely update other state.

---

## 4. State-Wrapper Lifetimes

Each state wrapper has a different rule for when its stored value is created and destroyed.

| Wrapper | Created | Destroyed | Notes |
|---------|---------|-----------|-------|
| `@State` | First time view identity appears | View identity leaves the hierarchy | Value type; SwiftUI owns it |
| `@Binding` | N/A (proxy to another source) | N/A | Just a pointer |
| `@StateObject` (iOS 14–16) | First appearance, once per identity | Identity leaves | Reference type; single instance across body re-runs |
| `@ObservedObject` (iOS 14–16) | Caller controls | Caller controls | You inject it; SwiftUI does *not* own the lifetime |
| `@State` on `@Observable` (iOS 17+) | Same as `@State` | Same as `@State` | Modern replacement for `@StateObject` — see [[iOS SwiftUI Architecture - Observation Macro]] |
| `@Bindable` (iOS 17+) | N/A (proxy) | N/A | Give a caller-injected `@Observable` `$binding` access |
| `@Environment(\.foo)` | Injected upstream | N/A | Value flows down the tree |
| `@AppStorage` / `@SceneStorage` | App-lifetime / Scene-lifetime | App/scene teardown | Persisted, not just in memory |

### The single most important rule

> **`@State` and `@StateObject` are tied to the view's *identity*, not the view *struct instance*.**

The struct is thrown away every body re-run. The state box lives in a separate side table keyed by identity. This is why `@State private var count = 0` doesn't reset to `0` every time `body` runs — SwiftUI looks up the box by identity, not by "did the struct just get constructed."

Change the identity (e.g., wrap the view in a conditional branch that swaps between two `if`/`else` paths, or apply `.id(newID)`), and SwiftUI treats it as a **different view** — the old state is destroyed, a new box is created.

### `.id(_:)` as a lifecycle scalpel

```swift
CountryDetailView(country: current)
    .id(current.id)   // when current.id changes, tear down + rebuild
```

- Old view's `@State`, `@StateObject`, `.task`, timers, and subscriptions are **all destroyed**.
- New view starts from scratch.
- Use sparingly — it's a big hammer. Great for "reset this whole screen when the underlying record changes."

---

## 5. Bridge — UIKit `UIViewController` Lifecycle

Coming from UIKit? Rough mental map:

| UIKit callback | SwiftUI equivalent | Notes |
|----------------|-------------------|-------|
| `init()` (VC) | View struct `init` | Runs constantly — do not treat as one-off |
| `loadView()` | `body` | Same "describe the UI" purpose |
| `viewDidLoad()` | Nothing exactly — closest is `@State`'s initial value | Views don't have a one-shot load hook |
| `viewWillAppear` | *No direct equivalent* | Often merged into `.onAppear`; use `.task` for async |
| `viewDidAppear` | `.onAppear` | But **may fire more than once** in edge cases |
| `viewWillDisappear` | *No direct equivalent* | Merged into `.onDisappear` |
| `viewDidDisappear` | `.onDisappear` | Same caveat as `.onAppear` |
| `deinit` | View identity leaving → state destroyed | You don't "own" a view instance to `deinit` |

**Biggest mental shift:** UIKit's lifecycle callbacks were about *this one instance*. SwiftUI's are about *view identity in the tree*. `body` re-running is not "the view is being re-created" — the view struct is cheap; the *state* survives.

---

## 6. Common Gotchas

### "My timer keeps running after I navigate away"

You started it in `.onAppear { Timer.scheduledTimer(...) }` without capturing a reference to invalidate on `.onDisappear`. Better: use `.task` with an `async` loop — cancellation is automatic.

```swift
.task {
    while !Task.isCancelled {
        await tick()
        try? await Task.sleep(for: .seconds(1))
    }
}
```

### "My `@StateObject` initializer runs every body re-render"

You wrote `@StateObject var vm = ViewModel(dependency: someExpensiveThing())` and `someExpensiveThing()` gets called every render. Swift evaluates the *default expression* every time the struct init is called, but SwiftUI **discards the second and later results** — the box is populated only once. Still, evaluating the expression is wasteful.

Fix: hide the expression behind an `@autoclosure` factory, or use the `@State` + `@Observable` pattern (iOS 17+) with the init trick from [[iOS Tutorial - Part 4 Domain Layer]].

### "My `.onAppear` fires twice"

Common in `NavigationStack` with `.navigationDestination`. If your view is added, removed, and re-added (list scrolls it out of view then back in), `.onAppear` fires each time. Use `@State private var didLoad = false` guard, or move to `.task(id:)`.

### "My view resets state when I navigate back"

You wrapped it in an `if let user = user` conditional. The `if` branch creates a *different view identity* each time `user` toggles between nil and non-nil. Either lift the `@State` up to the parent, or restructure so the branch doesn't cross identity boundaries.

### "`body` runs constantly — is that bad?"

No. SwiftUI is designed for it. Views are structs; `body` is expected to be cheap and pure. What you *must not* do: put side effects, network calls, or logging inside `body`. Move those to `.task`, `.onAppear`, `.onChange`.

---

## 7. Ordering — What Fires When

For a top-level view appearing on screen after a fresh launch:

```
1. App.init                                (once per process)
2. Scene body evaluated                    (constructing WindowGroup)
3. Root View struct init                   (view value created)
4. Root View body evaluated                (first render tree)
5. State boxes allocated (first time)      (@State / @StateObject storage)
6. UIKit hosting attaches views to window
7. .onAppear fires                          (view is now on screen)
8. .task closure starts                     (concurrent with .onAppear)
9. @Environment(\.scenePhase) → .active     (scene fully active)
```

For a state-driven re-render mid-session:

```
1. State changes (e.g., @Observable property mutation)
2. SwiftUI invalidates every view that read that property
3. Each invalidated View struct re-inits + body re-runs
4. SwiftUI diffs new tree vs old
5. Only changed nodes update in the render layer
6. .onChange handlers fire (post-body)
```

---

## Apple Docs — Primary References

| Topic | URL |
|-------|-----|
| `App` protocol | https://developer.apple.com/documentation/swiftui/app |
| `Scene` protocol | https://developer.apple.com/documentation/swiftui/scene |
| `WindowGroup` | https://developer.apple.com/documentation/swiftui/windowgroup |
| `ScenePhase` | https://developer.apple.com/documentation/swiftui/scenephase |
| `@Environment(\.scenePhase)` | https://developer.apple.com/documentation/swiftui/environmentvalues/scenephase |
| View lifecycle events | https://developer.apple.com/documentation/swiftui/view-lifecycle |
| `.onAppear(perform:)` | https://developer.apple.com/documentation/swiftui/view/onappear(perform:) |
| `.task(priority:_:)` | https://developer.apple.com/documentation/swiftui/view/task(priority:_:) |
| `.task(id:priority:_:)` | https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:) |
| `.onChange(of:_:)` | https://developer.apple.com/documentation/swiftui/view/onchange(of:_:) |
| `@UIApplicationDelegateAdaptor` | https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor |
| Managing model data | https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app |

---

## Related Notes

- [[iOS SwiftUI - Core Concepts]] — identity, `body` as function of state, layout
- [[iOS SwiftUI - Core Components]] — the views and modifiers referenced above
- [[iOS SwiftUI Architecture - Observation Macro]] — the modern `@Observable` state model
- [[iOS SwiftUI Architecture - MVVM with Combine]] — legacy `@StateObject` + `@Published`
- [[iOS Tutorial - Part 3 MVVM ViewModel]] — practical `@State` + `@Observable` usage
- [[iOS Tutorial Guide]] — hands-on path that uses everything on this page
