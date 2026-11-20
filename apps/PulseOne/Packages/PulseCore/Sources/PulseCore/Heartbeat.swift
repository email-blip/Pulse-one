import Foundation

/// Mechanical heartbeat curve for the Heart Chamber animation, derived only from a BPM value.
/// This is an illustration of rhythm, **not** a measured ECG (directive §5.3).
public enum Heartbeat {
    /// Contraction of atria and ventricles, each 0 (relaxed) … 1 (fully contracted).
    public struct Contraction: Equatable, Sendable {
        public let atria: Double
        public let ventricles: Double
    }

    /// Resting tempo shown while no live value exists (slow "idle" breathing, no fake pulse).
    public static let idlePeriod: TimeInterval = 4.0

    /// Seconds per beat for a BPM, clamped to a plausible range.
    public static func period(bpm: Int) -> TimeInterval {
        60.0 / Double(min(max(bpm, 30), 220))
    }

    /// Phase 0..<1 within the current beat at `time`.
    public static func phase(at time: TimeInterval, period: TimeInterval) -> Double {
        guard period > 0 else { return 0 }
        let p = time.truncatingRemainder(dividingBy: period) / period
        return p < 0 ? p + 1 : p
    }

    /// Atrial kick at the start of the beat, then a sharp ventricular systole and a slower relaxation.
    public static func contraction(phase: Double) -> Contraction {
        let atria = pulse(phase, start: 0.0, rise: 0.06, fall: 0.10)
        let ventricles = pulse(phase, start: 0.12, rise: 0.10, fall: 0.28)
        return Contraction(atria: atria, ventricles: ventricles)
    }

    /// Gentle idle motion (no beat) while no live heart rate exists.
    public static func idle(phase: Double) -> Contraction {
        let v = 0.15 * (0.5 - 0.5 * cos(phase * 2 * .pi))
        return Contraction(atria: v, ventricles: v)
    }

    /// Phase offsets of the two heart sounds ("lub" at ventricular systole, "dub" at valve closure).
    public static let lubPhase = 0.12
    public static let dubPhase = 0.40

    /// Smooth bump: rises over `rise`, falls over `fall`, zero elsewhere.
    static func pulse(_ phase: Double, start: Double, rise: Double, fall: Double) -> Double {
        let t = phase - start
        if t < 0 || t > rise + fall { return 0 }
        if t < rise { return smooth(t / rise) }
        return 1 - smooth((t - rise) / fall)
    }

    static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
