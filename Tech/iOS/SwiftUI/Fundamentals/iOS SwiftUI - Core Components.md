---
tags:
  - ios
  - swiftui
  - fundamentals
  - components
  - views
  - controls
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/swiftui
apple_docs:
  - https://developer.apple.com/documentation/swiftui
  - https://developer.apple.com/documentation/swiftui/layout-fundamentals
  - https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content
---

# iOS SwiftUI - Core Components

> A categorized catalog of the building blocks you'll actually reach for. One-liner + minimal example per component. Link back to [[iOS SwiftUI Fundamentals Guide]].

---

## 1. Primitive Views

| Component | Purpose | Example |
|-----------|---------|---------|
| `Text` | Display a string, format inline | `Text("Hello").font(.title)` |
| `Image` | Static image (asset, SF Symbol, `UIImage`) | `Image(systemName: "star.fill")` |
| `Label` | Icon + text combo | `Label("Star", systemImage: "star")` |
| `Color` | Fills space with a color | `Color.blue` |
| `Shape` | `Rectangle`, `Circle`, `Capsule`, `Path` | `Circle().fill(.red).frame(width: 40)` |
| `Divider` | Horizontal separator line | `Divider()` |
| `Spacer` | Flexible gap, pushes siblings apart | `Spacer()` inside `HStack` |
| `EmptyView` | Renders nothing (placeholder) | `if isReady { Content() } else { EmptyView() }` |

**SF Symbols** are Apple's icon system — thousands of vector icons callable via `Image(systemName:)`. Full catalog in the SF Symbols app.

---

## 2. Layout Containers

### Stacks

```swift
VStack(alignment: .leading, spacing: 8) { ... }   // vertical
HStack(alignment: .center, spacing: 12) { ... }   // horizontal
ZStack(alignment: .topTrailing) { ... }           // layered (z-axis)
```

| Container | Layout | When |
|-----------|--------|------|
| `VStack` | Top → bottom | Rows of content |
| `HStack` | Left → right | Icon + text, form rows |
| `ZStack` | Back → front | Overlays, badges, backdrop |
| `LazyVStack` | Vertical, **lazy** (only renders visible) | Long scrollable lists inside `ScrollView` |
| `LazyHStack` | Horizontal, lazy | Long horizontal carousels |

**`VStack` vs `LazyVStack`:** `VStack` builds all children up front. Use `LazyVStack` inside a `ScrollView` when children number in the hundreds/thousands.

### Grids

```swift
Grid { GridRow { Text("A"); Text("B") }; GridRow { Text("C"); Text("D") } }  // fixed grid

LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
    ForEach(items) { ItemView(item: $0) }
}
```

| Grid | Use |
|------|-----|
| `Grid` / `GridRow` | Fixed row/column layout — tables, forms |
| `LazyVGrid` / `LazyHGrid` | Scrollable, lazy-rendered, column-driven |

### Scrolling

```swift
ScrollView(.vertical) { LazyVStack { ForEach(items) { ItemView(item: $0) } } }
ScrollView(.horizontal, showsIndicators: false) { HStack { ... } }
```

---

## 3. Collection Views

### `List`

Table-like scrollable collection with platform-standard styling.

```swift
List(users) { user in
    UserRow(user: user)
}
.listStyle(.insetGrouped)
```

Supports swipe-to-delete, section headers, pull-to-refresh (`.refreshable`).

### `ForEach`

Not a container — a **structural repeater** used inside `VStack`, `HStack`, `List`, `LazyVGrid`, etc.

```swift
ForEach(users) { user in UserRow(user: user) }
ForEach(0..<10, id: \.self) { i in Text("\(i)") }
```

Requires `Identifiable` conformance OR an explicit `id:` keypath.

### `Form`

Grouped-styled list for settings/entry screens.

```swift
Form {
    Section("Profile") {
        TextField("Name", text: $name)
        Toggle("Notifications", isOn: $notifications)
    }
}
```

---

## 4. Controls

### Buttons & Toggles

```swift
Button("Save") { save() }
Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
Button("Delete", role: .destructive) { delete() }

Toggle("Wi-Fi", isOn: $wifiEnabled)
Toggle(isOn: $wifi) { Label("Wi-Fi", systemImage: "wifi") }
```

Button styles: `.borderedProminent`, `.bordered`, `.plain`, `.borderless`.

