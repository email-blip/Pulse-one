import Foundation

// Shared types of the Begleiter "Aktivierung": short bodyweight sessions (push-ups, pull-ups, plank and
// friends) in the morning after waking, at midday and in the evening, plus short movement snacks when the
// day has been quiet. Contract between the core (planner, progression, activity check) and the app.
// Do not rename; only add. See docs/pulse-one-coordination/AKTIVIERUNG-KONZEPT.md.

/// When a session happens.
public enum ActivationSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, midday, evening, snack
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .morning: "Morgen-Aktivierung"
        case .midday: "Mittags-Aktivierung"
        case .evening: "Abend-Aktivierung"
        case .snack: "Bewegungs-Snack"
        }
    }
    public var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .midday: "sun.max"
        case .evening: "sunset"
        case .snack: "figure.walk"
        }
    }
}

/// Movement families that progress along their own ladder of exercises.
public enum ActivationFamily: String, Codable, CaseIterable, Sendable {
    /// Push-ups: wall → incline → knee → push-up → diamond → decline.
    case push
    /// Pull: table row → dead hang → scapular pull → negative → pull-up (bar needed from dead hang on).
    case pull
    /// Core holds: knee plank → plank → shoulder-tap plank → hollow hold.
    case core
    /// Legs: chair squat → squat → reverse lunge → split squat.
    case legs
    /// Short pulse raisers: marching → jumping jacks → mountain climbers.
    case cardio
    /// Joint circles, breathing; used for warm-up and gentle days.
    case mobility
}

/// What a block asks for.
public enum ActivationTarget: Codable, Equatable, Sendable {
    case reps(Int)
    /// Hold or timed work in seconds.
    case seconds(Int)
}

/// One exercise in a session: `rounds` × target, `restSeconds` after each round.
public struct ActivationBlock: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// `Exercise.id` from `ActivationLibrary.exercise(_:)` (own entries or the Coach library).
    public let exerciseID: String
    public let family: ActivationFamily
    public let target: ActivationTarget
    public let rounds: Int
    public let restSeconds: Int

    public init(id: String, exerciseID: String, family: ActivationFamily, target: ActivationTarget, rounds: Int,
                restSeconds: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.family = family
        self.target = target
        self.rounds = rounds
        self.restSeconds = restSeconds
    }
}

/// How the blocks are run.
public enum ActivationFormat: String, Codable, Sendable {
    /// All blocks one after another, repeated `rounds` times (circuit).
    case circuit
    /// Each block's rounds before the next block (straight sets).
    case sets
    /// Gentle day: mobility and breathing only.
    case gentle
}

/// The day's readiness for activation, from the companion's day type and pattern check.
public enum ActivationReadiness: String, Codable, Sendable {
    case full, reduced, gentle
}

/// A planned session.
public struct ActivationPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(slot.rawValue).\(dayStamp)" }
    public let slot: ActivationSlot
    /// yyyyMMdd of the day the plan is for.
    public let dayStamp: String
    public let format: ActivationFormat
    public let readiness: ActivationReadiness
    /// Warm-up blocks (mobility, ~1 min), not counted for progression.
    public let warmUp: [ActivationBlock]
    public let blocks: [ActivationBlock]
    /// Circuit rounds (1 for `sets` and `gentle`).
    public let circuitRounds: Int
    public let estimatedSeconds: Int
    /// One calm German sentence why the session looks like this today (e.g. "Kurze Nacht: heute etwas weniger.").
    public let reason: String
    /// Short German summary for notifications, e.g. "3 Runden: 12 Liegestütze, 4 Klimmzüge, 40 s Unterarmstütz".
    public let summary: String

    public init(slot: ActivationSlot, dayStamp: String, format: ActivationFormat, readiness: ActivationReadiness,
                warmUp: [ActivationBlock], blocks: [ActivationBlock], circuitRounds: Int, estimatedSeconds: Int,
                reason: String, summary: String) {
        self.slot = slot
        self.dayStamp = dayStamp
        self.format = format
        self.readiness = readiness
        self.warmUp = warmUp
        self.blocks = blocks
        self.circuitRounds = circuitRounds
        self.estimatedSeconds = estimatedSeconds
        self.reason = reason
        self.summary = summary
    }
}

/// The person's current level in one family: which exercise of the ladder, and the best clean set.
public struct ActivationLevel: Codable, Equatable, Sendable {
    public var family: ActivationFamily
    public var exerciseID: String
    /// Best clean set: reps, or seconds for holds.
    public var best: Int
    public var updatedAt: Date

