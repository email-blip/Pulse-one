import Foundation

// The day's plan (COACH-ENGINE-SPEC §3, §6.2, §6.4): the engine decides, texts describe.

public struct DayBlock: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: DayBlockKind
    public let title: String
    public let minutes: Int
    public let intensity: Intensity?
    public let detail: String
    public let exercises: [Exercise]
    /// Why this block looks the way it does today (e.g. adjusted after signals); nil when unchanged.
    public let reason: String?
}

public struct DailyPlan: Equatable, Sendable {
    public let day: Date
    public let decision: ReadinessDecision
    public let signals: [RecoverySignal]
    /// The session the program planned before any adjustment.
    public let planned: PlannedSession
    /// What the coach suggests now (after signals, feedback and the person's own changes).
    public let suggested: PlannedSession
    public let blocks: [DayBlock]
    /// Short descriptive notes (coverage, feedback, medical clearance).
    public let notes: [String]
}

/// A change the person asked for (spec §6.4). Shown before/after and saved only after confirmation.
public enum CoachIntent: Codable, Equatable, Sendable {
    case timeLimit(minutes: Int)
    case swapActivity(Sport)
    case easier
    case harder
    case soreness(region: BodyRegion, level: Int)
    case skipToday

    public var title: String {
        switch self {
        case .timeLimit(let minutes): "Heute nur \(minutes) Minuten"
        case .swapActivity(let sport): "Lieber \(sport.title)"
        case .easier: "Leichter"
        case .harder: "Etwas mehr"
        case .soreness(let region, let level): "Muskelkater \(region.title) (\(level)/10)"
        case .skipToday: "Heute aussetzen"
        }
    }
}

public struct PlanRevision: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let day: Date
    public let intent: CoachIntent
    public let before: PlannedSession
    public let after: PlannedSession
    public let reason: String
    public let createdAt: Date

    public init(id: UUID = UUID(), day: Date, intent: CoachIntent, before: PlannedSession, after: PlannedSession,
                reason: String, createdAt: Date) {
        self.id = id
        self.day = day
        self.intent = intent
        self.before = before
        self.after = after
        self.reason = reason
        self.createdAt = createdAt
    }
}

public enum PlanAdjuster {
    /// Applies an intent within the hard limits; returns the new session and a descriptive reason.
    /// - Parameter neighbourIsHard: the day before or after is a hard day; "Etwas mehr" then stops below hard,
    ///   so a change can never create hard days back to back.
    public static func apply(_ intent: CoachIntent, to session: PlannedSession, preferences raw: CoachPreferences,
                             decision: ReadinessDecision, neighbourIsHard: Bool = false) -> (PlannedSession, String) {
        let p = raw.sanitized
        var s = session
        switch intent {
        case .timeLimit(let limit):
            let minutes = max(limit, 5)
            guard s.kind != .rest else { return (s, "Heute ist ohnehin Ruhetag.") }
            s.minutes = min(s.minutes, minutes)
            return (s, "Die Einheit ist auf \(s.minutes) Minuten gekürzt, die Kernübungen bleiben, die Intensität bleibt gleich.")
        case .swapActivity(let sport):
            guard s.kind != .rest else {
                s = PlannedSession(kind: .main, sport: sport, minutes: min(20, p.minutesPerSession), intensity: .easy)
                return (s, "An einem Ruhetag schlägt der Coach nur eine lockere Einheit vor.")
            }
            // Same planned load: same minutes and intensity in the new sport.
            s.sport = sport
            if s.kind == .recovery { s.intensity = .recovery }
            return (s, "Gleiche Dauer und Anstrengung, jetzt als \(sport.title).")
        case .easier:
            guard s.kind != .rest else { return (s, "Heute ist Ruhetag.") }
            s.intensity = s.intensity.lowered()
            return (s, "Eine Stufe leichter: \(s.intensity.title).")
        case .harder:
            guard s.kind == .main else { return (s, "An Ruhe- und Erholungstagen bleibt es locker.") }
            let cap = min(p.intensityCap, decisionCap(decision), neighbourIsHard ? .moderate : .hard)
            let raised = min(s.intensity.raised(), cap)
            if raised <= s.intensity {
                if neighbourIsHard, s.intensity >= .moderate {
                    return (s, "Mehr ist heute nicht vorgesehen: direkt daneben liegt ein harter Tag, zwei harte Tage hintereinander plant der Coach nicht.")
                }
                return (s, "Mehr ist heute nicht vorgesehen: deine Grenzen und die heutigen Signale lassen \(s.intensity.title) zu.")
            }
            s.intensity = raised
            return (s, "Eine Stufe mehr: \(s.intensity.title).")
        case .soreness(let region, let level):
            if level >= 7 {
                s = PlannedSession(kind: .recovery, sport: nil, minutes: min(max(s.minutes, 15), p.minutesPerSession), intensity: .recovery)
                return (s, "Starker Muskelkater (\(region.title)): heute Erholung statt Training.")
            }
            guard s.kind != .rest else { return (s, "Heute ist Ruhetag.") }
            s.intensity = s.intensity.lowered()
            return (s, "Muskelkater (\(region.title)): eine Stufe leichter, Übungen für diese Region entfallen heute.")
        case .skipToday:
            return (.rest, "Heute ausgesetzt. Der Wochenplan bleibt sonst gleich.")
        }
    }

