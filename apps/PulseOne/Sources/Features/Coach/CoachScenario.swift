import Foundation
import PulseCore
import SwiftData

/// Test view data for the "coach" scenario: in-memory store only, never the real one.
enum CoachScenario {
    @MainActor
    static func insert(into context: ModelContext) {
        TestScenario.insertTabHistory(into: context)
        let calendar = Calendar.current
        let now = TestScenario.fixedTime
        let today = calendar.startOfDay(for: now)
        let preferences = CoachPreferences(sports: [.running, .strength], trainingDaysPerWeek: 4, minutesPerSession: 40,
                                           level: .active, equipment: [.mat, .bands])
        let start = calendar.date(byAdding: .day, value: -8, to: today) ?? today
        let program = ProgramBuilder.build(preferences: preferences, start: start, recentWeeklyLoad: nil, calendar: calendar)
        context.insert(CoachSettingsRecord(preferences: preferences, program: program, updatedAt: start))
        for offset in 1...8 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let session = program.session(on: day, calendar: calendar), session.kind != .rest else { continue }
            let review = EveningReview(day: day, completed: true, sport: session.sport, minutes: session.minutes,
                                       rpe: session.intensity.targetRPE.upperBound, plannedIntensity: session.intensity, mood: 4,
                                       check: SubjectiveCheck(soreness: offset == 1 ? 4 : 2))
            context.insert(CoachReviewRecord(review))
        }
    }
}
