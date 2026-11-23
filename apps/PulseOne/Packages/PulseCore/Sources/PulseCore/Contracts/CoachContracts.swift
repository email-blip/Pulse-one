import Foundation

/// What the coach's figure shows; the renderer (native now, Rive later) only reads this.
public enum RookPresence: String, Codable, CaseIterable, Sendable {
    case idle, listening, thinking, speaking, confirming, alerting
}

/// Points the coach's statement rests on. Opened via "Warum?".
public struct EvidenceRef: Equatable, Hashable, Sendable, Codable {
    public let kind: SampleKind?
    public let window: DateInterval
    /// Short label for the evidence row, e.g. "Ruhepuls letzte Nacht".
    public let label: String
    /// Value as shown, already formatted ("52 bpm"); nil for windows without a single value.
    public let shownValue: String?
    /// Comparison the coach used ("deine letzten 14 Nächte", "Erfahrungswert 40–50 Jahre").
    public let comparison: String?

    public init(kind: SampleKind?, window: DateInterval, label: String, shownValue: String?, comparison: String?) {
        self.kind = kind
        self.window = window
        self.label = label
        self.shownValue = shownValue
        self.comparison = comparison
    }
}

public enum CoachDirection: String, Codable, Sendable {
    case improving, stable, strained, watch, clarify, urgent
}

public enum CoachActionKind: String, Codable, Sendable {
    case startWorkout, rest, moveNow, goToBed, openTimeline, askUser, seeDoctor, none
}

public struct CoachAction: Equatable, Sendable, Codable {
    public let kind: CoachActionKind
    public let title: String
    /// Workout program to start, timeline window to open, question to ask.
    public let payload: String?

    public init(kind: CoachActionKind, title: String, payload: String? = nil) {
        self.kind = kind
        self.title = title
        self.payload = payload
    }
}

public struct UserCorrection: Equatable, Sendable, Codable {
    public let at: Date
    /// The user's words ("Ich bin krank", "Heute nur zehn Minuten").
    public let text: String

    public init(at: Date, text: String) {
        self.at = at
        self.text = text
    }
}

public struct CoachRevision: Equatable, Sendable, Codable {
    public let at: Date
    public let interpretation: String
    public let reason: String

    public init(at: Date, interpretation: String, reason: String) {
        self.at = at
        self.interpretation = interpretation
        self.reason = reason
    }
}

/// One statement of the coach: interpretation, direction, next action, with its evidence and follow-up.
public struct CoachInsight: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let subjectID: UUID?
    public let createdAt: Date
    /// What the data show, one sentence (shown under "Warum?").
    public let observation: String
    /// The visible two to three sentences.
    public var interpretation: String
    public let direction: CoachDirection
    public let evidence: [EvidenceRef]
    public var action: CoachAction?
    /// Higher first; the dashboard shows the highest valid one.
    public let priority: Int
    public let valid: DateInterval
    /// When the coach looks again whether the advice worked.
    public let recheckAt: Date?
    public var corrections: [UserCorrection]
    public var revisions: [CoachRevision]
    /// Spoken version split into cues so the timeline can follow.
    public let narration: [NarrationCue]

    public init(id: UUID = UUID(), subjectID: UUID?, createdAt: Date, observation: String, interpretation: String,
                direction: CoachDirection, evidence: [EvidenceRef], action: CoachAction?, priority: Int,
                valid: DateInterval, recheckAt: Date?, corrections: [UserCorrection] = [],
                revisions: [CoachRevision] = [], narration: [NarrationCue] = []) {
        self.id = id
        self.subjectID = subjectID
        self.createdAt = createdAt
        self.observation = observation
        self.interpretation = interpretation
        self.direction = direction
        self.evidence = evidence
        self.action = action
        self.priority = priority
        self.valid = valid
        self.recheckAt = recheckAt
        self.corrections = corrections
        self.revisions = revisions
        self.narration = narration
    }

    public func isValid(at date: Date) -> Bool { valid.contains(date) }

    /// Applies a user correction: the old text is kept as a revision, never silently overwritten.
    public mutating func revise(with correction: UserCorrection, newInterpretation: String, reason: String) {
        corrections.append(correction)
        revisions.append(CoachRevision(at: correction.at, interpretation: interpretation, reason: reason))
        interpretation = newInterpretation
    }
}
