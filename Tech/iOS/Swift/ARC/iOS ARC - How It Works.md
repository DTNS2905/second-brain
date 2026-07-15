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
---

# iOS ARC — How It Works

> The compile-time mechanism, retain count semantics, lexical lifetimes (Swift 5.7+), and `deinit` timing. Back to index: [[iOS ARC Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**ARC:** [[iOS Tutorial Glossary#ARC — Automatic Reference Counting|ARC]], [[iOS Tutorial Glossary#Reference count|Reference count]], [[iOS Tutorial Glossary#Strong reference|Strong reference]], [[iOS Tutorial Glossary#`deinit`|deinit]], [[iOS Tutorial Glossary#Value vs reference types|Value vs reference types]]

---

## Value vs Reference Types — the Prerequisite

**Only reference types participate in ARC.**

| Kind | Examples | Ownership |
|------|----------|-----------|
| Value type | `struct`, `enum`, tuple, most Swift stdlib types | Each variable owns its own copy |
| Reference type | `class`, `actor`, closures | Multiple variables share one instance |

```swift
struct Point { var x: Int }           // value type
var p1 = Point(x: 1)
var p2 = p1                            // p2 is a COPY
p2.x = 99                              // p1.x still 1

class Node { var x: Int; init(x: Int) { self.x = x } }   // reference type
let n1 = Node(x: 1)
let n2 = n1                            // n2 points to the SAME instance
n2.x = 99                              // n1.x is now 99 too
```

ARC only manages the class case. The struct case has no reference count — copies are independent.

---

## What the Compiler Actually Does

When you write:

```swift
let a = SomeClass()
let b = a
```

The compiler inserts (conceptually):

```swift
let a = SomeClass()       // instance created, refcount = 1
retain(a)                  // b = a → refcount = 2
let b = a
// ... end of scope
release(b)                 // b out of scope → refcount = 1
release(a)                 // a out of scope → refcount = 0 → deinit + free
```

You never see `retain` or `release` in your source. They exist as compiler-emitted calls into the Swift runtime.

Because insertion happens at compile time:

- **No runtime scan.** Unlike Java or Go, there's no background thread walking memory.
- **Deterministic-ish.** `deinit` runs at a well-defined point — subject to the lexical-lifetime caveat below.
- **Zero pause.** No stop-the-world GC. Real-time-adjacent workloads (audio, drawing) work.
- **Cycles aren't detected.** ARC doesn't know two classes point at each other; a cycle just leaks silently. See [[iOS ARC - Retain Cycles]].

---

## Lexical Lifetimes (Swift 5.7+) — the Nuance

Before Swift 5.7, you could reason: "the instance dies at end of scope." That's now **imprecise**.

Since Swift 5.7, the compiler can release an instance **as soon as it's no longer used**, even before the end of its lexical scope. This is called "lexical lifetimes" — the compiler optimizes deallocation for performance.

```swift
func doWork() {
    let temp = ExpensiveResource()
    temp.use()
    // ← temp may be deallocated HERE, not at the end of the function
    otherSlowWork()   // temp is likely already gone
}
```

**Practical consequences:**

- Don't rely on `deinit` timing for **ordering** — you don't control the exact moment.
- If you need an object to live longer than the compiler thinks, use `withExtendedLifetime(_:body:)`:
```swift
withExtendedLifetime(criticalReference) {
    performWorkThatDependsOnItStillBeingAlive()
}
```
- For most app code (VMs, screens), the imprecision doesn't matter — deinit runs "soon enough" after the last strong reference drops.
- For low-level code (unsafe pointers, C interop, atomic-lifetime protocols), read the WWDC22 "What's new in Swift" for the exact rules.

---

## `deinit` — the One-Shot Callback

Every class can define a `deinit`:

```swift
class Timer {
    let name: String
    init(name: String) {
        self.name = name
        print("Timer \(name) created")
    }
    deinit {
        print("Timer \(name) freed")
    }
}

do {
    let t = Timer(name: "A")   // "Timer A created"
}   // "Timer A freed" — refcount 1 → 0
```

Rules:

- Not called manually.
- Fires exactly once, on the thread where the last strong reference dropped — **which may be a background thread** in Combine or async code.
- Order among unrelated instances is not guaranteed.
- If a cycle exists, `deinit` **never runs**. That's the leak signature.

### Common `deinit` uses

- Removing observers (`NotificationCenter.removeObserver(self)`).
- Invalidating timers (`timer.invalidate()`).
- Closing file handles or database connections.
- Logging for lifetime debugging (`print("ViewModel freed")`).

---

## Refcount Semantics — What Counts as a Retain

Any of these operations increment the strong refcount:

| Operation | Example |
|-----------|---------|
| Variable assignment | `let b = a` |
| Function argument | `useIt(a)` — argument is retained for the call |
| Stored property | `self.item = a` |
| Array/set/dictionary insertion | `arr.append(a)` |
| Closure capture (strong, default) | `let c = { print(a) }` |

Any of these decrement it:

| Operation | Effect |
|-----------|--------|
| Variable goes out of scope | End of `let`/`var`'s lexical scope (or earlier with lexical lifetimes) |
| Reassignment | `b = other` releases previous `b` |
| Setting Optional to `nil` | `optionalRef = nil` releases the target |
| Container removal | `arr.remove(at: 0)` |
| Closure deallocation | The closure itself being freed releases its captures |

---

## Actors Also Use ARC

An `actor` is a reference type. It has an identity, a heap allocation, and a refcount:

```swift
actor Counter {
    private var count = 0
    func increment() { count += 1 }
}

let c = Counter()          // refcount 1
Task { await c.increment() }   // task captures c → refcount 2
                            // task completes → refcount 1
                            // c goes out of scope → refcount 0 → deinit
```

Actors add isolation on top of ARC — they don't replace it.

---

## What ARC Doesn't Give You

- **Cycle detection.** You must design your reference graph to avoid cycles.
- **Cross-process refcount.** ARC is per-process. Shared memory / XPC / files need their own lifecycle.
- **Value type management.** Structs are copy-on-assign — no ARC involved.
- **Thread-safety of the referred instance.** ARC's refcount ops are atomic, but that doesn't make the *properties* of the class thread-safe. Use actors or locks.

---

## Apple Docs

| Topic | URL |
|-------|-----|
| Swift book — ARC | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/ |
| WWDC21 — ARC in Swift: Basics and beyond | https://developer.apple.com/videos/play/wwdc2021/10216/ |
| `withExtendedLifetime(_:_:)` | https://developer.apple.com/documentation/swift/withextendedlifetime(_:_:) |
| Actor | https://developer.apple.com/documentation/swift/actor |

---

## Continue

- [[iOS ARC - Strong Weak Unowned]] — the three qualifiers you use to control refcount behavior
- [[iOS ARC - Retain Cycles]] — the failure mode ARC can't prevent on its own