### Sliders, Steppers, Progress

```swift
Slider(value: $volume, in: 0...1)
Stepper("Qty: \(qty)", value: $qty, in: 1...99)
ProgressView(value: progress)          // determinate
ProgressView()                          // indeterminate spinner
```

### Text Input

```swift
TextField("Email", text: $email)
    .textFieldStyle(.roundedBorder)
    .keyboardType(.emailAddress)
    .textInputAutocapitalization(.never)

SecureField("Password", text: $password)
TextEditor(text: $longNote)             // multi-line editable
```

### Selection

```swift
Picker("Role", selection: $role) {
    ForEach(Role.allCases) { Text($0.title).tag($0) }
}
.pickerStyle(.segmented)                // or .menu, .wheel, .inline

DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
ColorPicker("Tint", selection: $tint)
```

---

## 5. Navigation & Presentation

### `NavigationStack` (iOS 16+)

Replaces the older `NavigationView`. Push/pop is state-driven.

```swift
NavigationStack {
    List(users) { user in
        NavigationLink(user.name, value: user)   // value-based routing
    }
    .navigationDestination(for: User.self) { user in
        UserDetailView(user: user)
    }
    .navigationTitle("Users")
}
```

**Programmatic navigation** via a `path` binding:

```swift
@State private var path = NavigationPath()
NavigationStack(path: $path) { ... }
// push:
path.append(user)
// pop:
path.removeLast()
```

### `TabView`

```swift
TabView(selection: $selectedTab) {
    HomeView().tabItem { Label("Home", systemImage: "house") }.tag(0)
    ProfileView().tabItem { Label("Me", systemImage: "person") }.tag(1)
}
```

**iOS 18+:** the new `Tab { … }` DSL replaces `.tabItem` for cleaner definitions.

### Sheets, Full-Screen Covers, Alerts, Popovers

```swift
.sheet(isPresented: $showEditor) { EditorView() }
.sheet(item: $selectedUser) { user in EditorView(user: user) }
.fullScreenCover(isPresented: $showOnboarding) { Onboarding() }
.alert("Delete?", isPresented: $confirmDelete) {
    Button("Delete", role: .destructive, action: delete)
    Button("Cancel", role: .cancel) { }
}
.confirmationDialog("Actions", isPresented: $showActions) { ... }
.popover(isPresented: $showTip) { TipView() }
```

**Detent-controlled sheets** (partial-height, iOS 16+):

```swift
.sheet(isPresented: $show) {
    ContentView().presentationDetents([.medium, .large])
}
```

---

## 6. Drawing & Effects

| Component | Purpose |
|-----------|---------|
| `Canvas` | Immediate-mode drawing (`GraphicsContext`) — think Core Graphics |
| `TimelineView` | Redraws on a schedule (clocks, animations) |
| `GeometryReader` | Access parent's size/coordinate space |
| `Path` | Vector shape defined by draw commands |
| `AngularGradient`, `LinearGradient`, `RadialGradient` | Gradient fills |
| `Material` (`.ultraThinMaterial`) | Frosted-glass backdrop |

```swift
Canvas { context, size in
    context.fill(Path { p in p.addEllipse(in: CGRect(origin: .zero, size: size)) },
                 with: .color(.blue))
}
```

---

## 7. Modifiers — The Configuration Language

Modifiers return a **new View** wrapping the receiver. They're how you configure everything: color, size, gestures, transitions.

### Sizing & Layout

```swift
.frame(width:, height:, alignment:)
.frame(minWidth:, maxWidth:, minHeight:, maxHeight:, alignment:)
.padding()                             // default padding on all edges
.padding(.horizontal, 16)
.offset(x:, y:)                        // visual displacement, no layout change
.position(x:, y:)                      // absolute, replaces layout
.fixedSize()                            // ignore proposed size
.aspectRatio(_:contentMode:)
.layoutPriority(_)                      // hint for space contention
```

### Appearance

```swift
.foregroundStyle(.primary)             // replaces older .foregroundColor
.background(.blue.opacity(0.2))
.background { RoundedRectangle(cornerRadius: 12).fill(.gray) }
.overlay { Circle().stroke(.red) }
.tint(.orange)
.cornerRadius(12)
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(radius: 4, y: 2)
.opacity(0.5)
```

### Typography

