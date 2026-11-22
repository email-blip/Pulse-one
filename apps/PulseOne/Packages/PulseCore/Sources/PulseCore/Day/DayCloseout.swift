import Foundation

// "Tagesabschluss": one evening step that replaces the separate Abend-Notiz (TODAY) and Abendrückblick (Coach).
// It writes the Coach review and the note with one shared mood. Pure rules, no I/O.

public enum DayCloseout {
    /// The review the sheet starts with when none exists yet. The session is not marked as done by default:
    /// someone who only writes a note must not log a training they did not do.
    public static func startingReview(day: Date, planned: PlannedSession?, calendar: Calendar) -> EveningReview {
        let session = planned.flatMap { $0.kind == .rest ? nil : $0 }
        return EveningReview(day: calendar.startOfDay(for: day), completed: false, sport: session?.sport,
                             minutes: session?.minutes, rpe: nil, plannedIntensity: session?.intensity)
    }

    /// The review as saved: the shared mood, and effort only when the session happened and effort was given.
    /// A stepper shows 5 until touched, so an untouched effort saves what the person saw.
    public static func finalReview(_ review: EveningReview, effortGiven: Bool, mood: Int?) -> EveningReview {
        var result = review
        result.mood = mood.map { min(max($0, 1), 5) }
        if !effortGiven || !result.completed {
            result.rpe = nil
        } else if result.rpe == nil {
            result.rpe = 5
        }
        return result
    }

    /// A note is only kept when it holds something: text, a confirmed tag or a mood.
    public static func keepsNote(text: String, tags: [ContextTag], mood: Int?) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tags.isEmpty || mood != nil
    }

    /// One line about the movement part, as the Coach and TODAY show it.
    public static func movementText(_ review: EveningReview) -> String {
        guard review.completed else { return "Heute ausgelassen." }
        var parts = ["Erledigt"]
        if let minutes = review.minutes { parts.append("\(minutes) min") }
        if let rpe = review.rpe { parts.append("Anstrengung \(rpe)/10") }
        if let load = review.load { parts.append("Belastung \(Int(load))") }
        return parts.joined(separator: " · ")
    }

    /// The summary of a finished closeout for the TODAY card; nil while nothing is saved for today.
    /// Free text never appears here, only confirmed tags and the mood.
    public static func summary(review: EveningReview?, note: ContextEvent?) -> String? {
        guard review != nil || note != nil else { return nil }
        var lines: [String] = []
        if let review { lines.append("Bewegung: \(movementText(review))") }
        let mood = note?.mood ?? review?.mood
        var feeling = (note?.tags ?? []).map(\.title)
        if let mood { feeling.append("Stimmung \(mood)/5") }
        if !feeling.isEmpty { lines.append(feeling.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}
