import Foundation

// PULSE COACH core types (COACH-ENGINE-SPEC §2–§4, SPORT-UND-ALLTAG §1–§3).
// Sport-neutral: every preference is optional and "no sport" is a full profile, not an incomplete one.

/// A sport module the person can choose. None is preset; riding is an optional module only.
public enum Sport: String, Codable, CaseIterable, Sendable, Identifiable {
    case running
    case cycling
    case strength
    case bodyweight
    case rowing
    case football
    case hiking
    case mobility
    case endurance
    case riding

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .running: "Laufen"
        case .cycling: "Radfahren"
        case .strength: "Krafttraining"
        case .bodyweight: "Training mit Körpergewicht"
        case .rowing: "Rudern"
        case .football: "Fußball / Teamsport"
        case .hiking: "Wandern / Outdoor"
        case .mobility: "Beweglichkeit"
        case .endurance: "Gehen, Schwimmen, Crosstrainer"
        case .riding: "Reiten"
        }
    }

    /// SF Symbol available since iOS 17.
    public var symbol: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .strength: "dumbbell"
        case .bodyweight: "figure.strengthtraining.functional"
        case .rowing: "figure.rower"
        case .football: "figure.soccer"
        case .hiking: "figure.hiking"
        case .mobility: "figure.flexibility"
        case .endurance: "figure.walk"
        case .riding: "figure.equestrian.sports"
        }
    }

    /// Shown in the choice list only when the person asks for more modules (SPORT-UND-ALLTAG §1.2).
    public var isOptionalModule: Bool { self == .riding }

    /// Sports where a session is mostly sets and repetitions, not continuous duration.
    public var isStrengthBased: Bool { self == .strength || self == .bodyweight }

    /// Fits a recovery or easy day without changing the sport.
    public var allowsEasyVariant: Bool { self != .football }

    /// What a session of this sport is in the plan, in one line.
    public var sessionFocus: String {
        switch self {
        case .running: "Lauf nach Gefühl, Tempo über die Anstrengung steuern"
        case .cycling: "Ausfahrt oder Ergometer, gleichmäßig treten"
        case .strength: "Ganzkörper-Kraft: Kniebeuge, Drücken, Ziehen, Hüfte, Rumpf"
        case .bodyweight: "Bewegungsmuster mit eigenem Gewicht, Stufe nach Können"
        case .rowing: "Technik zuerst, dann gleichmäßige Abschnitte"
        case .football: "Training oder Spiel, dazu Vorbeugeübungen"
        case .hiking: "Wanderung oder zügiges Gehen draußen"
        case .mobility: "Gelenke der Reihe nach bewegen, ruhig halten"
        case .endurance: "gleichmäßige Ausdauer in lockerem Tempo"
        case .riding: "Reiteinheit, dazu Rumpf und Hüftbeweglichkeit"
        }
    }
}

public enum FitnessLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case beginner, active, trained, performance
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .beginner: "Einsteiger"
        case .active: "regelmäßig aktiv"
        case .trained: "trainiert"
        case .performance: "leistungsorientiert"
        }
    }
    /// Highest allowed week-to-week rise of the planned load (spec §6.3).
    public var maxWeeklyIncrease: Double { self == .beginner ? 0.05 : 0.10 }
}

/// How firmly the coach pushes. Changes progression speed and wording, never the hard limits.
public enum CoachingStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case calm, balanced, demanding
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .calm: "ruhig"
        case .balanced: "ausgewogen"
        case .demanding: "fordernd"
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Sendable, Identifiable {
    case mat, dumbbells, kettlebell, barbell, pullUpBar, bands, rower, bike
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mat: "Matte"
        case .dumbbells: "Kurzhanteln"
        case .kettlebell: "Kettlebell"
        case .barbell: "Langhantel"
        case .pullUpBar: "Klimmzugstange"
        case .bands: "Widerstandsbänder"
        case .rower: "Rudergerät"
        case .bike: "Fahrrad / Ergometer"
        }
    }
}

/// Body regions for limitations; an exercise that loads a limited region is excluded (hard rule).
public enum BodyRegion: String, Codable, CaseIterable, Sendable, Identifiable {
    case neck, shoulder, elbowWrist, back, hip, knee, ankleFoot
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .neck: "Nacken"
        case .shoulder: "Schulter"
        case .elbowWrist: "Ellbogen / Handgelenk"
        case .back: "Rücken"
        case .hip: "Hüfte"
        case .knee: "Knie"
        case .ankleFoot: "Sprunggelenk / Fuß"
        }
    }
}

