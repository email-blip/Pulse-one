---
name: studio-haptics
description: Studio standard for haptic feedback with SwiftUI sensoryFeedback and Core Haptics (CHHapticEngine, patterns, AHAP), synchronized with animation and sound. Use when adding or reviewing any haptic, vibration, or tactile feedback.
---

# Haptics (SwiftUI + Core Haptics)

## Activation
- Any `.sensoryFeedback`, `UIImpactFeedbackGenerator`, `CHHapticEngine`, `.ahap` file, or "make it feel …".

## Choose
- **Standard feedback** (selection, success, warning, impact): SwiftUI `.sensoryFeedback(_:trigger:)` (iOS 17+). Prefer this.
- **Custom patterns** (signature interactions, textures, sync to sound): Core Haptics `CHHapticEngine` + `CHHapticPattern` (events: `.hapticTransient`, `.hapticContinuous`; parameters: intensity, sharpness).

## Standards
- Check `CHHapticEngine.capabilitiesForHardware().supportsHaptics`; no-op otherwise (Simulator has no haptics).
- One `HapticEngine` service: create engine once, set `resetHandler` (restart) and `stoppedHandler` (log), `isAutoShutdownEnabled = true`.
- Patterns are data: build `CHHapticPattern` from a small Swift struct (time, intensity, sharpness) so they are unit-testable; AHAP files allowed for complex patterns.
- **Sync rule:** a `FeedbackCoordinator` receives one semantic event (e.g. `.orbCaptured`) and triggers animation state, haptic pattern and sound at the same moment. Haptic event times match audio transients (tolerance ≤ 10 ms in the pattern data).
- Restraint: haptics confirm user actions or important state changes; no haptics on scroll, no continuous buzzing > 1 s.
- Respect the system setting implicitly (system handles it) and offer an in-app toggle "Haptik" together with "Töne".

## Quality checks
- [ ] Pattern unit tests: event count, times ascending, intensity/sharpness within 0…1, total duration ≤ 1 s for UI feedback.
- [ ] Sync test: for each semantic event, haptic event times == sound transient times (from the same definition).
- [ ] App runs without haptics (Simulator) without errors in log.
- [ ] Device check via TestFlight: feel test noted in the PR.

## Example
```swift
struct HapticBeat: Equatable { var time: TimeInterval; var intensity: Float; var sharpness: Float }

extension Array where Element == HapticBeat {
    func pattern() throws -> CHHapticPattern {
        let events = map { beat in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness)
            ], relativeTime: beat.time)
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
```
