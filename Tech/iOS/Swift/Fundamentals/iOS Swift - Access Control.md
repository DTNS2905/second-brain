---
tags:
  - ios
  - swift
  - fundamentals
  - access-control
  - mobile
created: 2026-07-10
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/
---

# iOS Swift - Access Control

> Swift's six-level system for deciding who can see, call, subclass, or override your code. The tool that keeps a codebase from turning into a wire-mesh ball. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Access control** — compile-time rules about which code can reference a declaration (a type, method, property, initializer, etc.).
- **Module** — a unit of code distribution. An app target is one module. Each framework target (e.g., `NetworkKit.framework`) is its own module. Files in the same module can see one another's `internal` declarations.
- **Source file** — a single `.swift` file inside a module. Boundary for `fileprivate` and `private`.
- **Package** — a Swift Package Manager package. Boundary for the `package` access level.
- **Open** — the highest visibility. Public *and* subclassable/overridable from outside the module.
- **Public** — visible outside the module, but only *subclassable/overridable inside* the defining module.
- **Package** (keyword) — visible to any code in the same Swift package but hidden from code that only depends on the package.
- **Internal** — visible anywhere inside the same module, hidden outside it. **The default** if you write no keyword.
- **File-private** — visible only in the same source file.
- **Private** — visible only in the same declaration (`class`, `struct`, `enum`, `extension`) and its extensions *in the same file*.
- **`private(set)`** — the getter has the outer access level; the setter is `private`. Public read, private write.

---

## The Six Levels, Ranked

From most to least visible:

```
open > public > package > internal > fileprivate > private
```

```swift
open class OpenPokemon {}          // subclass from anywhere
public class PublicPokemon {}      // reference from anywhere, subclass only in-module
package class PackagePokemon {}    // reference from anywhere in the package
internal class InternalPokemon {}  // reference in-module only (default)
fileprivate class FilePokemon {}   // reference in the same file
private class PrivatePokemon {}    // reference in the same enclosing declaration
```

---

## What Each Level Means Concretely

### `open` (frameworks only)

- Reference from any module.
- Subclass from any module.
- Override methods/properties from any module.

Use for framework classes that clients are *meant* to subclass — e.g., a base view controller you ship for consumers to extend. In app code, `open` is almost never right.

### `public`

- Reference from any module.
- *Cannot* be subclassed or overridden from outside the defining module.

Default choice for framework API you want to expose but not have subclassed. Add `open` only when subclassing is an intentional extension point.

### `package` (Swift 5.9+)

- Reference from any code in the same Swift package.
- Hidden from clients that consume the package as a dependency.

Useful when you split one product into several targets inside a package (e.g., `App`, `NetworkKit`, `DesignSystem`) and want them to share internals without leaking those internals to consumers.

### `internal` (default)

- Reference anywhere inside the same module.
- Hidden from other modules.

**This is the default.** You don't need to write `internal` — omitting the keyword means `internal`. Most app code stays here.

### `fileprivate`

- Reference only within the same `.swift` file.

Reach for it when two types in the same file need to share a helper that shouldn't leak.

### `private`

- Reference only within the enclosing declaration (and its extensions *in the same file*).

The tightest level. Default for stored properties and helper methods on a type.

---

## Property, Method, Initializer Rules

Access control applies to almost every named declaration:

```swift
public struct CountryRepository {
    private let api: CountryAPI                     // hidden from outside
    private var cache: [String: Country] = [:]      // hidden from outside

    public init(api: CountryAPI) {                  // callable from outside
        self.api = api
    }

    public func country(code: String) async throws -> Country {
        if let hit = cache[code] { return hit }
        let fresh = try await api.fetchCountry(code: code)
        cache[code] = fresh
        return fresh
    }

    private func normalize(_ code: String) -> String {  // internal helper
        code.uppercased()
    }
}
```

A type's members can be *no more visible* than the type itself. If `CountryRepository` is `internal`, its methods can't be `public` — the compiler blocks it.

---

## `private(set)` — Public Read, Private Write

Very common in ViewModels and Repositories. See [[iOS SwiftUI Architecture - MVVM with Combine]].

```swift
final class CountryListViewModel: ObservableObject {
    @Published private(set) var countries: [Country] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: DomainError?

    func load() {
        isLoading = true
        Task {
            do {
                countries = try await repository.allCountries()
                error = nil
            } catch let error as DomainError {
                self.error = error
            }
            isLoading = false
        }
    }
}
```

The View can *read* `countries`, `isLoading`, `error` to render — but only the ViewModel can *write* them. That's the "single source of truth" invariant enforced by the compiler.

Syntax: pick the outer access (defaults to `internal`), then `private(set)` clamps the setter.

```swift
public private(set) var value: Int = 0     // public read, private write
internal private(set) var count: Int = 0   // internal read, private write
```

---

## Access Levels in Extensions

An `extension` inherits the access level of the extended type by default. You can raise or lower individual members inside it.

```swift
public struct Country { ... }

extension Country {                     // internal by default from the file
    func normalized() -> Country { ... }
}

public extension Country {              // members are public by default
    var isSmall: Bool { area < 1_000 }
}

private extension Country {             // members are file-private in effect
    func debugDump() { ... }
}
```

You cannot mark a member `public` inside a `private extension` — the extension caps it.

### `private` extensions can see private members

