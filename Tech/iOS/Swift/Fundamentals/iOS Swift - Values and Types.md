---
tags:
  - ios
  - swift
  - fundamentals
  - types
  - mobile
created: 2026-07-06
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/
  - https://developer.apple.com/documentation/swift
---

# iOS Swift — Values and Types

> The starting layer. `let` vs `var`, type inference, the built-in scalar types, tuples, type aliases. Back to [[iOS Swift Fundamentals Guide]].

---

## `let` vs `var` — Constants vs Variables

Swift has **no `const` keyword**. Instead:

- **`let`** — bound once. Never reassigned.
- **`var`** — mutable. Can be reassigned.

```swift
let country = "Vietnam"          // constant
var counter = 0                  // variable
counter += 1                     // ✅ ok
// country = "Japan"             // ❌ compile error: cannot assign to 'let' constant
```

Rule: **default to `let`**. Only use `var` when you actually mutate. This is a Swift culture norm — Xcode even offers a fix-it to convert `var` → `let` if you never reassign.

> `let` does not mean "immutable value" — it means "immutable binding." For a `struct` (value type) they coincide. For a `class` (reference type), `let` locks the *reference*, not the object's properties. See [[iOS Swift - Value vs Reference Types]].

---

## Type Inference

Swift infers types from initial values. Annotate only when the compiler can't guess or when you want to be explicit.

```swift
let name = "Vietnam"             // inferred as String
let count = 250                  // inferred as Int
let flag: String = "🇻🇳"         // annotated (redundant here)

var scores: [Double] = []        // annotation REQUIRED — empty literal is ambiguous
```

Common trap: an empty collection literal (`[]`, `[:]`, `nil`) has no way to be inferred. You must annotate.

---

## The Built-in Scalar Types

The types you'll touch daily:

| Type | What it is | Example |
|------|-----------|---------|
| `Int` | Platform-native signed integer (64-bit on iOS) | `let n: Int = 42` |
| `Double` | 64-bit floating point (default for decimals) | `let π: Double = 3.14` |
| `Float` | 32-bit floating point (rare — use Double) | `let x: Float = 1.5` |
| `Bool` | `true` / `false` | `var isLoading = true` |
| `String` | Unicode text | `let s = "Hello"` |
| `Character` | A single Unicode grapheme | `let c: Character = "🇻🇳"` |

> No implicit numeric conversions. `Int` + `Double` won't compile — you must convert explicitly:
> ```swift
> let years = 5
> let rate = 0.03
> let total = Double(years) * rate    // ✅
> // let bad = years * rate           // ❌ won't compile
> ```

### Numeric literal underscores

For readability:

```swift
let million = 1_000_000              // ✅ same as 1000000
let hex = 0xFF_00_FF                 // ✅ hex with separators
```

---

## Collections at a Glance

Full deep-dives get their own notes; here's the vocabulary:

```swift
let names: [String] = ["Vietnam", "Japan"]              // Array
let capital: [String: String] = ["Vietnam": "Hanoi"]    // Dictionary
let unique: Set<Int> = [1, 2, 3]                        // Set
```

- **Array** — ordered, indexed, duplicates allowed.
- **Dictionary** — key-value pairs, key type must be `Hashable`.
- **Set** — unordered, no duplicates, element type must be `Hashable`.

All three are value types (see [[iOS Swift - Value vs Reference Types]]).

---

## Tuples — Ad-hoc Grouped Values

A tuple bundles multiple values without defining a `struct`. Useful for local, throwaway pairs.

```swift
let country: (name: String, capital: String) = ("Vietnam", "Hanoi")

country.name             // "Vietnam"
country.capital          // "Hanoi"

let (name, capital) = country      // destructure
```

**When to use tuples vs a struct:**

✅ Use a tuple when the grouping is local and short-lived — a function return value, a `zip` result.

```swift
func fetch() -> (data: Data, response: URLResponse) { … }
```

❌ Don't use tuples for domain types. As soon as the group escapes a function or is stored somewhere, promote it to a `struct`:

```swift
// ❌ Ugly, no methods, no Codable, no Identifiable
let country: (String, String, String) = ("Vietnam", "Hanoi", "🇻🇳")

// ✅ Named, extensible, conformable
struct Country {
    let name: String
    let capital: String
    let flag: String
}
```

---

## Type Aliases — Rename Existing Types

`typealias` gives an existing type a new name. Useful for readability, not for creating new types.

```swift
typealias CountryCode = String
typealias CompletionHandler = (Result<Country, Error>) -> Void

let vn: CountryCode = "VN"
```

> A type alias is **not** a new type. `CountryCode` and `String` are interchangeable — the compiler treats them identically. If you want type safety (a `CountryCode` that can't be passed where a plain `String` is expected), use a `struct` wrapper instead — the "newtype" or "phantom type" pattern.

---

## Common Newbie Traps

| Pattern | Fix |
|---------|-----|
| `let x` (uninitialized) inside a function body | Give it a value at declaration, or use `var` and assign later, or make it `let x: T` and assign before first read |
| `var name = ""` when you want "no name yet" | Use `String?` and `nil` — see [[iOS Swift - Optionals]] |
| Comparing `Int` and `Double` directly | Convert one side: `Double(int) == double` |
| Trying to mutate a `let` array | Change to `var`. Arrays are value types; `let` locks the whole collection. |
| Writing `1 / 2` and expecting `0.5` | `Int / Int` truncates. Use `Double(1) / Double(2)` for `0.5`. |

---

## Summary

| Concept | Rule |
|---------|------|
| `let` vs `var` | Default to `let`; use `var` only when you mutate |
| Type annotations | Optional when inferable; required for empty literals |
| Numeric conversions | Always explicit — no implicit `Int` → `Double` |
| Collections | `[T]`, `[K: V]`, `Set<T>` — all value types |
| Tuples | Fine for local groupings; promote to `struct` when it escapes |
| Type aliases | Rename only, no new type identity |

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Value vs Reference Types]] — struct vs class semantics (the next note)
- [[iOS Swift - Optionals]] — how "no value" is modeled in the type system
- [[iOS Tutorial Glossary]] — plain-English one-liners for these keywords

## Apple Docs

- The Basics — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/
- Collection Types — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/collectiontypes/
- Swift standard library — https://developer.apple.com/documentation/swift
