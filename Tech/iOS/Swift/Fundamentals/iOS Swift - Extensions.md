---
tags:
  - ios
  - swift
  - fundamentals
  - extensions
  - mobile
created: 2026-07-10
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/extensions/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/extensions/
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/#Protocol-Extensions
  - https://developer.apple.com/documentation/swift
---

# iOS Swift — Extensions

> Add methods, computed properties, initializers, and conformances to a type you don't own — without subclassing. Coming from Kotlin? These are extension functions on steroids. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Extension** — a block that adds new functionality to an existing named type (`class`, `struct`, `enum`, or `protocol`). Written `extension SomeType { … }`.
- **Retroactive conformance** — declaring a type conforms to a protocol from an extension, sometimes on a type you didn't define (`extension String: Identifiable`).
- **Computed property** — a property with no backing storage; its value is calculated on every read.
- **Conditional conformance** — a conformance that only applies when a generic parameter meets a constraint: `extension Array: Equatable where Element: Equatable`.
- **Stored property** — a `var`/`let` that holds a value in memory. Extensions **cannot** add these.
- **Protocol extension** — an extension on a protocol that provides default method bodies to all conformers. See [[iOS Swift - Protocols]].

---

## Basic Syntax

```swift
extension Int {
    var isEven: Bool { self % 2 == 0 }
    func squared() -> Int { self * self }
}

3.isEven          // false
4.squared()       // 16
```

You can extend any type, including standard-library ones (`Int`, `String`, `Array`, `Date`) and Apple framework types (`URL`, `Color`, `View`).

---

## What Extensions Can Add

| Member | Allowed | Notes |
|--------|---------|-------|
| Computed instance properties | ✅ | |
| Computed static properties | ✅ | |
| Instance methods | ✅ | Use `mutating` on value types when needed |
| Static / type methods | ✅ | |
| New initializers | ✅ | Convenience only on classes; any init on structs |
| Nested types | ✅ | |
| Subscripts | ✅ | |
| Conformance to protocols | ✅ | |
| Stored properties | ❌ | Fundamental limit — see below |
| Overriding existing methods | ❌ | Extensions add, never replace |
| Designated initializers on classes | ❌ | Only convenience inits |

---

## Adding Computed Properties

```swift
extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

"   ".isBlank        // true
"hi".isBlank         // false
```

Because there's no storage, computed properties recompute every read — keep them cheap.

---

## Adding Methods

```swift
extension Array where Element == Int {
    func sum() -> Int { reduce(0, +) }
}

[1, 2, 3].sum()      // 6
```

Mutating methods on value types need the `mutating` keyword:

```swift
extension Array where Element: Equatable {
    mutating func removeAll(_ value: Element) {
        removeAll { $0 == value }
    }
}
```

---

## Adding Initializers

```swift
struct Point { let x: Double; let y: Double }

extension Point {
    init(pair: (Double, Double)) {
        self.init(x: pair.0, y: pair.1)
    }
}

let p = Point(pair: (1, 2))
```

For structs, an extension init preserves the memberwise initializer — a nice trick you can't get by writing the init in the primary declaration.

---

## Extensions on Generic Types

You can extend a generic type; the generic parameters are available inside:

```swift
extension Array {
    var second: Element? {
        count >= 2 ? self[1] : nil
    }
}

[1, 2, 3].second     // Optional(2)
["a"].second         // nil
```

---

## Conditional Conformance

An extension can add conformance to a protocol **only when** the generic parameter satisfies some constraint:

```swift
extension Array: Identifiable where Element: Identifiable {
    public var id: [Element.ID] { map(\.id) }
}
```

Or add methods only when a constraint holds:

```swift
extension Array where Element: Numeric {
    func total() -> Element { reduce(.zero, +) }
}

[1, 2, 3].total()        // 6
[1.5, 2.5].total()       // 4.0
["a"].total()            // ❌ compile error — String isn't Numeric
```

This is one of the most powerful features in Swift's type system — it's how `Array<T>` becomes `Equatable`, `Hashable`, and `Codable` automatically when `T` is.

See [[iOS Swift - Generics]] for the underlying generic machinery.

---

## Extensions on Protocols — Default Implementations

The delivery mechanism for Protocol-Oriented Programming. See [[iOS Swift - Protocols]] for the full story.

```swift
protocol Named {
    var name: String { get }
}

extension Named {
    func introduce() {
        print("Hi, I'm \(name)")
    }
}

struct Country: Named { let name: String }

Country(name: "Vietnam").introduce()
```

Every conformer gets `introduce()` for free — no boilerplate.

---

## Organizing Code with Extensions

The canonical Swift file layout uses one extension per logical group. This is a **style convention**, not a language feature, but almost every iOS codebase follows it.

### ❌ Everything in the main declaration

```swift
final class CountryListViewModel: ObservableObject {
    @Published var countries: [Country] = []
    @Published var isLoading = false
    @Published var error: Error?
    let repository: CountryRepository
    init(repository: CountryRepository) { self.repository = repository }
    func load() async { … }
    func retry() async { … }
    func filter(by name: String) -> [Country] { … }
    private func handle(_ error: Error) { … }
    var displayCount: Int { countries.count }
    static func mock() -> CountryListViewModel { … }
}
```

