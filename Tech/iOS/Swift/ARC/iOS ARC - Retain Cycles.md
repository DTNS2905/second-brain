---
tags:
  - ios
  - swift
  - arc
  - memory-management
  - retain-cycle
  - fundamentals
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/
---

# iOS ARC — Retain Cycles

> The one failure mode ARC can't prevent. Two-node diagrams, closure captures, and the "big three" real-world sources: Timer, NotificationCenter, Combine sink. Back to index: [[iOS ARC Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**ARC:** [[iOS Tutorial Glossary#Retain cycle / reference cycle|Retain cycle]], [[iOS Tutorial Glossary#Memory leak|Memory leak]], [[iOS Tutorial Glossary#Strong reference|Strong]], [[iOS Tutorial Glossary#Weak reference|Weak]], [[iOS Tutorial Glossary#`[weak self]` — closure capture list|[weak self]]]

---

## Prerequisites

- [[iOS ARC - How It Works]] — refcount semantics.
- [[iOS ARC - Strong Weak Unowned]] — the qualifiers you'll use to break cycles.

---

## The Two-Node Cycle

The canonical example (Swift book):

```swift
class Person {
    let name: String
    var apartment: Apartment?
    init(name: String) { self.name = name }
    deinit { print("Person \(name) freed") }
}

class Apartment {
    let unit: String
    var tenant: Person?              // ❌ strong — cycle!
    init(unit: String) { self.unit = unit }
    deinit { print("Apartment \(unit) freed") }
}

do {
    let john = Person(name: "John")
    let apt = Apartment(unit: "A101")
    john.apartment = apt             // john → apt (strong)
    apt.tenant = john                // apt → john (strong)  ⚠️ cycle formed
}
// Neither deinit prints. Both instances leak forever.
```

Reference graph:

```
    john ──strong──▶ apt
     ▲                │
     └───strong───────┘
```

Two objects, each holding a strong reference to the other. Refcount is 1 on each — neither drops. Silent leak.

**Fix:** make one side weak.

```swift
class Apartment {
    weak var tenant: Person?         // ✅ weak breaks the cycle
}
```

New graph:

```
    john ──strong──▶ apt
     ▲                │
     └─── weak ───────┘
```

When `john` goes out of scope, `john`'s refcount → 0, `deinit` runs, `john`'s `apartment` slot releases `apt`, `apt`'s refcount → 0, `apt`'s `deinit` runs. Clean.

---

## Cycles Through Closures

Closures are reference types. When they capture `self` (a class), they retain it.

```swift
class ViewModel {
    var cancellables = Set<AnyCancellable>()

    func load() {
        somePublisher
            .sink { value in          // closure captures self strongly
                self.items = value
            }
            .store(in: &cancellables) // closure stored on self
    }
}
```

The cycle:

```
self ──▶ cancellables ──▶ AnyCancellable ──▶ closure ──▶ self
```

Fix with a capture list:

```swift
.sink { [weak self] value in
    self?.items = value
}
```

Full mechanics in [[iOS ARC - Capture Lists]].

---

## The Big Three Real-World Leak Sources

Every experienced iOS developer has been burned by these. Learn the pattern once, apply forever.

### 1. `Timer.scheduledTimer` (target-based)

```swift
class Screen {
    var timer: Timer?

    func start() {
        // ❌ scheduledTimer retains its target STRONGLY.
        timer = Timer.scheduledTimer(timeInterval: 1,
                                     target: self,
                                     selector: #selector(tick),
                                     userInfo: nil,
                                     repeats: true)
    }

    @objc func tick() { print("tick") }
    deinit { print("Screen freed") }   // never prints
}
```

Even after `Screen` "goes out of scope," the run loop holds the timer, the timer holds `Screen`, `Screen` holds the timer → cycle.

Fixes:

- **Block-based timer** + `[weak self]` + explicit `invalidate()`:
```swift
timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
    self?.tick()
}

deinit {
    timer?.invalidate()   // required — without this, the timer keeps firing
}
```
- **Modern option** — use Swift Concurrency:
```swift
task = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        await self?.tick()
    }
}
deinit { task?.cancel() }
```

