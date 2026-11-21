import Foundation

/// Which report the user asked for (spec §4). Release 3 starts with day, week and month.
public enum AnalysisPeriodKind: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly

    public var title: String {
        switch self {
        case .daily: "Tagesbericht"
        case .weekly: "Wochenbericht"
        case .monthly: "Monatsbericht"
        }
    }

    /// Days in the analysed period, ending with today.
    public var days: Int {
        switch self {
        case .daily: 1
        case .weekly: 7
        case .monthly: 30
        }
    }

    /// Opus effort per spec §3.2: reports high, the short day report medium.
    public var effort: String { self == .daily ? "medium" : "high" }

    /// Rough output size for the cost preview (spec §4).
    public var expectedOutputTokens: Int {
        switch self {
        case .daily: 3_000
        case .weekly: 6_000
        case .monthly: 10_000
        }
    }
}

/// What the user allows to leave the device (spec §2 "Datenfreigaben"). Clinical context is not part
/// of Release 3 and therefore not a category here.
public enum ConsentCategory: String, Codable, CaseIterable, Sendable {
    case heart
    case spo2
    case sleep
    case activity
    case training
    case body
    case notes

    public var title: String {
        switch self {
        case .heart: "Herz (Puls, Ruhepuls, HRV)"
        case .spo2: "Sauerstoffsättigung"
        case .sleep: "Schlaf"
        case .activity: "Aktivität (Schritte, Energie)"
        case .training: "Training"
        case .body: "Körpermaße und Temperatur"
        case .notes: "Stichworte aus Abend-Notizen"
        }
    }

    public var kinds: [SampleKind] {
        switch self {
        case .heart: [.restingHeartRate, .heartRate, .heartRateVariability, .respiratoryRate]
        case .spo2: [.oxygenSaturation]
        case .sleep: [.sleepDuration]
        case .activity: [.steps, .activeEnergy, .distance, .elevationGain]
        case .training: [.trainingDuration, .vo2Max]
        case .body: [.bodyMass, .skinTemperatureDeviation, .bodyTemperature]
        case .notes: []
        }
    }

    public static func category(for kind: SampleKind) -> ConsentCategory? {
        allCases.first { $0.kinds.contains(kind) }
    }

    /// Default: everything measured, notes too; the user switches off what should stay.
    public static let defaultConsent: Set<ConsentCategory> = Set(allCases)
}

/// The personal band as sent to Claude: 28 days before the period, at least 7 days (same rule as the
/// TODAY screen's `PersonalBaseline`).
public struct FactBaseline: Codable, Sendable, Equatable {
    public let median: Double
    public let p25: Double
    public let p75: Double
    public let windowDays: Int
    public let n: Int
}

/// One number Claude may cite, with a stable id (spec §3.1).
public struct AnalysisFact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// `SampleKind` raw value, or a derived name such as `spo2_low_readings`.
    public let kind: String
    public let title: String
    /// "median", "mean_per_day", "day_value", "count", "day_change".
    public let stat: String
    public let value: Double
    public let unit: String
    public let period: String
    public let n: Int
    /// Share of days in the period that had data (0–1).
    public let coverage: Double
    public let baseline: FactBaseline?
    public let source: String
    public let quality: String

    public init(id: String, kind: String, title: String, stat: String, value: Double, unit: String, period: String,
                n: Int, coverage: Double, baseline: FactBaseline?, source: String, quality: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.stat = stat
        self.value = value
        self.unit = unit
        self.period = period
        self.n = n
        self.coverage = coverage
        self.baseline = baseline
        self.source = source
        self.quality = quality
    }

    /// Every number a statement citing this fact may contain (spec §3.4 "Zahlenabgleich").
    public var citableNumbers: [Double] {
        var numbers = [value, abs(value), Double(n), coverage * 100]
        if let b = baseline {
            numbers += [b.median, b.p25, b.p75, Double(b.windowDays), Double(b.n)]
            let difference = value - b.median
            numbers.append(abs(difference))
            numbers.append(abs(value - b.p75))
            numbers.append(abs(value - b.p25))
            if b.median != 0 { numbers.append(abs(difference) / abs(b.median) * 100) }
        }
        return numbers
    }
}

/// A rank correlation between two daily series; never a cause.
public struct CorrelationFact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let a: String
    public let b: String
    public let titleA: String
    public let titleB: String
    public let method: String
    public let rho: Double
    public let n: Int
    public let lagDays: Int
    public let note: String

    public var citableNumbers: [Double] { [rho, abs(rho), Double(n), Double(lagDays)] }
}

