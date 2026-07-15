---
tags:
  - ios
  - swiftui
  - fundamentals
  - animations
  - mobile
created: 2026-07-10
source: https://developer.apple.com/documentation/swiftui/animations
---

# iOS SwiftUI - Animations

> How SwiftUI animates state changes: implicit modifiers, explicit blocks, transitions, matched geometry, and time-driven animators. Link back to [[iOS SwiftUI Fundamentals Guide]].

---

## Definitions

- **Animation** — an interpolation of animatable properties (position, size, color, opacity, rotation) over time.
- **Implicit animation** — declared with `.animation(_:value:)`; SwiftUI animates any change to `value` for the modified view and its descendants.
- **Explicit animation** — declared with `withAnimation { … }`; the state mutation inside the block runs animated, regardless of where it lives.
- **Animation curve** — the function that maps elapsed time to progress (linear, ease-in-out, spring, etc.).
- **Spring** — a physics-based curve parameterized by `response` (period) and `dampingFraction` (bounciness).
- **`.transition(_:)`** — how a view animates when it is **inserted or removed** from the hierarchy (as opposed to changing in place).
- **`matchedGeometryEffect(id:in:)`** — links two views with the same `id` in the same `Namespace`; SwiftUI interpolates position/size between them for shared-element transitions.
- **`Namespace`** — a scope inside which matched-geometry `id`s are unique. Declared with `@Namespace`.
- **`PhaseAnimator`** (iOS 17+) — runs an animation through a sequence of user-defined **phases**.
- **`KeyframeAnimator`** (iOS 17+) — animates multiple properties along independent keyframe tracks.
- **`TimelineView`** — a container that redraws on a schedule (`.animation`, `.periodic(from:by:)`, `.everyMinute`, custom).
- **`@State`** — view-local mutable state; changing it re-renders the view and triggers any attached animations. See [[iOS SwiftUI - Property Wrappers]].

---

## Implicit Animation

```swift
struct HeartToggle: View {
    @State private var liked = false

    var body: some View {
        Image(systemName: liked ? "heart.fill" : "heart")
            .foregroundStyle(liked ? .red : .gray)
            .scaleEffect(liked ? 1.3 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: liked)
            .onTapGesture { liked.toggle() }
    }
}
```

`.animation(_:value:)` observes `liked`; when it changes, every animatable property upstream in the chain interpolates. The `value:` argument is mandatory — the older `.animation(_)` overload is deprecated because it animated too much.

---

## Explicit Animation

```swift
struct ExpandCard: View {
    @State private var expanded = false

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue)
                .frame(height: expanded ? 300 : 100)

            Button("Toggle") {
                withAnimation(.easeInOut(duration: 0.4)) {
                    expanded.toggle()
                }
            }
        }
    }
}
```

- ✅ Use `withAnimation` when the state lives in a `ViewModel` or a non-`View` type — the caller decides whether the change is animated.
- ✅ Use `.animation(_:value:)` when the animation is a property of the view, not the caller.

---

## Built-in Curves

```swift
.animation(.linear, value: v)
.animation(.easeIn, value: v)
.animation(.easeOut, value: v)
.animation(.easeInOut, value: v)
.animation(.easeInOut(duration: 0.5), value: v)

.animation(.spring, value: v)
.animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: v)
.animation(.bouncy, value: v)
.animation(.smooth, value: v)
.animation(.snappy, value: v)

.animation(.interpolatingSpring(stiffness: 200, damping: 20), value: v)
```

| Curve | Feel | Use |
|-------|------|-----|
| `.linear` | Constant speed | Progress bars, marquees |
| `.easeIn` / `.easeOut` | Accelerate / decelerate | Fades, subtle reveals |
| `.easeInOut` | Both | Most transitions |
| `.spring` | Physics, natural | Gestures, taps, drags |
| `.interpolatingSpring` | Physics with stiffness/damping | Gesture handoffs (velocity preserved) |
| `.bouncy` / `.smooth` / `.snappy` | Preset springs (iOS 17+) | Quick defaults |

