import Foundation

// Session-RPE load (COACH-ENGINE-SPEC §6.1): duration × perceived effort on the CR-10 scale.
// A missing RPE stays missing; it is never replaced by a default (unlike open-coach's RPE = 5).

/// The evening review of one day (spec §3 "Evening Review"). Doubles as the training log.
public struct EveningReview: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Start of the day the review is about.
    public var day: Date
    /// Did the main session happen?
    public var completed: Bool
    public var sport: Sport?
    public var minutes: Int?
    /// CR-10, 0…10.
    public var rpe: Int?
    /// What the plan asked for, so feedback can compare planned with felt effort.
    public var plannedIntensity: Intensity?
    /// 1 (low) … 5 (good).
    public var mood: Int?
    public var check: SubjectiveCheck
    public var note: String

    public init(id: UUID = UUID(), day: Date, completed: Bool, sport: Sport? = nil, minutes: Int? = nil, rpe: Int? = nil,
                plannedIntensity: Intensity? = nil, mood: Int? = nil, check: SubjectiveCheck = SubjectiveCheck(), note: String = "") {
        self.id = id
        self.day = day
        self.completed = completed
        self.sport = sport
        self.minutes = minutes
        self.rpe = rpe.map { min(max($0, 0), 10) }
        self.plannedIntensity = plannedIntensity
        self.mood = mood
        self.check = check
        self.note = note
    }

    /// Session load in arbitrary units (minutes × RPE); nil when the session did not happen or data is missing.
    public var load: Double? {
        guard completed, let minutes, let rpe else { return nil }
        return Double(minutes * rpe)
    }
}

public struct LoadSummary: Equatable, Sendable {
    /// Load of the 7 days ending with the reference day.
    public let weekLoad: Double
    /// Mean weekly load of the 4 weeks before; nil without history.
    public let fourWeekMean: Double?
    /// Mean/standard deviation of the daily loads of the last 7 days; background figure only.
    public let monotony: Double?
    /// Reviews in the 7 days that had no RPE; shown as a gap.
    public let missingRPE: Int
}

public enum TrainingLoad {
    public static func summary(_ reviews: [EveningReview], endingOn day: Date, calendar: Calendar) -> LoadSummary {
        let end = calendar.startOfDay(for: day)
        let week = dailyLoads(reviews, lastDay: end, days: 7, calendar: calendar)
        var weekly: [Double] = []
        for w in 1...4 {
            guard let last = calendar.date(byAdding: .day, value: -7 * w, to: end) else { continue }
            let loads = dailyLoads(reviews, lastDay: last, days: 7, calendar: calendar)
            let hasData = reviewsIn(reviews, lastDay: last, days: 7, calendar: calendar).isEmpty == false
            if hasData { weekly.append(loads.reduce(0, +)) }
        }
        let missing = reviewsIn(reviews, lastDay: end, days: 7, calendar: calendar).filter { $0.completed && $0.rpe == nil }.count
        return LoadSummary(weekLoad: week.reduce(0, +),
                           fourWeekMean: weekly.isEmpty ? nil : weekly.reduce(0, +) / Double(weekly.count),
                           monotony: monotony(week), missingRPE: missing)
    }

    /// Load per day, oldest first, for `days` days ending with `lastDay`.
    public static func dailyLoads(_ reviews: [EveningReview], lastDay: Date, days: Int, calendar: Calendar) -> [Double] {
        (0..<days).reversed().map { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: lastDay)) else { return 0 }
            return reviews.filter { calendar.isDate($0.day, inSameDayAs: d) }.compactMap(\.load).reduce(0, +)
        }
    }

    static func reviewsIn(_ reviews: [EveningReview], lastDay: Date, days: Int, calendar: Calendar) -> [EveningReview] {
        let end = calendar.startOfDay(for: lastDay)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end),
              let after = calendar.date(byAdding: .day, value: 1, to: end) else { return [] }
        return reviews.filter { $0.day >= start && $0.day < after }
    }

    /// Mean divided by standard deviation; nil when all days are equal or there is no load.
    public static func monotony(_ daily: [Double]) -> Double? {
        guard daily.count >= 2 else { return nil }
        let mean = daily.reduce(0, +) / Double(daily.count)
        let variance = daily.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(daily.count)
        let sd = variance.squareRoot()
        guard mean > 0, sd > 0 else { return nil }
        return mean / sd
    }
}

/// How the last sessions felt compared with the plan (spec §6.4 "Feedback-Anpassung").
public struct FeedbackAdvice: Equatable, Sendable {
    /// Multiplier for the next main sessions' minutes (0.8…1.1). Hard limits still apply afterwards.
    public let minutesFactor: Double
    /// Intensity steps to shift the next main session (−1, 0, +1).
    public let intensityShift: Int
    /// Descriptive reason, nil when nothing changes.
    public let note: String?

    public static let unchanged = FeedbackAdvice(minutesFactor: 1, intensityShift: 0, note: nil)
}

public enum FeedbackAdaptation {
    /// Looks at the last three reviews with a planned intensity before `day`.
    public static func advice(_ reviews: [EveningReview], before day: Date, style: CoachingStyle, calendar: Calendar) -> FeedbackAdvice {
        let start = calendar.startOfDay(for: day)
        let recent = reviews.filter { $0.day < start }.sorted { $0.day > $1.day }
        let planned = recent.filter { $0.plannedIntensity != nil && $0.plannedIntensity != .recovery }.prefix(3)
        let skipped = recent.prefix(7).filter { !$0.completed && $0.plannedIntensity != nil }.count
        if skipped >= 3 {
            return FeedbackAdvice(minutesFactor: 0.8, intensityShift: 0,
                                  note: "Einige geplante Einheiten sind zuletzt ausgefallen. Der Coach plant die nächsten kürzer, damit sie leichter in deinen Tag passen.")
        }
        let rated = planned.compactMap { r -> (Int, ClosedRange<Int>)? in
            guard r.completed, let rpe = r.rpe, let target = r.plannedIntensity?.targetRPE else { return nil }
            return (rpe, target)
        }
        guard rated.count >= 2 else { return .unchanged }
        let tooHard = rated.filter { $0.0 >= $0.1.upperBound + 2 }.count
        let tooEasy = rated.filter { $0.0 <= $0.1.lowerBound - 2 }.count
        if tooHard >= 2 {
            return FeedbackAdvice(minutesFactor: 0.9, intensityShift: -1,
                                  note: "Die letzten Einheiten waren anstrengender als geplant. Der Coach nimmt die nächste eine Stufe zurück.")
        }
        if tooEasy == rated.count, rated.count >= 3, style != .calm {
            return FeedbackAdvice(minutesFactor: style == .demanding ? 1.1 : 1.05, intensityShift: 0,
                                  note: "Die letzten Einheiten waren leichter als geplant. Der Coach verlängert die nächste etwas.")
        }
        return .unchanged
    }
}
