---
tags:
  - ios
  - swift
  - fundamentals
  - closures
  - concurrency
  - arc
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/
  - https://developer.apple.com/documentation/swift/closures
---

# iOS Swift — Closures

> Anonymous functions with captured state. The second most-common newbie trap (after optionals). Get closures right and Combine, async callbacks, and SwiftUI trailing-modifier syntax all click. Back to [[iOS Swift Fundamentals Guide]].

---

## What Is a Closure?

A closure is a self-contained block of code you can pass around like a value. It "closes over" — captures — variables from the surrounding scope.

```swift
let greet = { (name: String) in
    print("Hello, \(name)")
}
greet("Vietnam")     // "Hello, Vietnam"
```

Three properties:

1. **First-class value.** Assign to a variable, pass to functions, return from functions.
2. **Anonymous.** No name required — literally written inline.
3. **Captures its context.** Can read/write outer variables. This is the "closure" part.

---

## Function Type Syntax

Closures have types written as `(Inputs) -> Output`:

```swift
let doubler: (Int) -> Int = { $0 * 2 }
let onTap: () -> Void = { print("tapped") }
let combine: (Int, Int) -> Int = { a, b in a + b }
let makeName: () -> String = { "Vietnam" }
```

`Void` is Swift's `()` — "no return value." Same thing as an empty tuple.

---

## Trailing Closure Syntax

If a function's *last* argument is a closure, you can write the closure **after** the parentheses. Every SwiftUI modifier uses this:

```swift
// Long form
Button(action: {
    print("tapped")
}, label: {
    Text("Tap me")
})

// Trailing closure — cleaner
Button(action: { print("tapped") }) {
    Text("Tap me")
}

// Multi-trailing (Swift 5.3+) — labels come back for later ones
Button {
    print("tapped")
} label: {
    Text("Tap me")
}
```

Rule: if the trailing closure is the *only* argument, you can also drop the `()`:

```swift
let nums = [1, 2, 3]
nums.map { $0 * 2 }             // Trailing closure, no parens
```

---

## Shorthand Arguments — `$0`, `$1`, `$2`

Inside a closure you can refer to arguments positionally instead of naming them:

```swift
// Full form
let doubled = [1, 2, 3].map { (n: Int) -> Int in n * 2 }

// Type inferred
let doubled = [1, 2, 3].map { n in n * 2 }

// Shorthand
let doubled = [1, 2, 3].map { $0 * 2 }
```

Use shorthand when the closure fits on one line and the meaning is obvious. Name the argument when the body is more than a line or two.

---

## Capture Semantics — the Load-Bearing Part

A closure captures variables from its enclosing scope. Reference-type captures are the tripwire.

### Value type — captured by copy

```swift
var counter = 0

let addOne = {
    counter += 1
}

addOne()
addOne()
print(counter)     // 2
```

Wait — `counter` is `Int` (a value type). But the closure still mutated it? Yes: closures capture **variables**, not just their current value. The closure holds a reference to the *storage* of `counter`. This is deliberate — it's what makes closures useful for state carriers.

### Reference type — captured by reference

```swift
class Store { var value = 0 }
let store = Store()

let increment = {
    store.value += 1
}

increment()
increment()
print(store.value)   // 2
```

Both the closure and the outer scope hold references to the same `Store`. Now — if `store` also holds the closure, you have a **retain cycle**.

---

## The Retain Cycle — Combine's Most Common Bug

```swift
class ViewModel {
    var onLoad: (() -> Void)?
    var name = "Vietnam"

    init() {
        // ❌ Retain cycle: self → onLoad → { self } → self
        onLoad = {
            print(self.name)
        }
    }
}
```

The closure captures `self` strongly. `self` holds the closure via `onLoad`. Neither can be freed. See [[iOS ARC - Retain Cycles]].

### Fix — capture lists

```swift
class ViewModel {
    var onLoad: (() -> Void)?
    var name = "Vietnam"

    init() {
        // ✅ [weak self] — closure holds a weak reference to self
        onLoad = { [weak self] in
            guard let self else { return }
            print(self.name)
        }
    }
}
```

Capture lists appear at the start of the closure: `{ [weak self] in … }`. Three options:

| Capture | When |
|---------|------|
| `[weak self]` | Default in Combine/callback closures. Self may be nil during callback. |
| `[unowned self]` | You *guarantee* self outlives the closure. Crash if wrong. |
| `[self]` (Swift 5.3+) | Explicitly capture strong. Makes the retain-cycle risk visible in review. |

