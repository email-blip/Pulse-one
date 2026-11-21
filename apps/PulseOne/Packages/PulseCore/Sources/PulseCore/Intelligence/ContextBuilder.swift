import Foundation

/// A pair of daily series whose rank correlation is computed locally (spec §3.1 "C" facts and body
/// biography cards). `lagDays` 1 means: A on one day, B on the following day.
public struct CorrelationPair: Sendable, Equatable {
    public let a: SampleKind
    public let b: SampleKind
    public let lagDays: Int

    public static let standard: [CorrelationPair] = [
        CorrelationPair(a: .sleepDuration, b: .restingHeartRate, lagDays: 0),
        CorrelationPair(a: .sleepDuration, b: .heartRateVariability, lagDays: 0),
        CorrelationPair(a: .steps, b: .sleepDuration, lagDays: 0),
        CorrelationPair(a: .trainingDuration, b: .restingHeartRate, lagDays: 1),
        CorrelationPair(a: .trainingDuration, b: .heartRateVariability, lagDays: 1),
        // Ring HRV is its own series (method undisclosed), never merged with SDNN.
        CorrelationPair(a: .sleepDuration, b: .ringHRV, lagDays: 0),
        CorrelationPair(a: .trainingDuration, b: .ringHRV, lagDays: 1),
        CorrelationPair(a: .steps, b: .restingHeartRate, lagDays: 1),
    ]
}

/// Collects, computes and minimises (spec §3 steps 1–3). Same inputs give the same context.
public struct ContextBuilder: Sendable {
    public var calendar: Calendar
    public var policy: SourcePolicy
    /// Personal band window, identical to the TODAY screen (28 days, at least 7 days with data).
    public static let baselineWindowDays = 28
    public static let baselineMinimumDays = 7
    public static let minimumCorrelationPairs = 14

    public init(calendar: Calendar = .current, policy: SourcePolicy = SourcePolicy()) {
        self.calendar = calendar
        self.policy = policy
    }

