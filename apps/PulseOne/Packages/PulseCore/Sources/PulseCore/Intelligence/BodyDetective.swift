import Foundation

/// One day described by the kinds the detective compares.
public struct DayProfile: Sendable, Equatable {
    public let day: Date
    public let values: [SampleKind: Double]
}

public enum DeviationDirection: String, Sendable, Codable {
    case above, below

    public var text: String { self == .above ? "über" : "unter" }
}

/// A value outside the personal band on the latest days (creative lab idea 2, trigger).
public struct Deviation: Sendable, Equatable {
    public let kind: SampleKind
    public let day: Date
    public let value: Double
    public let median: Double
    public let p25: Double
    public let p75: Double
    public let direction: DeviationDirection
    public let consecutiveDays: Int
    /// Days the personal band was computed from (at least `ContextBuilder.baselineMinimumDays`).
    public var baselineDays: Int = ContextBuilder.baselineMinimumDays
}

/// A similar earlier day and what the person noted in the days after it.
public struct AnalogMatch: Sendable, Equatable {
    public let day: Date
    /// Mean normalised distance; smaller is more similar.
    public let distance: Double
    public let followingTags: [ContextTag]
    public let followingDays: Int
}

/// Another measured value on the deviation day with its own personal band, so Claude sees more
/// than the one deviating number.
public struct DayContextValue: Sendable, Equatable {
    public let kind: SampleKind
    public let value: Double
    public let median: Double
    public let p25: Double
    public let p75: Double
    public let baselineDays: Int
}

public struct DetectiveCase: Sendable, Equatable {
    public let deviation: Deviation
    public let analogs: [AnalogMatch]
    /// Other kinds measured on the deviation day, each with a band from the 28 days before.
    public var dayContext: [DayContextValue] = []

    /// Claude only gets asked when there is something to compare: another value that day or an
    /// analogue day. With the deviating number alone, any answer is guesswork.
    public var hasEnoughForClaude: Bool { !analogs.isEmpty || !dayContext.isEmpty }

    /// "2-mal folgte Krankheitsgefühl, 3-mal nichts Besonderes".
    public var followUpSummary: [(tag: ContextTag?, count: Int)] {
        var counts: [ContextTag: Int] = [:]
        var nothing = 0
        for analog in analogs {
            if analog.followingTags.isEmpty { nothing += 1 }
            for tag in Set(analog.followingTags) { counts[tag, default: 0] += 1 }
        }
        var result: [(tag: ContextTag?, count: Int)] = ContextTag.allCases.compactMap { tag in
            counts[tag].map { (tag: Optional(tag), count: $0) }
        }.sorted { $0.count > $1.count }
        if nothing > 0 { result.append((tag: nil, count: nothing)) }
        return result
    }

    public static func == (a: DetectiveCase, b: DetectiveCase) -> Bool {
        a.deviation == b.deviation && a.analogs == b.analogs && a.dayContext == b.dayContext
    }
}

/// Body detective with analogue days (method from weather forecasting): all local, no Claude needed.
/// Claude only adds the hypothesis board on request.
public struct BodyDetective: Sendable {
    /// Ring HRV is a separate feature next to SDNN; the ring's stress score is never one (vendor value).
    public static let featureKinds: [SampleKind] = [.restingHeartRate, .heartRateVariability, .ringHRV, .sleepDuration, .steps]
    public let calendar: Calendar
    public let policy: SourcePolicy

    public init(calendar: Calendar = .current, policy: SourcePolicy = SourcePolicy()) {
        self.calendar = calendar
        self.policy = policy
    }

    /// `now` set: a running day's totals (steps, energy, distance) are left out, because an unfinished day
    /// must never be compared with whole days.
    public func profiles(from samples: [HealthSample], now: Date? = nil) -> [DayProfile] {
        var byDay: [Date: [SampleKind: Double]] = [:]
        let today = now.map { calendar.startOfDay(for: $0) }
        for kind in Self.featureKinds {
            let usable = samples.filter { $0.kind == kind && $0.quality.usableForAnalysis && $0.profileID != nil }
            for value in DailySeries.build(usable, kind: kind, calendar: calendar, policy: policy) {
                if kind.isRunningTotal, let today, value.day >= today { continue }
                byDay[value.day, default: [:]][kind] = value.value
            }
        }
        return byDay.keys.sorted().map { DayProfile(day: $0, values: byDay[$0] ?? [:]) }
    }

