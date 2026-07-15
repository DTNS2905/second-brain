---
tags:
  - ios
  - swiftui
  - fundamentals
  - view-protocol
  - viewbuilder
  - layout
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/swiftui/view
apple_docs:
  - https://developer.apple.com/documentation/swiftui/view
  - https://developer.apple.com/documentation/swiftui/view-fundamentals
  - https://developer.apple.com/documentation/swiftui/layout-fundamentals
  - https://developer.apple.com/documentation/swiftui/viewbuilder
  - https://developer.apple.com/documentation/swiftui/environment
---

# iOS SwiftUI - Core Concepts

> The mental model behind SwiftUI: what a `View` really is, how the tree is built, how layout is negotiated, and why modifier order matters. Link back to [[iOS SwiftUI Fundamentals Guide]].

---

## 1. Declarative, Not Imperative

**Imperative (UIKit):**

```swift
let label = UILabel()
label.text = "Hello"
label.textColor = .blue
label.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(label)
NSLayoutConstraint.activate([
    label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
])
```

**Declarative (SwiftUI):**

```swift
Text("Hello")
    .foregroundStyle(.blue)
```

You describe the **end state** for the current data. SwiftUI figures out the diff and applies it. No `addSubview`, no manual constraints, no `viewDidLoad`.

---

## 2. `View` Is a Value, Not an Object

`View` is a **protocol**, and almost every conforming type is a **`struct`** (value type):

```swift
struct Greeting: View {
    let name: String
    var body: some View {
        Text("Hello, \(name)")
    }
}
```

