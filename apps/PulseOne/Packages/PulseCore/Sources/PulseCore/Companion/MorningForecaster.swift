import Foundation

// Companion (Begleiter) T1, ideas P1/P17: an evening tip for the next night's resting heart rate from
// the person's own history, checked the next morning. Deliberately simple and transparent:
// median of the last 14 nights, nudged by yesterday's steps (least-squares slope, clamped ±3 bpm).

public enum MorningForecaster {
    /// Nights with a resting heart rate needed before a tip is made.
    public static let minimumNights = 14
    /// Largest step adjustment in bpm.
    public static let maximumAdjustment = 3.0
    /// Smallest half width of the tipped range in bpm.
    public static let minimumHalfWidth = 1.5
    /// HRV within ±5 % of the median counts as "around the median".
    public static let hrvTolerance = 0.05
    /// Pairs (steps, next night) needed before the step slope is used.
    static let minimumPairs = 7

    /// Evening forecast for tomorrow from the person's own history (needs ≥ 14 nights, else nil).
    public static func forecast(for targetDay: Date, input: CompanionInput) -> MorningForecast? {
        let calendar = input.calendar
        let target = calendar.startOfDay(for: targetDay)
        let pool = NightSamples(input.samples)
        let history = NightMath.records(endingOn: NightMath.day(target, offset: -1, calendar: calendar),
                                        count: NightAnalyzer.bandWindowNights, pool: pool, dailyResting: [:], calendar: calendar)
        let nights = history.filter { $0.nightRestingHeartRate != nil }
        guard nights.count >= minimumNights else { return nil }
        let recent = nights.suffix(minimumNights).compactMap(\.nightRestingHeartRate)
        guard let median = NightMath.median(recent) else { return nil }
        let sorted = recent.sorted()
        let iqr = PersonalBaseline.percentile(sorted, 0.75) - PersonalBaseline.percentile(sorted, 0.25)

        // Steps of the day before each night → that night's resting heart rate.
        let steps = NightMath.dailySteps(input.samples, calendar: calendar)
        var pairs: [(steps: Double, resting: Double)] = []
        for night in nights {
            let dayBefore = NightMath.day(night.day, offset: -1, calendar: calendar)
            if let daySteps = steps[dayBefore], let resting = night.nightRestingHeartRate {
                pairs.append((steps: daySteps, resting: resting))
            }
        }
        var adjustment = 0.0
        if let yesterdaySteps = steps[NightMath.day(target, offset: -1, calendar: calendar)],
           let stepSlope = slope(pairs), let stepMedian = NightMath.median(pairs.map { $0.steps }) {
            adjustment = min(max(stepSlope * (yesterdaySteps - stepMedian), -maximumAdjustment), maximumAdjustment)
        }

        let predicted = median + adjustment
        let half = max(minimumHalfWidth, iqr / 2)
        return MorningForecast(targetDay: target, madeAt: input.now, restingHeartRateLow: (predicted - half).rounded(),
                               restingHeartRateHigh: (predicted + half).rounded(),
                               hrvTendency: hrvTendency(history: history), trainingDays: nights.count)
    }

    public static func evaluate(_ forecast: MorningForecast, night: NightSummary, input: CompanionInput) -> ForecastOutcome {
        let low = Int(forecast.restingHeartRateLow.rounded())
        let high = Int(forecast.restingHeartRateHigh.rounded())
        let tip = "Gestern Abend tippte ich auf \(low)–\(high) Schläge"

        var actualTendency: Int?
        if let hrv = night.hrv, let kind = night.hrvKind {
            let calendar = input.calendar
            let history = NightMath.records(endingOn: NightMath.day(forecast.targetDay, offset: -1, calendar: calendar),
                                            count: NightAnalyzer.bandWindowNights, pool: NightSamples(input.samples),
                                            dailyResting: [:], calendar: calendar)
            let values = history.compactMap { $0.hrv(kind) }
            if values.count >= PersonalBaseline.minimumDays, let median = NightMath.median(values) {
                actualTendency = tendency(hrv, median: median)
            }
        }
        var hrvHit: Bool?
        if let expected = forecast.hrvTendency, let actual = actualTendency { hrvHit = expected == actual }

        guard let actual = night.nightRestingHeartRate else {
            return ForecastOutcome(forecast: forecast, actualRestingHeartRate: nil, actualHRVTendency: actualTendency,
                                   restingHeartRateHit: nil, hrvHit: hrvHit,
                                   sentence: "\(tip).")
        }
        let measured = Int(actual.rounded())
        let hit = measured >= low && measured <= high
        return ForecastOutcome(forecast: forecast, actualRestingHeartRate: actual, actualHRVTendency: actualTendency,
                               restingHeartRateHit: hit, hrvHit: hrvHit,
                               sentence: "\(tip), gemessen \(measured): \(hit ? "Treffer" : "daneben").")
    }

    /// Share of hits over stored outcomes (0…1), nil when empty.
    public static func hitRate(_ outcomes: [ForecastOutcome]) -> Double? {
        let checked = outcomes.compactMap(\.restingHeartRateHit)
        guard !checked.isEmpty else { return nil }
        return Double(checked.filter { $0 }.count) / Double(checked.count)
    }

    /// −1 below, 0 around, +1 above the median (±5 %).
    static func tendency(_ value: Double, median: Double) -> Int {
        if value > median * (1 + hrvTolerance) { return 1 }
        if value < median * (1 - hrvTolerance) { return -1 }
        return 0
    }

    /// Mean HRV of the last 3 nights against the median of the window, one kind only (ring first).
    static func hrvTendency(history: [NightRecord]) -> Int? {
        let kind: SampleKind = history.contains(where: { $0.ringHRV != nil }) ? .ringHRV : .heartRateVariability
        let values = history.compactMap { $0.hrv(kind) }
        guard values.count >= PersonalBaseline.minimumDays, let median = NightMath.median(values),
              let recent = NightMath.mean(history.suffix(3).compactMap({ $0.hrv(kind) })) else { return nil }
        return tendency(recent, median: median)
    }

    /// Least-squares slope of resting heart rate on steps; nil with too few pairs or no step variation.
    static func slope(_ pairs: [(steps: Double, resting: Double)]) -> Double? {
        guard pairs.count >= minimumPairs else { return nil }
        let count = Double(pairs.count)
        let meanSteps = pairs.reduce(0.0) { $0 + $1.steps } / count
        let meanResting = pairs.reduce(0.0) { $0 + $1.resting } / count
        var covariance = 0.0
        var variance = 0.0
        for pair in pairs {
            covariance += (pair.steps - meanSteps) * (pair.resting - meanResting)
            variance += (pair.steps - meanSteps) * (pair.steps - meanSteps)
        }
        guard variance > 0 else { return nil }
        return covariance / variance
    }
}