Full deep dive: [[iOS ARC - Capture Lists]].

---

## `@escaping` — Closures That Outlive the Call

By default, closure parameters are **non-escaping** — they must be called before the function returns. This lets the compiler skip retain-cycle machinery.

```swift
func syncMap<T>(_ items: [Int], _ transform: (Int) -> T) -> [T] {
    items.map(transform)     // transform used and gone before return — no @escaping needed
}
```

If a closure survives past the function return (stored as a property, dispatched to a queue, subscribed to a publisher), mark it `@escaping`:

```swift
class Downloader {
    var completion: (() -> Void)?

    func start(_ done: @escaping () -> Void) {   // @escaping — stored beyond function scope
        completion = done                         // ← survives past `start` returning
        // …
    }
}
```

Every `URLSession.dataTask(completionHandler:)` and Combine `.sink` receives escaping closures. That's why capture lists matter — they run *later*, when `self` may already be gone.

---

## `@autoclosure` — Rare But You'll See It

Wraps an argument expression in a closure automatically. Used by short-circuit operators (`??`, `&&`) and `assert`:

```swift
func || (lhs: Bool, rhs: @autoclosure () -> Bool) -> Bool {
    lhs ? true : rhs()      // rhs only evaluated if lhs is false
}

// call site
let ok = isCached || fetchFromServer()   // fetchFromServer() only runs if isCached is false
```

You rarely write `@autoclosure` yourself. Recognize it when reading the standard library.

---

## Closures as Callbacks vs `async/await`

Callback closures are the *older* async style. Modern code often prefers `async/await`:

```swift
// Callback style — pre-Swift-5.5
func fetchCountry(completion: @escaping (Result<Country, Error>) -> Void) {
    // …
}

// async/await — Swift 5.5+
func fetchCountry() async throws -> Country {
    // …
}
```

Callbacks remain everywhere:

- Combine `.sink { … }`
- SwiftUI `Button { … }`, `.onAppear { … }`
- UIKit delegate-adjacent APIs

They're not going anywhere. See [[iOS Swift Core Tech Guide]] era 7 for the async/await evolution story.

---

## Common Newbie Traps

| Trap | Fix |
|------|-----|
| Forgetting `[weak self]` in a Combine `.sink` — memory leak | Add capture list; project-wide rule |
| Using `[unowned self]` on a closure whose lifetime you don't control — crash | Prefer `[weak self]` unless you can prove self outlives the closure |
| Overusing `$0`, `$1` in a five-line closure body — unreadable | Name the parameters explicitly |
| Trying to reassign a captured `let` — compile error | Change to `var`, or restructure to return a value |
| Storing an `@escaping` closure and calling it after the owner deallocs — crash | Use `[weak self]` + `guard let self else { return }` |

---

## Real Example — Combine Pipeline

Every Combine subscription in the tutorial is a closure with a capture list:

```swift
class CountriesViewModel {
    private var cancellables = Set<AnyCancellable>()

    func load() {
        fetchCountries.execute()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let error) = completion {
                        self.error = error
                    }
                },
                receiveValue: { [weak self] countries in
                    self?.countries = countries
                }
            )
            .store(in: &cancellables)
    }
}
```

Both closures are `@escaping` (Combine holds them). Both use `[weak self]` to prevent the pipeline from keeping the VM alive after the view goes away.

---

## Summary

| Piece | Rule |
|-------|------|
| Trailing closure syntax | Use when the closure is the last (or only) arg — cleaner reading |
| Shorthand `$0` | Fine for one-liners; name args for longer bodies |
| Escaping | Required when the closure survives past the function return |
| Capture list | Default to `[weak self]` in `@escaping` closures that touch `self` |
| Value-type capture | Closure holds a reference to the *variable*, so mutations are visible |
| Reference-type capture | Closure and outer scope share the object — retain-cycle risk |

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Optionals]] — pairs with `guard let self else { return }` pattern
- [[iOS ARC Guide]] — the memory model closures interact with
- [[iOS ARC - Capture Lists]] — deep dive on `[weak self]` / `[unowned self]`
- [[iOS ARC - Retain Cycles]] — why closures cause them
- [[iOS SwiftUI - Concurrency and Threading]] — closures + threading (Combine pipelines, `DispatchQueue.main.async`)
- [[iOS Swift Core Tech Guide]] — callback closures → async/await evolution

## Apple Docs

- Closures — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/
- Automatic Reference Counting — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/
- `@escaping` attribute reference — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes/#escaping
