import Foundation

public enum InsightStrength: String, Codable, Sendable, Comparable {
    case weak, medium, strong

    public var title: String {
        switch self {
        case .weak: "schwach"
        case .medium: "mittel"
        case .strong: "deutlich"
        }
    }

    var rank: Int { self == .weak ? 0 : self == .medium ? 1 : 2 }
    public static func < (a: InsightStrength, b: InsightStrength) -> Bool { a.rank < b.rank }

    static func from(rho: Double) -> InsightStrength {
        abs(rho) >= 0.5 ? .strong : abs(rho) >= 0.35 ? .medium : .weak
    }
}

public enum InsightOrigin: String, Codable, Sendable {
    case correlation, experiment, analogDays

    public var title: String {
        switch self {
        case .correlation: "Zusammenhang in deinen Daten"
        case .experiment: "Selbstversuch"
        case .analogDays: "Analogtage"
        }
    }
}

public enum InsightStatus: String, Codable, Sendable {
    case active
    /// The pattern no longer holds when recomputed; kept for history, shown greyed.
    case faded
}

/// One card of the body biography (creative lab idea 5): a measurable pattern with evidence and an
/// expiry date. Every number on it is recomputed locally when it is due.
public struct InsightCard: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var statement: String
    public var kindA: SampleKind
    public var kindB: SampleKind?
    public var lagDays: Int
    public var rho: Double?
    public var n: Int
    public var periodText: String
    public var strength: InsightStrength
    public var origin: InsightOrigin
    public var createdAt: Date
    public var checkedAt: Date
    public var recheckDue: Date
    public var status: InsightStatus

    public init(id: UUID = UUID(), statement: String, kindA: SampleKind, kindB: SampleKind?, lagDays: Int, rho: Double?,
                n: Int, periodText: String, strength: InsightStrength, origin: InsightOrigin, createdAt: Date,
                checkedAt: Date, recheckDue: Date, status: InsightStatus) {
        self.id = id
        self.statement = statement
        self.kindA = kindA
        self.kindB = kindB
        self.lagDays = lagDays
        self.rho = rho
        self.n = n
        self.periodText = periodText
        self.strength = strength
        self.origin = origin
        self.createdAt = createdAt
        self.checkedAt = checkedAt
        self.recheckDue = recheckDue
        self.status = status
    }

    /// Plain evidence line: "ρ = −0,41 · 28 Tage · 23.08.–20.11.2026".
    public var evidenceText: String {
        var parts: [String] = []
        if let rho {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            parts.append("ρ = " + (f.string(from: NSNumber(value: rho)) ?? "\(rho)"))
        }
        parts.append("\(n) Tage")
        parts.append(periodText)
        return parts.joined(separator: " · ")
    }
}

public enum BodyBiography {
    public static let recheckDays = 90
    public static let windowDays = 90
    static let minimumPairs = 21
    static let createThreshold = 0.3
    static let fadeThreshold = 0.2

    /// Pattern sentence for a pair. Observed together, never a cause.
    public static func sentence(_ pair: CorrelationPair, rho: Double) -> String {
        let more = rho > 0
        let when: String
        switch pair.a {
        case .sleepDuration: when = pair.lagDays == 0 ? "In Nächten mit mehr Schlaf" : "Nach Nächten mit mehr Schlaf"
        case .steps: when = pair.lagDays == 0 ? "An Tagen mit mehr Schritten" : "Am Tag nach vielen Schritten"
        case .trainingDuration: when = pair.lagDays == 0 ? "An Tagen mit längerem Training" : "Am Tag nach längerem Training"
        default: when = "Wenn \(pair.a.title) höher war,"
        }
        let what: String
        switch pair.b {
        case .restingHeartRate: what = "war dein Ruhepuls eher " + (more ? "höher" : "niedriger")
        case .heartRateVariability: what = "war deine HRV eher " + (more ? "höher" : "niedriger")
        case .sleepDuration: what = "hast du eher " + (more ? "länger" : "kürzer") + " geschlafen"
        default: what = "lag \(pair.b.title) eher " + (more ? "höher" : "niedriger")
        }
        return "\(when) \(what)."
    }

    static func daily(_ samples: [HealthSample], kind: SampleKind, calendar: Calendar, policy: SourcePolicy) -> [Date: Double] {
        let usable = samples.filter { $0.kind == kind && $0.quality.usableForAnalysis && $0.profileID != nil }
        return Dictionary(DailySeries.build(usable, kind: kind, calendar: calendar, policy: policy).map { ($0.day, $0.value) },
                          uniquingKeysWith: { a, _ in a })
    }

    static func periodText(from: Date, to: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = calendar.timeZone
        f.dateFormat = "dd.MM."
        let g = DateFormatter()
        g.locale = Locale(identifier: "de_DE")
        g.timeZone = calendar.timeZone
        g.dateFormat = "dd.MM.yyyy"
        let last = calendar.date(byAdding: .day, value: -1, to: to) ?? to
        return "\(f.string(from: from))–\(g.string(from: last))"
    }