### 2. `NotificationCenter.addObserver` (block-based)

```swift
class Screen {
    init() {
        NotificationCenter.default.addObserver(
            forName: .someEvent, object: nil, queue: .main
        ) { [weak self] note in         // ✅ [weak self] required
            self?.handle(note)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)   // also required
    }
}
```

Without `[weak self]`: closure retains `self` → NC retains closure → NC lives forever (it's a singleton) → `self` leaks.

Without `removeObserver`: even with weak self, the closure hangs around getting called with `nil self` → wasted work. On older iOS versions this was also a crash source.

### 3. Combine `.sink` when the `AnyCancellable` is stored on `self`

The tutorial you're building already uses this pattern in [[iOS Tutorial - Part 4 Domain Layer]]:

```swift
class CountriesViewModel {
    private var cancellables = Set<AnyCancellable>()

    func load() {
        fetchCountries.execute()
            .sink { [weak self] countries in     // ✅ required
                self?.countries = countries
            }
            .store(in: &cancellables)
    }
}
```

**Nuance:** the cycle only forms **when the cancellable is stored on self**. If you had:

```swift
let cancellable = publisher.sink { … }        // stored in a local, not on self
```

Then no cycle — the closure holds self, but nothing holds the cancellable-then-self chain.

Apple's docs don't discuss this explicitly. In practice, VMs always store cancellables on self, so this pattern is basically universal. Supplementary reading: [Swift by Sundell — Combine self & cancellable memory management](https://www.swiftbysundell.com/articles/combine-self-cancellable-memory-management/).

---

## Delegate Pattern — Always Weak

The classic UIKit pattern; still shows up in SwiftUI when you bridge to `UIViewRepresentable`:

```swift
protocol DataSourceDelegate: AnyObject {  // AnyObject means "class-only"
    func didLoad(_ items: [Item])
}

class DataSource {
    weak var delegate: DataSourceDelegate?   // ✅ weak — the ViewController owns us, not vice versa
}

class ScreenViewController: DataSourceDelegate {
    let dataSource = DataSource()

    init() {
        dataSource.delegate = self   // ✅ safe with weak
    }
}
```

Why `AnyObject` on the protocol? `weak` only works with reference types. A `class`-constrained protocol lets you declare `weak var delegate`.

---

## Cycles You Might Not Notice

- **Parent-child in view models.** A shared root VM that holds children which back-reference it. Break with `weak`.
- **Coordinator/router patterns.** Coordinators often hold their child screens strongly; screens holding a coordinator reference back need to be `weak`.
- **Reactive property bindings.** Two-way bindings that each install a `sink` observing the other. Rare in SwiftUI, common in legacy RxSwift.
- **KVO with closures.** `NSObject.observe(_:changeHandler:)` returns a token — retain the token, but observe with `[weak self]`.

---

## How to Find Cycles

- **Add lifetime logging.** `deinit { print("X freed") }` on every VM/repo/coordinator. Missing prints = missing deallocations = a cycle.
- **Xcode Memory Graph Debugger.** See [[iOS ARC - Debugging Memory Issues]].
- **Instruments — Leaks template.**

---

## Apple Docs

| Topic | URL |
|-------|-----|
| Swift book — Strong Reference Cycles Between Class Instances | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Strong-Reference-Cycles-Between-Class-Instances |
| Swift book — Strong Reference Cycles for Closures | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Strong-Reference-Cycles-for-Closures |
| `Timer` | https://developer.apple.com/documentation/foundation/timer |
| `NotificationCenter.addObserver(forName:object:queue:using:)` | https://developer.apple.com/documentation/foundation/nsnotificationcenter/1411723-addobserverforname |
| Combine `.sink(receiveValue:)` | https://developer.apple.com/documentation/combine/publisher/sink(receivevalue:) |

---

## Continue

- [[iOS ARC - Capture Lists]] — the exact syntax for `[weak self]` and friends
- [[iOS ARC - Debugging Memory Issues]] — Memory Graph Debugger walk-through
