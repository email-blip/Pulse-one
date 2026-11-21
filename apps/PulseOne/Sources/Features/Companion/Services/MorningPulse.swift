import Foundation
import PulseCore

/// Short live heart-rate measurement right after waking, through the app's existing ring measurement
/// (`RingStore.startHeartRate`). Only real ring answers count; returns nil when the ring is not connected,
/// delivers fewer than three values, or in UI tests. Never invents a value.
@MainActor
enum MorningPulse {
    /// Measures for up to `seconds` and returns the median of the received values (bpm).
    static func measure(with ring: RingStore, seconds: Int = 30) async -> Double? {
        guard !LaunchOptions.current.isUITesting, ring.snapshot.connection == .ready,
              !ring.snapshot.measurement.isActive else { return nil }
        ring.startHeartRate()
        var values: [Int] = []
        var lastValueAt: Date?
        for _ in 0..<max(seconds, 1) {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            if case .receiving(let value, let at, _) = ring.snapshot.measurement, at != lastValueAt {
                values.append(value)
                lastValueAt = at
            }
            if !ring.snapshot.measurement.isActive { break }
        }
        ring.stopHeartRate()
        return median(values)
    }

    /// Median of at least three values, else nil.
    static func median(_ values: [Int]) -> Double? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return Double(sorted[mid]) }
        return Double(sorted[mid - 1] + sorted[mid]) / 2
    }
}
