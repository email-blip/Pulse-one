import Foundation

// Companion (Begleiter) T1: summary of the last night and the character of the day.
// Night window = 18:00 of the previous calendar day until the wake moment (or now). Bands are the
// person's own middle half (p25…p75) of the 28 nights before, never population norms.

public enum NightAnalyzer {
    /// Days of history the personal bands are built from.
    public static let bandWindowNights = 28
    /// A rolling 30-minute mean within this factor of the night's lowest one counts as asleep.
    public static let onsetFactor = 1.10

    /// Night = 18:00 previous day … wake (or now). Band from the 28 nights before.
    public static func summarize(_ input: CompanionInput) -> NightSummary {
        let calendar = input.calendar
        let now = input.now
        let today = calendar.startOfDay(for: now)
        let pool = NightSamples(input.samples)
        let start = NightMath.windowStart(for: today, calendar: calendar)

        // Wake first: it closes the window.
        let heartUntilNow = NightMath.within(pool.heartRate, from: start, to: now)
        let sleepUntilNow = NightMath.oneSource(NightMath.within(pool.sleep, from: start, to: now))
        let sleepEnd = sleepUntilNow.map(\.end).max()
        var confirmed: Date?
        if let tapped = input.confirmedWake, tapped >= start, tapped <= now { confirmed = tapped }
        let wake = WakeDetector.detect(heartRate: heartUntilNow, steps: NightMath.within(pool.steps, from: start, to: now),
                                       sleepEnd: sleepEnd, confirmed: confirmed, now: now, calendar: calendar)
        let end = max(min(wake.time ?? now, now), start)

        // Heart rate.
        let heart = NightMath.within(pool.heartRate, from: start, to: end)
        let resting = NightMath.restingLevel(heart)
        let lowest = heart.map(\.value).min()
        var sleepStart: Date?
        if let resting {
            let limit = resting * onsetFactor
            sleepStart = NightMath.rollingMeans(heart).first(where: { $0.mean <= limit })?.start
        }

        // Sleep duration: stored record first, else estimated from heart rate.
        var sleepDuration: TimeInterval?
        var estimated = false
        if !sleepUntilNow.isEmpty {
            sleepDuration = sleepUntilNow.reduce(0.0) { $0 + $1.value }
        } else if let onset = sleepStart, let wakeTime = wake.time, wakeTime > onset {
            sleepDuration = wakeTime.timeIntervalSince(onset)
            estimated = true
        }

        // HRV: ring first, else Apple; never mixed.
        var hrv: Double?
        var hrvKind: SampleKind?
        if let ring = NightMath.mean(NightMath.within(pool.ringHRV, from: start, to: end).map(\.value)) {
            hrv = ring
            hrvKind = .ringHRV
        } else if let apple = NightMath.mean(NightMath.within(pool.appleHRV, from: start, to: end).map(\.value)) {
            hrv = apple
            hrvKind = .heartRateVariability
        }
        let spo2 = NightMath.mean(NightMath.within(pool.spo2, from: start, to: end).map(\.value))

        // Personal bands from the nights before today, same method and kind as tonight.
        let history = NightMath.records(endingOn: NightMath.day(today, offset: -1, calendar: calendar),
                                        count: bandWindowNights, pool: pool, dailyResting: [:], calendar: calendar)
        var restingPosition: BandPosition?
        if let resting, let band = NightBand.make(history.compactMap(\.nightRestingHeartRate)) {
            restingPosition = band.position(of: resting)
        }
        var hrvPosition: BandPosition?
        if let hrv, let kind = hrvKind, let band = NightBand.make(history.compactMap { $0.hrv(kind) }) {
            hrvPosition = band.position(of: hrv)
        }
        var sleepPosition: BandPosition?
        if let sleepDuration, let band = NightBand.make(history.compactMap(\.sleepSeconds)) {
            sleepPosition = band.position(of: sleepDuration)
        }

        var missing: [SampleKind] = []
        if heart.isEmpty { missing.append(.heartRate) }
        if hrv == nil { missing.append(.ringHRV) }
        if sleepUntilNow.isEmpty { missing.append(.sleepDuration) }
        if spo2 == nil { missing.append(.oxygenSaturation) }

        return NightSummary(sleepStart: sleepStart, wake: wake, sleepDuration: sleepDuration,
                            sleepDurationIsEstimated: estimated, nightRestingHeartRate: resting, lowestHeartRate: lowest,
                            hrv: hrv, hrvKind: hrvKind, spo2Average: spo2, restingHeartRatePosition: restingPosition,
                            hrvPosition: hrvPosition, sleepPosition: sleepPosition, morningHeartRate: input.morningHeartRate,
                            missing: missing)
    }
}

