---
tags:
  - ios
  - swift
  - fundamentals
  - value-types
  - reference-types
  - struct
  - class
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/structuresandclasses/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/structuresandclasses/
  - https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes
---

# iOS Swift — Value vs Reference Types

> The single most important type-system decision in Swift. Get this right and half of iOS makes sense. Back to [[iOS Swift Fundamentals Guide]].

---

## The Split

Swift has two kinds of user-defined types:

| | Value type | Reference type |
|-|------------|----------------|
| Keyword | `struct`, `enum`, tuple | `class`, `actor` |
| Semantics | **Copied** on assignment | **Shared** — new bindings point to the same instance |
| Identity | None — two structs with equal properties are equal | Has identity (`===`) — even equal-valued instances are distinct |
| Memory | Usually stack (or inline in the enclosing type) | Always heap; managed by [[iOS ARC Guide|ARC]] |
| Inheritance | ❌ No subclassing | ✅ Subclassing (`class`) |
| Mutation from `let` | ❌ Whole binding is frozen | ✅ Properties can still mutate if they're `var` |

If you remember one thing: **structs are copied, classes are shared.**

---

## The Canonical Example

```swift
struct StructPoint { var x: Int; var y: Int }
class  ClassPoint  { var x: Int; var y: Int
    init(x: Int, y: Int) { self.x = x; self.y = y }
}

var a = StructPoint(x: 1, y: 2)
var b = a                        // b is a COPY
b.x = 99
print(a.x)                       // 1  — a unchanged ✅

var c = ClassPoint(x: 1, y: 2)
var d = c                        // d points to the SAME instance
d.x = 99
print(c.x)                       // 99 — c mutated through d ⚠️
```

Assignment for a `struct` runs a copy. Assignment for a `class` runs a pointer copy — both variables now reference the same heap object.

---

## Why Value Types Are Swift's Default

Apple's [official guidance](https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes):

> **Use structures by default.** Use classes when you need Objective-C interop, need identity, or need to control the lifetime of shared, mutable state.

Reasons:

1. **Thread safety by construction.** A value type passed to another thread is a copy — no shared mutable state, no data race.
2. **Predictable behavior.** No spooky action at a distance. You know a function can't mutate the value you passed in unless it says `inout`.
3. **SwiftUI needs it.** `View` is a `struct`. SwiftUI diffs values cheaply because they're immutable snapshots. See [[iOS SwiftUI - Core Concepts]].
4. **Compiler optimizations.** Structs often live on the stack or get inlined, avoiding heap allocations.

---

## When You Actually Need a Class

The narrow but important cases:

- **You need identity.** Two "same-looking" instances must be distinguishable. Example: two `URLSessionTask`s are distinct even if they hit the same URL.
- **You need shared mutable state.** A cache, a database connection, an audio player — one instance, multiple owners.
- **Objective-C interop.** UIKit types (`UIViewController`, `UIView`) are classes because they bridge to Obj-C.
- **You need `deinit`.** Only classes have destructors. See [[iOS ARC - How It Works]].
- **You need inheritance.** Structs can't subclass. Prefer composition + protocols (Protocol-Oriented Programming) when possible.

In this tutorial:

| Type | Why | Reference |
|------|-----|-----------|
| `Country` | Domain entity, immutable, cheap to copy | `struct` |
| `CountryDTO` | Transport shape, no identity | `struct` |
| `CountriesRepositoryImpl` | Stateless implementation | `struct` |
| `CountriesViewModel` | UI state owner — SwiftUI subscribes to its `@Observable` properties | `class` (via `@Observable`) |

The ViewModel is the odd one out — it's a class *specifically because* SwiftUI needs a stable identity to observe state changes across `body` re-invocations.

---

## Mutability Rules — the `let` Twist

`let` locks the **binding**, not always the value:

```swift
struct Point { var x, y: Int }
let p = Point(x: 1, y: 2)
// p.x = 99         // ❌ compile error — p is 'let', struct is frozen whole

class Box { var value = 0 }
let b = Box()
b.value = 99         // ✅ ok! `let` locks the reference, not the object.
b.value = 100        // ✅ still ok
// b = Box()         // ❌ can't reassign the reference itself
```

For a `struct`, `let` = frozen everything.
For a `class`, `let` = frozen reference, but the object itself is still mutable.

**Consequence:** to make a class truly immutable, declare its properties `let`. To make a struct mutable, use `var` for both the binding and its mutating properties.

---

## `mutating` Methods

Methods on a value type that change `self` must be marked `mutating`:

```swift
struct Counter {
    var count = 0
    mutating func increment() { count += 1 }
}

var c = Counter()      // must be var
c.increment()          // ✅ ok
let d = Counter()
// d.increment()       // ❌ can't call mutating method on 'let'
```

Classes have no such keyword — a `class` method can freely mutate `self` because you already share the reference.

---

## Enums Are Value Types Too

`enum` is a value type. Common iOS patterns:

```swift
enum LoadState {
    case idle
    case loading
    case loaded([Country])
    case failed(Error)
}
```

- Copied on assignment (cheap — enums are usually a single discriminator byte + inline payload).
- Perfect for view state, network state, feature flags.
- Pattern-matched with `switch` — exhaustiveness checking is a compile-time win.

---

## The One Escape Hatch: `class` in a Value-Type World

If you need "shared mutable state, but I want to hand it around like a value" — wrap the class:

```swift
final class Storage { var items: [Country] = [] }

struct CountriesStore {
    private let storage = Storage()   // reference held by every copy
    var items: [Country] {
        get { storage.items }
        set { storage.items = newValue }
    }
}
```

Every `CountriesStore` copy shares the same `Storage`. This is the mechanism behind Swift's copy-on-write collections (`Array`, `Dictionary`) — the struct is small, the buffer is a class, sharing is transparent.

You'll rarely write this yourself. Reach for it only when profiling proves you're copying huge arrays hot.

---

## Common Traps

| Trap | Fix |
|------|-----|
| Passing a `class` VM to a child view and mutating it — parent sees the change but the parent's view doesn't re-render | Use `@Observable` (iOS 17+) or `@Published` + `@ObservedObject` — see [[iOS SwiftUI Architecture - Observation Macro]] |
| Storing a `class` inside a `struct` and expecting isolation | You get a shared reference. Either use `struct` end-to-end or acknowledge the sharing. |
| Copying a big `[UIImage]` array around and profiling shows CPU spikes | Arrays are copy-on-write — copying is cheap until you mutate one side. Profile before optimizing. |
| `class` VM without `deinit` for cleanup | If you own network subscriptions (`Set<AnyCancellable>`), let ARC handle it — the cancellables cancel automatically on deinit. See [[iOS ARC Guide]]. |

---

## Summary — Which Do I Reach For?

```
Do you need identity, subclassing, deinit, or Obj-C interop?
├─ Yes → class
└─ No  → struct  (default for 90% of new types)
```

Then:

- If it holds UI state observed by SwiftUI → still `class`, but wrapped by `@Observable`.
- If it holds shared mutable state → `class`, and consider `actor` if crossing threads.
- Everything else → `struct`.

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Values and Types]] — the layer below
- [[iOS ARC Guide]] — reference-type memory management
- [[iOS SwiftUI Architecture - Observation Macro]] — why VMs are classes even in a value-first world
- [[iOS Swift Core Tech Guide]] — POP era (Swift 2) established value-first as the norm

## Apple Docs

- Structures and Classes — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/structuresandclasses/
- Choosing Between Structures and Classes — https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes
- Value and Reference Types (WWDC) — https://developer.apple.com/videos/play/wwdc2015/414/