**Delay & repeat:**

```swift
.animation(.easeInOut(duration: 0.3).delay(0.1), value: v)
.animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: v)
```

---

## Transitions (Insertion / Removal)

`.transition(_:)` describes how a view enters and exits — used with conditional rendering inside a `withAnimation` block or an animated parent.

```swift
struct Banner: View {
    @State private var showBanner = false

    var body: some View {
        VStack {
            if showBanner {
                Text("Saved!")
                    .padding()
                    .background(.green.opacity(0.2))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button("Toggle") {
                withAnimation(.spring) { showBanner.toggle() }
            }
        }
    }
}
```

Common transitions: `.opacity`, `.slide`, `.scale`, `.move(edge:)`, `.push(from:)`, `.asymmetric(insertion:removal:)`, `.combined(with:)`.

**Custom transition (iOS 17+):**

```swift
struct BlurFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 12)
    }
}

view.transition(BlurFade())
```

---

## `matchedGeometryEffect` (Shared Element Transitions)

```swift
struct HeroExample: View {
    @Namespace private var ns
    @State private var expanded = false

    var body: some View {
        ZStack {
            if expanded {
                RoundedRectangle(cornerRadius: 32)
                    .fill(.blue)
                    .matchedGeometryEffect(id: "hero", in: ns)
                    .frame(width: 320, height: 480)
                    .onTapGesture { withAnimation(.spring) { expanded = false } }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue)
                    .matchedGeometryEffect(id: "hero", in: ns)
                    .frame(width: 80, height: 80)
                    .onTapGesture { withAnimation(.spring) { expanded = true } }
            }
        }
    }
}
```

Two views with the same `id` in the same `Namespace` interpolate size + position between them. Ideal for photo previews expanding to full-screen, or a card promoting to a detail view.

---

## `PhaseAnimator` (iOS 17+)

Runs a sequence of phases with your rendering function called once per phase.

```swift
enum PulsePhase: CaseIterable { case rest, expanded, contracted }

struct Pulse: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(.pink)
            .phaseAnimator(PulsePhase.allCases) { view, phase in
                view.scaleEffect(phase == .expanded ? 1.4 : phase == .contracted ? 0.9 : 1.0)
            } animation: { phase in
                switch phase {
                case .rest:       .easeInOut(duration: 0.8)
                case .expanded:   .spring(response: 0.3)
                case .contracted: .spring(response: 0.5)
                }
            }
    }
}
```

Loops through phases automatically. Great for attention-grabbing idle animations.

---

## `KeyframeAnimator` (iOS 17+)

Animate multiple properties along **independent tracks**.

```swift
struct BouncePop: View {
    @State private var trigger = 0

    var body: some View {
        Image(systemName: "bell.fill")
            .keyframeAnimator(initialValue: AnimationValues(), trigger: trigger) { view, val in
                view
                    .scaleEffect(val.scale)
                    .rotationEffect(.degrees(val.rotation))
                    .offset(y: val.yOffset)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.3, duration: 0.2)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
                KeyframeTrack(\.rotation) {
                    CubicKeyframe(-15, duration: 0.15)
                    CubicKeyframe(15,  duration: 0.15)
                    CubicKeyframe(0,   duration: 0.2)
                }
                KeyframeTrack(\.yOffset) {
                    CubicKeyframe(-20, duration: 0.2)
                    SpringKeyframe(0,   duration: 0.4)
                }
            }
            .onTapGesture { trigger += 1 }
    }
}

struct AnimationValues {
    var scale: Double = 1
    var rotation: Double = 0
    var yOffset: Double = 0
}
```

Each track has its own timeline; SwiftUI composes them per-frame.

---

## `TimelineView` (Time-Driven)

