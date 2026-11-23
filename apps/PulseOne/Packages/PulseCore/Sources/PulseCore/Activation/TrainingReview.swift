import Foundation

/// What is known about one guided session. Heart rate is optional and only describes the body's response.
public struct TrainingSessionFacts: Sendable {
    public var family: ActivationFamily
    public var plannedBlocks: Int
    public var doneBlocks: Int
    public var minutes: Int
    /// Perceived exertion 1–10, if the person gave one.
    public var rpe: Int?
    /// Heart rates measured during the session (bpm); empty without a live measurement.
    public var heartRates: [Double]
    public var restingHeartRate: Double?
    /// Earlier sessions of the same family with comparable content.
    public var comparableSessions: Int

    public init(family: ActivationFamily, plannedBlocks: Int, doneBlocks: Int, minutes: Int, rpe: Int?, heartRates: [Double],
                restingHeartRate: Double?, comparableSessions: Int) {
        self.family = family
        self.plannedBlocks = plannedBlocks
        self.doneBlocks = doneBlocks
        self.minutes = minutes
        self.rpe = rpe
        self.heartRates = heartRates
        self.restingHeartRate = restingHeartRate
        self.comparableSessions = comparableSessions
    }
}

public enum TrainingExecution: String, Codable, Sendable {
    case complete, partial, notStarted
}

/// Feedback in three separate parts (Codex P1-005): execution, measurable response, long-term effect.
/// Heart rate never proves or disproves that a session worked, and never judges the person.
public struct TrainingReview: Equatable, Sendable {
    public let execution: TrainingExecution
    public let executionText: String
    public let responseText: String
    public let effectText: String
}

public enum TrainingReviewer {
    /// Sessions of one kind before a trend in the effect is described at all.
    public static let sessionsForEffect = 6

    public static func review(_ facts: TrainingSessionFacts) -> TrainingReview {
        let execution: TrainingExecution = facts.doneBlocks == 0 ? .notStarted
            : facts.doneBlocks >= facts.plannedBlocks ? .complete : .partial
        var executionText: String
        switch execution {
        case .complete: executionText = "Alle \(facts.plannedBlocks) Blöcke gemacht, \(facts.minutes) Minuten."
        case .partial: executionText = "\(facts.doneBlocks) von \(facts.plannedBlocks) Blöcken gemacht, \(facts.minutes) Minuten."
        case .notStarted: executionText = "Heute nicht gemacht. Das ist in Ordnung, morgen gibt es einen neuen Plan."
        }
        if let rpe = facts.rpe { executionText += " Gefühlte Anstrengung \(rpe) von 10." }

        let responseText: String
        if facts.heartRates.isEmpty {
            responseText = "Ohne Pulsmessung während der Einheit. Die Ausführung zählt trotzdem."
        } else {
            let mean = facts.heartRates.reduce(0, +) / Double(facts.heartRates.count)
            let peak = facts.heartRates.max() ?? mean
            var text = "Puls gemessen: im Mittel \(LocalCheckIn.number(mean.rounded())) bpm, höchstens \(LocalCheckIn.number(peak.rounded())) bpm."
            if facts.family != .cardio {
                text += " Bei Kraft- und Beweglichkeitsübungen steigt der Puls oft wenig; das sagt nichts über die Qualität der Einheit."
            }
            responseText = text
        }

        let effectText = facts.comparableSessions + 1 >= sessionsForEffect
            ? "Ob es wirkt, zeigt der Vergleich deiner Wiederholungen und Zeiten über die Wochen, nicht der Puls von heute."
            : "Die Wirkung ist nach \(facts.comparableSessions + 1) Einheit\(facts.comparableSessions == 0 ? "" : "en") noch nicht beurteilbar."
        return TrainingReview(execution: execution, executionText: executionText, responseText: responseText, effectText: effectText)
    }
}
