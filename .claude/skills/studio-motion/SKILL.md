---
name: studio-motion
description: Studio standard for fluid SwiftUI animations, transitions and microinteractions. Use when adding or reviewing any animation, transition, gesture-driven motion, loading state, button feedback, or when motion feels stiff, slow, janky or overdone.
---

# Motion & Microinteractions

## Activation
- Any `withAnimation`, `.animation`, `.transition`, `matchedGeometryEffect`, `PhaseAnimator`, `KeyframeAnimator`, `TimelineView`, gesture-driven state.
- Button/tap feedback, state changes (empty → loaded, error), navigation transitions.

## Standards
- **Springs by default.** Use named tokens from `DesignSystem/Motion.swift`, never inline magic numbers:
  ```swift
  enum Motion {
      static let snappy  = Animation.spring(duration: 0.3, bounce: 0.15)
      static let gentle  = Animation.spring(duration: 0.5, bounce: 0.05)
      static let playful = Animation.spring(duration: 0.45, bounce: 0.35)
  }
  ```
- Feedback within 100 ms of touch. Microinteractions 150–350 ms, screen transitions ≤ 500 ms.
- Motion explains something (where it came from, what changed). No decorative loops on content screens.
- Gestures are interruptible: drive state from the gesture, animate the release with the gesture's velocity (`.interactiveSpring` / spring with initial velocity).
- Animate only cheap properties (opacity, scale, offset, rotation, shader parameters). Avoid animating layout of large lists.
- Numbers: `.contentTransition(.numericText())`. Symbols: `.symbolEffect` / `.contentTransition(.symbolEffect(.replace))`.
- Multi-step sequences: `PhaseAnimator` (discrete) or `KeyframeAnimator` (curves) – not chained `DispatchQueue.asyncAfter`.
- Continuous effects: `TimelineView(.animation)` and pause when off-screen or when `scenePhase != .active`.
- **Reduce Motion is mandatory:** read `@Environment(\.accessibilityReduceMotion)`. Replace movement/scale/parallax with crossfades; stop looping animations. Haptics/sound timing stays the same (see `studio-haptics`).
- Every animation that pairs with a haptic or sound triggers them from the same state change (one source of truth), so they stay in sync.

## Quality checks
- [ ] No raw durations/curves outside `Motion.swift` (`grep -rn "\.easeInOut\|spring(response" apps/`).
- [ ] Reduce Motion variant exists and is covered by a UI test launch argument (`-UIAccessibilityReduceMotion` is not settable; use app launch flag `-reduceMotion YES` that the app maps onto its own environment override).
- [ ] Hitch check: `XCTOSSignpostMetric.animationHitches`-style performance test (see `studio-architecture`) on the main animated interaction.
- [ ] Screenshots mid-animation are not needed; verify end states in the screenshot matrix.

## Example (press feedback + sync point)
```swift
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}
```