    public init(family: ActivationFamily, exerciseID: String, best: Int, updatedAt: Date) {
        self.family = family
        self.exerciseID = exerciseID
        self.best = best
        self.updatedAt = updatedAt
    }
}

/// All levels; families without a level start from the defaults for the fitness level.
public struct ActivationProfile: Codable, Equatable, Sendable {
    public var levels: [ActivationFamily: ActivationLevel]
    public init(levels: [ActivationFamily: ActivationLevel] = [:]) { self.levels = levels }
}

/// How the session felt.
public enum ActivationFeedback: String, Codable, CaseIterable, Sendable {
    case tooEasy, right, tooHard
    public var title: String {
        switch self {
        case .tooEasy: "Zu leicht"
        case .right: "Passend"
        case .tooHard: "Zu schwer"
        }
    }
}

/// What was actually done in one block (sum over rounds and the weakest round).
public struct ActivationBlockResult: Codable, Equatable, Sendable {
    public let blockID: String
    public let exerciseID: String
    public let family: ActivationFamily
    /// Done per round (reps or seconds), in order; empty when skipped.
    public let done: [Int]

    public init(blockID: String, exerciseID: String, family: ActivationFamily, done: [Int]) {
        self.blockID = blockID
        self.exerciseID = exerciseID
        self.family = family
        self.done = done
    }
}

/// A finished (or partly finished) session.
public struct ActivationResult: Codable, Equatable, Sendable {
    public let plan: ActivationPlan
    public let results: [ActivationBlockResult]
    public let feedback: ActivationFeedback?
    public let finishedAt: Date

    public init(plan: ActivationPlan, results: [ActivationBlockResult], feedback: ActivationFeedback?, finishedAt: Date) {
        self.plan = plan
        self.results = results
        self.feedback = feedback
        self.finishedAt = finishedAt
    }
}

/// The person's activation settings (stored by the app).
public struct ActivationSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Morning session length, 5…15 minutes.
    public var morningMinutes: Int
    public var middayEnabled: Bool
    public var middayHour: Int
    public var middayMinute: Int
    public var eveningEnabled: Bool
    public var eveningHour: Int
    public var eveningMinute: Int
    /// Midday/evening length, 3…10 minutes.
    public var shortMinutes: Int
    /// Remind when the day has been quiet (in-app hint and, where possible, a notification).
    public var activityReminders: Bool

    public init(isEnabled: Bool = true, morningMinutes: Int = 8, middayEnabled: Bool = true, middayHour: Int = 12,
                middayMinute: Int = 30, eveningEnabled: Bool = true, eveningHour: Int = 18, eveningMinute: Int = 0,
                shortMinutes: Int = 5, activityReminders: Bool = true) {
        self.isEnabled = isEnabled
        self.morningMinutes = morningMinutes
        self.middayEnabled = middayEnabled
        self.middayHour = middayHour
        self.middayMinute = middayMinute
        self.eveningEnabled = eveningEnabled
        self.eveningHour = eveningHour
        self.eveningMinute = eveningMinute
        self.shortMinutes = shortMinutes
        self.activityReminders = activityReminders
    }

    public static let morningRange = 5...15
    public static let shortRange = 3...10
}

/// Everything the planner needs; the app gathers it.
public struct ActivationInput: Sendable {
    public let slot: ActivationSlot
    public let now: Date
    public let calendar: Calendar
    public let settings: ActivationSettings
    public let profile: ActivationProfile
    /// Equipment, limitations, level and medical clearance come from the Coach settings (defaults when unset).
    public let coach: CoachPreferences
    public let dayType: CompanionDayType
    public let infectionLevel: InfectionLevel
    /// Sessions already finished today (any slot), oldest first.
    public let doneToday: [ActivationResult]

    public init(slot: ActivationSlot, now: Date, calendar: Calendar, settings: ActivationSettings,
                profile: ActivationProfile, coach: CoachPreferences, dayType: CompanionDayType,
                infectionLevel: InfectionLevel, doneToday: [ActivationResult]) {
        self.slot = slot
        self.now = now
        self.calendar = calendar
        self.settings = settings
        self.profile = profile
        self.coach = coach
        self.dayType = dayType
        self.infectionLevel = infectionLevel
        self.doneToday = doneToday
    }
}

/// Today's movement so far, from hourly steps (ring and Apple Health, never double counted by the reader).
public enum ActivityStatus: Equatable, Sendable {
    /// No step data for today.
    case unknown
    case active
    /// The last `hours` finished waking hours had fewer than 250 steps each.
    case quiet(hours: Int)
}
