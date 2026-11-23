import Foundation

// Three day scores 0–100 like Oura (owner decision 2026-11-23): sleep, recovery, activity. Each score is
// the weighted mean of a few visible building blocks, so every number can be traced. Our own simple
// formulas, not Oura's. Recovery works from the first day: it starts from typical adult values and moves
// to the person's own band with every measured day (fully personal after `personalDays`).

public enum ScoreKind: String, CaseIterable, Sendable, Identifiable {
    case sleep, recovery, activity

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: "Schlaf"
        case .recovery: "Erholung"
        case .activity: "Aktivität"
        }
    }

    public var systemImage: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .recovery: "leaf.fill"
        case .activity: "figure.walk"
        }
    }

    /// One sentence on what the score says, shown on the detail screen.
    public var explanation: String {
        switch self {
        case .sleep: "Wie lang und wie ruhig du letzte Nacht geschlafen hast und wie regelmäßig deine Schlafenszeit ist."
        case .recovery: "Wie erholt dein Körper heute wirkt: Ruhepuls und HRV verglichen mit deinem üblichen Bereich, dazu Schlaf und Vortag."
        case .activity: "Wie viel du dich heute bewegt hast, wie gleichmäßig über den Tag und wie die letzte Woche lief."
        }
    }
}

/// One building block of a score with its own 0–100 value and a short German detail ("7 h 12 min").
public struct ScoreComponent: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let score: Int
    public let detail: String
    public let weight: Double

    public init(title: String, score: Int, detail: String, weight: Double) {
        self.title = title
        self.score = max(0, min(100, score))
        self.detail = detail
        self.weight = weight
    }
}

public struct DayScore: Equatable, Sendable {
    public let kind: ScoreKind
    public let day: Date
    public let value: Int
    public let components: [ScoreComponent]
    /// Shown under the components, e.g. that the ring's sleep stages are not validated.
    public let note: String?

    /// Descriptive word, never a traffic light.
    public var word: String { Self.word(for: value) }

    public static func word(for value: Int) -> String {
        switch value {
        case 85...: "sehr gut"
        case 70..<85: "gut"
        case 60..<70: "mittel"
        default: "niedrig"
        }
    }
}

public enum ScoreResult: Equatable, Sendable {
    case ready(DayScore)
    /// Nothing measured for this day.
    case noData

    public var score: DayScore? {
        if case .ready(let score) = self { return score }
        return nil
    }

    /// Short line for the ring on TODAY when there is no number.
    public var placeholder: String {
        switch self {
        case .ready(let score): score.word
        case .noData: "keine Daten"
        }
    }
}

/// One night: wake day, minutes asleep, bed time and (ring only) minutes per stage.
public struct NightSleep: Equatable, Sendable {
    /// Start of the day the person woke up on.
    public let day: Date
    public let asleepSeconds: Double
    public let start: Date
    public let stages: [SleepStage: Int]

    public init(day: Date, asleepSeconds: Double, start: Date, stages: [SleepStage: Int] = [:]) {
        self.day = day
        self.asleepSeconds = asleepSeconds
        self.start = start
        self.stages = stages
    }

    /// Reads the ring's stage summary as stored ("tief 85 min · leicht 200 min · REM 70 min · wach 20 min").
    public static func stages(fromSummary summary: String?) -> [SleepStage: Int] {
        guard let summary else { return [:] }
        var result: [SleepStage: Int] = [:]
        for part in summary.components(separatedBy: "·") {
            let words = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard words.count >= 2, let minutes = Int(words[1]),
                  let stage = [SleepStage.deep, .light, .rem, .awake].first(where: { $0.title == String(words[0]) }) else { continue }
            result[stage, default: 0] += minutes
        }
        return result
    }
}

public enum DailyScores {
    /// Measured days after which the recovery band is fully personal; before, it blends with `RecoveryPrior`.
    public static let personalDays = 14
    /// Daily step goal until the profile has its own.
    public static let defaultStepGoal = 8_000.0
    static let windowDays = 28

    // MARK: Sleep

