import Foundation

/// What the ring or Apple Health measured during a session. Kept apart from what was done (execution) and how it
/// felt (perceived exertion): three different statements.
public struct WorkoutReaction: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let averageHeartRate: Double?
    public let maxHeartRate: Double?

    public init(sampleCount: Int, averageHeartRate: Double?, maxHeartRate: Double?) {
        self.sampleCount = sampleCount
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }

    /// Pulse values whose time lies inside the session window. nil when nothing was measured there.
    public static func measure(heartRate: [(date: Date, bpm: Double)], during window: DateInterval) -> WorkoutReaction? {
        let inside = heartRate.filter { window.contains($0.date) && $0.bpm > 0 }.map(\.bpm)
        guard !inside.isEmpty else { return nil }
        return WorkoutReaction(sampleCount: inside.count, averageHeartRate: inside.reduce(0, +) / Double(inside.count),
                               maxHeartRate: inside.max())
    }
}

/// One finished (or ended early) session, as stored and shown in the day's timeline (track `training`).
public struct WorkoutSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let programID: String
    public let title: String
    public let startedAt: Date
    public let endedAt: Date
    public let plannedSteps: Int
    public let completedSteps: Int
    public let skippedSteps: Int
    /// false when the person ended the session before the last step.
    public let finishedAsPlanned: Bool
    /// CR-10 / 1–10, given after the session; nil when the person gave none.
    public var perceivedExertion: Int?
    public var reaction: WorkoutReaction?

    public init(id: UUID, programID: String, title: String, startedAt: Date, endedAt: Date, plannedSteps: Int,
                completedSteps: Int, skippedSteps: Int, finishedAsPlanned: Bool, perceivedExertion: Int? = nil,
                reaction: WorkoutReaction? = nil) {
        self.id = id
        self.programID = programID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSteps = plannedSteps
        self.completedSteps = completedSteps
        self.skippedSteps = skippedSteps
        self.finishedAsPlanned = finishedAsPlanned
        self.perceivedExertion = perceivedExertion
        self.reaction = reaction
    }

    /// Summary of an ended session; nil when it never started. Steps count as completed when they were reached
    /// and finished (current step of an early end only if its rest had begun), minus skipped ones.
    public static func make(from session: WorkoutSession, title: String, skippedStepIDs: Set<String>) -> WorkoutSummary? {
        guard let start = session.startedAt, let end = session.endedAt,
              session.state == .finished || session.state == .cancelled else { return nil }
        let reached = session.state == .finished
            ? session.steps.count
            : min(session.steps.count, session.stepIndex + (session.phase == .rest ? 1 : 0))
        let reachedSteps = session.steps.prefix(reached)
        let skipped = session.steps.filter { skippedStepIDs.contains($0.id) }.count
        return WorkoutSummary(id: session.id, programID: session.programID, title: title, startedAt: start, endedAt: end,
                              plannedSteps: session.steps.count,
                              completedSteps: reachedSteps.filter { !skippedStepIDs.contains($0.id) }.count,
                              skippedSteps: skipped, finishedAsPlanned: session.state == .finished,
                              perceivedExertion: session.perceivedExertion)
    }

    public var interval: DateInterval { DateInterval(start: startedAt, end: max(endedAt, startedAt)) }

    /// Whole minutes, at least 1.
    public var minutes: Int { max(1, Int((interval.duration / 60).rounded())) }

    /// Training load (minutes × perceived exertion), the coach's load unit; nil without exertion.
    public var load: Double? { perceivedExertion.map { Double(minutes * $0) } }

    /// "11 von 12 Abschnitten, 1 übersprungen" – what was done, nothing measured.
    public var executionText: String {
        var text = "\(completedSteps) von \(plannedSteps) Abschnitten"
        if skippedSteps > 0 { text += ", \(skippedSteps) übersprungen" }
        if !finishedAsPlanned { text += ", früher beendet" }
        return text
    }

    public var timelineEntry: TrainingTimelineEntry {
        var detail = "\(minutes) min · " + executionText
        if let perceivedExertion { detail += " · Anstrengung \(perceivedExertion)/10" }
        return TrainingTimelineEntry(id: id, interval: interval, title: title, detail: detail)
    }

    /// Entries of the `training` track that overlap the visible window, oldest first.
    public static func timelineEntries(_ summaries: [WorkoutSummary], in window: DateInterval) -> [TrainingTimelineEntry] {
        summaries
            .filter { $0.interval.intersects(window) }
            .sorted { $0.startedAt < $1.startedAt }
            .map(\.timelineEntry)
    }
}

/// One block on the `training` track of the Verlauf (team 03 draws it on the shared time axis).
public struct TrainingTimelineEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let interval: DateInterval
    public let title: String
    public let detail: String
    public var track: TimelineTrack { .training }

    public init(id: UUID, interval: DateInterval, title: String, detail: String) {
        self.id = id
        self.interval = interval
        self.title = title
        self.detail = detail
    }
}