    /// Kinds whose latest two days are both above p75 or both below p25 of the 28 days before.
    public func deviations(in profiles: [DayProfile], now: Date) -> [Deviation] {
        let today = calendar.startOfDay(for: now)
        var result: [Deviation] = []
        for kind in Self.featureKinds {
            let series = profiles.compactMap { p in p.values[kind].map { (day: p.day, value: $0) } }
                .filter { kind.isRunningTotal ? $0.day < today : $0.day <= today }
            guard series.count >= 2, let last = series.last else { continue }
            // Only fresh signals: the latest value is from today or yesterday.
            guard let age = calendar.dateComponents([.day], from: last.day, to: today).day, age <= 1 else { continue }
            let previous = series[series.count - 2]
            let windowStart = calendar.date(byAdding: .day, value: -ContextBuilder.baselineWindowDays, to: previous.day) ?? previous.day
            let base = series.filter { $0.day >= windowStart && $0.day < previous.day }.map(\.value)
            guard base.count >= ContextBuilder.baselineMinimumDays,
                  let m = IntelligenceStats.median(base),
                  let lo = IntelligenceStats.quantile(base, 0.25),
                  let hi = IntelligenceStats.quantile(base, 0.75), hi > lo else { continue }
            let direction: DeviationDirection
            if last.value > hi, previous.value > hi { direction = .above }
            else if last.value < lo, previous.value < lo { direction = .below }
            else { continue }
            var streak = 0
            for point in series.reversed() {
                let outside = direction == .above ? point.value > hi : point.value < lo
                if outside { streak += 1 } else { break }
            }
            result.append(Deviation(kind: kind, day: last.day, value: last.value, median: m, p25: lo, p75: hi,
                                    direction: direction, consecutiveDays: streak, baselineDays: base.count))
        }
        return result
    }

    /// The k most similar earlier days to `target`, each with tags noted in the `followDays` after it.
    /// Distance: mean squared difference of values scaled by each kind's spread (IQR), over the kinds
    /// both days have (at least two).
    public func analogs(for target: DayProfile, history: [DayProfile], events: [ContextEvent], k: Int = 5,
                        followDays: Int = 3) -> [AnalogMatch] {
        var scale: [SampleKind: Double] = [:]
        for kind in Self.featureKinds {
            let values = history.compactMap { $0.values[kind] }
            guard let lo = IntelligenceStats.quantile(values, 0.25), let hi = IntelligenceStats.quantile(values, 0.75) else { continue }
            scale[kind] = hi - lo > 0 ? hi - lo : (IntelligenceStats.standardDeviation(values) ?? 1)
        }
        // A candidate's following days must lie before the target day.
        guard let latestCandidate = calendar.date(byAdding: .day, value: -(followDays + 1), to: target.day) else { return [] }
        var matches: [AnalogMatch] = []
        for candidate in history where candidate.day <= latestCandidate {
            let shared = Self.featureKinds.filter { target.values[$0] != nil && candidate.values[$0] != nil && (scale[$0] ?? 0) > 0 }
            guard shared.count >= 2 else { continue }
            let squares = shared.map { kind -> Double in
                let d = ((target.values[kind] ?? 0) - (candidate.values[kind] ?? 0)) / (scale[kind] ?? 1)
                return d * d
            }
            let distance = (squares.reduce(0, +) / Double(shared.count)).squareRoot()
            let end = calendar.date(byAdding: .day, value: followDays + 1, to: candidate.day) ?? candidate.day
            let after = calendar.date(byAdding: .day, value: 1, to: candidate.day) ?? candidate.day
            let tags = events.filter { $0.date >= after && $0.date < end }.flatMap(\.tags)
            var unique: [ContextTag] = []
            for tag in tags where !unique.contains(tag) { unique.append(tag) }
            matches.append(AnalogMatch(day: candidate.day, distance: IntelligenceStats.rounded(distance, decimals: 2),
                                       followingTags: unique, followingDays: followDays))
        }
        return Array(matches.sorted { $0.distance < $1.distance }.prefix(k))
    }

    /// Everything the detective screen needs, newest deviation first.
    public func cases(samples: [HealthSample], events: [ContextEvent], now: Date) -> [DetectiveCase] {
        let all = profiles(from: samples, now: now)
        return deviations(in: all, now: now).map { deviation in
            let target = all.first { $0.day == deviation.day } ?? DayProfile(day: deviation.day, values: [deviation.kind: deviation.value])
            let history = all.filter { $0.day < deviation.day }
            return DetectiveCase(deviation: deviation, analogs: analogs(for: target, history: history, events: events),
                                 dayContext: dayContext(for: target, excluding: deviation.kind, history: history))
        }
    }