/// The five optional building blocks of a day (spec §3).
public enum DayBlockKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case activation, mainWorkout, movementSnack, recovery, eveningReview
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .activation: "Aktivierung am Morgen"
        case .mainWorkout: "Haupteinheit"
        case .movementSnack: "Bewegungspause"
        case .recovery: "Erholung"
        case .eveningReview: "Abendrückblick"
        }
    }
    public var symbol: String {
        switch self {
        case .activation: "sunrise"
        case .mainWorkout: "flame"
        case .movementSnack: "figure.walk"
        case .recovery: "leaf"
        case .eveningReview: "moon.stars"
        }
    }
}

/// Planned effort, expressed on the CR-10 scale (session RPE). No heart rate zones until a reliable
/// training pulse source exists (spec §4).
public enum Intensity: Int, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case recovery = 1, easy, moderate, hard
    public var id: Int { rawValue }
    public static func < (a: Intensity, b: Intensity) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .recovery: "sehr locker"
        case .easy: "locker"
        case .moderate: "mittel"
        case .hard: "fordernd"
        }
    }
    /// Target range on the CR-10 scale.
    public var targetRPE: ClosedRange<Int> {
        switch self {
        case .recovery: 1...2
        case .easy: 3...4
        case .moderate: 5...6
        case .hard: 7...8
        }
    }
    /// Midpoint used to estimate planned load (minutes × RPE).
    public var plannedRPE: Double { Double(targetRPE.lowerBound + targetRPE.upperBound) / 2 }
    /// How it feels, so the person can steer without a pulse strap.
    public var feeling: String {
        switch self {
        case .recovery: "Du kannst dich mühelos unterhalten."
        case .easy: "Unterhalten geht noch gut, du atmest etwas tiefer."
        case .moderate: "Kurze Sätze gehen, ganze Unterhaltung nicht mehr."
        case .hard: "Nur noch einzelne Worte, gut kontrolliert."
        }
    }
    public func lowered() -> Intensity { Intensity(rawValue: max(rawValue - 1, Intensity.recovery.rawValue)) ?? .recovery }
    public func raised() -> Intensity { Intensity(rawValue: min(rawValue + 1, Intensity.hard.rawValue)) ?? .hard }
}

/// What the person told the coach. Every field is optional in practice; defaults are neutral.
public struct CoachPreferences: Codable, Equatable, Sendable {
    /// Empty = no sport goal: the plan covers everyday movement, mobility and recovery only.
    public var sports: [Sport]
    /// 0…6; at least one rest day per week is a hard rule.
    public var trainingDaysPerWeek: Int
    /// Upper time budget of a main session; never exceeded.
    public var minutesPerSession: Int
    public var level: FitnessLevel
    public var style: CoachingStyle
    public var equipment: Set<Equipment>
    public var limitations: Set<BodyRegion>
    /// One of the health questions was answered with yes: only light intensity until a doctor confirmed.
    public var needsMedicalClearance: Bool
    /// Blocks the person wants to see.
    public var enabledBlocks: Set<DayBlockKind>
    /// Waking window for movement snacks, in hours of the day.
    public var wakeHours: ClosedRange<Int>

    public init(sports: [Sport] = [], trainingDaysPerWeek: Int = 3, minutesPerSession: Int = 30,
                level: FitnessLevel = .active, style: CoachingStyle = .balanced, equipment: Set<Equipment> = [],
                limitations: Set<BodyRegion> = [], needsMedicalClearance: Bool = false,
                enabledBlocks: Set<DayBlockKind> = Set(DayBlockKind.allCases), wakeHours: ClosedRange<Int> = 7...21) {
        self.sports = sports
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.minutesPerSession = minutesPerSession
        self.level = level
        self.style = style
        self.equipment = equipment
        self.limitations = limitations
        self.needsMedicalClearance = needsMedicalClearance
        self.enabledBlocks = enabledBlocks
        self.wakeHours = wakeHours
    }

    /// Values clamped to the hard limits of the engine.
    public var sanitized: CoachPreferences {
        var p = self
        p.trainingDaysPerWeek = min(max(p.trainingDaysPerWeek, 0), 6)
        p.minutesPerSession = min(max(p.minutesPerSession, 10), 120)
        var seen = Set<Sport>()
        p.sports = p.sports.filter { seen.insert($0).inserted }
        return p
    }

    /// Highest intensity the engine may plan for this person.
    public var intensityCap: Intensity {
        if needsMedicalClearance { return .easy }
        return level == .beginner ? .moderate : .hard
    }
}