public struct ContextEventFact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let date: String
    public let type: String
    public let label: String
}

public struct DataGap: Codable, Sendable, Equatable {
    public let kind: String
    public let reason: String
}

public struct AnalysisPeriod: Codable, Sendable, Equatable {
    public let start: String
    public let end: String
    public let timezone: String
}

/// Only coarse profile data: age range instead of birth date, no name (spec §3.1 "Datenminimierung").
public struct ProfileSummary: Codable, Sendable, Equatable {
    public let ageRange: String?
    public let sex: String?
    public let goals: [String]

    public init(ageRange: String?, sex: String?, goals: [String]) {
        self.ageRange = ageRange
        self.sex = sex
        self.goals = goals
    }

    public static let empty = ProfileSummary(ageRange: nil, sex: nil, goals: [])

    /// "40-49" from a birth year.
    public static func ageRange(birthYear: Int?, now: Date, calendar: Calendar) -> String? {
        guard let birthYear else { return nil }
        let age = calendar.component(.year, from: now) - birthYear
        guard age > 0, age < 120 else { return nil }
        let lower = age / 10 * 10
        return "\(lower)-\(lower + 9)"
    }
}

/// Version 1 of what Claude receives (spec §3.1). Raw samples, names, device ids, places and note texts
/// are never part of it.
public struct HealthAnalysisContext: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public let contextVersion: Int
    public let analysisType: String
    public let generatedAt: String
    public let period: AnalysisPeriod
    public let comparisonPeriod: AnalysisPeriod?
    public let profile: ProfileSummary
    public let consentedCategories: [String]
    public let facts: [AnalysisFact]
    public let correlations: [CorrelationFact]
    public let events: [ContextEventFact]
    public let dataGaps: [DataGap]
    /// Release 7 only; always nil in this release.
    public let clinicalContext: String?

    public init(analysisType: String, generatedAt: String, period: AnalysisPeriod, comparisonPeriod: AnalysisPeriod?,
                profile: ProfileSummary, consentedCategories: [String], facts: [AnalysisFact],
                correlations: [CorrelationFact], events: [ContextEventFact], dataGaps: [DataGap]) {
        contextVersion = Self.currentVersion
        self.analysisType = analysisType
        self.generatedAt = generatedAt
        self.period = period
        self.comparisonPeriod = comparisonPeriod
        self.profile = profile
        self.consentedCategories = consentedCategories
        self.facts = facts
        self.correlations = correlations
        self.events = events
        self.dataGaps = dataGaps
        clinicalContext = nil
    }

    public var allIDs: Set<String> {
        Set(facts.map(\.id)).union(correlations.map(\.id)).union(events.map(\.id))
    }

    /// Numbers a statement may contain when it cites these ids.
    public func citableNumbers(for ids: [String]) -> [Double] {
        var numbers: [Double] = []
        for id in ids {
            if let f = facts.first(where: { $0.id == id }) { numbers += f.citableNumbers }
            if let c = correlations.first(where: { $0.id == id }) { numbers += c.citableNumbers }
        }
        // Pairs of cited facts: differences between two cited values ("3 bpm höher als in Woche A").
        let values = ids.compactMap { id in facts.first(where: { $0.id == id })?.value }
        for i in values.indices { for j in values.indices where i < j { numbers.append(abs(values[i] - values[j])) } }
        return numbers
    }

    public var factCount: Int { facts.count + correlations.count + events.count }

    public func prettyJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public func compactJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// How a canonical value is shown and sent: sleep in hours, training in minutes, distance in km.
public enum FactUnits {
    public static func display(_ kind: SampleKind, _ canonical: Double) -> (value: Double, unit: String) {
        switch kind {
        case .sleepDuration: (IntelligenceStats.rounded(canonical / 3_600, decimals: 1), "h")
        case .trainingDuration: (IntelligenceStats.rounded(canonical / 60, decimals: 0), "min")
        case .distance: (IntelligenceStats.rounded(canonical / 1_000, decimals: 1), "km")
        case .steps, .activeEnergy, .basalEnergy, .elevationGain, .heartRate, .restingHeartRate, .heartRateVariability:
            (IntelligenceStats.rounded(canonical, decimals: 0), kind.canonicalUnit.rawValue)
        default: (IntelligenceStats.rounded(canonical, decimals: 1), kind.canonicalUnit.rawValue)
        }
    }

    /// German number with the unit, e.g. "6,1 h".
    public static func text(_ value: Double, unit: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: NSNumber(value: value)) ?? String(value)
        return unit.isEmpty || unit == "count" ? number : "\(number) \(unit)"
    }
}