    /// The other kinds measured on `target`, each with median and band of the 28 days before.
    public func dayContext(for target: DayProfile, excluding kind: SampleKind, history: [DayProfile]) -> [DayContextValue] {
        let windowStart = calendar.date(byAdding: .day, value: -ContextBuilder.baselineWindowDays, to: target.day) ?? target.day
        let window = history.filter { $0.day >= windowStart && $0.day < target.day }
        return Self.featureKinds.compactMap { other in
            guard other != kind, let value = target.values[other] else { return nil }
            let base = window.compactMap { $0.values[other] }
            guard base.count >= ContextBuilder.baselineMinimumDays,
                  let m = IntelligenceStats.median(base),
                  let lo = IntelligenceStats.quantile(base, 0.25),
                  let hi = IntelligenceStats.quantile(base, 0.75) else { return nil }
            return DayContextValue(kind: other, value: value, median: m, p25: lo, p75: hi, baselineDays: base.count)
        }
    }

    /// Context for the hypothesis board: deviation and band, the other values of that day with their
    /// bands, analogue days and own tags.
    public func context(for detectiveCase: DetectiveCase, events: [ContextEvent], consent: Set<ConsentCategory>,
                        now: Date) -> HealthAnalysisContext {
        let d = detectiveCase.deviation
        let shown = FactUnits.display(d.kind, d.value)
        let builder = ContextBuilder(calendar: calendar, policy: policy)
        let day = builder.day(d.day)
        var facts = [AnalysisFact(
            id: "F1", kind: d.kind.rawValue, title: d.kind.title, stat: "day_value", value: shown.value, unit: shown.unit,
            period: day, n: d.consecutiveDays, coverage: 1,
            baseline: FactBaseline(median: FactUnits.display(d.kind, d.median).value,
                                   p25: FactUnits.display(d.kind, d.p25).value,
                                   p75: FactUnits.display(d.kind, d.p75).value,
                                   windowDays: ContextBuilder.baselineWindowDays, n: d.baselineDays),
            source: "local", quality: "plausible")]
        for extra in detectiveCase.dayContext {
            if let category = ConsentCategory.category(for: extra.kind), !consent.contains(category) { continue }
            let value = FactUnits.display(extra.kind, extra.value)
            facts.append(AnalysisFact(
                id: "F\(facts.count + 1)", kind: extra.kind.rawValue, title: extra.kind.title, stat: "day_value",
                value: value.value, unit: value.unit, period: day, n: 1, coverage: 1,
                baseline: FactBaseline(median: FactUnits.display(extra.kind, extra.median).value,
                                       p25: FactUnits.display(extra.kind, extra.p25).value,
                                       p75: FactUnits.display(extra.kind, extra.p75).value,
                                       windowDays: ContextBuilder.baselineWindowDays, n: extra.baselineDays),
                source: "local", quality: "plausible"))
        }
        var events_: [ContextEventFact] = []
        if consent.contains(.notes) {
            for (index, analog) in detectiveCase.analogs.enumerated() {
                let label = analog.followingTags.isEmpty ? "danach nichts notiert"
                    : "danach notiert: " + analog.followingTags.map(\.title).joined(separator: ", ")
                events_.append(ContextEventFact(id: "A\(index + 1)", date: builder.day(analog.day), type: "analog_day", label: label))
            }
            let recentStart = calendar.date(byAdding: .day, value: -3, to: d.day) ?? d.day
            for event in events where event.date >= recentStart && event.date <= now {
                events_.append(ContextEventFact(id: "E\(events_.count + 1)", date: builder.day(event.date), type: "note", label: event.tagLabel))
            }
        }
        if let category = ConsentCategory.category(for: d.kind), !consent.contains(category) { facts = [] }
        return HealthAnalysisContext(analysisType: "detective", generatedAt: builder.timestamp(now),
                                     period: AnalysisPeriod(start: day, end: day, timezone: calendar.timeZone.identifier),
                                     comparisonPeriod: nil, profile: .empty,
                                     consentedCategories: ConsentCategory.allCases.filter { consent.contains($0) }.map(\.rawValue),
                                     facts: facts, correlations: [], events: events_, dataGaps: [])
    }
}