Redraws on a schedule — the view function receives the current `Date`.

```swift
TimelineView(.animation) { context in
    Circle()
        .fill(.orange)
        .scaleEffect(1 + 0.1 * sin(context.date.timeIntervalSince1970 * 4))
}
```

Schedules: `.animation` (~60fps), `.periodic(from:by:)`, `.everyMinute`, `.explicit([Date])`.

Use for clocks, waveforms, ambient loops. **Not** for state-driven UI (use `.animation` / `withAnimation` for those).

---

## Interaction with `@State` and `ViewModel`

Animations only fire when the observed value changes **through a state-tracking wrapper** — `@State`, `@Published` on an `ObservableObject`, or an `@Observable` property.

```swift
@MainActor
final class LikeViewModel: ObservableObject {
    @Published var liked = false
    func toggle() { liked.toggle() }
}

struct LikeButton: View {
    @StateObject var vm = LikeViewModel()

    var body: some View {
        Image(systemName: vm.liked ? "heart.fill" : "heart")
            .scaleEffect(vm.liked ? 1.3 : 1.0)
            .animation(.spring, value: vm.liked)
            .onTapGesture {
                withAnimation(.spring) { vm.toggle() }
            }
    }
}
```

The `withAnimation` block is optional here — `.animation(.spring, value: vm.liked)` will pick up the change either way. Wrap with `withAnimation` if the change might propagate to siblings you also want animated.

---

## Anti-Patterns

### 1. Global implicit animation with no value

❌ Before — animates every state change under this modifier, including unrelated ones (perf hit + jitter):

```swift
VStack {
    HeavyList()
    Toggle("On", isOn: $on)
}
.animation(.easeInOut)   // deprecated overload
```

✅ After — target one value:

```swift
VStack {
    HeavyList()
    Toggle("On", isOn: $on)
}
.animation(.easeInOut, value: on)
```

### 2. Animating the wrong state

❌ Before — animate `x` but mutate `y`; nothing animates:

```swift
Rectangle()
    .offset(x: x)
    .animation(.spring, value: y)
```

✅ After — animate the value that actually drives the visual change:

```swift
Rectangle()
    .offset(x: x)
    .animation(.spring, value: x)
```

### 3. Mutating state outside `withAnimation` when the ViewModel needs it animated

❌ Before — imperative caller forgets to wrap:

```swift
Button("Expand") { vm.expand() }
```

✅ After — either wrap the caller, or let the view declare it implicitly:

```swift
Button("Expand") {
    withAnimation(.spring) { vm.expand() }
}
```

or

```swift
Rectangle()
    .frame(height: vm.expanded ? 300 : 100)
    .animation(.spring, value: vm.expanded)
```

### 4. Animating layout of an expensive subtree

❌ Before — every frame re-lays out a 500-row list:

```swift
List(rows) { RowView(row: $0) }
    .frame(height: expanded ? 600 : 200)
    .animation(.easeInOut, value: expanded)
```

✅ After — clip / mask instead of resizing the container:

```swift
List(rows) { RowView(row: $0) }
    .frame(height: 600)
    .clipShape(Rectangle().size(width: .infinity, height: expanded ? 600 : 200))
    .animation(.easeInOut, value: expanded)
```

Or animate a fixed-size container with an internal offset. Layout is the expensive part; opacity / transform are cheap.

### 5. Repeating forever without stopping condition

❌ Before — animation keeps running even when off-screen:

```swift
Circle()
    .scaleEffect(pulse ? 1.2 : 1)
    .animation(.easeInOut.repeatForever(autoreverses: true), value: pulse)
    .onAppear { pulse = true }
```

✅ After — stop when the view disappears or the state settles:

```swift
Circle()
    .scaleEffect(pulse ? 1.2 : 1)
    .animation(.easeInOut.repeatForever(autoreverses: true), value: pulse)
    .onAppear { pulse = true }
    .onDisappear { pulse = false }
```