    /// Highest intensity the day's decision allows.
    public static func decisionCap(_ decision: ReadinessDecision) -> Intensity {
        switch decision {
        case .asPlanned, .offerLighter: .hard
        case .easyOrRecovery: .easy
        case .rest, .seekHelp: .recovery
        }
    }
}

public enum DailyPlanner {
    /// Builds the plan for `now`'s day.
    /// - Parameters:
    ///   - hourlySteps: today's steps per hour of the day (0…23); nil when no step data exists.
    ///   - revisions: confirmed changes for this day, oldest first.
    ///   - activationDone: Begleiter activation sessions finished today; they count as the day's activation
    ///     and movement snacks, so the Coach does not ask for the same movement twice.
    public static func plan(now: Date, program: TrainingProgram?, preferences raw: CoachPreferences,
                            signals: [RecoverySignal], subjective: SubjectiveCheck?, feedback: FeedbackAdvice,
                            hourlySteps: [Int: Double]?, revisions: [PlanRevision],
                            activationDone: [ActivationResult] = [], calendar: Calendar) -> DailyPlan {
        let p = raw.sanitized
        let day = calendar.startOfDay(for: now)
        let decision = CoachRules.decide(signals: signals, subjective: subjective)
        let planned = program?.session(on: day, calendar: calendar) ?? fallbackSession(preferences: p, day: day, calendar: calendar)
        var notes: [String] = []
        var suggested = planned
        var reason: String?

        // 1. Feedback from the last sessions (before any signal rule, which may lower further).
        if suggested.kind == .main, feedback != .unchanged {
            suggested.minutes = ProgramBuilder.clampMinutes(Double(suggested.minutes) * feedback.minutesFactor, budget: p.minutesPerSession)
            if feedback.intensityShift < 0 { suggested.intensity = suggested.intensity.lowered() }
            if feedback.intensityShift > 0 { suggested.intensity = min(suggested.intensity.raised(), p.intensityCap) }
            if let note = feedback.note { notes.append(note) }
        }

        // 2. Signals.
        switch decision {
        case .asPlanned, .offerLighter:
            break
        case .easyOrRecovery:
            if suggested.kind == .main {
                suggested.intensity = min(suggested.intensity, .easy)
                if suggested.sport?.allowsEasyVariant == false { suggested = PlannedSession(kind: .recovery, sport: nil, minutes: min(20, p.minutesPerSession), intensity: .recovery) }
                reason = "Angepasst, weil mehrere Signale jenseits der Coach-Schwelle liegen."
            }
        case .rest, .seekHelp:
            suggested = .rest
            reason = decision.explanation
        }

        // 3. The person's confirmed changes, in order.
        // Not on rest days set by the rules: feeling sick or alarm symptoms are not negotiable.
        let todaysRevisions = revisions.filter { calendar.isDate($0.day, inSameDayAs: day) }
        if decision != .rest, decision != .seekHelp {
            for revision in todaysRevisions {
                suggested = revision.after
                reason = revision.reason
            }
        }
        // The hard caps hold after every change.
        if suggested.kind != .rest {
            suggested.intensity = min(suggested.intensity, p.intensityCap, PlanAdjuster.decisionCap(decision))
            suggested.minutes = min(suggested.minutes, p.minutesPerSession)
        }

        if p.needsMedicalClearance {
            notes.append("Du hast bei den Gesundheitsfragen etwas mit Ja beantwortet. Bis zur ärztlichen Rücksprache plant der Coach nur leichte Einheiten.")
        }
        if let coverage = CoachRules.coverageNote(signals) { notes.append(coverage) }

        var avoid = p
        avoid.limitations.formUnion(subjective?.painRegions ?? [])
        for revision in todaysRevisions {
            if case .soreness(let region, _) = revision.intent { avoid.limitations.insert(region) }
        }
        let dayIndex = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        let doneToday = activationDone.filter { calendar.isDate($0.finishedAt, inSameDayAs: day) }
        let blocks = makeBlocks(suggested: suggested, decision: decision, reason: reason, preferences: avoid,
                                hourlySteps: hourlySteps, activationDone: doneToday, now: now, dayIndex: dayIndex,
                                calendar: calendar)
        return DailyPlan(day: day, decision: decision, signals: signals, planned: planned, suggested: suggested,
                         blocks: blocks, notes: notes)
    }