    /// New cards from the last 90 days: |ρ| ≥ 0.3 over at least 21 day pairs. Pairs already on a card
    /// are skipped (they are rechecked instead).
    public static func candidates(samples: [HealthSample], existing: [InsightCard], now: Date,
                                  calendar: Calendar = .current, policy: SourcePolicy = SourcePolicy()) -> [InsightCard] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -windowDays, to: end) ?? now
        var cards: [InsightCard] = []
        for pair in CorrelationPair.standard {
            if existing.contains(where: { $0.kindA == pair.a && $0.kindB == pair.b && $0.lagDays == pair.lagDays }) { continue }
            let a = daily(samples, kind: pair.a, calendar: calendar, policy: policy)
            let b = daily(samples, kind: pair.b, calendar: calendar, policy: policy)
            guard let r = ContextBuilder.correlate(a, b, lagDays: pair.lagDays, from: start, to: end, calendar: calendar),
                  r.n >= minimumPairs, abs(r.rho) >= createThreshold else { continue }
            let rho = IntelligenceStats.rounded(r.rho, decimals: 2)
            cards.append(InsightCard(
                id: UUID(), statement: sentence(pair, rho: rho), kindA: pair.a, kindB: pair.b, lagDays: pair.lagDays,
                rho: rho, n: r.n, periodText: periodText(from: start, to: end, calendar: calendar),
                strength: .from(rho: rho), origin: .correlation, createdAt: now, checkedAt: now,
                recheckDue: calendar.date(byAdding: .day, value: recheckDays, to: now) ?? now, status: .active))
        }
        return cards
    }

    public static func isDue(_ card: InsightCard, now: Date) -> Bool { card.recheckDue <= now }

    /// Recomputes a correlation card on the latest 90 days. It fades when the pattern is gone
    /// (|ρ| < 0.2, sign flipped, or too few days).
    public static func recheck(_ card: InsightCard, samples: [HealthSample], now: Date,
                               calendar: Calendar = .current, policy: SourcePolicy = SourcePolicy()) -> InsightCard {
        guard card.origin == .correlation, let kindB = card.kindB else {
            var copy = card
            copy.checkedAt = now
            copy.recheckDue = calendar.date(byAdding: .day, value: recheckDays, to: now) ?? now
            return copy
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -windowDays, to: end) ?? now
        let a = daily(samples, kind: card.kindA, calendar: calendar, policy: policy)
        let b = daily(samples, kind: kindB, calendar: calendar, policy: policy)
        var copy = card
        copy.checkedAt = now
        copy.recheckDue = calendar.date(byAdding: .day, value: recheckDays, to: now) ?? now
        copy.periodText = periodText(from: start, to: end, calendar: calendar)
        guard let r = ContextBuilder.correlate(a, b, lagDays: card.lagDays, from: start, to: end, calendar: calendar),
              r.n >= minimumPairs else {
            copy.status = .faded
            return copy
        }
        let rho = IntelligenceStats.rounded(r.rho, decimals: 2)
        let flipped = (card.rho ?? 0) * rho < 0
        copy.rho = rho
        copy.n = r.n
        copy.strength = .from(rho: rho)
        copy.status = abs(rho) < fadeThreshold || flipped ? .faded : .active
        if copy.status == .active {
            copy.statement = sentence(CorrelationPair(a: card.kindA, b: kindB, lagDays: card.lagDays), rho: rho)
        }
        return copy
    }

    /// A finished experiment with a visible difference becomes a card too.
    public static func card(from result: ExperimentResult, plan: ExperimentPlan, start: Date, now: Date,
                            calendar: Calendar = .current) -> InsightCard? {
        guard result.verdict == .difference else { return nil }
        let direction = result.difference > 0 ? "höher" : "niedriger"
        let statement = "Im Selbstversuch „\(plan.title)“ lag \(plan.targetKind.title) unter „\(plan.conditionB)“ "
            + "eher \(direction) als unter „\(plan.conditionA)“."
        let end = calendar.date(byAdding: .day, value: plan.totalDays, to: start) ?? now
        return InsightCard(id: UUID(), statement: statement, kindA: plan.targetKind, kindB: nil, lagDays: 0, rho: nil,
                           n: result.daysUsed, periodText: periodText(from: start, to: end, calendar: calendar),
                           strength: result.pValue <= 0.05 ? .strong : .medium, origin: .experiment, createdAt: now,
                           checkedAt: now, recheckDue: calendar.date(byAdding: .day, value: recheckDays, to: now) ?? now,
                           status: .active)
    }

    /// Short context for Claude conversations instead of long histories (saves tokens, sends less).
    public static func conversationContext(_ cards: [InsightCard]) -> String {
        cards.filter { $0.status == .active }.map { "- \($0.statement) (\($0.strength.title), \($0.evidenceText))" }
            .joined(separator: "\n")
    }
}
