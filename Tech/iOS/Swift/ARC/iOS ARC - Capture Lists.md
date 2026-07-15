---
tags:
  - ios
  - swift
  - arc
  - closures
  - capture-list
  - swift-concurrency
  - fundamentals
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/
---

# iOS ARC — Capture Lists

> The `[weak self]` syntax and everything around it. Escaping vs non-escaping, Swift 6 `@Sendable` and actor-isolation rules, and how to pick `weak` vs `unowned` in closures. Back to index: [[iOS ARC Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**ARC:** [[iOS Tutorial Glossary#Capture list|Capture list]], [[iOS Tutorial Glossary#`[weak self]` — closure capture list|[weak self]]], [[iOS Tutorial Glossary#Escaping closure|Escaping closure]]
**Concurrency:** [[iOS Tutorial Glossary#`@Sendable`|@Sendable]], [[iOS Tutorial Glossary#`@MainActor`|@MainActor]]

---

## Prerequisites

- [[iOS ARC - Strong Weak Unowned]] — the qualifiers you're about to apply in a closure context.
- [[iOS ARC - Retain Cycles]] — the leak patterns capture lists are designed to prevent.

---

## Syntax

```swift
{ [captureList] (parameters) -> ReturnType in
    // body
}
```

The capture list is the square brackets *before* the parameters, right at the start.

```swift
publisher.sink { [weak self] value in
    self?.items = value
}
```

Each element of the list is a capture directive:

| Directive | Meaning |
|-----------|---------|
| `weak self` | Capture self weakly. Inside the closure, `self` is `Optional`. |
| `unowned self` | Capture self unowned. Non-optional; crash if target already dealloc'd. |
| `weak reference` | Capture some other reference weakly. |
| `capturedName = expression` | Capture the value of an expression by name (used to break "capture by reference" behavior). |

Example of all three:

```swift
let closure = { [weak self, unowned parent, name = expensiveName()] in
    guard let self else { return }
    parent.notify(self)
    print(name)
}
```

---

## When Do You Need a Capture List?

Only for closures that:

1. Capture `self` (or another class reference), **AND**
2. Are stored somewhere that outlives the current stack frame.

The second condition is what "escaping" means.

### Escaping vs Non-Escaping

- **Non-escaping** — the closure only runs during the function call. No storage, no retain problem.
```swift
countries.map { $0.name }                    // .map's closure is non-escaping → no capture list needed
countries.sorted { $0.name < $1.name }       // ditto
```

- **`@escaping`** — the closure is stored for later. Must be explicitly marked in the parameter type.
```swift
func fetch(completion: @escaping ([Country]) -> Void) { ... }
// completion may run after fetch() returns → self capture might outlive the call site
```

Swift **forces** you to write `self.` explicitly inside escaping closures. That's a compiler nudge: think about capture before you touch self.

### Contexts that store closures (need `[weak self]` when capturing self)

- `Timer.scheduledTimer(withTimeInterval:repeats:block:)`
- `NotificationCenter.default.addObserver(forName:… using:)`
- Combine `.sink { }`, `.assign { }`, `.map { }` — **only** if the resulting `AnyCancellable` is stored on `self`
- `Task { }` — only if the task itself is stored on `self` and long-lived
- `URLSession.dataTask(with:completionHandler:)`
- Any closure property (`var onTap: (() -> Void)?`)

### Contexts that don't store closures (no `[weak self]` needed)

- `.map`, `.filter`, `.reduce`, `.sorted` on collections (execute synchronously and discard)
- `withCheckedContinuation { … }`
- SwiftUI `Button(action: { … })` — the button is owned by `self`, closure lifetime matches
- One-shot `DispatchQueue.main.async { … }` after which the closure is released

---

## `[weak self]` — the Right-99%-of-the-Time Choice

```swift
publisher.sink { [weak self] value in
    guard let self else { return }   // early-exit if self is gone
    self.items = value                // now unwrapped, use freely
}
```

- Inside the closure, `self` becomes `Self?`.
- `guard let self else { return }` is the modern idiom (Swift 5.7+). Older code uses `guard let strongSelf = self else { return }` then `strongSelf.foo`.
- If the target is already dealloc'd, the guard bails — no work done, no crash.

---

## `[unowned self]` — Faster but Sharper

```swift
button.action = { [unowned self] in
    self.doSomething()
}
```

- Inside the closure, `self` is non-optional. No unwrapping.
- Slightly faster access (no side-table lookup).
- **Crashes** if the target has already dealloc'd.

Use when the closure's lifetime is *provably* enclosed by `self`'s lifetime. Example: `self.button.action = …` — the button dies when `self` dies, so the closure can't outrun `self`.

Rule of thumb: **`[weak self]` unless you can prove `[unowned self]` is safe.** The safety proof is often not worth the pointer-check-saved.

---

## Swift 6 — Strict Concurrency and Captures

Swift 6 tightens the rules for closures that cross concurrency boundaries. Two flavors matter:

### `@Sendable` closures

A `@Sendable` closure is one that may be sent across concurrent contexts (actors, tasks, threads). All captured values must themselves be `Sendable`.

```swift
class ViewModel { ... }                            // classes are non-Sendable by default

Task { [weak vm = self] in                          // ✅ vm is Sendable? No — but weak references are conditionally allowed
    await vm?.load()
}
```

If `self` is a non-Sendable class and the closure is `@Sendable`, capturing `self` strongly is a compile error under Swift 6. `weak` captures are permitted because they cross the boundary as a nilable slot, not the underlying non-Sendable value.

Fix if you hit this:
- Mark the class `@MainActor` (its methods become main-actor-isolated → callable from `await`).
- Or mark it `Sendable` and audit that all properties are safe.

### Actor-isolation inheritance

In Swift 6, closures inherit the isolation of their enclosing context.

```swift
@MainActor
class VM {
    var items: [Item] = []

    func loadAsync() async {
        Task {                        // inherits @MainActor from VM
            self.items = await fetch() // safe — still on main actor
        }
    }
}
```

The `Task` closure runs on the main actor because `VM` is `@MainActor`. That means `[weak self]` inside doesn't hop off the actor — it just captures weakly. This is the modern-friendly pattern.

Deep dive: [[iOS SwiftUI - Concurrency and Threading]].

---

## Common Cheatsheet

| Situation | Closure kind | Capture list |
|-----------|--------------|--------------|
| `.map { $0.name }` on an array | Non-escaping | none |
| `.sink { … }` in Combine, stored on self | Escaping | `[weak self]` |
| `Timer.scheduledTimer(withTimeInterval:… block:)` | Escaping | `[weak self]` |
| `NotificationCenter.addObserver(… using:)` | Escaping | `[weak self]` |
| `Button(action: { … })` in SwiftUI | Escaping-ish (owned by view, view is struct) | none |
| `Task { await … }` for a short-lived task | Escaping | none (task retains self only briefly) |
| `Task { while !Task.isCancelled { … } }` stored on self | Escaping + long-lived | `[weak self]` |
| `withCheckedContinuation { c in … }` | Escaping but scoped | none |

---

## Anti-Pattern — Capture-list Cargo-Culting

Not every closure needs `[weak self]`. Sprinkling it everywhere adds noise and forces `self?.` at every use.

```swift
countries.map { [weak self] country in    // ❌ pointless
    self?.transform(country) ?? country
}
```

The `.map` closure runs synchronously — `self` is guaranteed alive. No cycle possible. Just write `self.transform(country)` (or omit `self.` since map is non-escaping).

Reserve `[weak self]` for **escaping** closures where the retention path back to `self` is real.

---

## Apple Docs

| Topic | URL |
|-------|-----|
| Swift book — Closures | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/ |
| Swift book — Capture Lists | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/expressions/#Capture-Lists |
| Swift book — Strong Reference Cycles for Closures | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Strong-Reference-Cycles-for-Closures |
| Swift Concurrency — Sendable | https://developer.apple.com/documentation/swift/sendable |
| Swift 6 Language Mode | https://www.swift.org/migration/documentation/migrationguide/ |

---

## Continue

- [[iOS ARC - Debugging Memory Issues]] — when the theory doesn't match the runtime, how to find what leaked
