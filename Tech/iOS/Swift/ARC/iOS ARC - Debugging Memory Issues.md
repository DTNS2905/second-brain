---
tags:
  - ios
  - swift
  - arc
  - debugging
  - instruments
  - xcode
  - fundamentals
  - mobile
created: 2026-07-06
source: https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use
---

# iOS ARC — Debugging Memory Issues

> Xcode's Memory Graph Debugger, Instruments Leaks + Allocations, the purple `!` badge, and SwiftUI-specific gotchas. When your `deinit` doesn't print, this is how you find out why. Back to index: [[iOS ARC Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**ARC/debug:** [[iOS Tutorial Glossary#Memory Graph Debugger|Memory Graph Debugger]], [[iOS Tutorial Glossary#Memory leak|Memory leak]], [[iOS Tutorial Glossary#Retain cycle / reference cycle|Retain cycle]]

---

## Prerequisites

- [[iOS ARC - How It Works]] — refcount model.
- [[iOS ARC - Retain Cycles]] — the failure mode you're hunting.

---

## Step 0 — Instrument Your Classes

Before reaching for tools, add lifetime logs. It's the fastest signal.

```swift
final class CountriesViewModel {
    init() { print("CountriesViewModel init") }
    deinit { print("CountriesViewModel deinit") }
}
```

Push the screen, dismiss it — expect a `deinit` line. Missing? You have a retain cycle. Present? No leak from *this* class; move on.

Keep the logs even in `#if DEBUG` shipping code — they're near-zero cost and priceless during triage.

---

## Xcode's Purple `!` Badge (First-Line Detection)

Xcode automatically detects some leaks and cycles at runtime. When it does, the Debug bar shows a **purple `!` badge** next to the memory graph icon.

Click it to open the Memory Graph — Xcode has already highlighted the leaking instance.

**Coverage:** the purple badge catches many cycles between plain classes but misses cycles that involve certain Combine/Swift Concurrency patterns. Use it as a signal, not a guarantee.

Apple docs: https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use

---

## Memory Graph Debugger (In-IDE, Best First Tool)

**How to open:**

1. Run the app in the simulator or on a device (Debug build).
2. Reproduce the suspected leak — push and dismiss a screen a few times.
3. In the Debug bar at the bottom of Xcode, click the **three connected nodes** icon (looks like: ● — ● — ●). Alternatively: **Debug → Debug Workflow → View Memory Graph Hierarchy**.

(Note: "Capture GPU Frame" is a *different* icon nearby — don't confuse them.)

Xcode pauses the app and shows the memory graph:

- **Left sidebar:** every allocated instance grouped by class name, with counts.
- **Main canvas:** the reference graph for the selected instance.
- **Right inspector:** the backtrace of how each reference was created.

### What to look for

- **Instances that shouldn't still exist.** If you dismissed a screen and `CountriesViewModel` still has count > 0, there's your leak.
- **Purple `!` badge** next to a class in the sidebar — Xcode auto-detected a cycle.
- **Cyclic edges** in the graph view — visible loops between instances.

### Finding *why* the leak survived

Right-click an instance → "Show Only Instances of `CountriesViewModel`" → click a specific instance. The graph shows every strong incoming reference. Follow them back until you find the unexpected owner (a stored closure, a Combine cancellable, an observer registration).

---

## Instruments — Leaks Template

For deeper investigation, especially of small transient leaks or spikes over time:

**Product → Profile → Leaks**

Instruments records every allocation and shows:

- **Leaks (top pane)** — instances the runtime knows are unreferenced by any strong path but not yet freed. Note: cyclical retains don't count as "leaks" here — they're referenced (by each other). Use the Cycles view for those.
- **Cycles view** — the Leaks instrument has a specific "Cycles & Roots" mode that shows exactly the retain cycles.
- **Call Tree** — where the leaked allocations happened.

### Allocations Template

For "why is memory growing over time" investigations (not just cycles):

**Product → Profile → Allocations**

Shows the total live-allocations graph over time. Perfect for finding "every time I navigate back and forth, memory goes up by 4MB."

Use "Mark Generation" between actions to see exactly which allocations survived a supposed-clean cycle (open screen → dismiss → mark → look at the diff).

Apple docs: https://developer.apple.com/documentation/xcode/analyzing-memory-usage

---

## SwiftUI-Specific Gotchas

SwiftUI's value-type view struct makes some patterns look scary that aren't, and hides others that are.

### View struct captures — not usually a problem

```swift
struct MyView: View {
    let viewModel: ViewModel

    var body: some View {
        Button("Reload") {
            viewModel.reload()   // View is a struct; captures don't retain-cycle
        }
    }
}
```

Views are values. They're not the retain-cycle source. Focus your leak hunt on the **classes** the view references — VMs, coordinators, repos.

### `@State private var vm = VM()` — safe

The VM lives as long as the view's *identity* lives. When the identity leaves (screen dismissed, back button, `.id(_:)` changes), SwiftUI releases the state box, VM refcount drops, `deinit` runs. If it doesn't, the leak isn't SwiftUI's fault — you have a cycle inside the VM.

### `.onAppear { Task { await viewModel.watch() } }` — dangerous

The `Task { }` isn't cancelled on view disappear. If it captures `self` (the class VM), and it never returns, the VM leaks.

Fix: use `.task { await viewModel.watch() }` — auto-cancelled. See [[iOS SwiftUI - Lifecycle]].

### Environment objects that never dealloc

`@EnvironmentObject` on a root-scoped object (installed on the root scene) intentionally lives forever. That's not a leak — it's ownership by the scene. Only worry about it if you see leaks of *child* objects that reference the environment object.

---

## Reproducing Leaks in Previews

Xcode Previews use their own `NSHostingController` under the hood. Previews may or may not exhibit real-app leaks. For serious debugging, always use the actual simulator/device build, not the preview canvas.

---

## A Reliable Debugging Workflow

1. **Add `deinit { print("X freed") }`** to the suspect classes.
2. **Reproduce**: perform the action that should tear down the classes (dismiss the screen, back-navigate, log out).
3. **Check the console.** Missing print = leak. Present print = not this class.
4. **If missing:** open the Memory Graph Debugger, filter by the class name, inspect who still holds it.
5. **Fix the reference path** with `weak` or `unowned` at the correct edge — see [[iOS ARC - Strong Weak Unowned]].
6. **Re-run.** Verify the `deinit` line now prints.
7. **Instruments Leaks** as a final pass for any residual small allocations.

---

## Common Symptoms → Likely Causes

| Symptom | Likely cause | Where to look |
|---------|--------------|---------------|
| Screen VM never `deinit`s | Stored `.sink { self... }` without `[weak self]` | [[iOS ARC - Capture Lists]] |
| Two VMs both never `deinit` | Mutual strong references | [[iOS ARC - Retain Cycles]] "two-node cycle" |
| Memory grows every navigation | Repeatedly-installed observer or timer | Big-three section of [[iOS ARC - Retain Cycles]] |
| Crash on delegate callback | `unowned` reference to already-dead target | Change to `weak` |
| Combine subscription never fires | `AnyCancellable` was dropped — no cycle, opposite problem | Make sure `.store(in: &cancellables)` is called |
| `deinit` runs on background thread | Last release happened on a Combine background scheduler | Move cleanup to `Task { await MainActor.run { ... } }` if it must be main |

---

## Apple Docs

| Topic | URL |
|-------|-----|
| Gathering information about memory use | https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use |
| Analyzing memory usage | https://developer.apple.com/documentation/xcode/analyzing-memory-usage |
| WWDC21 — Detect and diagnose memory issues | https://developer.apple.com/videos/play/wwdc2021/10180/ |
| WWDC25 — Improve memory usage and performance with Swift | https://developer.apple.com/videos/play/wwdc2025/312/ |

---

## Related Notes

- [[iOS ARC Guide]] — top-level index
- [[iOS ARC - Retain Cycles]] — the patterns you're debugging
- [[iOS SwiftUI - Concurrency and Threading]] — deinit-on-wrong-thread is a common surprise
- [[iOS Tutorial - Part 4 Domain Layer]] — the first tutorial part where these skills matter in practice