public enum DayTypeClassifier {
    public static func classify(night: NightSummary, infection: InfectionSignal, sleepNeedHours: Double) -> CompanionDayType {
        if infection.level >= .pattern { return .unusualPattern }
        if night.nightRestingHeartRate == nil && night.sleepDuration == nil { return .notEnoughData }
        if let sleep = night.sleepDuration, sleep < (sleepNeedHours - 1.5) * 3_600 { return .shortNight }
        let restingOK = night.restingHeartRatePosition == .within || night.restingHeartRatePosition == .below
        let hrvOK = night.hrvPosition == .within || night.hrvPosition == .above
        var sleepOK = false
        if let sleep = night.sleepDuration { sleepOK = sleep >= (sleepNeedHours - 0.5) * 3_600 }
        if restingOK && hrvOK && sleepOK { return .recovered }
        return .normal
    }
}

// MARK: - Shared night helpers (internal to PulseCore, used by the T1 engines)

/// Usable samples of the kinds the night engines read, each sorted by start.
struct NightSamples: Sendable {
    let heartRate: [HealthSample]
    let ringHRV: [HealthSample]
    let appleHRV: [HealthSample]
    let sleep: [HealthSample]
    let spo2: [HealthSample]
    let skinTemperatureDeviation: [HealthSample]
    let skinTemperature: [HealthSample]
    let steps: [HealthSample]

    init(_ samples: [HealthSample]) {
        let usable = samples.filter { $0.quality.usableForAnalysis }.sorted { $0.start < $1.start }
        heartRate = Self.pick(usable, .heartRate)
        ringHRV = Self.pick(usable, .ringHRV)
        appleHRV = Self.pick(usable, .heartRateVariability)
        sleep = Self.pick(usable, .sleepDuration)
        spo2 = Self.pick(usable, .oxygenSaturation)
        skinTemperatureDeviation = Self.pick(usable, .skinTemperatureDeviation)
        skinTemperature = Self.pick(usable, .skinTemperature)
        steps = Self.pick(usable, .steps)
    }

    private static func pick(_ samples: [HealthSample], _ kind: SampleKind) -> [HealthSample] {
        samples.filter { $0.kind == kind }
    }
}

/// Which resting heart rate a comparison uses; one comparison never mixes the two.
enum RestingSource: Sendable {
    /// Lowest rolling 30-minute mean of the night's heart rate.
    case night
    /// The source's own daily resting heart rate (`.restingHeartRate`, e.g. Apple Health).
    case daily
}

/// Metrics of one night (18:00 the day before until 12:00 of `day`).
struct NightRecord: Sendable {
    let day: Date
    let nightRestingHeartRate: Double?
    let dailyRestingHeartRate: Double?
    let ringHRV: Double?
    let appleHRV: Double?
    let sleepSeconds: Double?
    let spo2: Double?
    let skinTemperatureDeviation: Double?
    let skinTemperature: Double?

    func resting(_ source: RestingSource) -> Double? {
        switch source {
        case .night: nightRestingHeartRate
        case .daily: dailyRestingHeartRate
        }
    }

    func hrv(_ kind: SampleKind) -> Double? {
        if kind == .ringHRV { return ringHRV }
        if kind == .heartRateVariability { return appleHRV }
        return nil
    }
}

struct RollingMean: Sendable {
    let start: Date
    let mean: Double
}

/// Personal band: p25…p75 of the values, needs `PersonalBaseline.minimumDays` values.
struct NightBand: Sendable {
    let lower: Double
    let median: Double
    let upper: Double
    let count: Int

    static func make(_ values: [Double], minimum: Int = PersonalBaseline.minimumDays) -> NightBand? {
        guard values.count >= minimum, !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return NightBand(lower: PersonalBaseline.percentile(sorted, 0.25), median: PersonalBaseline.percentile(sorted, 0.5),
                         upper: PersonalBaseline.percentile(sorted, 0.75), count: sorted.count)
    }

    func position(of value: Double) -> BandPosition {
        if value < lower { return .below }
        if value > upper { return .above }
        return .within
    }
}

enum NightMath {
    static let rollingWindow: TimeInterval = 30 * 60
    /// Heart rate samples a night needs before a resting level is computed.
    static let minimumNightSamples = 6
    /// Samples a 30-minute window needs to count.
    static let minimumWindowSamples = 2

    static func day(_ day: Date, offset: Int, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start.addingTimeInterval(Double(offset) * 86_400)
    }

