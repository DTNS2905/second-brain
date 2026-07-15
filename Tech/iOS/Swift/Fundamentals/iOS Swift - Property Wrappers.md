---
tags:
  - ios
  - swift
  - fundamentals
  - property-wrappers
  - mobile
created: 2026-07-10
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/properties/#Property-Wrappers
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/properties/#Property-Wrappers
  - https://developer.apple.com/documentation/swiftui/state
  - https://developer.apple.com/documentation/foundation/userdefaults
---

# iOS Swift — Property Wrappers

> The language feature that powers `@State`, `@Published`, `@AppStorage`, and friends. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Property wrapper**: a type marked `@propertyWrapper` that transforms how a stored property is *read* and *written*. You attach it to a property with `@Name`, and the compiler generates a hidden storage property of the wrapper type and rewrites `get`/`set` to go through it.
- **`wrappedValue`**: the *required* property on a wrapper. This is what `myProperty` reads/writes to. It's the "unwrapped" value the caller sees.
- **`projectedValue`**: an *optional* secondary value exposed through the `$` sigil (`$myProperty`). Convention: use it for something related-but-different — a binding, a publisher, a validator.
- **`$` sigil**: prefix that accesses `projectedValue` instead of `wrappedValue`. `progress` gives you the `Int`; `$progress` gives you whatever the wrapper projects.
- **Synthesized storage**: for `@Foo var x: Int`, the compiler creates a hidden `_x: Foo` property. You almost never touch it directly.

Prerequisites: [[iOS Swift - Values and Types]], [[iOS Swift - Value vs Reference Types]], [[iOS Swift - Protocols]].

---

## Anatomy

A minimal wrapper has one required piece: `wrappedValue`.

```swift
@propertyWrapper
struct Trimmed {
    private var value: String = ""

    var wrappedValue: String {
        get { value }
        set { value = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    init(wrappedValue: String) {
        self.wrappedValue = wrappedValue
    }
}

struct User {
    @Trimmed var name: String
}

var u = User(name: "  Sang  ")
print(u.name)   // "Sang"
u.name = "  Liem\n"
print(u.name)   // "Liem"
```

The `@Trimmed` on `name` desugars to:

```swift
private var _name: Trimmed = Trimmed(wrappedValue: "  Sang  ")
var name: String {
    get { _name.wrappedValue }
    set { _name.wrappedValue = newValue }
}
```

---

## Worked Example: `@Clamped`

Constrain a numeric property to a range, with a `projectedValue` reporting whether the last write was clamped.

```swift
@propertyWrapper
struct Clamped<Value: Comparable> {
    private var value: Value
    private let range: ClosedRange<Value>
    private(set) var wasClamped: Bool = false

    var wrappedValue: Value {
        get { value }
        set {
            wasClamped = !range.contains(newValue)
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }

    var projectedValue: Bool { wasClamped }

    init(wrappedValue: Value, _ range: ClosedRange<Value>) {
        self.range = range
        self.value = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }
}

struct Download {
    @Clamped(0...100) var progress: Int = 0
}

var d = Download()
d.progress = 150
print(d.progress)     // 100
print(d.$progress)    // true — projectedValue tells us it was clamped
```

Note the initializer signature: the first parameter is `wrappedValue`, extra parameters go inside the `@Clamped(...)` attribute.

---

## Worked Example: `@UserDefault`