Hard to scan. Public API, private helpers, previews, and derived properties are mixed.

### ✅ Grouped extensions

```swift
final class CountryListViewModel: ObservableObject {
    @Published var countries: [Country] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let repository: CountryRepository

    init(repository: CountryRepository) { self.repository = repository }
}

// MARK: - Public API
extension CountryListViewModel {
    func load() async { … }
    func retry() async { … }
    func filter(by name: String) -> [Country] { … }
}

// MARK: - Derived
extension CountryListViewModel {
    var displayCount: Int { countries.count }
}

// MARK: - Error handling
private extension CountryListViewModel {
    func handle(_ error: Error) { … }
}

#if DEBUG
extension CountryListViewModel {
    static func mock() -> CountryListViewModel { … }
}
#endif
```

Each concern is a labeled block; the file reads top-to-bottom like a table of contents.

---

## Protocol Conformance in an Extension

Splitting each conformance into its own extension is the standard style:

```swift
struct Country { let id: String; let name: String }

extension Country: Identifiable {}
extension Country: Equatable {}
extension Country: Codable {}
```

When conformance requires implementation, the methods live in the extension where you declare the conformance — the compiler treats that as the natural grouping.

```swift
extension Country: Comparable {
    static func < (lhs: Country, rhs: Country) -> Bool {
        lhs.name < rhs.name
    }
}
```

---

## Limitation — No Stored Properties

Extensions **cannot** add stored properties.

### ❌ Won't compile

```swift
extension URLSession {
    var cachedResponses: [URL: Data] = [:]   // ❌ error
}
```

### ✅ Workarounds

1. Computed property backed by an associated object (Objective-C-style — reserved for framework authors, rare in modern Swift).
2. Wrapper type:

```swift
struct CachedSession {
    let session: URLSession
    var cachedResponses: [URL: Data] = [:]
}
```

3. Static storage in a dedicated type:

```swift
enum SessionCache {
    static var responses: [URL: Data] = [:]
}
```

**The rule exists because stored properties change the memory layout of a type — extensions must not.**

---

## Retroactive Conformance — Handle with Care

Declaring conformance for a type you don't own on a protocol you don't own is called *retroactive conformance*. Swift 6 warns about it because if two modules do it differently, the winner is undefined.

```swift
extension String: Identifiable {          // ⚠️ warning in Swift 6
    public var id: String { self }
}
```

Fix by wrapping in your own type:

```swift
struct StringID: Identifiable { let id: String }
```

---

## Real-World SwiftUI Examples

Extensions are how SwiftUI code stays readable:

```swift
extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

Text("Hello").cardStyle()
```

Extensions on `Color`, `Font`, and `Image` are how design systems ship in most iOS apps. See [[iOS SwiftUI Architecture - MVVM with Combine]] for VM organization patterns.

---

## Anti-Pattern — Overusing Extensions on Foundation Types

### ❌ Global namespace pollution

```swift
extension String {
    func toDate() -> Date? { … }
    func fromBase64() -> String? { … }
    func md5() -> String { … }
    var isValidEmail: Bool { … }
    var isValidPhoneNumber: Bool { … }
}
```

Every `String` in the whole codebase now has these — including strings that have nothing to do with dates, base64, or validation. Autocomplete becomes noisy.

### ✅ Scoped types

```swift
enum DateParsing {
    static func parse(_ string: String) -> Date? { … }
}

enum EmailValidator {
    static func isValid(_ string: String) -> Bool { … }
}
```

Or a wrapping struct:

```swift
struct Email {
    let raw: String
    var isValid: Bool { … }
}
```

Rule: extend for behavior that is *inherent* to the type. Domain-specific logic belongs on a domain type.

---

## Summary

| Add… | Extension can? | Notes |
|------|----------------|-------|
| Computed property | ✅ | Cheap, no storage |
| Method | ✅ | `mutating` for value-type mutation |
| Initializer | ✅ | Convenience only on classes |
| Protocol conformance | ✅ | One extension per protocol is idiomatic |
| Conditional conformance | ✅ | `where` clause on generic parameters |
| Default implementation | ✅ | On `extension P where …` |
| Stored property | ❌ | Would change memory layout |
| Override | ❌ | Extensions add, never replace |

Golden rule: **use extensions to group code by concern, not to shove one-off helpers onto Foundation types.**

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Protocols]] — default implementations live in protocol extensions
- [[iOS Swift - Generics]] — conditional conformance is where extensions meet generics
- [[iOS Swift - Value vs Reference Types]] — extension mutating semantics differ per kind
- [[iOS Swift - Values and Types]] — the layer below
- [[iOS SwiftUI Architecture - MVVM with Combine]] — extensions organize ViewModel code

## Apple Docs

- The Swift Programming Language — Extensions — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/extensions/
- The Swift Programming Language — Protocol Extensions — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/#Protocol-Extensions
- Swift Standard Library — https://developer.apple.com/documentation/swift
