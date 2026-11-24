import Foundation
import PulseCore
import SwiftData

/// One saved training session (team 05). New model, lightweight migration: every field has a default.
/// The summary is stored as JSON so the core type stays plain Swift. Stays on the device.
@Model
final class WorkoutRecord {
    var sessionID: String = ""
    /// Start of the local day the session belongs to.
    var day: Date = Date.distantPast
    var startedAt: Date = Date.distantPast
    var endedAt: Date = Date.distantPast
    var profileID: UUID?
    var summaryJSON: Data = Data()

    init(_ summary: WorkoutSummary, profileID: UUID?, calendar: Calendar) {
        sessionID = summary.id.uuidString
        day = calendar.startOfDay(for: summary.startedAt)
        startedAt = summary.startedAt
        endedAt = summary.endedAt
        self.profileID = profileID
        summaryJSON = (try? JSONEncoder().encode(summary)) ?? Data()
    }

    var summary: WorkoutSummary? { try? JSONDecoder().decode(WorkoutSummary.self, from: summaryJSON) }
}

enum TrainingPersistence {
    static let models: [any PersistentModel.Type] = [WorkoutRecord.self]
}

/// Reads and writes saved sessions; the Verlauf's `training` track reads `entries(in:)`.
@MainActor
struct WorkoutLog {
    let context: ModelContext
    var calendar: Calendar = .current

    /// Saves once per session id (a second save updates the first).
    func save(_ summary: WorkoutSummary, profileID: UUID?) {
        let id = summary.id.uuidString
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.sessionID == id })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.summaryJSON = (try? JSONEncoder().encode(summary)) ?? existing.summaryJSON
            existing.endedAt = summary.endedAt
        } else {
            context.insert(WorkoutRecord(summary, profileID: profileID, calendar: calendar))
        }
        try? context.save()
    }

    /// Sessions that overlap `window`, oldest first.
    func summaries(in window: DateInterval) -> [WorkoutSummary] {
        let from = window.start.addingTimeInterval(-6 * 3600)
        let to = window.end
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.startedAt >= from && $0.startedAt < to },
                                                        sortBy: [SortDescriptor(\.startedAt)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.summary).filter { $0.interval.intersects(window) }
    }

    /// Entries of the `training` track for the shared time axis.
    func entries(in window: DateInterval) -> [TrainingTimelineEntry] {
        WorkoutSummary.timelineEntries(summaries(in: window), in: window)
    }

    func today(now: Date) -> [WorkoutSummary] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return summaries(in: DateInterval(start: start, end: end))
    }

    /// Load of saved sessions with exertion (minutes × exertion) in the coach's load window.
    func loads(endingOn now: Date, days: Int = 42) -> [DayValue] {
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: now) ?? now)
        return summaries(in: DateInterval(start: start, end: max(now, start))).compactMap { summary in
            summary.load.map { DayValue(day: calendar.startOfDay(for: summary.startedAt), value: $0) }
        }
    }
}
