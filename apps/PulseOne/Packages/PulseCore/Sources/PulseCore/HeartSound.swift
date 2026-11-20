import Foundation

/// Synthesised "lub-dub" for the Heart Chamber: two low, soft thumps. Pure → testable.
public enum HeartSound {
    /// Mono samples for one beat; `gap` = seconds between lub and dub.
    public static func beat(gap: TimeInterval, sampleRate: Double = 48_000) -> [Float] {
        let lub = thump(frequency: 52, duration: 0.16, amplitude: 0.9, sampleRate: sampleRate)
        let dub = thump(frequency: 68, duration: 0.12, amplitude: 0.6, sampleRate: sampleRate)
        let dubStart = Int(max(0.18, gap) * sampleRate)
        var mix = [Float](repeating: 0, count: dubStart + dub.count)
        for (i, s) in lub.enumerated() { mix[i] += s }
        for (i, s) in dub.enumerated() { mix[dubStart + i] += s }
        return mix.map { Float(tanh(Double($0))) }
    }

    static func thump(frequency: Double, duration: Double, amplitude: Double, sampleRate: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        let attack = 0.008 * sampleRate
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let env = min(1, Double(i) / attack) * exp(-t * 28) * min(1, Double(count - 1 - i) / attack)
            // Slight downward pitch glide makes it sound like a body, not a beep.
            let f = frequency * (1 - 0.25 * t / duration)
            return Float(amplitude * env * sin(2 * .pi * f * t))
        }
    }
}
