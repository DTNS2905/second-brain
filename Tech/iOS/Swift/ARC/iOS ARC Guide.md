---
tags:
  - ios
  - swift
  - arc
  - memory-management
  - fundamentals
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/
  - https://developer.apple.com/videos/play/wwdc2021/10216/
  - https://developer.apple.com/videos/play/wwdc2021/10180/
---

# iOS ARC Guide — Automatic Reference Counting in Swift

> How Swift decides when to free memory. Why `[weak self]` exists. What `deinit` really means. The vocabulary and mental model every iOS developer needs, before writing any ViewModel that stores subscriptions.

---

## What ARC Is (One Paragraph)

> **ARC** is Swift's compile-time memory management. For every reference-type instance (a `class` or `actor`), the compiler counts how many strong references point to it. When that count reaches zero, the instance is deallocated and its `deinit` runs. There is no garbage collector — no runtime scan, no unpredictable pauses.

That single mechanism plus **three reference qualifiers** (`strong`, `weak`, `unowned`) is the entire user-facing surface of ARC. Everything else — retain cycles, `[weak self]`, `deinit` timing, memory leaks — flows from that.

---

## Contents

| Note | Covers |
|------|--------|
| [[iOS ARC - How It Works]] | Compile-time retain/release insertion, lexical lifetimes (Swift 5.7+), `deinit` timing, value vs reference types |
| [[iOS ARC - Strong Weak Unowned]] | The three reference qualifiers, when to pick each, `weak` vs `unowned(safe)` vs `unowned(unsafe)` |
| [[iOS ARC - Retain Cycles]] | The classic 2-node cycle, closure captures, delegate pattern, the "big three" leak sources (Timer, NotificationCenter, Combine sink) |
| [[iOS ARC - Capture Lists]] | `[weak self]` / `[unowned self]` syntax, when each is right, escaping vs non-escaping, Swift 6 Sendable/isolation rules |
| [[iOS ARC - Debugging Memory Issues]] | Xcode's Memory Graph Debugger, Instruments Leaks/Allocations, the purple `!` badge, SwiftUI-specific gotchas |

---

## The Mental Model in 30 Seconds

```
class Country {                     // 'class' → reference type → ARC-managed
    let name: String
    init(name: String) { self.name = name }
    deinit { print("Country \(name) freed") }
}

var a: Country? = Country(name: "Vietnam")   // strong-refcount = 1
var b = a                                    // strong-refcount = 2
a = nil                                      // strong-refcount = 1  (b still holds it)
b = nil                                      // strong-refcount = 0  → deinit runs, memory freed
```

- `a` and `b` are two variables pointing to the same instance.
- Assigning to a variable is a **retain** (increment).
- Reassigning or setting to `nil` is a **release** (decrement) of the previous target.
- Reaching zero triggers `deinit`.

**Value types don't participate.** A `struct` copy is a copy — no shared ownership, no reference count.

---

## Why You Should Care (Newbie Motivation)

Three real bugs that ARC concepts fix:

1. **"My ViewModel never deinits after I dismiss the screen."** → Retain cycle. Fix: `[weak self]` inside stored `.sink { }` closures. See [[iOS ARC - Retain Cycles]].
2. **"My timer keeps firing after the view is gone."** → `Timer.scheduledTimer` retains its target strongly. Fix: `weak var timer` + `invalidate()` in `deinit`. See [[iOS ARC - Retain Cycles]].
3. **"App crashes with 'Bad access' after I call a delegate."** → `unowned` reference to a deallocated instance. Fix: `weak` instead. See [[iOS ARC - Strong Weak Unowned]].

You can code without knowing ARC — right up until you can't. This guide is the "why."

---

## Where ARC Fits In the Vault

- **[[iOS SwiftUI - Concurrency and Threading]]** — the "why" behind thread hops. ARC-managed subscription objects (`AnyCancellable`) live tied to the VM's lifetime.
- **[[iOS SwiftUI - Lifecycle]]** — the "when" of state creation and destruction. `deinit` timing matters when a `@Observable` VM goes out of scope.
- **[[iOS SwiftUI Architecture - MVVM with Combine]]** — ARC is why every stored `.sink` needs `[weak self]`.
- **[[iOS Tutorial - Part 4 Domain Layer]]** — the first tutorial part that requires ARC understanding to avoid leaks.

---

## Apple Docs (Primary References)

| Topic | URL |
|-------|-----|
| Swift book — Automatic Reference Counting | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/ |
| WWDC21 — ARC in Swift: Basics and beyond | https://developer.apple.com/videos/play/wwdc2021/10216/ |
| WWDC21 — Detect and diagnose memory issues | https://developer.apple.com/videos/play/wwdc2021/10180/ |
| WWDC25 — Improve memory usage and performance with Swift | https://developer.apple.com/videos/play/wwdc2025/312/ |
| Xcode — Gathering information about memory use | https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use |
| Xcode — Analyzing memory usage | https://developer.apple.com/documentation/xcode/analyzing-memory-usage |

**Watch order for the videos:** WWDC21 10216 (concepts) → WWDC21 10180 (debugging) → WWDC25 312 (Swift 6 refinements).

---

## Related Notes

- [[iOS SwiftUI Fundamentals Guide]] — where Swift + SwiftUI reference material lives
- [[iOS SwiftUI - Concurrency and Threading]] — pairs with ARC for every VM you write
- [[iOS SwiftUI - Lifecycle]] — pairs with ARC for understanding when things dealloc
- [[iOS Tutorial Glossary]] — one-line definitions of every ARC term
