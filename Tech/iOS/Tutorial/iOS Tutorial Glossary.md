---
tags:
  - ios
  - swiftui
  - tutorial
  - glossary
  - reference
  - mobile
created: 2026-07-02
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/
---

# iOS Tutorial — Glossary

> Every keyword, symbol, and concept used across the iOS tutorial (Parts 1-8) *and* the Fundamentals deep-dive notes ([[iOS SwiftUI - Lifecycle]], [[iOS SwiftUI - Concurrency and Threading]], [[iOS ARC Guide]]), explained plain-English. Skim the categories, or jump to a specific entry via the table of contents. Back to index: [[iOS Tutorial Guide]].

**How to link to a specific entry from another note:** `[[iOS Tutorial Glossary#@State]]`

---

## Categories

- [Swift Language Basics](#swift-language-basics)
- [Swift Types & Protocols](#swift-types--protocols)
- [Swift Concurrency](#swift-concurrency)
- [ARC & Memory Management](#arc--memory-management)
- [Property Wrappers](#property-wrappers)
- [SwiftUI Core](#swiftui-core)
- [SwiftUI Views & Modifiers](#swiftui-views--modifiers)
- [Combine Framework](#combine-framework)
- [Foundation & Networking](#foundation--networking)
- [Architecture Concepts](#architecture-concepts)
- [Testing](#testing)

---

## Swift Language Basics

### `struct`
A **value type**. Copied when passed around, not shared. SwiftUI views are almost always structs — they're cheap to create and destroy.
```swift
struct Country { let name: String }
let a = Country(name: "Vietnam")
var b = a; b = Country(name: "Japan")   // 'a' is unchanged
```
First seen: [[iOS Tutorial - Part 1 First SwiftUI Screen]] (Step 2).

---

### `class`
A **reference type**. Multiple variables can point to the same instance. Use for ViewModels (need identity across `body` re-runs) and repositories (may hold state like a database connection).
```swift
class CountriesViewModel { var count = 0 }
let a = CountriesViewModel()
let b = a; b.count = 5                  // a.count is also 5
```
First seen: [[iOS Tutorial - Part 3 MVVM ViewModel]].

---

### `let` vs `var`
`let` = constant (can't be reassigned). `var` = variable (can). **Default to `let`**; switch to `var` only when you need mutation.
```swift
let name = "Vietnam"    // ✅ immutable
var count = 0           // ✅ mutable
count += 1
```
First seen: Part 1.

---

### `enum`
A closed set of named values. Great for state machines, filter modes, sort orders.
```swift
enum SortMode { case name, populationDesc }
```
First seen: [[iOS Tutorial - Part 9 From Tutorial to Real App]] (T3.3).

---

### `guard`
Early exit if a condition fails. Reads better than nested `if`. Must exit (return, throw, break, continue).
```swift
guard !searchText.isEmpty else { return countries }
```
First seen: [[iOS Tutorial - Part 2 Local State]] (Step 2).

---

### `if let`
Unwrap an optional into a non-optional variable, scoped to the `if` block.
```swift
if let capital = country.capital {
    print("Capital is \(capital)")
}
```
First seen: Part 5.

---

### Optional (`?` and `!`)
`Type?` means "value OR nil." `?` is safe access; `!` force-unwraps and crashes if nil. **Avoid `!`** except in previews and tests.
```swift
let capital: String? = "Hanoi"          // Optional<String>
let count = capital?.count              // Int? — nil if capital was nil
let force = capital!.count              // ❌ crashes if nil
```
First seen: Part 5 (`CountryDTO`).

---

### Closure `{ … }`
An anonymous function. Passed to methods like `.map`, `.filter`, `.sink`. Captures surrounding variables.
```swift
let names = countries.map { $0.name }   // { … } is a closure
```
`$0`, `$1` are shorthand for the first, second closure argument. First seen: Part 1.

---

### `self`
Refers to the current instance of a class/struct. Required inside closures to disambiguate captured references.
```swift
class VM {
    var items: [String] = []
    func load() {
        publisher.sink { self.items = $0 }.store(in: &cancellables)
    }
}
```
First seen: Part 4.

---

### `[weak self]` — closure capture list
Prevents a retain cycle by holding a weak (non-owning) reference to `self` inside a closure. `self` becomes optional (`self?`).
```swift
publisher.sink { [weak self] value in
    self?.items = value    // no retain cycle
}
```
Rule of thumb: use `[weak self]` when the closure is stored (e.g., in `cancellables`). Not needed for one-shot closures like `.map`. First seen: Part 4.

---

### `throws` / `try` / `throw`
Marks a function that can fail. Callers must handle with `try`, `try?` (returns nil on error), or `try!` (crash on error). Use `throw` to raise an error.
```swift
func fetch() throws -> [Country] { … }

let items = try fetch()      // may throw up
let maybe = try? fetch()     // [Country]? — nil on error
```
First seen: Part 4 (async/await alternative callout).

---

## Swift Types & Protocols

### `protocol`
A contract of methods/properties a conforming type must implement. Foundation of Clean Architecture — Domain defines protocols, Data implements them.
```swift
protocol CountriesRepository {
    func fetchCountries() -> AnyPublisher<[Country], Error>
}
```
First seen: [[iOS Tutorial - Part 4 Domain Layer]] (Step 3).

---

### `extension`
Adds methods/computed properties to an existing type (yours or Apple's) *without* subclassing.
```swift
extension CountryDTO {
    func toDomain() -> Country? { … }
}
```
First seen: Part 5.

---

### `final`
Prevents subclassing. Small perf win (compiler devirtualizes calls) and required in some macro contexts. Use on classes you don't intend to subclass.
```swift
final class CountriesViewModel { … }
```
First seen: Part 3.

---

### Access levels — `private`, `internal`, `public`
Who can see this symbol. Default is `internal` (visible in the same module).
- `private` — visible only inside the enclosing declaration.
- `internal` (default) — visible inside the module.
- `public` — visible from other modules.
- `open` — like `public` + can be subclassed.
```swift
private var cancellables = Set<AnyCancellable>()
```
First seen: Part 4.

---

### `private(set)`
Read-anywhere, write-only-inside. Views can read `countries` but only the VM can mutate it.
```swift
private(set) var countries: [Country] = []
```
First seen: Part 3.

---

### Generics `<T>`
A placeholder for a type the caller picks. Lets one function work for many types.
```swift
func get<T: Decodable>(_ request: URLRequest, as type: T.Type) -> AnyPublisher<T, Error>
```
`T: Decodable` means "T must conform to `Decodable`." First seen: Part 5.

---

### `KeyPath` (`\.name`)
A first-class reference to a property. Used by `List(items, id: \.name)`, sorts, filters.
```swift
List(countries, id: \.name)              // uses \.name as the row identity
countries.sorted { $0.name < $1.name }   // longer form
```
First seen: Part 1.

---

### `Identifiable`
Protocol requiring an `id` property. Lets SwiftUI `List` and `ForEach` diff rows correctly.
```swift
struct Country: Identifiable {
    var id: String { name }
}
```
First seen: [[iOS Tutorial - Part 2 Local State]] (Step 1).

---

### `Equatable` / `Hashable`
- `Equatable` — you can compare two values with `==`.
- `Hashable` — the value can be used as a dictionary key or in a `Set`.

Both are auto-synthesized by Swift if all your stored properties conform.
```swift
struct Country: Identifiable, Equatable { … }   // Swift generates ==
```
First seen: Part 4.

---

### `Decodable` / `Encodable` / `Codable`
- `Decodable` — can be built from JSON/plist/etc.
- `Encodable` — can be written to JSON/plist/etc.
- `Codable` — both.

Auto-synthesized if every stored property is also Codable/Decodable.
```swift
struct CountryDTO: Decodable {
    let names: NamesDTO
    let capitals: [CapitalDTO]?
    let flag: FlagDTO?
}
```
First seen: [[iOS Tutorial - Part 5 Data Layer]].

---

### `Result` type — implicit
Combine's `Publisher.Failure` and `throws` functions produce success or failure. You rarely need to type `Result<T, E>` yourself in this tutorial. See Apple docs: https://developer.apple.com/documentation/swift/result

---

## Swift Concurrency

### `async` / `await`
Structured concurrency. `async` marks a function that can suspend; `await` marks the suspension point in the caller.
```swift
func load() async throws -> [Country] { … }

let items = try await load()   // pauses here without blocking the thread
```
First seen: Part 4 (as the alternative to Combine).

---

### `Task { … }`
Kicks off an async operation from a synchronous context (e.g., inside `.onAppear`). Prefer `.task` on a View — it auto-cancels.
```swift
.onAppear {
    Task { await viewModel.load() }
}
```
Better: `.task { await viewModel.load() }`. First seen: Part 4 (implicit via `.task`).

---

### `@MainActor`
Marks that code must run on the main (UI) thread. SwiftUI state updates require the main actor. Applied to types, functions, or single closures.
```swift
@MainActor
final class CountriesViewModel { … }
```
First seen: [[iOS Tutorial - Part 6 Dependency Injection]] (Step 1).

---

### `Task.isCancelled`
Check inside an `async` loop to bail early if the enclosing `.task` was cancelled (e.g., view disappeared).
```swift
while !Task.isCancelled {
    await tick()
}
```
First seen: [[iOS SwiftUI - Lifecycle]] (gotchas section).

---

### `@Sendable`
Marks a closure or type as safe to pass across concurrent contexts (actors, tasks, threads). All captures must themselves be `Sendable`. Under Swift 6, closures crossing actor boundaries are `@Sendable` by default.
```swift
Task { @Sendable in
    await work()
}
```
Deep dive: [[iOS ARC - Capture Lists]] (Swift 6 section). First seen: [[iOS ARC - Capture Lists]].

---

## ARC & Memory Management

### ARC — Automatic Reference Counting
Swift's compile-time memory management for class instances. The compiler inserts `retain`/`release` calls; when a class instance's strong refcount hits zero, `deinit` runs and memory is freed. No garbage collector.

Deep dive: [[iOS ARC Guide]]. First seen: [[iOS ARC - How It Works]].

---

### Reference count
The number of strong references currently pointing to a class instance. When it hits zero, the instance is deallocated.
Deep dive: [[iOS ARC - How It Works]].

---

### Value vs reference types
- **Value type** — `struct`, `enum`, tuple. Copied on assignment. Not ARC-managed.
- **Reference type** — `class`, `actor`, closures. Shared by pointer. ARC-managed.

Deep dive: [[iOS ARC - How It Works]].

---

### Strong reference
The default reference kind. Keeps the target alive by incrementing its refcount. Just a normal `let`/`var`/property with no keyword.
```swift
let vm = ViewModel()   // strong
```
Deep dive: [[iOS ARC - Strong Weak Unowned]].

---

### Weak reference
Does not retain the target. Must be `var Optional`. Automatically set to `nil` when the target deallocates. Standard choice for delegate patterns and back-references.
```swift
weak var delegate: MyDelegate?
```
Deep dive: [[iOS ARC - Strong Weak Unowned]].

---

### Unowned reference
Does not retain the target. Non-Optional. Does *not* zero when the target deallocates — accessing an unowned reference to a dead object is a runtime crash. Use only when the referred object is guaranteed to outlive the reference.
```swift
unowned let owner: Customer
```
Deep dive: [[iOS ARC - Strong Weak Unowned]].

---

### Retain cycle / reference cycle
Two (or more) class instances hold strong references to each other. Refcount never reaches zero → `deinit` never runs → memory leaked. Break with `weak` or `unowned` on at least one edge.

Deep dive: [[iOS ARC - Retain Cycles]].

---

### Memory leak
Memory that stays allocated after it's no longer needed. In Swift, almost always caused by a retain cycle. Detect with lifetime `print` in `deinit`, Xcode Memory Graph Debugger, or Instruments.

Deep dive: [[iOS ARC - Debugging Memory Issues]].

---

### `deinit`
A method that runs when the last strong reference to a class instance drops. Fires exactly once. Not called manually. Use for cleanup — invalidating timers, removing observers, closing handles.
```swift
deinit { print("Freed") }
```
Deep dive: [[iOS ARC - How It Works]].

---

### Capture list
The `[ ... ] in` prefix on a closure that controls how it captures references. `[weak self]` and `[unowned self]` are the most common. Also used to shadow captures with computed values (`[value = expensiveExpr()] in ...`).
```swift
publisher.sink { [weak self] value in
    self?.items = value
}
```
Deep dive: [[iOS ARC - Capture Lists]].

---

### Escaping closure
A closure that may run *after* the function that received it returns. Stored somewhere; must be marked `@escaping` in parameter types. Requires `self.` disambiguation. This is where `[weak self]` matters.
```swift
func run(completion: @escaping () -> Void)
```
Deep dive: [[iOS ARC - Capture Lists]].

---

### Memory Graph Debugger
Xcode's in-IDE tool for visualizing the live reference graph. Debug bar → three-connected-nodes icon, or Debug → Debug Workflow → View Memory Graph Hierarchy. Primary tool for finding retain cycles.

Deep dive: [[iOS ARC - Debugging Memory Issues]].

---

## Property Wrappers

Property wrappers add behavior to a stored property. The `@` sigil is the giveaway. `$prop` accesses the wrapper's "projected value" (usually a `Binding`).

### `@State`
Local, view-owned mutable state. SwiftUI stores it in a side box keyed to view identity, so it survives `body` re-runs.
```swift
@State private var searchText: String = ""
```
Rule: use for state **owned and used only by this view**. First seen: [[iOS Tutorial - Part 2 Local State]].

---

### `@Binding`
Two-way pointer to state owned by a parent view.
```swift
struct ChildView: View {
    @Binding var text: String
}

// Parent passes: ChildView(text: $parentText)
```
First seen: Part 2 (as the `$` prefix).

---

### `@Observable` (iOS 17+)
Macro that makes a class observable by SwiftUI, tracking per-property reads. Modern replacement for `ObservableObject`.
```swift
import Observation

@Observable
final class CountriesViewModel {
    var searchText = ""
}
```
Deep dive: [[iOS SwiftUI Architecture - Observation Macro]]. First seen: [[iOS Tutorial - Part 3 MVVM ViewModel]].

---

### `@Bindable` (iOS 17+)
Give a caller-injected `@Observable` object `$binding` syntax inside a view.
```swift
struct EditView: View {
    @Bindable var vm: CountriesViewModel
    var body: some View {
        TextField("Search", text: $vm.searchText)   // $vm.searchText works because of @Bindable
    }
}
```
First seen: Part 3 (mentioned in "the one surprise" callout).

---

### `@StateObject` (iOS 14–16, legacy)
Pre-`@Observable` way to own a reference type in a view. Still valid on older deployment targets.
```swift
@StateObject var vm = ViewModel()
```
Deep dive: [[iOS SwiftUI Architecture - MVVM with Combine]]. Not used in this tutorial (we target iOS 17+).

---

### `@ObservedObject` (iOS 14–16, legacy)
Receive a caller-owned `ObservableObject`. Lifetime managed by the caller. Deprecated by `@Bindable` for iOS 17+.

---

### `@Published` (iOS 14–16, legacy)
Marks a property on an `ObservableObject` to auto-broadcast changes. Not needed with `@Observable`.

---

### `@Environment`
Read a value injected somewhere above in the view tree. Used for scene phase, color scheme, DI, etc.
```swift
@Environment(\.scenePhase) private var scenePhase
```
First seen: [[iOS SwiftUI - Lifecycle]].

---

### `@AppStorage`
A `@State`-like wrapper backed by `UserDefaults`. Persists across app launches.
```swift
@AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
```
First seen: [[iOS Tutorial - Part 9 From Tutorial to Real App]] (T2.2).

---

### `@SceneStorage`
Like `@AppStorage` but per-scene (per-window). Great for iPad multi-window state.

---

### `@ViewBuilder`
A **result builder** attribute that lets a function or property return multiple views without a wrapper.
```swift
@ViewBuilder
private var content: some View {
    if viewModel.isLoading { ProgressView() }
    else { List(…) }
}
```
Every `body` is implicitly `@ViewBuilder`. First seen: [[iOS Tutorial - Part 4 Domain Layer]] (Step 7).

---

### `@main`
Marks the app entry point. Only one struct in the module can be `@main`.
```swift
@main
struct CountriesAppApp: App { … }
```
First seen: Part 1.

---

### `@testable import`
Give a test target access to `internal` (default-visibility) symbols in the app module. Without it, tests can only see `public` symbols.
```swift
@testable import CountriesApp
```
First seen: [[iOS Tutorial - Part 6 Dependency Injection]] (Step 6).

---

### `@escaping`
Marks a closure parameter that outlives the function call. All `.sink { … }` closures are escaping by default when stored. You'll usually see this only if you write your own APIs that take closures — SwiftUI/Combine handle it under the hood.

---

## SwiftUI Core

### `View` protocol
The single thing every SwiftUI screen or piece conforms to. Requires a `body`.
```swift
struct CountryRow: View {
    var body: some View { Text("…") }
}
```
First seen: Part 1.

---

### `body`
The computed property SwiftUI calls to get the current UI description. Runs many times. Must be pure — no side effects.
```swift
var body: some View { … }
```
First seen: Part 1.

---

### `some View` (opaque return type)
"I return one specific `View` type, but I'm not telling you which." Lets you compose views without exposing the compound type.
```swift
var body: some View { HStack { … } }   // some concrete View, hidden
```
Deep dive: [[iOS SwiftUI - Core Concepts]]. First seen: Part 1.

---

### `App` protocol
Top-level protocol for the app. One `struct` per app conforms and is marked `@main`.
```swift
@main struct CountriesAppApp: App {
    var body: some Scene { WindowGroup { … } }
}
```
First seen: Part 1.

---

### `Scene`
A self-contained UI unit the system schedules independently. `WindowGroup`, `DocumentGroup`, `Settings` are scenes.

Deep dive: [[iOS SwiftUI - Lifecycle]].

---

### `WindowGroup`
The most common scene — hosts the app's main window(s).
```swift
WindowGroup { CountriesListView(…) }
```
First seen: Part 1.

---

### Modifier
A method chain that returns a **new** view with an added behavior/appearance. Order matters.
```swift
Text("Hi")
    .font(.headline)          // modifier 1
    .padding()                // modifier 2 (padding around the styled text)
```
First seen: Part 1.

---

### `#Preview` macro
Xcode-only. Renders a mini-canvas of the view for fast iteration.
```swift
#Preview("Loading") {
    CountriesListView(viewModel: DIContainer.mock.makeCountriesViewModel_loading())
}
```
First seen: Part 1.

---

### `$` — projected value
When you prefix a property-wrapped value with `$`, you get its projected value — for `@State` and `@Observable`+`@State`, that's a `Binding`.
```swift
@State var name = ""
TextField("Name", text: $name)   // $name is Binding<String>
```
First seen: Part 2.

---

### `_propName` — the wrapper itself
Rarely needed. Prefixing with underscore gives you the wrapper storage, not the value.
```swift
_viewModel = State(initialValue: viewModel)   // access the State wrapper
```
First seen: Part 4 (init trick).

---

## SwiftUI Views & Modifiers

### `Text`
Displays a string. Supports formatting, localization.
```swift
Text("Countries")
```

---

### `Image`
Displays an image asset, SF Symbol, or `UIImage`.
```swift
Image(systemName: "star.fill")
```

---

### `HStack`, `VStack`, `ZStack`
Horizontal / Vertical / Z-order (layered) stack.
```swift
HStack(spacing: 12) { Text("A"); Text("B") }
```
First seen: Part 1.

---

### `List`
Scrollable table with automatic row separators. Works with `Identifiable` collections.
```swift
List(countries) { country in CountryRow(country: country) }
```
First seen: Part 1.

---

### `NavigationStack` (iOS 16+)
Container for pushed navigation. Replaces `NavigationView`.
```swift
NavigationStack { content.navigationTitle("Countries") }
```
First seen: Part 1.

---

### `NavigationLink`
Tappable row that pushes a destination onto the `NavigationStack`.
```swift
NavigationLink("Details", value: country)
```
First seen: [[iOS Tutorial - Part 9 From Tutorial to Real App]] (T1.1).

---

### `Section`
Groups rows inside a `List` with a header/footer.
```swift
List { Section("Asia") { ForEach(asian) { … } } }
```
First seen: Part 9 (T3.1).

---

### `ForEach`
Repeats a view for each item. `List` uses it internally; use `ForEach` when you need multiple items inside a container like `Section`.

---

### `Picker`
Selection UI (menu, wheel, segmented control).
```swift
Picker("Region", selection: $selectedRegion) {
    ForEach(regions) { Text($0.name).tag($0) }
}
```
First seen: Part 9 (T3.2).

---

### `TextField`
Single-line text input.
```swift
TextField("Prompt", text: $binding)
```
First seen: Part 2.

---

### `ProgressView`
Native spinner / progress bar.
```swift
ProgressView("Loading…")
```
First seen: Part 4.

---

### `ContentUnavailableView` (iOS 17+)
Built-in empty/error placeholder.
```swift
ContentUnavailableView("Nothing here", systemImage: "tray")
```
First seen: Part 4.

---

### `.padding()`, `.font()`, `.foregroundStyle()`
Common modifiers.
- `.padding(.vertical, 4)` — adds space.
- `.font(.headline)` — semantic font style.
- `.foregroundStyle(.secondary)` — adapts to light/dark.

First seen: Part 1.

---

### `.searchable(text:prompt:)`
Nav-integrated search bar. Writes into a `Binding<String>`.
```swift
.searchable(text: $searchText, prompt: "Search")
```
First seen: Part 2.

---

### `.refreshable`
Pull-to-refresh. Runs an `async` closure.
```swift
.refreshable { await viewModel.load() }
```
First seen: Part 9 (T1.2).

---

### `.onAppear` / `.onDisappear`
Fires when a view is added/removed from the hierarchy. **`body` may re-run without either firing**; these are hierarchy-level events.
```swift
.onAppear { viewModel.load() }
```
Deep dive: [[iOS SwiftUI - Lifecycle]]. First seen: Part 4.

---

### `.task`
Runs an `async` closure on appear; auto-cancelled on disappear. **Prefer over `.onAppear { Task { … } }`**.
```swift
.task { await viewModel.load() }
```
First seen: [[iOS SwiftUI - Lifecycle]].

---

### `.onChange(of:_:)` (iOS 17+ signature)
Fires when a value changes. Two-parameter closure gives old + new.
```swift
.onChange(of: scenePhase) { _, newPhase in … }
```

---

### `.animation`
Animates changes to a value.
```swift
.animation(.default, value: filtered)
```
First seen: Part 9 (T1.4).

---

### `.id(_:)`
Force-changes a view's identity. Destroys old state; creates new state.
```swift
CountryDetailView(country: c).id(c.id)
```
Deep dive: [[iOS SwiftUI - Lifecycle]].

---

## Combine Framework

### `Publisher`
Anything that emits values over time. Streams. First seen: [[iOS Tutorial - Part 4 Domain Layer]].

---

### `AnyPublisher<Output, Failure>`
Type-erased publisher. Used as a return type so callers don't see internal operator chain.
```swift
func fetchCountries() -> AnyPublisher<[Country], Error>
```
First seen: Part 4.

---

### `Just`
A publisher that emits **one value** then finishes.
```swift
Just(data).setFailureType(to: Error.self).eraseToAnyPublisher()
```
First seen: Part 4 (mock repo).

---

### `Fail`
A publisher that immediately fails with a specific error.
```swift
Fail(error: URLError(.notConnectedToInternet))
```
First seen: [[iOS Tutorial - Part 6 Dependency Injection]] (Step 5).

---

### `Empty`
A publisher that never emits. Use for "stuck loading" preview state.
```swift
Empty(completeImmediately: false)
```
First seen: Part 6 (Step 5).

---

### `.map`
Transform each emitted value.
```swift
.map { dtos in dtos.compactMap { $0.toDomain() } }
```
First seen: Part 4.

---

### `.tryMap`
Like `.map` but the closure can `throw`. Failure becomes a downstream error.
```swift
.tryMap { data, response -> Data in
    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    return data
}
```
First seen: Part 5.

---

### `.decode(type:decoder:)`
Runs a `JSONDecoder` on incoming `Data`. Emits the decoded value; throws on parse failure.
```swift
.decode(type: CountriesResponseDTO.self, decoder: decoder)
```
First seen: Part 5.

---

### `.compactMap`
Two meanings:
- On `Publisher`: like `.map` but drops `nil` results.
- On `Array` (used inside `.map`): same idea for collections.
```swift
dtos.compactMap { $0.toDomain() }   // drops nils
```
First seen: Part 5.

---

### `.sink(receiveCompletion:receiveValue:)`
Terminal subscriber. Actually runs the pipeline. Returns a `Cancellable` you must retain.
```swift
publisher.sink(
    receiveCompletion: { … },
    receiveValue:      { … }
).store(in: &cancellables)
```
First seen: Part 4.

---

### `.assign(to:on:)` / `.assign(to:)`
Terminal subscriber that writes each value into a keypath. Requires a class-owned property.
```swift
publisher.assign(to: \.items, on: self)
```
Deep dive: [[iOS SwiftUI Architecture - Combine Operators]].

---

### `.receive(on:)`
Hops to a scheduler (usually `DispatchQueue.main`) before delivering downstream. Required before updating UI state.
```swift
.receive(on: DispatchQueue.main)
```
First seen: Part 4.

---

### `.eraseToAnyPublisher()`
Wraps a compound-typed publisher into `AnyPublisher<Output, Failure>` so callers don't see the internals.
First seen: Part 4.

---

### `.setFailureType(to:)`
Widens a `Never`-failure publisher (like `Just`) to any error type, so it fits a protocol requirement.
```swift
Just(data).setFailureType(to: Error.self)
```
First seen: Part 4.

---

### `.store(in:)`
Puts a `Cancellable` into a `Set<AnyCancellable>` that's freed when the owner deallocates. Prevents the pipeline from being cancelled immediately.
```swift
.store(in: &cancellables)
```
First seen: Part 4.

---

### `.debounce(for:scheduler:)`
Waits for a quiet period before emitting the latest value. Perfect for search-as-you-type.
```swift
$searchText.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
```
First seen: Part 9 (T4.3).

---

### `Cancellable` / `AnyCancellable`
A handle to a running Combine pipeline. Discarding it cancels the work. Retain via `store(in:)`.
First seen: Part 4.

---

## Foundation & Networking

### `URL`
A URL. Force-unwrap is fine for compile-time-known constants.
```swift
private let url = URL(string: "https://…")!
```
First seen: Part 5.

---

### `URLRequest`
A value type that bundles a `URL` with an HTTP method, headers, and an optional body. Prefer over a bare `URL` the moment you need auth (Bearer tokens), custom methods, or a body.
```swift
var req = URLRequest(url: url)
req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
```
First seen: Part 5 (added when REST Countries moved to v5 auth).

---

### `URLComponents`
Structured URL builder. Percent-encodes query values for you — the safe way to interpolate user input into a URL.
```swift
var c = URLComponents(string: "https://api.restcountries.com/countries/v5")!
c.queryItems = [URLQueryItem(name: "limit", value: "100")]
let url = c.url!
```
First seen: Part 5.

---

### `URLSession`
Apple's networking API. `URLSession.shared` is the singleton for one-off requests. Accepts either a bare `URL` or a fully-formed `URLRequest`.
```swift
URLSession.shared.dataTaskPublisher(for: request)
```
First seen: Part 5.

---

### `URLSession.DataTaskPublisher`
Combine publisher wrapping `URLSession`. Emits `(Data, URLResponse)`.
First seen: Part 5.

---

### `URLResponse` / `HTTPURLResponse`
Response metadata. Cast `URLResponse as? HTTPURLResponse` to inspect status code.
First seen: Part 5.

---

### `URLError`
Errors from `URLSession`. Common cases: `.notConnectedToInternet`, `.badServerResponse`, `.cannotDecodeContentData`.
First seen: Part 5.

---

### `Data`
Raw bytes. What `URLSession` returns before decoding.

---

### `JSONDecoder`
Decodes `Data` to a `Decodable` type.
```swift
let envelope = try JSONDecoder().decode(CountriesResponseDTO.self, from: data)
```
First seen: Part 5.

---

### `DispatchQueue`
Grand Central Dispatch queue. `.main` is the main thread. Used with `.receive(on:)`.
```swift
.receive(on: DispatchQueue.main)
```
First seen: Part 4.

---

### `Set<AnyCancellable>`
An unordered collection used to hold Combine cancellables. `Set` allows quick insert/remove.
```swift
private var cancellables = Set<AnyCancellable>()
```
First seen: Part 4.

---

## Architecture Concepts

### Clean Architecture
A layered design where dependencies point **inward**. Domain (business) has zero framework knowledge; Presentation and Data depend on Domain.

Deep dive: [[iOS SwiftUI Architecture - Clean Architecture]]. First seen: [[iOS Tutorial - Part 4 Domain Layer]].

---

### Layer
A slice of the app with a single responsibility (Presentation, Domain, Data). Layers may only depend on layers *inward* of them.

---

### Entity
A pure Swift representation of a domain concept. No frameworks. No JSON quirks.
```swift
struct Country: Identifiable, Equatable {
    var id: String { name }
    let name, capital, flag: String
}
```
Contrast with a **DTO**. First seen: Part 4.

---

### DTO — Data Transfer Object
A struct that matches the *server's* JSON shape. Never used outside the Data layer. Maps to an Entity via a mapper function.
```swift
struct CountryDTO: Decodable { let names: NamesDTO; let capitals: [CapitalDTO]?; let flag: FlagDTO? }
extension CountryDTO { func toDomain() -> Country? { … } }
```
First seen: Part 5.

---

### Envelope (JSON:API)
A wrapper DTO that mirrors the transport-level structure the server puts around the payload — e.g. REST Countries v5 wraps everything in `{ "data": { "objects": [...], "meta": {...} } }`. Kept separate from record-level DTOs so the wrapper detail never leaks into the repository signature.
```swift
struct CountriesResponseDTO: Decodable {
    let data: DataEnvelope
    struct DataEnvelope: Decodable { let objects: [CountryDTO] }
}
```
First seen: Part 5.

---

### Use Case (Interactor)
A business rule expressed as a callable object. Sits between ViewModel and Repository. If a rule is trivial pass-through, skip it.
```swift
struct FetchCountriesUseCaseImpl: FetchCountriesUseCase {
    let repository: CountriesRepository
    func execute() -> AnyPublisher<[Country], Error> {
        repository.fetchCountries().map { $0.sorted(…) }.eraseToAnyPublisher()
    }
}
```
First seen: Part 4.

---

### Repository — protocol vs impl
- **Protocol** lives in Domain. Declares "we can fetch countries."
- **Implementation** lives in Data. Actually calls the API or database.

The protocol is the seam that makes the app testable. First seen: Part 4.

---

### Dependency Rule
"Inner layers never import from outer layers." Domain imports nothing about UI or network. It's the single most important rule of Clean Architecture.

Deep dive: [[iOS SwiftUI Architecture - Clean Architecture]].

---

### MVVM — Model / View / ViewModel
UI pattern. View is dumb; ViewModel owns UI state and orchestration; Model = the Domain entities.
```
View  ⇄  ViewModel  ⇄  UseCase  ⇄  Repository
```
Deep dive: [[iOS SwiftUI Architecture - MVVM with Combine]]. First seen: [[iOS Tutorial - Part 3 MVVM ViewModel]].

---

### Dependency Injection (DI)
Passing collaborators in from the outside instead of constructing them inside. Makes the class testable and swappable.
```swift
init(fetchCountries: FetchCountriesUseCase) { … }   // ✅ injected
init() { self.repo = RealRepo() }                    // ❌ hard-coded
```
Deep dive: [[iOS SwiftUI Architecture - Dependency Injection]]. First seen: Part 4.

---

### Constructor Injection
Dependencies come in through `init`. The simplest DI style; no framework needed. Used throughout the tutorial.

---

### DI Container
An object that assembles the graph of dependencies in one place. `.live` vs `.mock` variants let you swap the whole world in one line.
```swift
DIContainer.live  // real network
DIContainer.mock  // for previews and tests
```
First seen: [[iOS Tutorial - Part 6 Dependency Injection]].

---

### Composition Root
The single place in the app where the object graph is wired up. Typically the `@main` App struct.

---

### Factory Method
A function that returns a fresh instance of something. Used on `DIContainer` to make ViewModels on demand.
```swift
func makeCountriesViewModel() -> CountriesViewModel
```
First seen: Part 6.

---

## Testing

### Swift Testing framework
Apple's modern test framework (2024+). Uses `@Test`, `#expect`, `@Suite`. Cleaner than XCTest.
```swift
import Testing

@Suite("CountriesViewModel")
struct CountriesViewModelTests {
    @Test func filtersByName() { … }
}
```
Docs: https://developer.apple.com/documentation/testing . First seen: Part 6.

---

### `@Test`
Marks a function as a test.

### `@Suite`
Groups multiple tests under a struct/class with a display name.

### `#expect`
Assertion macro. Fails the test if the expression is false; shows both sides on failure.
```swift
#expect(vm.filtered.count == 1)
```

### XCTest
Older test framework (`XCTAssertEqual`, `XCTestCase` subclassing). Still supported. Prefer Swift Testing for new code.

---

## Related Notes

- Fundamentals: [[iOS SwiftUI Fundamentals Guide]] → [[iOS SwiftUI - Core Concepts]], [[iOS SwiftUI - Core Components]], [[iOS SwiftUI - Lifecycle]]
- Architecture reference: [[iOS SwiftUI Architecture Guide]] → [[iOS SwiftUI Architecture - MVVM with Combine]], [[iOS SwiftUI Architecture - Combine Operators]], [[iOS SwiftUI Architecture - Observation Macro]], [[iOS SwiftUI Architecture - Dependency Injection]]
- Tutorial track: [[iOS Tutorial Guide]] → Parts 1-8

---

## Apple Docs (Where to Verify)

| Topic | URL |
|-------|-----|
| Swift language guide | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/ |
| SwiftUI framework | https://developer.apple.com/documentation/swiftui |
| Observation | https://developer.apple.com/documentation/observation |
| Combine | https://developer.apple.com/documentation/combine |
| Swift Concurrency (async/await) | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/ |
| Foundation | https://developer.apple.com/documentation/foundation |
| Swift Testing | https://developer.apple.com/documentation/testing |