    /// Without a program: everyday movement for a few minutes, nothing intense.
    static func fallbackSession(preferences p: CoachPreferences, day: Date, calendar: Calendar) -> PlannedSession {
        PlannedSession(kind: .main, sport: p.sports.first, minutes: min(20, p.minutesPerSession), intensity: .easy)
    }

    static func makeBlocks(suggested: PlannedSession, decision: ReadinessDecision, reason: String?,
                           preferences p: CoachPreferences, hourlySteps: [Int: Double]?,
                           activationDone: [ActivationResult] = [], now: Date, dayIndex: Int,
                           calendar: Calendar) -> [DayBlock] {
        var blocks: [DayBlock] = []
        let enabled = p.enabledBlocks
        if enabled.contains(.activation), decision != .seekHelp {
            if let morning = activationDone.first(where: { $0.plan.slot == .morning }) {
                // The Begleiter's morning activation already did this block's job.
                let minutes = max(1, Int((Double(morning.plan.estimatedSeconds) / 60).rounded()))
                blocks.append(DayBlock(id: "activation", kind: .activation, title: DayBlockKind.activation.title,
                                       minutes: minutes, intensity: .recovery,
                                       detail: "Schon erledigt mit der Morgen-Aktivierung im Begleiter.",
                                       exercises: [], reason: nil))
            } else {
                let exercises = ExerciseLibrary.pick(.activation, count: 3, preferences: p, dayIndex: dayIndex)
                blocks.append(DayBlock(id: "activation", kind: .activation, title: DayBlockKind.activation.title, minutes: 5,
                                       intensity: .recovery, detail: "Ruhig wach werden: Atmung und Gelenke bewegen.",
                                       exercises: exercises, reason: nil))
            }
        }
        if enabled.contains(.mainWorkout) {
            switch suggested.kind {
            case .main:
                let strength = suggested.sport?.isStrengthBased == true || suggested.sport == nil
                var exercises = strength ? ExerciseLibrary.pick(.strength, count: 4, preferences: p, dayIndex: dayIndex) : []
                exercises += ExerciseLibrary.pick(.prevention, count: 2, preferences: p, dayIndex: dayIndex)
                    .filter { e in e.sport != nil && e.sport == suggested.sport }
                blocks.append(DayBlock(id: "main", kind: .mainWorkout, title: suggested.title, minutes: suggested.minutes,
                                       intensity: suggested.intensity,
                                       detail: "\(suggested.focus). Anstrengung \(suggested.intensity.title) "
                                           + "(\(suggested.intensity.targetRPE.lowerBound)–\(suggested.intensity.targetRPE.upperBound) von 10): "
                                           + suggested.intensity.feeling,
                                       exercises: exercises, reason: reason))
            case .recovery:
                blocks.append(DayBlock(id: "main", kind: .recovery, title: DayBlockKind.recovery.title, minutes: suggested.minutes,
                                       intensity: .recovery, detail: suggested.focus,
                                       exercises: ExerciseLibrary.pick(.recovery, count: 4, preferences: p, dayIndex: dayIndex),
                                       reason: reason))
            case .rest:
                blocks.append(DayBlock(id: "main", kind: .recovery, title: "Ruhetag", minutes: 0, intensity: nil,
                                       detail: suggested.focus, exercises: [], reason: reason))
            }
        }
        if enabled.contains(.movementSnack), decision != .seekHelp {
            blocks += snacks(preferences: p, hourlySteps: hourlySteps, activationDone: activationDone, now: now,
                             dayIndex: dayIndex, calendar: calendar)
        }
        if enabled.contains(.recovery), suggested.kind == .main, suggested.intensity >= .moderate, decision != .seekHelp {
            blocks.append(DayBlock(id: "recovery", kind: .recovery, title: "Erholung nach der Einheit", minutes: 10,
                                   intensity: .recovery, detail: "Locker auslaufen oder gehen, danach dehnen.",
                                   exercises: ExerciseLibrary.pick(.recovery, count: 2, preferences: p, dayIndex: dayIndex),
                                   reason: nil))
        }
        if enabled.contains(.eveningReview) {
            blocks.append(DayBlock(id: "review", kind: .eveningReview, title: DayBlockKind.eveningReview.title, minutes: 2,
                                   intensity: nil,
                                   detail: "Erledigt? Wie anstrengend (0–10)? Stimmung, Muskelkater, Schmerzen. Daraus plant der Coach morgen.",
                                   exercises: [], reason: nil))
        }
        return blocks
    }

