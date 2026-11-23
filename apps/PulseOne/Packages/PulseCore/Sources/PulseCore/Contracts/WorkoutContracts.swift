import Foundation

public enum WorkoutPhase: String, Codable, Sendable {
    case ready, work, rest, done
}

public enum WorkoutRunState: String, Codable, Sendable {
    case idle, running, paused, finished, cancelled
}

/// What the voice is allowed to say right now; screen and voice read the same session.
public enum AnnouncementState: String, Codable, Sendable {
    case silent, announcingExercise, cueing, announcingPhaseChange, announcingFinish
}

public struct WorkoutStep: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let exerciseID: String
    public let title: String
    public let variant: String?
    /// Work time in seconds, or nil for a repetition step.
    public let workSeconds: Int?
    public let repetitions: Int?
    public let restSeconds: Int

    public init(id: String, exerciseID: String, title: String, variant: String?, workSeconds: Int?,
                repetitions: Int?, restSeconds: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.title = title
        self.variant = variant
        self.workSeconds = workSeconds
        self.repetitions = repetitions
        self.restSeconds = restSeconds
    }
}

/// One training session. All times derive from stored timestamps and pauses, never from UI ticks,
/// so a locked or relaunched app reconstructs the same state.
public struct WorkoutSession: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let programID: String
    public let steps: [WorkoutStep]
    public private(set) var state: WorkoutRunState
    public private(set) var stepIndex: Int
    public private(set) var phase: WorkoutPhase
    /// Wall-clock start of the current phase.
    public private(set) var phaseStartedAt: Date?
    /// Paused time already spent inside the current phase.
    public private(set) var pausedInPhase: TimeInterval
    public private(set) var pausedAt: Date?
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?
    public var completedRepetitions: [String: Int]
    /// Perceived exertion 1–10 after the session.
    public var perceivedExertion: Int?
    public var announcement: AnnouncementState

    public init(id: UUID = UUID(), programID: String, steps: [WorkoutStep]) {
        self.id = id
        self.programID = programID
        self.steps = steps
        state = .idle
        stepIndex = 0
        phase = .ready
        pausedInPhase = 0
        completedRepetitions = [:]
        announcement = .silent
    }

    public var currentStep: WorkoutStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }

    /// Planned length of the current phase in seconds; nil for open repetition work.
    public var phaseLength: TimeInterval? {
        guard let step = currentStep else { return nil }
        switch phase {
        case .work: return step.workSeconds.map(TimeInterval.init)
        case .rest: return TimeInterval(step.restSeconds)
        case .ready, .done: return nil
        }
    }

    public func elapsedInPhase(at now: Date) -> TimeInterval {
        guard let started = phaseStartedAt else { return 0 }
        let pausedNow = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(started) - pausedInPhase - pausedNow)
    }

    public func remaining(at now: Date) -> TimeInterval? {
        phaseLength.map { max(0, $0 - elapsedInPhase(at: now)) }
    }

    /// Wall-clock end of the running timed phase, for the local notification and the Live Activity.
    public var scheduledPhaseEnd: Date? {
        guard state == .running, let started = phaseStartedAt, let length = phaseLength else { return nil }
        return started.addingTimeInterval(length + pausedInPhase)
    }

    public mutating func start(at now: Date) {
        guard state == .idle, !steps.isEmpty else { return }
        state = .running
        startedAt = now
        enter(.work, at: now)
        announcement = .announcingExercise
    }

    public mutating func pause(at now: Date) {
        guard state == .running else { return }
        state = .paused
        pausedAt = now
        // A pause drops any queued cue: the screen says "Pause", the voice must not drive on.
        announcement = .silent
    }

    public mutating func resume(at now: Date) {
        guard state == .paused, let pausedAt else { return }
        pausedInPhase += now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
        state = .running
    }

    /// Moves to the next phase: work → rest → next step's work, last rest → done.
    public mutating func advance(at now: Date) {
        guard state == .running || state == .paused else { return }
        if state == .paused { resume(at: now) }
        switch phase {
        case .ready:
            enter(.work, at: now)
        case .work:
            if let step = currentStep, step.restSeconds > 0, stepIndex < steps.count - 1 {
                enter(.rest, at: now)
                announcement = .announcingPhaseChange
            } else {
                nextStepOrFinish(at: now)
            }
        case .rest:
            nextStepOrFinish(at: now)
        case .done:
            break
        }
    }

    /// Skips the current step entirely; stale cues are dropped.
    public mutating func skip(at now: Date) {
        guard state == .running || state == .paused else { return }
        if state == .paused { resume(at: now) }
        announcement = .silent
        nextStepOrFinish(at: now)
    }

    public mutating func cancel(at now: Date) {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
        endedAt = now
        pausedAt = nil
        announcement = .silent
    }

    /// Applies every phase end that passed while the app was suspended (timed phases only).
    public mutating func catchUp(to now: Date) {
        while state == .running, let end = scheduledPhaseEnd, end <= now {
            advance(at: end)
        }
    }

    private mutating func nextStepOrFinish(at now: Date) {
        if stepIndex < steps.count - 1 {
            stepIndex += 1
            enter(.work, at: now)
            announcement = .announcingExercise
        } else {
            phase = .done
            state = .finished
            endedAt = now
            phaseStartedAt = nil
            announcement = .announcingFinish
        }
    }

    private mutating func enter(_ next: WorkoutPhase, at now: Date) {
        phase = next
        phaseStartedAt = now
        pausedInPhase = 0
        pausedAt = nil
    }
}
