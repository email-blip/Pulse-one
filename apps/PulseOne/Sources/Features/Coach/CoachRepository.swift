import Foundation
import PulseCore
import SwiftData

/// Everything the Coach tab shows for one moment, computed from stored data.
struct CoachSnapshot {
    let preferences: CoachPreferences
    let program: TrainingProgram
    let plan: DailyPlan
    let load: LoadSummary
    /// Week and day index of today in the program.
    let position: (week: Int, day: Int)?
    let todayReview: EveningReview?
}

/// Reads and writes coach data and runs the engine. The engine decides; this type only gathers inputs.
@MainActor
struct CoachRepository {
    let context: ModelContext
    var calendar: Calendar = .current

    // MARK: Storage

    func settings() -> CoachSettingsRecord? {
        let descriptor = FetchDescriptor<CoachSettingsRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor))?.first
    }

    /// Saves preferences and starts a new 4-week program from today.
    func save(preferences: CoachPreferences, now: Date) {
        let reviews = self.reviews(since: calendar.date(byAdding: .day, value: -42, to: now) ?? now)
        let history = TrainingLoad.summary(reviews, endingOn: now, calendar: calendar).fourWeekMean
        let program = ProgramBuilder.build(preferences: preferences, start: now, recentWeeklyLoad: history, calendar: calendar)
        if let record = settings() {
            record.update(preferences: preferences, program: program, at: now)
        } else {
            context.insert(CoachSettingsRecord(preferences: preferences, program: program, updatedAt: now))
        }
        try? context.save()
    }

    func reviews(since: Date) -> [EveningReview] {
        let start = calendar.startOfDay(for: since)
        let descriptor = FetchDescriptor<CoachReviewRecord>(predicate: #Predicate { $0.day >= start },
                                                            sortBy: [SortDescriptor(\.day)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.review)
    }

    func save(review: EveningReview) {
        let day = calendar.startOfDay(for: review.day)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<CoachReviewRecord>(predicate: #Predicate { $0.day >= day && $0.day < next })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.update(review)
        } else {
            context.insert(CoachReviewRecord(review))
        }
        try? context.save()
    }

    func revisions(on date: Date) -> [PlanRevision] {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<CoachRevisionRecord>(predicate: #Predicate { $0.day >= day && $0.day < next },
                                                              sortBy: [SortDescriptor(\.createdAt)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.revision)
    }

    func save(revision: PlanRevision) {
        context.insert(CoachRevisionRecord(revision))
        try? context.save()
    }

    // MARK: Engine

    /// nil until the coach was set up. Starts the next 4-week cycle automatically when the last one ended.
    func snapshot(now: Date, profileID: UUID?) -> CoachSnapshot? {
        guard let record = settings(), let preferences = record.preferences else { return nil }
        let reviews = self.reviews(since: calendar.date(byAdding: .day, value: -42, to: now) ?? now)
        var program = record.program
        if program?.position(of: now, calendar: calendar) == nil {
            let history = TrainingLoad.summary(reviews, endingOn: now, calendar: calendar).fourWeekMean
            program = ProgramBuilder.build(preferences: preferences, start: now, recentWeeklyLoad: history, calendar: calendar)
            record.update(preferences: preferences, program: program, at: now)
            try? context.save()
        }
        guard let program else { return nil }

        let reader = SampleReader(context: context)
        func days(_ kind: SampleKind) -> [DayValue] {
            reader.daily(kind, days: 35, profileID: profileID, calendar: calendar, now: now).map { DayValue(day: $0.day, value: $0.value) }
        }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let todayReview = reviews.first { calendar.isDate($0.day, inSameDayAs: today) }
        let subjective = reviews.first { calendar.isDate($0.day, inSameDayAs: yesterday) }?.check
        // HRV from one method only, never mixed: ring HRV ("hrv_ring", method not disclosed) when present,
        // otherwise Apple's SDNN. Looked up by raw value so this compiles before the ring kind lands on main.
        let ringHRV = SampleKind(rawValue: "hrv_ring").map(days) ?? []
        let hrv = ringHRV.isEmpty ? days(.heartRateVariability) : ringHRV
        let signals = RecoveryAssessment.assess(restingHeartRate: days(.restingHeartRate), heartRateVariability: hrv,
                                                sleep: days(.sleepDuration), subjective: subjective, today: now, calendar: calendar)
        let feedback = FeedbackAdaptation.advice(reviews, before: now, style: preferences.style, calendar: calendar)
        let plan = DailyPlanner.plan(now: now, program: program, preferences: preferences, signals: signals, subjective: subjective,
                                     feedback: feedback, hourlySteps: hourlySteps(reader: reader, now: now, profileID: profileID),
                                     revisions: revisions(on: now), calendar: calendar)
        let load = TrainingLoad.summary(reviews, endingOn: now, calendar: calendar)
        return CoachSnapshot(preferences: preferences, program: program, plan: plan, load: load,
                             position: program.position(of: now, calendar: calendar), todayReview: todayReview)
    }

    /// Steps per hour today. Each source is summed per hour; the largest source counts, so Health and
    /// ring steps are never added twice. nil when there is no step data today at all.
    func hourlySteps(reader: SampleReader, now: Date, profileID: UUID?) -> [Int: Double]? {
        let samples = reader.samples([.steps], since: calendar.startOfDay(for: now), profileID: profileID)
        guard !samples.isEmpty else { return nil }
        var perSource: [String: [Int: Double]] = [:]
        for s in samples where s.start <= now {
            let hour = calendar.component(.hour, from: s.start)
            perSource[s.deviceID, default: [:]][hour, default: 0] += s.value
        }
        var result: [Int: Double] = [:]
        for hours in perSource.values {
            for (hour, value) in hours { result[hour] = max(result[hour] ?? 0, value) }
        }
        return result
    }
}
