---
tags:
  - ios
  - swift
  - fundamentals
  - protocols
  - mobile
created: 2026-07-10
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/
  - https://developer.apple.com/videos/play/wwdc2015/408/
---

# iOS Swift — Protocols

> Swift's contract type. If you're coming from Java/Kotlin, these are interfaces — but with default implementations, value-type conformance, and a whole design philosophy (POP) built around them. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Protocol** — a named contract that lists required properties, methods, initializers, and associated types. Types (structs, classes, enums, actors) declare conformance to promise they implement the contract.
- **Conformance** — declaring that a type satisfies a protocol, written `struct Foo: Bar { … }`.
- **Protocol composition** — combining multiple protocols with `&`: `Codable & Identifiable`.
- **Protocol extension** — adding default implementations to a protocol so conformers get the method for free.
- **Protocol-Oriented Programming (POP)** — Swift's design style: prefer protocols + value types + protocol extensions over class inheritance. Introduced at WWDC 2015.
- **Associated type** — a placeholder type declared inside a protocol with `associatedtype`. The conformer picks the concrete type.
- **Existential** — a runtime box holding "some value whose type conforms to P." Written `any P` since Swift 5.7.
- **Opaque type** — a compile-time-known but hidden concrete type. Written `some P`. The compiler knows the type; the caller doesn't.
- **PAT** — Protocol with Associated Types. Cannot be used as a plain type; must be used with `some`, `any`, or as a generic constraint.

---

## Declaration Syntax

```swift
protocol Identifiable {
    var id: String { get }
}

protocol Drawable {
    func draw()
    mutating func scale(by factor: Double)
}
```

- `{ get }` = read-only requirement (conformer can back it with `let` or `var`).
- `{ get set }` = read-write requirement (conformer must back it with `var`).
- `mutating` = required on methods that mutate `self` when the conformer is a value type.

---

## Conformance

```swift
struct Country: Identifiable {
    let id: String
    let name: String
}

struct Circle: Drawable {
    var radius: Double
    func draw() { print("O") }
    mutating func scale(by factor: Double) { radius *= factor }
}
```

A type can conform to any number of protocols; conformance can also be declared in an [[iOS Swift - Extensions]] block, which is the idiomatic way to organize it.

```swift
struct Country {
    let id: String
    let name: String
}

extension Country: Identifiable {}
```

---

## Protocol Composition (`&`)

Use `&` to require conformance to multiple protocols at once, without declaring a new named protocol.

```swift
func save(_ item: Codable & Identifiable) {
    // item has both id and encode(to:)
}
```

Composition is anonymous — no need to invent a `CodableIdentifiable` protocol.

---

## Protocol Extensions — Default Implementations

The single feature that separates Swift protocols from Java interfaces pre-Java 8. Add method bodies inside `extension Protocol`:

```swift
protocol Greetable {
    var name: String { get }
    func greet()
}

extension Greetable {
    func greet() {
        print("Hello, \(name)!")
    }
}

struct Person: Greetable { let name: String }

Person(name: "Sang").greet()
```

Conformers get `greet()` for free. They can still override it by providing their own implementation.

You can also constrain the extension:

```swift
extension Collection where Element: Numeric {
    func sum() -> Element {
        reduce(.zero, +)
    }
}

[1, 2, 3].sum()          // 6
[1.0, 2.0].sum()         // 3.0
```

See [[iOS Swift - Extensions]] for the full mechanics.

---

## Protocol-Oriented Programming (POP)

The Swift standard-library style: model behavior with protocols + protocol extensions + value types, not class hierarchies.

```swift
protocol Animal {
    var name: String { get }
    func speak()
}

extension Animal {
    func introduce() { print("I am \(name)") }
}

struct Dog: Animal {
    let name: String
    func speak() { print("Woof") }
}

struct Cat: Animal {
    let name: String
    func speak() { print("Meow") }
}
```

No superclass, no `override`, no reference semantics you didn't ask for. Compare with [[iOS Swift - Value vs Reference Types]] — POP leans on value types.

### ❌ Inheritance-first (Java style)

```swift
class Animal {
    let name: String
    init(name: String) { self.name = name }
    func speak() { fatalError("subclass must override") }
}

class Dog: Animal {
    override func speak() { print("Woof") }
}
```

Problems: forced reference semantics, runtime crash for missing overrides, deep hierarchies.

### ✅ Protocol-first

```swift
protocol Animal {
    var name: String { get }
    func speak()
}

struct Dog: Animal {
    let name: String
    func speak() { print("Woof") }
}
```

Compiler enforces `speak()`. Value semantics. Composition over inheritance.

---

## Associated Types (`associatedtype`)

When a protocol needs to talk about "some type the conformer chooses," use `associatedtype`.

```swift
protocol Repository {
    associatedtype Item
    func fetch(id: String) async throws -> Item
    func save(_ item: Item) async throws
}

struct CountryRepository: Repository {
    typealias Item = Country
    func fetch(id: String) async throws -> Country { … }
    func save(_ item: Country) async throws { … }
}
```

Swift can usually infer the `typealias` from the method signatures — write it explicitly only when the compiler can't infer it.

Associated types are the Swift analogue to generics on an interface (`interface Repository<T>` in Kotlin/Java). See the full recap in [[iOS Swift - Generics]].

---

## Existentials (`any Protocol`)

An existential is a **runtime** box holding some conforming value.

```swift
let animals: [any Animal] = [Dog(name: "Rex"), Cat(name: "Milo")]
for a in animals { a.speak() }
```

- Heterogeneous collection: OK.
- Costs a dynamic dispatch + a small heap allocation per element.
- Can't be used for PATs unless you also erase the associated types (e.g. `any Repository<Country>` since Swift 5.7 primary associated types).