A `private extension` in the *same file* as the type can access the type's `private` members. This is the trick that lets you split a type across small focused extensions without switching to `fileprivate`.

```swift
struct Country {
    private let region: String
}

extension Country {
    var isAsian: Bool { region == "Asia" }   // ✅ can read region — same file
}
```

---

## Module Boundaries: App vs Framework

A typical iOS app has one app target — everything is in one module, so `internal` (the default) works everywhere. Access control mostly means `private` on stored properties.

Once you split into frameworks or Swift packages (a common Clean Architecture step), the boundaries become real:

```
DomainKit (package)          — pure entities and use cases
    ↑ depended on by
NetworkKit (package)         — repository implementations
    ↑ depended on by
App (app target)             — SwiftUI views, ViewModels
```

- Types you want other modules to see must be `public`.
- Types shared between `DomainKit` and `NetworkKit` internals (but hidden from `App`) can be `package`.
- Anything not `public` stays inside its module.

See [[iOS SwiftUI Architecture - Data Layer]] for a concrete split.

---

## Why `internal` Is the Default

The Swift language guide's justification: **most code is app code**, and in an app the module boundary is your natural encapsulation boundary. `internal` gives free movement inside the app without accidentally exposing anything to hypothetical future clients. If you're not writing a framework, `public` is almost never the answer.

Compare with other languages where `public` is often the default and encapsulation is a discipline problem — Swift makes the default the *safe* choice.

---

## Interaction with Protocols

A protocol's access level caps everything about it:

```swift
public protocol CountryRepositoryProtocol {
    func country(code: String) async throws -> Country
}
```

If the protocol is `public`, **every conforming type's implementation of its requirements must also be `public`.** The compiler enforces this — a public protocol requirement can't be satisfied by an internal method.

```swift
public struct RemoteCountryRepository: CountryRepositoryProtocol {
    public func country(code: String) async throws -> Country { ... }   // must be public
}
```

Contrast:

```swift
protocol CountryRepositoryProtocol {                     // internal
    func country(code: String) async throws -> Country
}

struct RemoteCountryRepository: CountryRepositoryProtocol {
    func country(code: String) async throws -> Country { ... }          // internal is fine
}
```

Design rule: **the protocol's visibility should match its intended usage.** If only your app talks to the repository, keep the protocol `internal`. Make it `public` only when a *different module* needs to reference the type. See [[iOS Swift - Protocols]].

---

## Anti-Patterns

### Making everything `public` "just in case"

```swift
// ❌ Every property and method is a maintenance commitment to outside callers
public struct CountryRepository {
    public let api: CountryAPI
    public var cache: [String: Country] = [:]

    public func normalize(_ code: String) -> String { code.uppercased() }
}

// ✅ Expose the smallest useful surface
public struct CountryRepository {
    private let api: CountryAPI
    private var cache: [String: Country] = [:]

    public init(api: CountryAPI) { self.api = api }
    public func country(code: String) async throws -> Country { ... }
}
```

Anything `public` becomes contract. `internal` and `private` can be refactored freely.

### `public` without `open` when you meant subclassable

```swift
// ❌ Consumers can reference BaseCoordinator but cannot subclass it — you probably meant them to
public class BaseCoordinator { ... }

// ✅ Explicitly opt in to subclassing
open class BaseCoordinator { ... }
```

`public` for a class is the "final by default" choice. Reach for `open` only when subclassing is a supported extension point.

### Public storage instead of `private(set)`

```swift
// ❌ Callers can mutate your invariants
public final class CountryListViewModel: ObservableObject {
    @Published public var countries: [Country] = []
}

// ✅ Read from outside, write only from inside
public final class CountryListViewModel: ObservableObject {
    @Published public private(set) var countries: [Country] = []
}
```

### `fileprivate` when `private` would do

`fileprivate` used to be a common workaround before `private` extensions in the same file could see private members. In modern Swift, `private` is almost always tighter and equally convenient. Reach for `fileprivate` only when two *different* types in the same file must share access.

---

## Summary

| Level | Same declaration | Same file | Same module | Same package | Anywhere | Subclass anywhere |
|-------|:-:|:-:|:-:|:-:|:-:|:-:|
| `private` | Yes | | | | | |
| `fileprivate` | Yes | Yes | | | | |
| `internal` (default) | Yes | Yes | Yes | | | |
| `package` | Yes | Yes | Yes | Yes | | |
| `public` | Yes | Yes | Yes | Yes | Yes | |
| `open` | Yes | Yes | Yes | Yes | Yes | Yes |

| Modifier | Meaning |
|----------|---------|
| `private(set)` | Getter at outer level, setter is `private` |
| `public private(set)` | Read from anywhere, write only from within the type |
| `open` on a class | Subclassable from other modules |
| `open` on a method | Overridable from other modules |

Golden rule: **write the least visible thing that still compiles.** Widen only when a real caller in a different scope needs it.

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Protocols]] — public protocols force public conforming members
- [[iOS Swift - Value vs Reference Types]] — `open` and subclassing only apply to classes
- [[iOS SwiftUI Architecture - Data Layer]] — where module boundaries and `public` API design get concrete
- [[iOS SwiftUI Architecture - MVVM with Combine]] — `@Published private(set)` is the ViewModel default

## Apple Docs

- Access Control — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/
