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

# iOS ARC — Strong, Weak, Unowned

> The three reference qualifiers. Pick correctly and cycles never happen. Pick wrong and you get either leaks (too strong) or crashes (too unowned). Back to index: [[iOS ARC Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**ARC:** [[iOS Tutorial Glossary#Strong reference|Strong]], [[iOS Tutorial Glossary#Weak reference|Weak]], [[iOS Tutorial Glossary#Unowned reference|Unowned]], [[iOS Tutorial Glossary#Retain cycle / reference cycle|Retain cycle]]

---

## Prerequisites — Read First

- [[iOS ARC - How It Works]] — the refcount mechanism these qualifiers modify.

---

## The Three-Second Decision Tree

```
Does the reference need to keep the target alive?
├── Yes  →  strong (default — no keyword needed)
└── No   →  Can the target outlive this reference?
           ├── Yes, sometimes  →  weak    (Type? var, nil'd on dealloc)
           └── No, guaranteed  →  unowned (non-optional, crash if wrong)
```

Roughly: **default to `strong`. Use `weak` in the back-reference of a parent-child relationship or delegate. Use `unowned` only when the two objects have provably-linked lifetimes.**

---

## Strong (default)

Every reference is strong unless you say otherwise:

```swift
class ViewModel {
    let repository: Repository   // strong reference — Repository lives at least as long as ViewModel
}
```

- No keyword needed.
- Increments the target's refcount.
- If the target has no other strong references, it stays alive as long as this variable does.

**Use for:** properties, function arguments, closure captures — the common case. Don't overthink this; `strong` is right most of the time.

---

## Weak

```swift
class Employee {
    weak var manager: Manager?     // weak var, must be Optional
}
```

Rules:

- **Must be `var`** — `weak let` is a compile error. The runtime needs to write `nil` into the slot when the target deallocates.
- **Must be Optional** — same reason. When the target dies, the reference becomes `nil` automatically.
- Does **not** increment the refcount.
- Reading a `weak` var is safe — you always get either the current target or `nil`.

### Zeroing behavior (why `weak` is safer than `unowned`)

```swift
class Manager { var name: String; init(name: String) { self.name = name } }
class Employee { weak var manager: Manager?; init() {} }

let e = Employee()
do {
    let m = Manager(name: "Alice")
    e.manager = m
    print(e.manager?.name)   // "Alice"
}
print(e.manager?.name)       // nil — m was deallocated, weak zeroed itself
```

The runtime keeps a small side table of "who has weak refs to this instance." When the instance dies, it walks the table and nil's each one. Slightly slower than a raw pointer but crash-proof.

**Use for:**
- Back-reference in parent-child (child ← parent).
- Delegates (`weak var delegate: MyDelegate?`).
- Notification observer targets in some patterns.
- The `self` capture in most stored `.sink` closures — see [[iOS ARC - Capture Lists]].

---

## Unowned

```swift
class Customer {
    let card: CreditCard   // strong
    init() { self.card = CreditCard(owner: self) }
}
class CreditCard {
    unowned let owner: Customer   // unowned — Customer always outlives its card
    init(owner: Customer) { self.owner = owner }
}
```

Rules:

- Non-optional (usually). Access with `.` not `?.`.
- Does **not** increment the refcount.
- Does **not** zero itself on deallocation.
- Accessing an unowned reference **after** the target dies is a **runtime crash** (safe unowned) or **undefined behavior** (unowned(unsafe)).

### `unowned` vs `unowned(safe)` vs `unowned(unsafe)`

- `unowned` = `unowned(safe)` in almost all cases. The runtime traps on access-after-dealloc — you get a clean crash instead of memory corruption.
- `unowned(unsafe)` is a raw pointer — no runtime check, undefined behavior if the target is dead. Only use if profiling proves the safe-unowned check is a bottleneck. Extremely rare.

### When to use `unowned` instead of `weak`

Only when you can prove the target's lifetime **encloses** the reference's. Common patterns:

- **Composition** — an instance owns another instance which back-references it, and the two have identical lifetimes (`Customer` ↔ `CreditCard`).
- **Closure captures in short-lived work** — if the object is guaranteed to still exist when the closure runs.

If you have any doubt: prefer `weak`. Slightly slower access is much better than a random crash.

---

## Comparison Table

| Property | strong | weak | unowned |
|----------|--------|------|---------|
| Keyword | *(default)* | `weak` | `unowned` |
| Increments refcount? | ✅ | ❌ | ❌ |
| Must be `var`? | No | ✅ | No |
| Must be Optional? | No | ✅ | No (usually not) |
| Zeroed on target dealloc? | N/A (target can't die) | ✅ | ❌ |
| Access after target dies? | Impossible | Returns `nil` safely | Crash (safe) / UB (unsafe) |
| Overhead per access | 0 | Small (side table) | ~0 |
| Overhead on target dealloc | 0 | Small (nil the refs) | 0 |
| Right for the delegate pattern? | ❌ (cycle) | ✅ | 🤔 (rarely) |

---

## Real-World Anti-Patterns

### ❌ Strong delegate

```swift
class Child {
    var delegate: ParentDelegate?    // ❌ strong — Parent → Child → delegate → Parent = cycle
}
```

Fix: `weak var delegate: ParentDelegate?`

### ❌ Unowned when the target might dealloc first

```swift
class ViewModel {
    unowned let router: Router     // ❌ if Router dies first, next access crashes
}
```

Fix: `weak var router: Router?` unless you *own* the Router.

### ❌ Weak in a closure that only runs while the target is alive

```swift
button.action = { [weak self] in
    self?.doSomething()            // works but noisy — button is owned by self, closure only fires while self is alive
}
```

Not strictly wrong — just verbose. `[unowned self]` is fine here since the button can only fire while `self` is alive. Some teams standardize on `[weak self]` everywhere to avoid the mental audit; that's a valid style choice.

---

## Apple Docs

| Topic | URL |
|-------|-----|
| Swift book — Resolving Strong Reference Cycles | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Resolving-Strong-Reference-Cycles-Between-Class-Instances |
| Weak References (Swift book) | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Weak-References |
| Unowned References (Swift book) | https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Unowned-References |

---

## Continue

- [[iOS ARC - Retain Cycles]] — the patterns these qualifiers exist to prevent
- [[iOS ARC - Capture Lists]] — applying them in closures