Wrap `UserDefaults` (iOS's key-value settings store) so reading/writing a property persists automatically.

```swift
@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    let store: UserDefaults = .standard

    var wrappedValue: Value {
        get { store.object(forKey: key) as? Value ?? defaultValue }
        set { store.set(newValue, forKey: key) }
    }
}

enum Preferences {
    @UserDefault(key: "hasSeenOnboarding", defaultValue: false)
    static var hasSeenOnboarding: Bool

    @UserDefault(key: "launchCount", defaultValue: 0)
    static var launchCount: Int
}

Preferences.launchCount += 1        // persisted across app launches
```

This is essentially what SwiftUI's `@AppStorage` is — see [[iOS SwiftUI - Property Wrappers]] for its observation integration.

---

## The `$` Sigil in Practice

```swift
@Clamped(0...100) var progress: Int = 0

progress       // Int             → wrappedValue
$progress      // Bool            → projectedValue (wasClamped)
_progress      // Clamped<Int>    → the wrapper itself (rarely used)
```

In SwiftUI you'll see `$` all the time — `@State var name = ""` gives `$name` a `Binding<String>` that child views can write to. That's `projectedValue` doing its job.

---

## How SwiftUI Wrappers Fit In

SwiftUI's headline property wrappers are all built on this exact mechanism:

| Wrapper | `wrappedValue` | `projectedValue` (`$`) |
|---------|----------------|------------------------|
| `@State` | the stored value | `Binding<Value>` |
| `@Binding` | read/write proxy | `Binding<Value>` |
| `@Published` (Combine) | the stored value | `Publisher<Value, Never>` |
| `@AppStorage` | value in `UserDefaults` | `Binding<Value>` |
| `@Environment` | value read from environment | — |
| `@StateObject` / `@ObservedObject` | the reference-type object | `Binding` to its properties |

Each of these gets its own note — see [[iOS SwiftUI - Property Wrappers]]. Understanding the language feature here makes SwiftUI's magic feel much less magical.

---

## Composition (Limited Support)

You *can* stack wrappers, but only if the inner wrapper's `wrappedValue` type matches what the outer expects. In practice this is fragile and rarely worth it:

```swift
@propertyWrapper
struct Logged<Value> {
    private var value: Value
    var wrappedValue: Value {
        get { value }
        set { print("set to \(newValue)"); value = newValue }
    }
    init(wrappedValue: Value) { self.value = wrappedValue }
}

struct Example {
    @Logged @Clamped(0...100) var progress: Int = 0
}
```

If it doesn't compile on the first try, stop. Prefer building one wrapper that does both jobs.

---

## Anti-Pattern: Hiding Side Effects

Property wrappers should be *transparent* transformations of storage. Anything a caller can't reasonably guess by seeing `@Name` at the declaration is a footgun.

### ❌ Before — network I/O in a setter

```swift
@propertyWrapper
struct SyncedToServer<Value: Encodable> {
    private var value: Value
    var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            URLSession.shared.dataTask(with: /* POST to /update */).resume()
        }
    }
    init(wrappedValue: Value) { self.value = wrappedValue }
}

struct Profile {
    @SyncedToServer var name: String    // caller has no idea a write triggers a network call
}

profile.name = "Sang"    // silently fires a POST — untestable, unobservable, race-prone
```

### ✅ After — explicit call site

```swift
struct Profile {
    var name: String
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: Profile
    private let repo: ProfileRepository

    func updateName(_ new: String) async throws {
        profile.name = new
        try await repo.save(profile)   // side effect visible at the call site
    }
}
```

Rule of thumb: if the transformation isn't pure (or at least local to that one value), it doesn't belong in a wrapper.

---

## When to Reach for a Property Wrapper

| You want to… | Use |
|--------------|-----|
| Enforce a validation rule on every write (clamp, trim, uppercase) | `@propertyWrapper` |
| Persist a single value transparently | `@propertyWrapper` (or `@AppStorage`) |
| Expose a paired value (binding, publisher, validation flag) via `$` | `@propertyWrapper` with `projectedValue` |
| Compute a value from *other* properties on demand | **computed property** — no wrapper needed |
| Run a side effect (network, analytics) on assignment | **explicit setter method** — not a wrapper |
| Reuse behavior across one property in one type | plain `didSet` / `willSet` observer — a wrapper is overkill |

If the behavior applies to a single property in a single type, `didSet` is simpler. If it applies to N properties across M types, a wrapper pays for itself.

---

## Summary

| Concept | Meaning |
|---------|---------|
| `@propertyWrapper` | Attribute on a type that lets it be used as `@Name` on properties |
| `wrappedValue` | **Required**. What the caller reads/writes through the property name |
| `projectedValue` | **Optional**. What the caller reads through `$propertyName` |
| `$` sigil | Access `projectedValue` |
| `_propertyName` | The wrapper instance itself — rarely touched |
| Init parameters | First is `wrappedValue`; extras go inside `@Name(...)` |
| Composition | Supported but brittle — prefer one wrapper doing two jobs |

Golden rule: **a property wrapper is a lens on storage, not a hook for side effects.**

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Values and Types]] — what a stored property even is
- [[iOS Swift - Value vs Reference Types]] — wrappers as structs vs classes
- [[iOS Swift - Optionals]] — many wrappers use `Optional` in their storage
- [[iOS Swift - Protocols]] — generic wrappers usually constrain their `Value`
- [[iOS SwiftUI - Property Wrappers]] — the SwiftUI-specific set (`@State`, `@Binding`, `@Published`, `@AppStorage`, `@Environment`)

## Apple Docs

- The Swift Language Guide — Property Wrappers — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/properties/#Property-Wrappers
- `@State` reference — https://developer.apple.com/documentation/swiftui/state
- `UserDefaults` reference — https://developer.apple.com/documentation/foundation/userdefaults
