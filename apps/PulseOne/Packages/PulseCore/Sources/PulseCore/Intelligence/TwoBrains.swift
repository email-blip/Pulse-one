import Foundation

/// Which "brain" answers (creative lab idea 1): short everyday sentences come free and offline from
/// the iPhone, Claude is called only for the deep questions, and never silently.
public enum Brain: String, Sendable, Codable {
    /// Apple's on-device model, or fixed sentences when it is unavailable.
    case local
    case claude

    public var title: String { self == .local ? "auf dem iPhone" : "Claude" }
}

public enum BrainRouter {
    static let deepMarkers = ["warum", "wieso", "weshalb", "zusammenhang", "hängt", "vergleich", "vergleiche",
                              "unterschied", "trend", "entwicklung", "seit", "monat", "monaten", "jahr", "muster",
                              "woran", "erklär", "analys", "experiment", "einfluss", "besser", "schlechter"]
    static let simpleMarkers = ["wie viel", "wie viele", "wieviel", "wieviele", "wie hoch", "wie lange", "wie war",
                                "was war", "wie ist", "letzte nacht", "heute", "gestern"]

    /// Simple lookups ("Wie viele Schritte heute?") stay local; why/compare/trend questions go to Claude.
    public static func route(_ question: String) -> Brain {
        let lower = question.lowercased()
        if deepMarkers.contains(where: { lower.contains($0) }) { return .claude }
        if simpleMarkers.contains(where: { lower.contains($0) }) { return .local }
        return .claude
    }
}

/// Fixed sentences from local facts: the fallback when Apple's model is missing, and the reference the
/// model's wording is checked against (same numbers, nothing added).
public enum LocalSentences {
    public static func describe(_ fact: AnalysisFact) -> String {
        let value = FactUnits.text(fact.value, unit: fact.unit)
        let lead: String
        switch fact.stat {
        case "day_value": lead = "\(fact.title): \(value)"
        case "mean_per_day": lead = "\(fact.title): im Mittel \(value) pro Tag"
        case "so_far_today": lead = "\(fact.title): bisher heute \(value)"
        case "count": lead = "\(fact.title): \(value)"
        default: lead = "\(fact.title): Median \(value)"
        }
        guard let b = fact.baseline else { return lead + "." }
        let band = "\(FactUnits.text(b.p25, unit: ""))–\(FactUnits.text(b.p75, unit: fact.unit))"
        let position = fact.value > b.p75 ? "über deinem üblichen Bereich" : fact.value < b.p25 ? "unter deinem üblichen Bereich" : "im üblichen Bereich"
        return "\(lead), \(position) (\(band))."
    }

    /// Morning or evening lines: the kinds people look at first, in a fixed order.
    public static func summary(_ context: HealthAnalysisContext, limit: Int = 4) -> [String] {
        let kinds: [SampleKind] = [.sleepDuration, .restingHeartRate, .heartRateVariability, .steps, .oxygenSaturation]
        let order = kinds.map(\.rawValue)
        let sorted = context.facts.filter { order.contains($0.kind) }
            .sorted { (order.firstIndex(of: $0.kind) ?? 99) < (order.firstIndex(of: $1.kind) ?? 99) }
        var lines = sorted.prefix(limit).map(describe)
        if lines.isEmpty { lines = ["Für heute liegen noch keine auswertbaren Messwerte vor."] }
        return lines
    }

    /// Answers a simple lookup locally if a fact fits the question; nil means "ask Claude instead".
    public static func answer(_ question: String, context: HealthAnalysisContext) -> String? {
        let lower = question.lowercased()
        let keywords: [(String, [String])] = [
            (SampleKind.steps.rawValue, ["schritt"]),
            (SampleKind.sleepDuration.rawValue, ["schlaf", "geschlafen", "nacht"]),
            (SampleKind.restingHeartRate.rawValue, ["ruhepuls"]),
            (SampleKind.heartRateVariability.rawValue, ["hrv", "variabilität"]),
            (SampleKind.heartRate.rawValue, ["puls"]),
            (SampleKind.oxygenSaturation.rawValue, ["sauerstoff", "spo2", "spo₂"]),
            (SampleKind.activeEnergy.rawValue, ["kalorien", "energie"]),
        ]
        for (kind, words) in keywords where words.contains(where: { lower.contains($0) }) {
            if let fact = context.facts.first(where: { $0.kind == kind }) { return describe(fact) }
        }
        return nil
    }

    /// Words the local model's answer must not contain (same safety as Claude).
    public static func isSafe(_ text: String) -> Bool {
        if case .reject = SafetyRules.check(text) { return false }
        return true
    }
}

/// "Gläserner Bote": what leaves the iPhone before any send (creative lab idea 1, spec §3.1 preview).
public struct SendPreview: Sendable, Equatable {
    public let title: String
    public let periodText: String
    public let categoriesSent: [ConsentCategory]
    public let categoriesWithheld: [ConsentCategory]
    /// Never sent, whatever the settings.
    public let alwaysWithheld: [String]
    public let factCount: Int
    public let estimate: CostEstimate
    public let model: ClaudeModel
    public let sendsRemaining: Int
    public let payload: String

    public static let neverSent = [
        "dein Name", "Geburtsdatum (nur Altersspanne)", "Geräte-IDs", "Orte", "einzelne Rohmesswerte",
        "Text deiner Notizen (nur Stichworte)", "dein API-Schlüssel (geht nur als Zugangsnachweis an Anthropic)",
    ]

    public static func make(title: String, context: HealthAnalysisContext, consent: Set<ConsentCategory>, model: ClaudeModel,
                            systemPrompt: String, expectedOutputTokens: Int, sendBudget: SendBudget) -> SendPreview {
        let payload = context.prettyJSON()
        let characters = context.compactJSON().count + systemPrompt.count + 2_000
        let period = context.period.start.isEmpty ? "frei gewählt"
            : context.period.start == context.period.end ? context.period.start : "\(context.period.start) bis \(context.period.end)"
        return SendPreview(
            title: title, periodText: period,
            categoriesSent: ConsentCategory.allCases.filter { consent.contains($0) },
            categoriesWithheld: ConsentCategory.allCases.filter { !consent.contains($0) },
            alwaysWithheld: neverSent, factCount: context.factCount,
            estimate: CostEstimator.estimate(inputCharacters: characters, expectedOutputTokens: expectedOutputTokens, model: model),
            model: model, sendsRemaining: sendBudget.remaining, payload: payload)
    }
}