    /// First day of the analysed period and the day after its end.
    public func periodBounds(_ kind: AnalysisPeriodKind, now: Date) -> (start: Date, end: Date) {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -kind.days, to: end) ?? now
        return (start, end)
    }

    public func build(samples: [HealthSample], events: [ContextEvent], kind: AnalysisPeriodKind, now: Date,
                      consent: Set<ConsentCategory>, profile: ProfileSummary) -> HealthAnalysisContext {
        let (start, end) = periodBounds(kind, now: now)
        let baselineStart = calendar.date(byAdding: .day, value: -Self.baselineWindowDays, to: start) ?? start
        let correlationStart = calendar.date(byAdding: .day, value: -90, to: end) ?? start
        let usable = samples.filter { $0.quality.usableForAnalysis && $0.profileID != nil }

        var facts: [AnalysisFact] = []
        var gaps: [DataGap] = []
        var dailyByKind: [SampleKind: [Date: Double]] = [:]
        let periodLabel = "\(day(start))/\(day(lastDay(before: end)))"

        for category in ConsentCategory.allCases where consent.contains(category) {
            for sampleKind in category.kinds {
                let relevant = usable.filter { $0.kind == sampleKind && $0.start >= min(baselineStart, correlationStart) && $0.start < end }
                let daily = DailySeries.build(relevant, kind: sampleKind, calendar: calendar, policy: policy)
                // Correlations use whole days only: a running day's total is left out.
                let runningDay = calendar.startOfDay(for: now)
                let whole = sampleKind.isRunningTotal ? daily.filter { $0.day < runningDay } : daily
                dailyByKind[sampleKind] = Dictionary(whole.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
                let inPeriod = daily.filter { $0.day >= start && $0.day < end }
                guard !inPeriod.isEmpty else {
                    // Only kinds the person usually has are worth naming as a gap.
                    if daily.contains(where: { $0.day >= baselineStart }) {
                        gaps.append(DataGap(kind: sampleKind.rawValue, reason: "keine Messwerte im Zeitraum"))
                    }
                    continue
                }
                // A running day is not finished for counters (steps, energy, distance, training): it never
                // enters a mean and is never compared with the usual range of whole days.
                let today = calendar.startOfDay(for: now)
                var complete = inPeriod
                var soFarToday = false
                if sampleKind.isRunningTotal, let last = inPeriod.last, last.day >= today {
                    let finished = inPeriod.filter { $0.day < today }
                    if kind == .daily || finished.isEmpty {
                        complete = [last]
                        soFarToday = true
                    } else {
                        complete = finished
                    }
                }
                let values = complete.map(\.value)
                let stat: String
                let central: Double
                if soFarToday {
                    stat = "so_far_today"
                    central = values.last ?? 0
                } else if sampleKind.isVendorScore {
                    stat = "vendor_median"
                    central = IntelligenceStats.median(values) ?? 0
                } else if kind == .daily {
                    stat = "day_value"
                    central = values.last ?? 0
                } else if sampleKind.isCumulative {
                    stat = "mean_per_day"
                    central = IntelligenceStats.mean(values) ?? 0
                } else {
                    stat = "median"
                    central = IntelligenceStats.median(values) ?? 0
                }
                let shown = FactUnits.display(sampleKind, central)
                let baseValues = daily.filter { $0.day >= baselineStart && $0.day < start }.map(\.value)
                var baseline: FactBaseline?
                if !soFarToday, !sampleKind.isVendorScore, baseValues.count >= Self.baselineMinimumDays,
                   let m = IntelligenceStats.median(baseValues),
                   let lo = IntelligenceStats.quantile(baseValues, 0.25),
                   let hi = IntelligenceStats.quantile(baseValues, 0.75) {
                    baseline = FactBaseline(median: FactUnits.display(sampleKind, m).value,
                                            p25: FactUnits.display(sampleKind, lo).value,
                                            p75: FactUnits.display(sampleKind, hi).value,
                                            windowDays: Self.baselineWindowDays, n: baseValues.count)
                }
                let periodSamples = relevant.filter { $0.start >= start && $0.start < end }
                let sources = Dictionary(grouping: inPeriod.flatMap(\.origins), by: \.source)
                let mainSource = sources.max { $0.value.count < $1.value.count }?.key.rawValue ?? "unknown"
                let quality = periodSamples.allSatisfy { $0.quality == .valid } ? "valid" : "plausible"
                facts.append(AnalysisFact(
                    id: "F\(facts.count + 1)", kind: sampleKind.rawValue, title: sampleKind.title, stat: stat,
                    value: shown.value, unit: shown.unit, period: periodLabel, n: complete.count,
                    coverage: IntelligenceStats.rounded(Double(complete.count) / Double(kind.days), decimals: 2),
                    baseline: baseline, source: mainSource, quality: quality))
            }
        }

        // Low single SpO₂ readings are counted, because the median hides them (SafetyRules S5).
        if consent.contains(.spo2) {
            // Ring and Health can carry the same reading; the source policy keeps one per minute.
            let raw = usable.filter { $0.kind == .oxygenSaturation && $0.start >= start && $0.start < end }
            let byDay = Dictionary(grouping: raw) { calendar.startOfDay(for: $0.start) }
            let all = byDay.values.flatMap { DataSourceResolver.resolvePoints($0, policy: policy) }
            let low = all.filter { $0.value < 90 }
            if !all.isEmpty {
                facts.append(AnalysisFact(
                    id: "F\(facts.count + 1)", kind: "spo2_low_readings", title: "SpO₂-Einzelwerte unter 90 %",
                    stat: "count", value: Double(low.count), unit: "count", period: periodLabel, n: all.count,
                    coverage: 1, baseline: nil, source: all.first?.source.rawValue ?? "unknown", quality: "plausible"))
            }
        }

        var correlations: [CorrelationFact] = []
        if kind != .daily {
            for pair in CorrelationPair.standard {
                guard let a = dailyByKind[pair.a], let b = dailyByKind[pair.b],
                      let result = Self.correlate(a, b, lagDays: pair.lagDays, from: correlationStart, to: end, calendar: calendar),
                      result.n >= Self.minimumCorrelationPairs else { continue }
                correlations.append(CorrelationFact(
                    id: "C\(correlations.count + 1)", a: pair.a.rawValue, b: pair.b.rawValue, titleA: pair.a.title,
                    titleB: pair.b.title, method: "spearman", rho: IntelligenceStats.rounded(result.rho, decimals: 2),
                    n: result.n, lagDays: pair.lagDays, note: "beobachteter Zusammenhang, keine Ursache"))
            }
        }

        var eventFacts: [ContextEventFact] = []
        if consent.contains(.notes) {
            for event in events.sorted(by: { $0.date < $1.date }) where event.date >= start && event.date < end {
                eventFacts.append(ContextEventFact(id: "E\(eventFacts.count + 1)", date: day(event.date),
                                                   type: "note", label: event.tagLabel))
            }
        }

        let tz = calendar.timeZone.identifier
        return HealthAnalysisContext(
            analysisType: kind.rawValue, generatedAt: timestamp(now),
            period: AnalysisPeriod(start: day(start), end: day(lastDay(before: end)), timezone: tz),
            comparisonPeriod: AnalysisPeriod(start: day(baselineStart), end: day(lastDay(before: start)), timezone: tz),
            profile: profile,
            consentedCategories: ConsentCategory.allCases.filter { consent.contains($0) }.map(\.rawValue),
            facts: facts, correlations: correlations, events: eventFacts, dataGaps: gaps)
    }

    /// Spearman over days present in both series; B is read `lagDays` after A.
    public static func correlate(_ a: [Date: Double], _ b: [Date: Double], lagDays: Int, from: Date, to: Date,
                                 calendar: Calendar) -> (rho: Double, n: Int)? {
        var xs: [Double] = []
        var ys: [Double] = []
        for (dayA, valueA) in a where dayA >= from && dayA < to {
            guard let dayB = calendar.date(byAdding: .day, value: lagDays, to: dayA),
                  let valueB = b[calendar.startOfDay(for: dayB)] else { continue }
            xs.append(valueA)
            ys.append(valueB)
        }
        guard let rho = IntelligenceStats.spearman(xs, ys) else { return nil }
        return (rho, xs.count)
    }

    private func lastDay(before end: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: end) ?? end
    }

    func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        return f.string(from: date)
    }
}