    /// Sleep score for the night ending on `day`. Works from the first night; regularity needs 5 earlier nights.
    public static func sleep(on day: Date, nights: [NightSleep], calendar: Calendar) -> ScoreResult {
        let target = calendar.startOfDay(for: day)
        guard let night = nights.last(where: { calendar.isDate($0.day, inSameDayAs: target) }), night.asleepSeconds > 0 else {
            return .noData
        }
        let hours = night.asleepSeconds / 3_600
        var parts = [ScoreComponent(title: "Dauer", score: interpolate(hours, [(4, 20), (5, 45), (6, 65), (7, 85), (8, 100)]),
                                    detail: durationText(night.asleepSeconds), weight: 0.4)]
        let asleepMinutes = Double([SleepStage.deep, .light, .rem].compactMap { night.stages[$0] }.reduce(0, +))
        if asleepMinutes > 0 {
            let deep = Double(night.stages[.deep] ?? 0) / asleepMinutes
            let rem = Double(night.stages[.rem] ?? 0) / asleepMinutes
            let awake = Double(night.stages[.awake] ?? 0)
            parts.append(ScoreComponent(title: "Tiefschlaf", score: interpolate(deep, [(0.05, 30), (0.10, 60), (0.15, 85), (0.20, 100)]),
                                        detail: "\(Int((deep * 100).rounded())) % der Schlafzeit", weight: 0.15))
            parts.append(ScoreComponent(title: "REM-Schlaf", score: interpolate(rem, [(0.06, 30), (0.12, 60), (0.18, 85), (0.22, 100)]),
                                        detail: "\(Int((rem * 100).rounded())) % der Schlafzeit", weight: 0.15))
            parts.append(ScoreComponent(title: "Ruhe", score: interpolate(-awake, [(-90, 30), (-60, 55), (-30, 80), (-10, 100)]),
                                        detail: "\(Int(awake)) min wach", weight: 0.15))
        }
        let earlier = nights.filter { $0.day < target && $0.day >= target.addingTimeInterval(-14 * 86_400) }
        if earlier.count >= 5 {
            let usual = earlier.map { minutesAfterSixPM($0.start, calendar: calendar) }.sorted()
            let median = percentile(usual, 0.5)
            let shift = abs(minutesAfterSixPM(night.start, calendar: calendar) - median)
            parts.append(ScoreComponent(title: "Regelmäßigkeit", score: interpolate(-shift, [(-180, 20), (-120, 45), (-60, 75), (-15, 100)]),
                                        detail: shift < 15 ? "wie üblich ins Bett" : "\(Int(shift.rounded())) min \(minutesAfterSixPM(night.start, calendar: calendar) > median ? "später" : "früher") als üblich",
                                        weight: 0.15))
        }
        let note = night.stages.isEmpty ? nil : "Schlafphasen schätzt der Ring aus Puls und Bewegung; wie genau das beim R03 ist, ist nicht geprüft."
        return .ready(DayScore(kind: .sleep, day: target, value: weighted(parts), components: parts, note: note))
    }

    // MARK: Recovery

    /// Recovery for `day`: resting pulse and HRV against the 28 days before, plus last night's sleep score
    /// and the previous day's steps. From the first day: with fewer than `personalDays` earlier days the
    /// band is a blend of typical adult values and the person's own days.
    public static func recovery(on day: Date, restingHeartRate: [DayValue], hrv: [DayValue], nights: [NightSleep],
                                steps: [DayValue], calendar: Calendar) -> ScoreResult {
        let target = calendar.startOfDay(for: day)
        let windowStart = target.addingTimeInterval(-Double(windowDays) * 86_400)
        func window(_ values: [DayValue]) -> [Double] {
            values.filter { $0.day >= windowStart && $0.day < target }.map(\.value)
        }
        func today(_ values: [DayValue]) -> Double? {
            values.last { calendar.isDate($0.day, inSameDayAs: target) }?.value
        }
        let restingWindow = window(restingHeartRate), hrvWindow = window(hrv)
        let restingToday = today(restingHeartRate), hrvToday = today(hrv)
        guard restingToday != nil || hrvToday != nil else { return .noData }
        var parts: [ScoreComponent] = []
        if let value = restingToday {
            let (median, spread) = band(restingWindow, prior: .restingHeartRate, minimumSpread: 1)
            let difference = value - median
            parts.append(ScoreComponent(title: "Ruhepuls", score: Int((75 - 15 * difference / spread).rounded()),
                                        detail: relativeText(difference, unit: "bpm", median: median, days: restingWindow.count), weight: 0.35))
        }
        if let value = hrvToday {
            let (median, spread) = band(hrvWindow, prior: .hrv, minimumSpread: 2)
            let difference = value - median
            parts.append(ScoreComponent(title: "HRV", score: Int((75 + 15 * difference / spread).rounded()),
                                        detail: relativeText(difference, unit: "ms", median: median, days: hrvWindow.count), weight: 0.35))
        }
        if let sleep = sleep(on: target, nights: nights, calendar: calendar).score {
            parts.append(ScoreComponent(title: "Schlaf letzte Nacht", score: sleep.value, detail: "Schlafwert \(sleep.value)", weight: 0.2))
        }
        let yesterday = target.addingTimeInterval(-86_400)
        let stepsWindow = steps.filter { $0.day >= windowStart && $0.day < yesterday }.map(\.value)
        if let previous = steps.last(where: { calendar.isDate($0.day, inSameDayAs: yesterday) })?.value, stepsWindow.count >= 7 {
            let ratio = previous / max(percentile(stepsWindow.sorted(), 0.5), 1)
            parts.append(ScoreComponent(title: "Vortag", score: interpolate(-ratio, [(-3, 45), (-2, 65), (-1.5, 85)]),
                                        detail: ratio > 1.5 ? "viel bewegt (\(Int((ratio * 100).rounded())) % deines Üblichen)" : "üblich bewegt",
                                        weight: 0.1))
        }
        return .ready(DayScore(kind: .recovery, day: target, value: weighted(parts), components: parts, note: nil))
    }

    // MARK: Activity

