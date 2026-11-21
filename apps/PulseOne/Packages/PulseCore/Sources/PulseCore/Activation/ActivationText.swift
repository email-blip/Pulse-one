import Foundation

/// German display texts for activation plans (targets, durations, summaries).
public enum ActivationText {
    /// "12 × Liegestütz" for repetitions, "40 s Unterarmstütz" for holds and timed work.
    public static func target(_ block: ActivationBlock) -> String {
        let name: String = ActivationLibrary.exercise(block.exerciseID)?.name ?? block.exerciseID
        switch block.target {
        case .reps(let reps):
            return "\(reps) × \(name)"
        case .seconds(let seconds):
            return "\(seconds) s \(name)"
        }
    }

    /// "etwa 7 Minuten" (at least one minute).
    public static func duration(_ seconds: Int) -> String {
        let exact: Double = Double(max(0, seconds)) / 60.0
        let minutes: Int = max(1, Int(exact.rounded()))
        if minutes == 1 { return "etwa 1 Minute" }
        return "etwa \(minutes) Minuten"
    }

    /// "1 Runde" / "3 Runden".
    public static func rounds(_ count: Int) -> String {
        count == 1 ? "1 Runde" : "\(count) Runden"
    }

    /// "3 Runden: 6 × Liegestütz, 20 s Unterarmstütz · etwa 5 Minuten".
    static func summary(blocks: [ActivationBlock], rounds: Int, seconds: Int, gentle: Bool) -> String {
        let parts: [String] = blocks.map { target($0) }
        let list: String = parts.joined(separator: ", ")
        let head: String = gentle ? "Sanft bewegen" : ActivationText.rounds(rounds)
        return "\(head): \(list) · \(duration(seconds))"
    }
}