**Implications:**
- Views are cheap to create and destroy — SwiftUI recreates them on every state change.
- They live in the SwiftUI graph as descriptions, not heap objects.
- Identity is not tied to object identity — see [section 6](#6-view-identity).

---

## 3. The `View` Protocol

```swift
public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Self.Body { get }
}
```

Two rules:
1. Every `View` returns a `body` that is itself a `View`.
2. The recursion stops at **primitive views** (`Text`, `Image`, `Color`, `Shape`, empty views) whose `Body` type is `Never`.

```
CustomView.body → HStack.body → Text (primitive, terminal)
```

---

## 4. `some View` — Opaque Return Type

```swift
var body: some View { ... }
```

`some View` says: **"a specific concrete type that conforms to View, chosen by the compiler and hidden from the caller."**

Why not just write `View`?

```swift
var body: View { ... }   // ❌ compile error — View has associated types
```

Protocols with associated types (`Body`) can't be used as existentials directly. `some View` is Swift's answer — a **compile-time-fixed type** you don't have to spell out.

**The concrete type gets huge:**

```swift
var body: some View {
    VStack {
        Text("a").padding()
        Text("b").background(.red)
    }
}
// Real return type:
// VStack<TupleView<(ModifiedContent<Text, _PaddingLayout>,
//                   ModifiedContent<Text, _BackgroundStyleModifier<Color>>)>>
```

You don't type that. `some View` erases it.

### `some View` vs `AnyView`

| | `some View` | `AnyView` |
|---|-------------|-----------|
| Type known at | compile time | runtime |
| Perf | ✅ fast, SwiftUI can diff efficiently | ⚠️ type-erased, defeats structural diffing |
| Use when | almost always | Heterogeneous view arrays where types differ per branch |

**Rule of thumb:** reach for `AnyView` only when you truly can't type the branches (rare). Prefer `Group` / `@ViewBuilder if/else` instead.

---

## 5. `@ViewBuilder` and Result Builders

The compiler auto-wraps `body` in `@ViewBuilder`, a **result builder** that turns statement lists into a single composite `View`:

```swift
var body: some View {
    Text("a")
    Text("b")
    Text("c")
}
// Rewritten by @ViewBuilder to:
// TupleView(Text("a"), Text("b"), Text("c"))
```

**`@ViewBuilder` supports control flow:**

| Statement | Compiles to |
|-----------|-------------|
| Sequence of views | `TupleView<(V1, V2, …)>` (max 10 children) |
| `if condition { A }` | `Optional<A>` |
| `if/else { A } else { B }` | `_ConditionalContent<A, B>` |
| `switch` | `_ConditionalContent<…>` chain |
| `ForEach(items) { … }` | Dynamic — different (not a `@ViewBuilder` construct) |

**Custom container that takes a `@ViewBuilder`:**

```swift
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding().background(.gray.opacity(0.1))
    }
}

Card {
    Text("Title")
    Text("Subtitle")
}
```

---

## 6. View Identity

SwiftUI diffs the view tree between renders. To do so, every view needs an **identity** — an answer to "is this the same view I saw last time, or a new one?"

### Structural Identity (Implicit, Default)

Position in the view tree = identity. Two `Text` views at the same spot in `body` are considered the same view across renders → SwiftUI updates them in place (animating changes).

```swift
if condition {
    Text("Hello")       // identity 1
} else {
    Text("Goodbye")     // identity 2 — DIFFERENT view (branch changed)
}
```

Even though both are `Text`, the `if`/`else` branches produce distinct identities via `_ConditionalContent`. Toggling `condition` = full swap, not text edit.

### Explicit Identity

Attach an `.id(…)` modifier to force SwiftUI to treat a view as new when the id changes:

```swift
Text(user.name).id(user.id)
```

Or in a `ForEach`:

```swift
ForEach(users) { user in     // uses user.id (Identifiable)
    UserRow(user: user)
}
```

**Why identity matters:**
- Correct animation and transition targets
- `@State` inside a subview is keyed by its identity — changing the id resets that state
- Efficient diffing (SwiftUI can skip unchanged branches)

---

## 7. View Lifecycle — There Isn't One (Like UIKit's)

No `viewDidLoad`, `viewWillAppear`, `viewDidDisappear` in the old sense. Instead:

| Lifecycle event | Modifier |
|-----------------|----------|
| First appear + on task | `.task { await load() }` (auto-cancels on disappear) |
| Appear | `.onAppear { … }` |
| Disappear | `.onDisappear { … }` |
| State change | `.onChange(of: value) { old, new in … }` |
| Receive value | `.onReceive(publisher) { … }` (Combine) |

**Prefer `.task { … }`** for async work — it handles Task cancellation on disappear automatically.

---

## 8. The Layout System — Parent Proposes, Child Chooses

SwiftUI layout is a **3-step negotiation** on each parent-child pair:

```
1. Parent PROPOSES a size to child.
2. Child CHOOSES its own size (parent cannot override).
3. Parent POSITIONS the child in its coordinate space.
```

**Key insight:** the child is sovereign over its own size. `.frame(width: 100)` doesn't force `Text` into 100 points — it wraps `Text` in a **new parent view** that takes 100 points and centers `Text` inside.

```swift
Text("Hello").frame(width: 100, height: 100)
// ┌─────────────┐  ← frame (100×100)
// │             │
// │   Hello     │  ← Text (uses its natural size, centered)
// │             │
// └─────────────┘
```

### Common Sizing Behaviors

| View | Behavior |
|------|----------|
| `Text`, `Image` | Natural (intrinsic) size |
| `Image(...).resizable()` | Takes any proposed size |
| `Color`, `Rectangle`, `Spacer` | Takes ALL proposed size |
| `VStack` / `HStack` | Wraps children, uses smallest fit |
| `.frame(maxWidth: .infinity)` | Fills available proposed width |
| `.fixedSize()` | Ignores proposed size, uses ideal size |

---

## 9. Modifier Order Matters

Modifiers **wrap** the view they're applied to. Each returns a new view. Order changes what wraps what.

```swift
// ✅ padding INSIDE background — background covers the padded area
Text("Hi")
    .padding()
    .background(.yellow)

// ✅ padding OUTSIDE background — background hugs the text, padding pushes it out
Text("Hi")
    .background(.yellow)
    .padding()
```

### Frame + Padding

```swift
// frame first, then padding — total width = 200 + padding*2
Text("Hi").frame(width: 200).padding()

// padding first, then frame — frame constrains total width to 200
Text("Hi").padding().frame(width: 200)
```

**Reading rule:** modifiers apply **bottom-up** in source order (each wraps the previous result).

---

## 10. Environment — Implicit Data Injection

`@Environment` values propagate down the view tree without being passed explicitly.

**Built-in examples:**

```swift
struct MyView: View {
    @Environment(\.colorScheme) var colorScheme   // .light or .dark
    @Environment(\.locale) var locale
    @Environment(\.dismiss) var dismiss           // to close a sheet
}
```

**Set from a parent:**

```swift
ChildView()
    .environment(\.locale, Locale(identifier: "vi_VN"))
    .foregroundStyle(.blue)     // this is also environment-based
```

**Custom keys:** define an `EnvironmentKey` and add a computed property on `EnvironmentValues`. See [[iOS SwiftUI Architecture - Dependency Injection]] for using `@Environment` to inject a `DIContainer`.

---

## 11. Preview — Iterate Without Running the App

```swift
#Preview {
    UserListView(viewModel: .init(fetchUsers: MockFetchUsersUseCase()))
        .environment(\.colorScheme, .dark)
}
```

Runs in Xcode's canvas. Zero-cost to spin up. Wire mocks in via constructors — see [[iOS SwiftUI Architecture - Dependency Injection]].

**Rule:** every non-trivial view should have at least one `#Preview`. If it's hard to preview, the view is over-coupled.

---

## 12. Animation — State Changes Are Animatable

Wrapping a state change in `withAnimation` animates every dependent view:

```swift
@State private var expanded = false

Button("Toggle") {
    withAnimation(.spring) { expanded.toggle() }
}
Text("Hello")
    .scaleEffect(expanded ? 2 : 1)   // animates when `expanded` flips
```

Or attach `.animation(_:value:)` to a modifier tied to state:

```swift
Text("Hello")
    .scaleEffect(expanded ? 2 : 1)
    .animation(.spring, value: expanded)
```

---

## Concept Summary

| Concept | One-liner |
|---------|-----------|
| Declarative | Describe UI as a function of state |
| `View` is a struct | Cheap, ephemeral value type |
| `some View` | Opaque return of a concrete but hidden `View` type |
| `@ViewBuilder` | Result builder turning statement lists into one composite view |
| Identity | Position in tree (implicit) or `.id(…)` (explicit) |
| Layout | Parent proposes, child chooses, parent positions |
| Modifier order | Bottom-up wrapping — order changes the outcome |
| Environment | Implicit down-tree data pipe |
| Lifecycle | `.task` / `.onAppear` / `.onChange` — no `viewDidLoad` |

---

## Related

- [[iOS SwiftUI - Core Components]] — the concrete building blocks
- [[iOS SwiftUI Architecture - Presentation Layer]] — how these concepts sit in a real app
- [[iOS SwiftUI Architecture - MVVM with Combine]] — data flow into views
