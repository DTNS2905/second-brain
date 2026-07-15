---
tags:
  - ios
  - swift
  - fundamentals
  - generics
  - mobile
created: 2026-07-10
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/
  - https://developer.apple.com/documentation/swift/array
---

# iOS Swift — Generics

> Write code once, use it with any type — checked at compile time. Same core idea as Java/Kotlin generics but tighter, thanks to constraints and associated types. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Generic** — code parameterized by one or more type placeholders. The compiler stamps out a specialized version per concrete type used.
- **Type parameter** — the placeholder itself, conventionally `T`, `U`, `Element`, `Key`, `Value`, written in angle brackets: `<T>`.
- **Generic function** — a function with type parameters: `func swap<T>(_ a: inout T, _ b: inout T)`.
- **Generic type** — a struct, class, enum, or actor with type parameters: `struct Stack<Element>`.
- **Type constraint** — a requirement on a type parameter, written `<T: Protocol>` or `<T: SuperClass>`.
- **`where` clause** — extra constraints attached to a function or extension: `where Element: Equatable`.
- **Associated type** — a type placeholder declared inside a [[iOS Swift - Protocols|protocol]] with `associatedtype`.
- **Existential (`any P`)** — a runtime box holding some value conforming to `P`. Dynamic dispatch.
- **Opaque type (`some P`)** — a compile-time-known concrete type hidden from the caller. Static dispatch.
- **Specialization** — the compiler generating a dedicated version of a generic function/type for each concrete type used at a call site.

---

## Generic Functions

```swift
func swap<T>(_ a: inout T, _ b: inout T) {
    let tmp = a
    a = b
    b = tmp
}

var x = 1, y = 2
swap(&x, &y)              // works for Int

var s = "a", t = "b"
swap(&s, &t)              // works for String
```

`T` is inferred at each call site. The same function body works for any type — the compiler generates specialized versions for the concrete types you actually use.

Multiple type parameters:

```swift
func pair<A, B>(_ a: A, _ b: B) -> (A, B) { (a, b) }

pair(1, "one")           // (Int, String)
pair(true, [1, 2])       // (Bool, [Int])
```

---

## Generic Types

```swift
struct Stack<Element> {
    private var items: [Element] = []

    mutating func push(_ item: Element) { items.append(item) }
    mutating func pop() -> Element? { items.popLast() }
    var top: Element? { items.last }
}

var ints = Stack<Int>()
ints.push(1)
ints.push(2)
ints.pop()               // Optional(2)

var strings = Stack<String>()
strings.push("hi")
```

Standard-library types you use every day are generic: `Array<T>`, `Dictionary<K, V>`, `Set<T>`, `Optional<Wrapped>`, `Result<Success, Failure>`.

---

## Type Constraints

Constrain a type parameter to a protocol so you can call that protocol's methods inside the generic body:

```swift
func findIndex<T: Equatable>(of value: T, in array: [T]) -> Int? {
    for (i, v) in array.enumerated() where v == value {
        return i
    }
    return nil
}

findIndex(of: "b", in: ["a", "b", "c"])   // Optional(1)
```

Without `T: Equatable`, `v == value` wouldn't compile — Swift doesn't have universal `==`.

Multiple constraints with `&`:

```swift
func printAndSave<T: Codable & CustomStringConvertible>(_ value: T) { … }
```

Class-inheritance constraint:

```swift
func track<V: UIView>(_ view: V) { … }
```

---

## `where` Clauses

`where` moves the constraints out of the angle brackets — clearer when there are several.

```swift
func allEqual<C: Collection>(_ c: C) -> Bool
    where C.Element: Equatable
{
    guard let first = c.first else { return true }
    return c.allSatisfy { $0 == first }
}

allEqual([1, 1, 1])       // true
allEqual([1, 1, 2])       // false
```

