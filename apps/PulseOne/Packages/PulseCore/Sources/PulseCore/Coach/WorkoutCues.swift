import Foundation

/// Identifies the moment a cue was made for. A cue is spoken only while the session is still exactly there,
/// so pause, skip, end or a phase that passed while the phone was locked silence it.
public struct WorkoutCueToken: Equatable, Hashable, Sendable, Codable {
    public let sessionID: UUID
    public let stepIndex: Int
    public let phase: WorkoutPhase
    public let phaseStartedAt: Date?
    /// Separates the phase announcement from the countdown inside the same phase.
    public let purpose: String

    public init(sessionID: UUID, stepIndex: Int, phase: WorkoutPhase, phaseStartedAt: Date?, purpose: String) {
        self.sessionID = sessionID
        self.stepIndex = stepIndex
        self.phase = phase
        self.phaseStartedAt = phaseStartedAt
        self.purpose = purpose
    }
}

public extension WorkoutSession {
    func cueToken(_ purpose: String = "phase") -> WorkoutCueToken {
        WorkoutCueToken(sessionID: id, stepIndex: stepIndex, phase: phase, phaseStartedAt: phaseStartedAt, purpose: purpose)
    }

    /// True while a cue made for `token` may still be spoken: running (or just finished, for the finish cue)
    /// and still in the same step and phase. A paused session accepts nothing.
    func accepts(_ token: WorkoutCueToken) -> Bool {
        guard token.sessionID == id, token.stepIndex == stepIndex, token.phase == phase,
              token.phaseStartedAt == phaseStartedAt else { return false }
        switch state {
        case .running: return true
        case .finished: return phase == .done
        case .idle, .paused, .cancelled: return false
        }
    }

    /// The step after the current one, if any.
    var nextStep: WorkoutStep? { steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1] : nil }
}

public struct WorkoutCue: Equatable, Sendable {
    public let token: WorkoutCueToken
    public let kind: AnnouncementState
    /// Written text; `SpokenGerman.prepare` turns it into what the voice says.
    public let text: String
}

/// Words for the trainer voice and the phase-end notification. Short, direct, ROOK tone, no numbers lists.
public enum WorkoutCuePlanner {
    /// Countdown is spoken once per timed phase of at least this length.
    public static let countdownMinimumPhase: TimeInterval = 25
    public static let countdownAt: TimeInterval = 10

    /// The cue for the session's pending announcement; nil when silent or the session does not accept it.
    public static func cue(for session: WorkoutSession, at now: Date) -> WorkoutCue? {
        let token = session.cueToken()
        guard session.accepts(token) else { return nil }
        let text: String
        switch session.announcement {
        case .silent, .cueing:
            return nil
        case .announcingExercise:
            guard let step = session.currentStep else { return nil }
            text = (session.stepIndex == 0 ? "Los geht's. " : "") + exerciseLine(step, session: session, now: now)
        case .announcingPhaseChange:
            if let next = session.nextStep {
                text = "Pause. Als Nächstes: \(next.title)."
            } else {
                text = "Pause."
            }
        case .announcingFinish:
            text = "Geschafft. Sag mir gleich, wie anstrengend es war."
        }
        return WorkoutCue(token: token, kind: session.announcement, text: text)
    }

    /// "Noch zehn Sekunden" once per long timed phase, inside the last ten seconds (but not the last three).
    public static func countdown(for session: WorkoutSession, at now: Date, alreadySpoken: Set<WorkoutCueToken>) -> WorkoutCue? {
        let token = session.cueToken("countdown")
        guard session.state == .running, !alreadySpoken.contains(token),
              let length = session.phaseLength, length >= countdownMinimumPhase,
              let remaining = session.remaining(at: now), remaining <= countdownAt, remaining > 3 else { return nil }
        let text: String
        if session.phase == .rest, let next = session.nextStep {
            text = "Gleich geht's weiter mit \(next.title)."
        } else {
            text = "Noch zehn Sekunden."
        }
        return WorkoutCue(token: token, kind: .cueing, text: text)
    }

    static func exerciseLine(_ step: WorkoutStep, session: WorkoutSession, now: Date) -> String {
        let name = [step.title, step.variant?.components(separatedBy: " · ").first].compactMap { $0 }.joined(separator: " ")
        if let reps = step.repetitions {
            return "\(name). \(reps) Wiederholungen."
        }
        if let length = session.phaseLength, let remaining = session.remaining(at: now) {
            // After a lock or a late resume the voice names what is really left.
            if length - remaining > 3 {
                return "\(name). Noch \(Int(remaining.rounded())) Sekunden."
            }
            return "\(name). " + durationText(Int(length)) + "."
        }
        return "\(name)."
    }

    static func durationText(_ seconds: Int) -> String {
        if seconds >= 120, seconds % 60 == 0 { return "\(seconds / 60) Minuten" }
        if seconds == 60 { return "Eine Minute" }
        return "\(seconds) Sekunden"
    }

    /// Text of the local notification at the end of the running phase (lock screen); nil when nothing is timed.
    public static func phaseEndNotice(for session: WorkoutSession) -> (title: String, body: String)? {
        guard session.scheduledPhaseEnd != nil, let step = session.currentStep else { return nil }
        switch session.phase {
        case .work:
            if step.restSeconds > 0, let next = session.nextStep {
                return ("\(step.title) geschafft", "Jetzt \(durationText(step.restSeconds)) Pause. Danach: \(next.title).")
            }
            if let next = session.nextStep {
                return ("\(step.title) geschafft", "Weiter mit \(next.title).")
            }
            return ("Einheit geschafft", "Öffne PULSE ONE und sag, wie anstrengend es war.")
        case .rest:
            guard let next = session.nextStep else { return nil }
            return ("Pause vorbei", "Weiter mit \(next.title).")
        case .ready, .done:
            return nil
        }
    }
}
