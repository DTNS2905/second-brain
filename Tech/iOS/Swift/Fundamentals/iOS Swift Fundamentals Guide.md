---
tags:
  - ios
  - swift
  - fundamentals
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/
  - https://developer.apple.com/swift/
---

# iOS Swift Fundamentals Guide

> The language itself — separate from SwiftUI, separate from any framework. What every Swift developer needs to be fluent in before opinions on architecture make sense. Pairs with [[iOS Swift Core Tech Guide]] (paradigms & frameworks over time) and [[iOS SwiftUI Fundamentals Guide]] (the UI framework built on top).

---

## Contents

Notes in this folder cover Swift-the-language:

| Note                                                | Covers                                                                                       | Status |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------ |
| [[iOS Swift - Values and Types]]                    | `let` vs `var`, type inference, `Int`/`Double`/`String`/`Bool`, tuples, type aliases         | ✅      |
| [[iOS Swift - Value vs Reference Types]]            | `struct` vs `class` vs `enum`, copy semantics, when to pick which                            | ✅      |
| [[iOS Swift - Optionals]]                           | `?`, `!`, `if let`, `guard let`, nil-coalescing `??`, optional chaining                      | ✅      |
| [[iOS Swift - Closures]]                            | Trailing closures, `@escaping`, capture semantics, `[weak self]` (see [[iOS ARC Guide]])     | ✅      |
| [[iOS Swift - Protocols]]                           | Protocol-Oriented Programming, associated types, existentials (`any`), opaque types (`some`) | ✅     |
| [[iOS Swift - Extensions]]                          | Adding methods, conditional conformance, `extension` on generic types                        | ✅     |
| [[iOS Swift - Generics]]                            | `<T>`, type constraints, `where` clauses, `some` vs `any`                                    | ✅     |
| [[iOS Swift - Error Handling]]                      | `throws` / `try` / `try?` / `try!`, `Result`, custom `Error` types                           | ✅     |
| [[iOS Swift - Property Wrappers]]                   | `@propertyWrapper`, projected values (`$`), how `@State` etc. actually work                  | ✅     |
| [[iOS Swift - Access Control]]                      | `private`, `fileprivate`, `internal`, `public`, `open`, `private(set)`                       | ✅     |
| [[iOS Swift - Codable & Foundation]]                | `Codable`, `JSONDecoder`, `Date`, `URL`, `Data` — the Foundation types every app touches     | ✅     |

Cross-cutting sibling topic:

| [[iOS ARC Guide]] | Automatic Reference Counting — how Swift frees memory, retain cycles, `weak`/`unowned`. Lives in `Swift/ARC/`. | ✅ |

---

## Reading Order for iOS Newbies

If you're brand-new to Swift, work through the notes in the order above. Optionals and closures are the two most common tripping points — spend extra time there.

For readers coming from other languages:

| Coming from | Pay extra attention to |
|-------------|------------------------|
| JavaScript / TypeScript | Value types (`struct`), optionals (no `undefined`), strong typing, `guard` |
| Java / C# | Value types, protocols vs interfaces, POP, `some` / `any`, closures capture |
| Kotlin | Structs vs data classes, protocol-oriented (not class-oriented), no companion objects |
| Objective-C | ARC still applies (same runtime), but you now get value types + generics + protocol extensions |

---

## What's Explicitly NOT Here

- **SwiftUI** — see [[iOS SwiftUI Fundamentals Guide]].
- **Combine, async/await, Observation, Macros** — those are frameworks or language features layered on top of the fundamentals. See [[iOS Swift Core Tech Guide]] for the chronological view.
- **Clean Architecture / MVVM** — see [[iOS SwiftUI Architecture Guide]].

Keeping this folder narrow prevents "Swift Fundamentals" from becoming a dump for everything that isn't SwiftUI.

---

## Apple Docs (Primary References)

| Topic | URL |
|-------|-----|
| The Swift Programming Language (book) | https://docs.swift.org/swift-book/ |
| Swift language homepage | https://developer.apple.com/swift/ |
| Swift standard library | https://developer.apple.com/documentation/swift |
| Foundation framework | https://developer.apple.com/documentation/foundation |
| Swift Evolution proposals | https://github.com/apple/swift-evolution |

---

## Related

- [[iOS Swift Core Tech Guide]] — chronological view of Swift's major frameworks and language features
- [[iOS ARC Guide]] — memory model deep dive
- [[iOS SwiftUI Fundamentals Guide]] — UI framework built on these fundamentals
- [[iOS Tutorial Glossary]] — every keyword the tutorial uses, defined plainly