`where` clauses also attach to extensions — this is how [[iOS Swift - Extensions#Conditional Conformance|conditional conformance]] works:

```swift
extension Array where Element: Numeric {
    func sum() -> Element { reduce(.zero, +) }
}
```

Same-type constraint (`==`) requires the type to be exactly some other type:

```swift
extension Collection where Element == String {
    func joined() -> String { reduce("", +) }
}
```

---

## Associated Types Recap

`associatedtype` is the protocol-side counterpart to a generic parameter. See [[iOS Swift - Protocols#Associated Types associatedtype|Protocols]] for details; here's the connection:

```swift
protocol Container {
    associatedtype Item
    mutating func append(_ item: Item)
    var count: Int { get }
    subscript(i: Int) -> Item { get }
}

struct IntBox: Container {
    private var items: [Int] = []
    mutating func append(_ item: Int) { items.append(item) }
    var count: Int { items.count }
    subscript(i: Int) -> Int { items[i] }
}
```

Since Swift 5.7 you can use **primary associated types** — expose one associated type publicly, so you can write `some Container<Int>` or `any Container<Int>`:

```swift
protocol Container<Item> {
    associatedtype Item
    // …
}

func firstInt(from c: some Container<Int>) -> Int? {
    c.count > 0 ? c[0] : nil
}
```

That's identical to how `some View` and `any Publisher<Output, Failure>` are used in SwiftUI + [[iOS SwiftUI Architecture - MVVM with Combine|Combine]].

---

## `some` vs `any` — Opaque vs Existential

Both let you refer to "something conforming to P" as a value, but the trade-offs differ.

| | `some P` (opaque) | `any P` (existential) |
|---|---|---|
| When resolved | Compile time | Runtime |
| Dispatch | Static (fast) | Dynamic (small overhead) |
| Underlying type | One specific type, hidden from caller | May differ per value |
| Works with PATs directly | ✅ | Since Swift 5.7 with primary associated types |
| Heterogeneous collection | ❌ (all values same underlying type) | ✅ |
| Common use | SwiftUI `body: some View`, factory returns | Mixed collections, type-erased pipelines |

### Function that returns one concrete type

```swift
func makeStack() -> some Container<Int> {
    IntBox()
}
```

Caller can't see it's `IntBox`, but the compiler knows and inlines everything.

### Function that returns any conforming type

```swift
func loadContainer(kind: String) -> any Container<Int> {
    kind == "box" ? IntBox() : LinkedListBox()
}
```

Different branches return different concrete types — must be `any`.

### Rule of thumb

- Default to a **generic parameter `<T: P>`** when the function is called with one type per call site.
- Use **`some P`** when you want to hide the return type but keep static dispatch.
- Use **`any P`** only when you truly need heterogeneity or storage across kinds.

---

## When Generics Beat Overloading

### ❌ Overload explosion

```swift
func maxOf(_ a: Int, _ b: Int) -> Int { a > b ? a : b }
func maxOf(_ a: Double, _ b: Double) -> Double { a > b ? a : b }
func maxOf(_ a: String, _ b: String) -> String { a > b ? a : b }
```

Every new type = another copy of the same code.

### ✅ One generic function

```swift
func maxOf<T: Comparable>(_ a: T, _ b: T) -> T {
    a > b ? a : b
}

maxOf(1, 2)               // 2
maxOf(1.0, 2.0)           // 2.0
maxOf("a", "b")           // "b"
```

One implementation, checked once, works for every `Comparable`. This is the exact reason `Swift.max` is generic.

Overloading still wins when the implementations genuinely differ per type — but if the body is copy-paste, reach for generics.

---

## Anti-Pattern — Using `Any` Instead of Generics

### ❌ Erasing to `Any`

```swift
func firstElement(of array: [Any]) -> Any? {
    array.first
}

let n = firstElement(of: [1, 2, 3]) as? Int
```

Callers lose the type, need a cast, may crash if the cast fails, and the compiler can't help.

### ✅ Generic

```swift
func firstElement<T>(of array: [T]) -> T? {
    array.first
}

let n = firstElement(of: [1, 2, 3])   // Int? — no cast
```

Rule: **`Any` and `AnyObject` are escape hatches for edge cases (mixing types from a plist/JSON, bridging to Objective-C). Everywhere else, use generics.**

---

## Anti-Pattern — Over-Constraining

### ❌ Locking to a concrete type

```swift
func sum(_ ints: [Int]) -> Int { ints.reduce(0, +) }
```

Only works for `Int`. Doubles need a copy.

### ✅ Constrain to a protocol

```swift
func sum<T: Numeric>(_ values: [T]) -> T {
    values.reduce(.zero, +)
}

sum([1, 2, 3])            // Int
sum([1.5, 2.5])           // Double
```

Constrain to the smallest capability you actually need — no more, no less.

---

## Interaction with SwiftUI, Combine, Clean Architecture

- **SwiftUI:** `View` has an associated type `Body`. Every `body: some View` is opaque. Custom containers like `ForEach<Data, ID, Content>` are generic. See [[iOS SwiftUI Architecture - MVVM with Combine]].
- **Combine:** `Publisher` has associated types `Output` and `Failure`. Operators like `map`, `flatMap` are generic; pipelines are stitched together with static dispatch until you erase to `AnyPublisher<Output, Failure>` at the boundary.
- **Clean Architecture:** Domain repositories are protocols with associated types (see [[iOS Swift - Protocols]]). Use-case implementations are typically generic over the repository type, keeping them testable and inline-able. See [[iOS SwiftUI Architecture - Clean Architecture]] and [[iOS SwiftUI Architecture - Dependency Injection]].

```swift
struct FetchAllUseCase<Repo: CountryRepository> {
    let repository: Repo
    func callAsFunction() async throws -> [Country] {
        try await repository.fetchAll()
    }
}
```

The whole call chain specializes at compile time — no dynamic dispatch, no boxing.

---

## Summary

| Feature | Syntax | Purpose |
|---------|--------|---------|
| Generic function | `func f<T>(…)` | One body, many types |
| Generic type | `struct S<Element>` | Container / wrapper parameterized by type |
| Type constraint | `<T: Protocol>` or `<T: Class>` | Require capability from `T` |
| `where` clause | `where T.Element: Equatable` | Extra constraints, often on associated types |
| Associated type | `associatedtype Item` | Protocol-side placeholder |
| Primary associated type | `protocol P<Item>` | Expose one associated type for `some`/`any` |
| `some P` | Opaque return | Static dispatch, one hidden concrete type |
| `any P` | Existential | Dynamic dispatch, heterogeneous |
| Same-type constraint | `where A == B` | Exact type match |

Golden rule: **prefer generics with the smallest constraint that makes the body compile.** Reach for `any` only when heterogeneity is unavoidable.

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Protocols]] — associated types, `some` vs `any`
- [[iOS Swift - Extensions]] — conditional conformance is generics + extensions
- [[iOS Swift - Optionals]] — `Optional<Wrapped>` is a generic enum
- [[iOS Swift - Value vs Reference Types]] — `Array<T>` and `Dictionary<K, V>` are generic value types
- [[iOS Swift - Closures]] — closures + generics power `map`, `filter`, `reduce`
- [[iOS SwiftUI Architecture - Clean Architecture]] — generic use-cases over repositories
- [[iOS SwiftUI Architecture - Dependency Injection]] — generic seams vs existential seams
- [[iOS SwiftUI Architecture - MVVM with Combine]] — `Publisher` associated types

## Apple Docs

- The Swift Programming Language — Generics — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/
- The Swift Programming Language — Opaque and Boxed Types — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/
- `Array` reference — https://developer.apple.com/documentation/swift/array