```swift
.font(.title2)                         // .largeTitle, .title, .headline, .body, .caption
.fontWeight(.semibold)
.multilineTextAlignment(.leading)
.lineLimit(2)
.textCase(.uppercase)
```

### Interaction & Gestures

```swift
.disabled(loading)
.onTapGesture { tapped() }
.onLongPressGesture(minimumDuration: 0.5) { longPressed() }
.gesture(DragGesture().onChanged { … }.onEnded { … })
.contextMenu { Button("Delete", action: delete) }
.swipeActions(edge: .trailing) { Button("Delete", role: .destructive, action: delete) }
.contentShape(Rectangle())             // define tappable area
```

### State-Driven Lifecycle

```swift
.task { await load() }
.onAppear { … }
.onDisappear { … }
.onChange(of: query) { old, new in search(new) }
.refreshable { await reload() }        // pull-to-refresh on List/ScrollView
.searchable(text: $query)              // adds a search bar
```

### Animation & Transition

```swift
.animation(.spring, value: expanded)
.transition(.slide)
.matchedGeometryEffect(id: "hero", in: namespace)
```

### Accessibility

```swift
.accessibilityLabel("Delete post")
.accessibilityHint("Removes the post permanently")
.accessibilityAddTraits(.isButton)
```

---

## 8. Data Flow Wrappers (Quick Cross-Ref)

| Wrapper | Owns? | Purpose | Full note |
|---------|-------|---------|-----------|
| `@State` | ✅ | View-local mutable state (primitives) | [[iOS SwiftUI - Core Concepts]] |
| `@Binding` | ❌ | Two-way tie to parent's state | [[iOS SwiftUI Architecture - Presentation Layer]] |
| `@StateObject` | ✅ | Owns an `ObservableObject` | [[iOS SwiftUI Architecture - MVVM with Combine]] |
| `@ObservedObject` | ❌ | Consumes an `ObservableObject` from parent | [[iOS SwiftUI Architecture - MVVM with Combine]] |
| `@EnvironmentObject` | ❌ | Reads an `ObservableObject` from ancestor's `.environmentObject()` | [[iOS SwiftUI Architecture - MVVM with Combine]] |
| `@Environment` | ❌ | Reads an environment value (colorScheme, dismiss, etc.) | [[iOS SwiftUI - Core Concepts]] |
| `@FocusState` | ✅ | Focus tracking for text fields | — |
| `@Observable` (iOS 17+) | — | Macro replacing `ObservableObject` | [[iOS SwiftUI Architecture - Observation Macro]] |
| `@Bindable` (iOS 17+) | ❌ | Produce `Binding<T>` from an `@Observable` | [[iOS SwiftUI Architecture - Observation Macro]] |

---

## 9. App Structure

```swift
@main
struct MyApp: App {                         // App is the root protocol
    var body: some Scene {
        WindowGroup {                       // Scene = window
            RootView()
        }
    }
}
```

- `App` — the entry point (`@main`).
- `Scene` — a window / window group / document group / settings pane.
- `WindowGroup` — the standard iOS/macOS window container.
- `DocumentGroup` — for document-based apps.
- `Settings` — the macOS settings pane.

---

## 10. Component Selection Cheat Sheet

| Need | Reach for |
|------|-----------|
| Vertical list of arbitrary rows | `VStack` (short) or `LazyVStack` in `ScrollView` (long) |
| Vertical list of same-shape rows | `List` |
| Settings screen | `Form` with `Section` |
| Grid of items | `LazyVGrid` |
| Header/footer on scrolling collection | `ScrollView` + `LazyVStack(pinnedViews: .sectionHeaders)` |
| Overlay a badge | `.overlay(alignment: .topTrailing) { Badge() }` |
| Frosted backdrop | `.background(.ultraThinMaterial)` |
| Modal / detail screen | `.sheet` (partial) or `NavigationStack` (push) |
| Confirm destructive action | `.alert` or `.confirmationDialog` |
| Pull-to-refresh | `.refreshable { … }` on `List` / `ScrollView` |
| Search bar | `.searchable(text: $query)` |

---

## Related

- [[iOS SwiftUI - Core Concepts]] — the mental model these components fit into
- [[iOS SwiftUI Architecture - Presentation Layer]] — components inside a real app structure
- [[iOS SwiftUI Fundamentals Guide]] — top index
