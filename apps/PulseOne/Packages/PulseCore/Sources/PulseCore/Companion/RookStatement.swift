import Foundation

// ROOK, the one coach of PULSE ONE (NEUBAU-PLAN §9, Auftrag 04). Visible: headline, two to three sentences
// (interpretation → direction → next action) and one button. Everything else sits behind "Warum?":
// measurements, comparison window, events, calculation, alternative explanations and uncertainty.

/// Another possible explanation, shown under "Warum?" with a qualitative fit (never a percentage).
public struct RookAlternative: Codable, Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let fit: InsightFit
    public let note: String

    public init(title: String, fit: InsightFit, note: String) {
        self.title = title
        self.fit = fit
        self.note = note
    }
}

/// The background of one statement ("Warum?"). Measurements are the `EvidenceRef`s of the `CoachInsight`.
public struct RookWhy: Codable, Equatable, Sendable {
    /// What the values were compared with ("deine 28 Nächte vor heute").
    public var comparison: String
    /// Events and the person's own answers and corrections, oldest first.
    public var events: [String]
    /// How the statement was computed, in plain words.
    public var calculation: String
    public var alternatives: [RookAlternative]
    /// How sure the statement is and why.
    public var uncertainty: String

    public init(comparison: String, events: [String], calculation: String, alternatives: [RookAlternative],
                uncertainty: String) {
        self.comparison = comparison
        self.events = events
        self.calculation = calculation
        self.alternatives = alternatives
        self.uncertainty = uncertainty
    }

    public static let empty = RookWhy(comparison: "", events: [], calculation: "", alternatives: [], uncertainty: "")
}

public enum RookSource: String, Codable, Sendable {
    /// Computed on the iPhone (no key, offline, budget used up or Claude's answer failed the checks).
    case local
    /// Claude's answer after the local checks.
    case claude
    /// Synthetic demonstration case, only with `-uiTesting YES` and the "Testansicht" banner.
    case demo
}

/// One statement of ROOK: the shared `CoachInsight` contract plus headline and "Warum?".
public struct RookStatement: Codable, Equatable, Sendable, Identifiable {
    public var insight: CoachInsight
    public var headline: String
    public var why: RookWhy
    public var source: RookSource
    /// What the data show, in one sentence with numbers (from `insight.observation`).
    public var observation: String { insight.observation }

    public var id: UUID { insight.id }

    public init(insight: CoachInsight, headline: String, why: RookWhy, source: RookSource) {
        self.insight = insight
        self.headline = headline
        self.why = why
        self.source = source
    }

    /// Sentences to speak or show one by one. Before a correction the stored cues with their time anchors;
    /// after a correction the new text without anchors (the old anchors belonged to the old words).
    public var cues: [NarrationCue] {
        if insight.revisions.isEmpty, !insight.narration.isEmpty { return insight.narration }
        return RookTextGuard.sentences(insight.interpretation).map { NarrationCue(text: $0, anchor: nil, track: nil) }
    }

    /// Text for a notification body or a spoken summary.
    public var spokenText: String { cues.map(\.text).joined(separator: " ") }
}

/// Quick answers below a statement (Auftrag 04, point 5). All but "Warum?" revise the statement locally,
/// without a Claude call; the old interpretation stays as a revision.
public enum RookFeedback: String, Codable, Sendable, CaseIterable, Identifiable {
    case doesNotFit, sick, onlyTenMinutes, lighter, why

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .doesNotFit: "Das passt nicht"
        case .sick: "Ich bin krank"
        case .onlyTenMinutes: "Heute nur zehn Minuten"
        case .lighter: "Leichtere Variante"
        case .why: "Warum diese Empfehlung?"
        }
    }

    /// Reads a typed message as one of the quick answers, or nil when it needs a real reply.
    public static func match(_ text: String) -> RookFeedback? {
        let lower = text.lowercased()
        if lower.contains("krank") || lower.contains("erkält") || lower.contains("fieber") { return .sick }
        if lower.contains("zehn minuten") || lower.contains("10 minuten") || lower.contains("10 min") { return .onlyTenMinutes }
        if lower.contains("leichter") || lower.contains("lockerer") { return .lighter }
        if lower.contains("passt nicht") || lower.contains("stimmt nicht") { return .doesNotFit }
        if lower.hasPrefix("warum") { return .why }
        return nil
    }
}

/// Parameters a `CoachAction` hands to the training (team 05): "minutes=10;intensity=easy".
public struct RookWorkoutRequest: Equatable, Sendable {
    public var minutes: Int?
    /// "easy", "normal" or "hard".
    public var intensity: String?

    public init(minutes: Int? = nil, intensity: String? = nil) {
        self.minutes = minutes
        self.intensity = intensity
    }

    public var payload: String {
        var parts: [String] = []
        if let minutes { parts.append("minutes=\(minutes)") }
        if let intensity { parts.append("intensity=\(intensity)") }
        return parts.joined(separator: ";")
    }

    public init(payload: String?) {
        var minutes: Int?
        var intensity: String?
        for part in (payload ?? "").split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "minutes": minutes = Int(pair[1])
            case "intensity": intensity = pair[1]
            default: break
            }
        }
        self.init(minutes: minutes, intensity: intensity)
    }
}

extension CoachDirection {
    /// Shown as a small label next to the headline.
    public var title: String {
        switch self {
        case .improving: "Geht aufwärts"
        case .stable: "Im Rahmen"
        case .strained: "Belastet"
        case .watch: "Im Blick"
        case .clarify: "Abklären"
        case .urgent: "Dringend"
        }
    }

    /// The coach figure's state for this direction.
    public var presence: RookPresence {
        switch self {
        case .urgent, .clarify: .alerting
        case .improving: .confirming
        default: .idle
        }
    }

    /// Order for "the more serious of two".
    var severity: Int {
        switch self {
        case .improving: 0
        case .stable: 1
        case .watch: 2
        case .strained: 3
        case .clarify: 4
        case .urgent: 5
        }
    }
}

extension RookStatement {
    /// The stored check-in and its notification (`StoredCheckIn` keeps this shape until 00 migrates the schema).
    public var checkInMessage: CheckInMessage {
        let urgency: CheckInUrgency = switch insight.direction {
        case .urgent: .urgent
        case .clarify: .clarify
        case .watch, .strained: .watch
        case .improving, .stable: .none
        }
        let markers = insight.evidence.prefix(4).map { ref in
            CheckInMarker(symbol: urgency >= .clarify ? .warning : .insight, metric: ref.kind?.rawValue ?? "",
                          text: [ref.label, ref.shownValue].compactMap { $0 }.joined(separator: " "))
        }
        return CheckInMessage(headline: headline, text: insight.interpretation, suggestion: "", urgency: urgency,
                              markers: Array(markers))
    }
}