    /// Activity for `day`: steps toward the goal, hours without movement (8 to 20 o'clock, finished hours
    /// only) and the mean of the 7 days before. `hourlySteps` only for the day itself.
    public static func activity(on day: Date, steps: [DayValue], hourlySteps: [Int: Double]?, finishedHours: [Int],
                                goal: Double = defaultStepGoal, calendar: Calendar) -> ScoreResult {
        let target = calendar.startOfDay(for: day)
        guard let todaySteps = steps.last(where: { calendar.isDate($0.day, inSameDayAs: target) })?.value else { return .noData }
        var parts = [ScoreComponent(title: "Schritte", score: Int((min(todaySteps / goal, 1) * 100).rounded()),
                                    detail: "\(grouped(todaySteps)) von \(grouped(goal))", weight: 0.5)]
        let awakeHours = finishedHours.filter { (8..<20).contains($0) }
        if let hourly = hourlySteps, HourlySteps.hasEnoughCoverage(hourly, finishedHours: awakeHours) {
            let still = awakeHours.filter { (hourly[$0] ?? 0) < 250 }.count
            parts.append(ScoreComponent(title: "Bewegung über den Tag", score: interpolate(-Double(still), [(-6, 30), (-3, 70), (-1, 100)]),
                                        detail: still == 0 ? "keine Stunde ganz ruhig" : "\(still) Stunden fast ohne Schritte", weight: 0.25))
        }
        let week = steps.filter { $0.day < target && $0.day >= target.addingTimeInterval(-7 * 86_400) }.map(\.value)
        if week.count >= 4 {
            let mean = week.reduce(0, +) / Double(week.count)
            parts.append(ScoreComponent(title: "Letzte 7 Tage", score: Int((min(mean / goal, 1) * 100).rounded()),
                                        detail: "im Mittel \(grouped(mean)) Schritte", weight: 0.25))
        }
        return .ready(DayScore(kind: .activity, day: target, value: weighted(parts), components: parts, note: nil))
    }

    // MARK: Helpers

    static func weighted(_ parts: [ScoreComponent]) -> Int {
        let total = parts.map(\.weight).reduce(0, +)
        guard total > 0 else { return 0 }
        return Int((parts.map { Double($0.score) * $0.weight }.reduce(0, +) / total).rounded())
    }

    /// Piecewise linear through ascending `points`; flat beyond the ends.
    static func interpolate(_ x: Double, _ points: [(Double, Int)]) -> Int {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.0 {
            let t = (x - a.0) / (b.0 - a.0)
            return Int((Double(a.1) + t * Double(b.1 - a.1)).rounded())
        }
        return last.1
    }

    /// Reference band for recovery: the person's own days, blended with `prior` while there are fewer than
    /// `personalDays` of them (weight = days / personalDays). Without own days the prior alone.
    static func band(_ values: [Double], prior: RecoveryPrior, minimumSpread: Double) -> (median: Double, spread: Double) {
        let weight = min(Double(values.count) / Double(personalDays), 1)
        guard weight > 0 else { return (prior.median, max(prior.spread, minimumSpread)) }
        let own: (median: Double, spread: Double) = values.count >= 2
            ? robust(values, minimumSpread: minimumSpread) : (median: values[0], spread: prior.spread)
        return (weight * own.median + (1 - weight) * prior.median,
                max(weight * own.spread + (1 - weight) * prior.spread, minimumSpread))
    }

    /// Median and a robust spread (IQR / 1.349, at least `minimumSpread`).
    static func robust(_ values: [Double], minimumSpread: Double) -> (median: Double, spread: Double) {
        let sorted = values.sorted()
        let iqr = percentile(sorted, 0.75) - percentile(sorted, 0.25)
        return (percentile(sorted, 0.5), max(iqr / 1.349, minimumSpread))
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        PersonalBaseline.percentile(sorted, p)
    }

    /// Bed time as minutes after 18:00, so 23:30 and 00:30 lie 60 minutes apart.
    static func minutesAfterSixPM(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes - 18 * 60 + 1_440).truncatingRemainder(dividingBy: 1_440)
    }

    static func durationText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// `days`: own earlier days in the band; with fewer than `personalDays` the band still leans on typical values.
    static func relativeText(_ difference: Double, unit: String, median: Double, days: Int = personalDays) -> String {
        let amount = Int(abs(difference).rounded())
        let reference = days >= personalDays ? "deinem Mittel" : (days == 0 ? "typischen Werten" : "deinem bisherigen Mittel")
        guard amount > 0 else { return "wie üblich (\(Int(median.rounded())) \(unit))" }
        return "\(amount) \(unit) \(difference > 0 ? "über" : "unter") \(reference) (\(Int(median.rounded())) \(unit))"
    }

    static func grouped(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic).locale(Locale(identifier: "de_DE")))
    }
}

/// Typical adult starting values for the recovery band (resting pulse in bpm, ring HRV in ms). Only a start:
/// each measured day moves the band toward the person's own values.
public struct RecoveryPrior: Equatable, Sendable {
    public let median: Double
    public let spread: Double

    public static let restingHeartRate = RecoveryPrior(median: 60, spread: 6)
    public static let hrv = RecoveryPrior(median: 40, spread: 10)
}
