import SwiftUI

/// Motion contract (Neubau plan, Auftrag 02 §3): one entry per *meaning*, never per screen.
/// Every animated change in the app picks one of these events; durations and curves live only here.
///
/// Rules
/// - Motion explains a change (where it came from, what changed). No endless loops on content screens;
///   the only repeating motion is the coach orb while it listens, thinks or speaks.
/// - Reduce Motion: movement, scale and parallax become a short crossfade (`reduced`); haptic and sound
///   timing stay the same.
/// - Animation, haptic and sound fire from the same state change (`.dkMotion(_:value:)`), so they stay in sync.
/// - UI-test scenarios freeze motion (`freezeAnimations`), screenshots show end states.
enum MotionEvent: String, CaseIterable, Sendable {
    /// A new measurement lands on a tile or a track: number rolls, point fades in from the right.
    case measurementLands
    /// Day ↔ week ↔ month: tracks rescale together.
    case rangeChange
    /// The cursor snaps to an original data point.
    case pointSelect
    /// A tile moves to another place while arranging.
    case tileSwap
    /// A workout (Einheit) begins: start screen collapses into the timer.
    case workoutStart
    /// A workout phase ends; the next one slides in.
    case phaseEnd
    /// Coach statement opens its evidence ("Warum?").
    case insightToEvidence
    /// Button press feedback.
    case press

    /// The full animation.
    var animation: Animation {
        switch self {
        case .measurementLands: .spring(duration: 0.55, bounce: 0.12)
        case .rangeChange: .spring(duration: 0.45, bounce: 0.0)
        case .pointSelect: .spring(duration: 0.18, bounce: 0.0)
        case .tileSwap: .spring(duration: 0.38, bounce: 0.18)
        case .workoutStart: .spring(duration: 0.6, bounce: 0.1)
        case .phaseEnd: .spring(duration: 0.42, bounce: 0.08)
        case .insightToEvidence: .spring(duration: 0.4, bounce: 0.05)
        case .press: .spring(duration: 0.22, bounce: 0.3)
        }
    }

    /// Replacement under Reduce Motion: a crossfade without movement, or nothing where the change is instant anyway.
    var reduced: Animation? {
        switch self {
        case .pointSelect, .press: nil
        case .measurementLands, .rangeChange, .tileSwap, .phaseEnd, .insightToEvidence: .easeOut(duration: 0.2)
        case .workoutStart: .easeOut(duration: 0.25)
        }
    }

    /// How a view enters for this event.
    var transition: AnyTransition {
        switch self {
        case .measurementLands: .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity)
        case .phaseEnd: .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity))
        case .insightToEvidence: .move(edge: .bottom).combined(with: .opacity)
        case .workoutStart: .scale(scale: 0.92).combined(with: .opacity)
        case .rangeChange, .pointSelect, .tileSwap, .press: .opacity
        }
    }

    /// The haptic that belongs to the event (nil = silent). Same moment as the animation start.
    var haptic: SensoryFeedback? {
        switch self {
        case .measurementLands: nil   // data arrives often; no buzz for every point
        case .rangeChange: .selection
        case .pointSelect: .selection
        case .tileSwap: .impact(weight: .light, intensity: 0.7)
        case .workoutStart: .start
        case .phaseEnd: .impact(flexibility: .soft, intensity: 0.9)
        case .insightToEvidence: .impact(flexibility: .soft, intensity: 0.5)
        case .press: nil              // buttons get their haptic from the action they trigger
        }
    }

    /// The sound of the event (nil = silent). Only three moments make a sound; most changes are quiet.
    var sound: DKSound? {
        switch self {
        case .workoutStart: .start
        case .phaseEnd: .phase
        case .measurementLands, .rangeChange, .pointSelect, .tileSwap, .insightToEvidence, .press: nil
        }
    }

    /// The animation to use for the current settings; nil means "change without animation".
    func resolvedAnimation(reduceMotion: Bool, frozen: Bool = false) -> Animation? {
        if frozen { return nil }
        return reduceMotion ? reduced : animation
    }

    func resolvedTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

/// Orb rhythm per coach state. Loops only while the state lasts and never under Reduce Motion.
enum OrbMotion {
    /// Seconds per breath while listening.
    static let listeningPeriod: Double = 2.4
    /// Seconds per turn of the thinking arc.
    static let thinkingPeriod: Double = 1.6
    /// Seconds per pulse while speaking (roughly syllable rhythm, deliberately calm).
    static let speakingPeriod: Double = 0.9
    /// One-shot change between states.
    static let stateChange = Animation.spring(duration: 0.45, bounce: 0.15)
}

extension View {
    /// Animates `value` changes with the event's curve (or its Reduce-Motion replacement) and plays
    /// the event's haptic at the same moment. Sound is triggered by the owner of the state via `DKSoundPlayer`.
    func dkMotion<V: Equatable>(_ event: MotionEvent, value: V) -> some View {
        modifier(MotionEventModifier(event: event, value: value))
    }
}

private struct MotionEventModifier<V: Equatable>: ViewModifier {
    let event: MotionEvent
    let value: V
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var frozen

    func body(content: Content) -> some View {
        let animated = content.animation(event.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen), value: value)
        if let haptic = event.haptic {
            animated.sensoryFeedback(haptic, trigger: value)
        } else {
            animated
        }
    }
}