    /// 2 snacks by default; up to 4 when the step data shows inactive stretches of at least an hour.
    /// Activation sessions after the morning (midday, evening, snack) each replace one snack, and a quiet hour
    /// answered by a session in that hour or the next is no longer named as a reason.
    static func snacks(preferences p: CoachPreferences, hourlySteps: [Int: Double]?,
                       activationDone: [ActivationResult] = [], now: Date, dayIndex: Int,
                       calendar: Calendar) -> [DayBlock] {
        let doneHours: [Int] = activationDone.map { calendar.component(.hour, from: $0.finishedAt) }
        let inactive = inactiveHours(hourlySteps: hourlySteps, now: now, wakeHours: p.wakeHours, calendar: calendar)
            .filter { hour in !doneHours.contains { $0 == hour || $0 == hour + 1 } }
        let replaced = activationDone.filter { $0.plan.slot != .morning }.count
        let count = max(0, min(4, max(2, inactive.count)) - replaced)
        let exercises = ExerciseLibrary.pick(.snack, count: count, preferences: p, dayIndex: dayIndex)
        return (0..<count).map { i in
            let reason: String? = i < inactive.count
                ? "Zwischen \(inactive[i]) und \(inactive[i] + 1) Uhr hattest du kaum Schritte." : nil
            let exercise = exercises.isEmpty ? [] : [exercises[i % exercises.count]]
            return DayBlock(id: "snack-\(i)", kind: .movementSnack, title: "\(DayBlockKind.movementSnack.title) \(i + 1)",
                            minutes: 2, intensity: .recovery, detail: "Kurz aufstehen und bewegen, 1–3 Minuten.",
                            exercises: exercise, reason: reason)
        }
    }

    /// Finished hours inside the waking window with fewer than 250 steps (latest first).
    /// An hour without step data is unknown, not inactive; below 50 % coverage of the finished waking hours
    /// (same rule as the Begleiter, `HourlySteps.hasEnoughCoverage`) nothing is called inactive. nil data = none.
    public static func inactiveHours(hourlySteps: [Int: Double]?, now: Date, wakeHours: ClosedRange<Int>,
                                     calendar: Calendar) -> [Int] {
        guard let hourlySteps else { return [] }
        let currentHour = calendar.component(.hour, from: now)
        let finished = wakeHours.filter { $0 < currentHour }
        guard HourlySteps.hasEnoughCoverage(hourlySteps, finishedHours: finished) else { return [] }
        return finished.filter { hour in
            guard let steps = hourlySteps[hour] else { return false }
            return steps < ActivityCheck.quietStepsPerHour
        }.sorted(by: >)
    }
}