Better: use `.phaseAnimator` or `TimelineView` — both stop paying cost when off-screen.

### 6. Nesting `withAnimation` inside `.animation(_:value:)`

❌ Before — two competing animations, unpredictable result:

```swift
Rectangle()
    .frame(width: w)
    .animation(.spring, value: w)
    .onTapGesture {
        withAnimation(.easeInOut(duration: 2)) { w = 300 }
    }
}
```

✅ After — pick one:

```swift
Rectangle()
    .frame(width: w)
    .onTapGesture {
        withAnimation(.easeInOut(duration: 2)) { w = 300 }
    }
```

---

## Interaction with Clean Architecture / MVVM

- **View** — owns the animation modifiers (`.animation`, `.transition`, `matchedGeometryEffect`). Decides *how* things move.
- **ViewModel** — publishes state (`@Published`, `@Observable`) that the View reads. Never imports `Animation`.
- **Domain / Data** — no animation concerns at all.

If a ViewModel needs to trigger an "animated" change, it just flips its state. The View reads that state through an animated modifier. Wrap `withAnimation` at the **call site** (`Button` action, gesture handler), never inside the ViewModel — that keeps the ViewModel testable without SwiftUI.

See [[iOS SwiftUI Architecture - MVVM with Combine]] and [[iOS SwiftUI Architecture - Presentation Layer]].

---

## Summary Table

| Task | API | Notes |
|------|-----|-------|
| Animate a state change | `.animation(_:value:)` | Always pass `value:` |
| Animate from a call site | `withAnimation { … }` | State mutation runs animated |
| Curve — natural | `.spring` / `.bouncy` / `.smooth` | iOS 17+ presets |
| Curve — timed | `.easeInOut(duration:)` | Predictable, use for UI |
| Curve — physics | `.interpolatingSpring(stiffness:damping:)` | Preserve gesture velocity |
| Delay | `.animation(.spring.delay(0.1), …)` | Chain on the curve |
| Repeat | `.repeatForever(autoreverses:)` | Stop on `.onDisappear` |
| Insert / remove | `.transition(.move(edge:).combined(with: .opacity))` | Needs animated parent |
| Custom transition | `struct T: Transition` (iOS 17+) | Uses `TransitionPhase` |
| Shared element | `matchedGeometryEffect(id:in:)` + `@Namespace` | Same `id`, same `Namespace` |
| Phase loop | `.phaseAnimator(phases) { view, phase in … }` | iOS 17+ |
| Multi-track | `.keyframeAnimator(initialValue:trigger:)` | iOS 17+ |
| Time-driven | `TimelineView(.animation) { context in … }` | Not for state UI |

---

## Related

- [[iOS SwiftUI Fundamentals Guide]] — top index
- [[iOS SwiftUI - Core Concepts]] — state, view identity, why animation needs `value:`
- [[iOS SwiftUI - Core Components]] — the primitives you'll animate
- [[iOS SwiftUI - Lifecycle]] — `.onAppear` / `.onDisappear` to start/stop looping animations
- [[iOS SwiftUI - Property Wrappers]] — `@State`, `@Published`, `@Observable` driving changes
- [[iOS SwiftUI - Navigation]] — page transitions, sheet presentation
- [[iOS SwiftUI Architecture - MVVM with Combine]] — where animation triggers live
- [[iOS SwiftUI Architecture - Presentation Layer]] — View / ViewModel boundaries

---

## Apple Docs

- https://developer.apple.com/documentation/swiftui/animations
- https://developer.apple.com/documentation/swiftui/animation
- https://developer.apple.com/documentation/swiftui/withanimation(_:_:)
- https://developer.apple.com/documentation/swiftui/matchedgeometryeffect
- https://developer.apple.com/documentation/swiftui/phaseanimator
- https://developer.apple.com/documentation/swiftui/keyframeanimator