Since Swift 5.7, `any` is **required** when you mean an existential — bare `Animal` as a type is a warning today, an error tomorrow.

---

## Opaque Return Types (`some Protocol`)

An opaque type is a **compile-time** commitment: "I return one specific concrete type conforming to P, but I'm hiding which."

```swift
func makeAnimal() -> some Animal {
    Dog(name: "Rex")
}
```

- The caller sees `some Animal` — can call `speak()`, `introduce()`.
- The compiler knows it's exactly `Dog` — no dynamic dispatch, no boxing.
- Every call site of `makeAnimal()` gets the *same* underlying type.

SwiftUI's `some View` is the canonical example — every `body: some View` returns a single concrete view type the compiler works out from the expression.

---

## `some` vs `any` — Which to Pick

| Question | Answer |
|----------|--------|
| Do you want one concrete type, hidden from the caller? | `some` |
| Do you want to store a mixed collection of different conformers? | `any` |
| Does the protocol have `associatedtype`s and you want to use it as a value type? | `some`, or `any` with primary associated types (`any Repository<Country>`) |
| Do you want zero-cost, statically-dispatched calls? | `some` (or a generic `<T: P>`) |
| Do you want maximum flexibility at the cost of dynamic dispatch? | `any` |

Rule of thumb: **default to `some` (or generics). Reach for `any` only when you need heterogeneity or runtime polymorphism.**

### ❌ Existential where opaque would do

```swift
func loadView() -> any View {   // dynamic dispatch, unnecessary boxing
    Text("Hello")
}
```

### ✅ Opaque

```swift
func loadView() -> some View {   // compile-time Text, zero cost
    Text("Hello")
}
```

---

## Anti-Pattern — Class-Bound Protocols by Default

### ❌ Marking every protocol `AnyObject`

```swift
protocol UserService: AnyObject {
    func fetchUser() async throws -> User
}
```

Forces reference semantics. Prevents struct/enum conformance. Only do this when you *need* identity or `weak` references (delegate patterns, mostly).

### ✅ Leave it open

```swift
protocol UserService {
    func fetchUser() async throws -> User
}
```

Now both `struct MockUserService: UserService` (tests) and `final class LiveUserService: UserService` (production) work. This is the pattern used in [[iOS SwiftUI Architecture - Dependency Injection]].

---

## Interaction with SwiftUI + Clean Architecture

Protocols are the backbone of both:

- **DI:** Views take a protocol dependency; production and preview code inject different conformers. See [[iOS SwiftUI Architecture - Dependency Injection]].
- **Clean Architecture:** Use-cases and repositories are declared as protocols in the domain layer; concrete implementations live in the data layer. See [[iOS SwiftUI Architecture - Clean Architecture]].
- **MVVM:** ViewModels expose behavior as `@Published` properties + methods; a `protocol CountryListViewModel` lets you swap real and mock VMs in previews. See [[iOS SwiftUI Architecture - MVVM with Combine]].

```swift
protocol CountryRepository {
    func fetchAll() async throws -> [Country]
}

final class LiveCountryRepository: CountryRepository { … }
struct MockCountryRepository: CountryRepository {
    func fetchAll() async throws -> [Country] { [Country(id: "VN", name: "Vietnam")] }
}
```

---

## Comparison with Java / Kotlin Interfaces

| Feature | Swift Protocol | Java Interface | Kotlin Interface |
|---------|---------------|-----------------|------------------|
| Multiple conformance | ✅ | ✅ | ✅ |
| Default implementations | ✅ (via extensions) | ✅ (Java 8+ default methods) | ✅ |
| Value-type conformance (struct/enum) | ✅ | ❌ (classes only) | ❌ (classes only) |
| Associated types | ✅ (`associatedtype`) | ❌ (generic interface only) | ❌ (generic interface only) |
| Runtime existentials | `any P` | plain `P` reference | plain `P` reference |
| Opaque return types | ✅ (`some P`) | ❌ | ❌ |

The key Swift-specific idea: protocols work with **value types**, and `some` gives you static polymorphism for free.

---

## Summary

| Tool | Meaning | When to use |
|------|---------|-------------|
| `protocol P { … }` | Declare a contract | Any time you want to abstract behavior |
| `struct T: P` | Declare conformance | On the type, or in an [[iOS Swift - Extensions]] block |
| `A & B` | Compose two protocols | Ad-hoc "must satisfy both" |
| `extension P where …` | Default implementations | Share code across conformers |
| `associatedtype X` | Generic placeholder inside a protocol | Repository, Container, Sequence-like APIs |
| `any P` | Runtime existential | Mixed collections, dynamic dispatch |
| `some P` | Compile-time opaque type | SwiftUI `body`, factory returns |
| `: AnyObject` | Class-only protocol | Delegates, `weak` references |

Golden rule: **write the protocol first, pick the conformer's kind (struct/class/enum) second.**

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Extensions]] — the delivery mechanism for default implementations
- [[iOS Swift - Generics]] — associated types are the protocol version of generics
- [[iOS Swift - Value vs Reference Types]] — POP leans on values
- [[iOS Swift - Closures]] — often paired with protocol methods for callbacks
- [[iOS Swift - Property Wrappers]] — many wrappers are built on protocols (`DynamicProperty`)
- [[iOS SwiftUI Architecture - Dependency Injection]] — protocols as injection seams
- [[iOS SwiftUI Architecture - Clean Architecture]] — domain layer is protocols
- [[iOS SwiftUI Architecture - MVVM with Combine]] — protocol-based ViewModels for previews

## Apple Docs

- The Swift Programming Language — Protocols — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/
- The Swift Programming Language — Opaque and Boxed Types — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/
- WWDC 2015 — Protocol-Oriented Programming in Swift — https://developer.apple.com/videos/play/wwdc2015/408/
