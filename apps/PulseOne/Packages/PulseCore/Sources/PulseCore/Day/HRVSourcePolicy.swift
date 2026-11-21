import Foundation

/// The one rule for which heart rate variability series a module uses. Ring HRV (method not disclosed by the
/// vendor) and Apple's SDNN are different measurements and are never mixed in one band or comparison.
/// Rule: the ring series when it has any value in the window, otherwise Apple's.
public enum HRVSourcePolicy {
    /// The kind to use for a window, given which kinds have values in it; nil when neither has any.
    public static func kind(ringHasValues: Bool, appleHasValues: Bool) -> SampleKind? {
        if ringHasValues { return .ringHRV }
        if appleHasValues { return .heartRateVariability }
        return nil
    }

    /// Picks one series for a window, never mixing the two.
    public static func series<Value>(ring: [Value], apple: [Value]) -> (kind: SampleKind?, values: [Value]) {
        switch kind(ringHasValues: !ring.isEmpty, appleHasValues: !apple.isEmpty) {
        case .ringHRV?: (.ringHRV, ring)
        case .heartRateVariability?: (.heartRateVariability, apple)
        default: (nil, [])
        }
    }
}