    /// 18:00 of the calendar day before `day`.
    static func windowStart(for day: Date, calendar: Calendar) -> Date {
        let previous = Self.day(day, offset: -1, calendar: calendar)
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previous) ?? previous.addingTimeInterval(18 * 3_600)
    }

    /// 12:00 of `day`: end of a past night's window when the wake moment is unknown.
    static func historyEnd(for day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start.addingTimeInterval(12 * 3_600)
    }

    /// Samples whose start lies in `from…to` (inclusive).
    static func within(_ samples: [HealthSample], from: Date, to: Date) -> [HealthSample] {
        samples.filter { $0.start >= from && $0.start <= to }
    }

    /// Samples of one source only (ring first, then the order of `DataSourceKind.allCases`), so sleep
    /// recorded by two systems is never added twice.
    static func oneSource(_ samples: [HealthSample]) -> [HealthSample] {
        for source in DataSourceKind.allCases {
            let chosen = samples.filter { $0.source == source }
            if !chosen.isEmpty { return chosen }
        }
        return []
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return PersonalBaseline.percentile(values.sorted(), 0.5)
    }

    /// Mean of each 30-minute window that starts at a sample, in time order.
    static func rollingMeans(_ heart: [HealthSample]) -> [RollingMean] {
        let sorted = heart.sorted { $0.start < $1.start }
        var result: [RollingMean] = []
        for index in sorted.indices {
            let limit = sorted[index].start.addingTimeInterval(rollingWindow)
            var sum = 0.0
            var count = 0
            var cursor = index
            while cursor < sorted.count && sorted[cursor].start < limit {
                sum += sorted[cursor].value
                count += 1
                cursor += 1
            }
            if count >= minimumWindowSamples {
                result.append(RollingMean(start: sorted[index].start, mean: sum / Double(count)))
            }
        }
        return result
    }

    /// Lowest rolling 30-minute mean; nil below `minimumNightSamples` samples.
    static func restingLevel(_ heart: [HealthSample]) -> Double? {
        guard heart.count >= minimumNightSamples else { return nil }
        return rollingMeans(heart).map(\.mean).min()
    }

    /// Daily resting heart rate as the source computed it, keyed by start of day.
    static func dailyRestingHeartRates(_ samples: [HealthSample], calendar: Calendar) -> [Date: Double] {
        let days = DailySeries.build(samples, kind: .restingHeartRate, calendar: calendar)
        return Dictionary(days.map { ($0.day, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Daily step totals keyed by start of day.
    static func dailySteps(_ samples: [HealthSample], calendar: Calendar) -> [Date: Double] {
        let days = DailySeries.build(samples, kind: .steps, calendar: calendar)
        return Dictionary(days.map { ($0.day, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    static func record(for day: Date, pool: NightSamples, dailyResting: [Date: Double], calendar: Calendar) -> NightRecord {
        let dayStart = calendar.startOfDay(for: day)
        let start = windowStart(for: dayStart, calendar: calendar)
        let end = historyEnd(for: dayStart, calendar: calendar)
        let sleep = oneSource(within(pool.sleep, from: start, to: end))
        return NightRecord(day: dayStart,
                           nightRestingHeartRate: restingLevel(within(pool.heartRate, from: start, to: end)),
                           dailyRestingHeartRate: dailyResting[dayStart],
                           ringHRV: mean(within(pool.ringHRV, from: start, to: end).map(\.value)),
                           appleHRV: mean(within(pool.appleHRV, from: start, to: end).map(\.value)),
                           sleepSeconds: sleep.isEmpty ? nil : sleep.reduce(0.0) { $0 + $1.value },
                           spo2: mean(within(pool.spo2, from: start, to: end).map(\.value)),
                           skinTemperatureDeviation: mean(within(pool.skinTemperatureDeviation, from: start, to: end).map(\.value)),
                           skinTemperature: mean(within(pool.skinTemperature, from: start, to: end).map(\.value)))
    }

    /// One record per night for the `count` days ending with `lastDay` (inclusive), oldest first.
    static func records(endingOn lastDay: Date, count: Int, pool: NightSamples, dailyResting: [Date: Double],
                        calendar: Calendar) -> [NightRecord] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { back in
            record(for: day(lastDay, offset: -back, calendar: calendar), pool: pool, dailyResting: dailyResting, calendar: calendar)
        }
    }

    /// German decimal with one fraction digit, e.g. "7,5".
    static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        let sign = tenths < 0 ? "-" : ""
        let magnitude = abs(tenths)
        return "\(sign)\(magnitude / 10),\(magnitude % 10)"
    }
}
