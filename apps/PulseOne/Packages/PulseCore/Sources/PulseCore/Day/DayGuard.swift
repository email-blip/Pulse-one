import Foundation

/// How much today may ask of the body, ordered from no limit to no training.
public enum DayLoadLimit: Int, Codable, Sendable, Comparable, CaseIterable {
    /// Plan as usual.
    case full = 0
    /// Lighter: fewer reps, no max tests, no hard intensity.
    case reduced = 1
    /// Only mobility, breathing and easy walking.
    case gentleOnly = 2
    /// No training today.
    case noTraining = 3

    public static func < (lhs: DayLoadLimit, rhs: DayLoadLimit) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Share of the usual training volume that fits the limit (0 = no strength or conditioning work).
    public var volumeFactor: Double {
        switch self {
        case .full: 1
        case .reduced: 0.6
        case .gentleOnly, .noTraining: 0
        }
    }

    public var title: String {
        switch self {
        case .full: "Heute wie geplant"
        case .reduced: "Heute etwas leichter"
        case .gentleOnly: "Heute nur sanfte Bewegung"
        case .noTraining: "Heute kein Training"
        }
    }
}

/// Everything the modules know about today that limits training. Every field is optional, so a module
/// passes what it has; unknown never counts as "all good" or as "stop".
public struct DayGuardInput: Equatable, Sendable {
    /// The coach's decision from the recovery signals, when the coach is set up.
    public var coachDecision: ReadinessDecision?
    /// The person's own check from the last evening review (pain, feeling sick, alarm symptoms).
    public var subjective: SubjectiveCheck?
    /// Permanent limitations from the coach setup.
    public var limitations: Set<BodyRegion>
    /// A health question was answered with yes and no doctor has confirmed yet.
    public var needsMedicalClearance: Bool
    /// The Begleiter's reading of the last night.
    public var companionDayType: CompanionDayType?
    /// The Begleiter's night pattern check.
    public var infectionLevel: InfectionLevel?

    public init(coachDecision: ReadinessDecision? = nil, subjective: SubjectiveCheck? = nil, limitations: Set<BodyRegion> = [],
                needsMedicalClearance: Bool = false, companionDayType: CompanionDayType? = nil,
                infectionLevel: InfectionLevel? = nil) {
        self.coachDecision = coachDecision
        self.subjective = subjective
        self.limitations = limitations
        self.needsMedicalClearance = needsMedicalClearance
        self.companionDayType = companionDayType
        self.infectionLevel = infectionLevel
    }
}

/// One shared answer to "what may today's suggestions ask of me?". Coach, Begleiter, activation sessions and
/// TODAY read the same guard, so no module suggests push-ups the evening after shoulder pain was reported,
/// or strength work while the night pattern check asks for a calm day. The strictest input wins.
public struct DayGuard: Equatable, Sendable {
    public let limit: DayLoadLimit
    /// Regions not to load today: permanent limitations plus pain reported in the last review.
    public let avoidRegions: Set<BodyRegion>
    /// Alarm symptoms were reported: no training and a clear hint to seek medical advice.
    public let seekHelp: Bool
    /// Short German reasons, strictest first, for "Warum?" in the UI.
    public let reasons: [String]

    public init(limit: DayLoadLimit, avoidRegions: Set<BodyRegion> = [], seekHelp: Bool = false, reasons: [String] = []) {
        self.limit = limit
        self.avoidRegions = avoidRegions
        self.seekHelp = seekHelp
        self.reasons = reasons
    }

    /// No limits known.
    public static let open = DayGuard(limit: .full)

    /// Strength and conditioning work is allowed at all (possibly reduced).
    public var allowsStrength: Bool { limit <= .reduced }
    /// Maximum tests and progressions only on unrestricted days.
    public var allowsProgression: Bool { limit == .full }

    /// Whether an exercise fits today: its loaded regions are free and, unless it is gentle mobility,
    /// strength work is allowed.
    public func allows(_ exercise: Exercise) -> Bool {
        guard limit < .noTraining else { return false }
        guard exercise.loads.isDisjoint(with: avoidRegions) else { return false }
        if allowsStrength { return true }
        return DayGuard.gentlePatterns.contains(exercise.pattern) && exercise.difficulty <= 1
    }

    /// Movement patterns that count as gentle movement on restricted days (not on days without training).
    static let gentlePatterns: Set<MovementPattern> = [.mobility, .breathing]

    public static func evaluate(_ input: DayGuardInput) -> DayGuard {
        var limit = DayLoadLimit.full
        var reasons: [(DayLoadLimit, String)] = []
        var seekHelp = false

        func raise(_ to: DayLoadLimit, _ reason: String) {
            limit = max(limit, to)
            reasons.append((to, reason))
        }

        let subjective = input.subjective
        if subjective?.alarmSymptoms == true || input.coachDecision == .seekHelp {
            seekHelp = true
            raise(.noTraining, "Du hast Beschwerden bei Belastung angegeben. Bitte ärztlich abklären, bei akuten Beschwerden Notruf 112.")
        }
        if subjective?.feelsSick == true || input.coachDecision == .rest {
            raise(.noTraining, "Du fühlst dich krank. Heute zählt Erholung.")
        }
        if let level = input.infectionLevel {
            if level >= .clarify {
                raise(.noTraining, "Deine Nachtwerte weichen seit mehreren Nächten deutlich ab. Heute lieber Ruhe.")
            } else if level == .pattern {
                raise(.gentleOnly, "Deine Nachtwerte zeigen ein auffälliges Muster. Heute nur sanfte Bewegung.")
            }
        }
        if input.companionDayType == .unusualPattern {
            raise(.gentleOnly, "Der Begleiter sieht heute ein auffälliges Muster in der Nacht.")
        }
        if input.coachDecision == .easyOrRecovery {
            raise(.gentleOnly, "Mehrere Erholungssignale sind heute auffällig.")
        }
        if input.coachDecision == .offerLighter {
            raise(.reduced, "Ein Erholungssignal ist heute auffällig.")
        }
        if input.companionDayType == .shortNight {
            raise(.reduced, "Die Nacht war kurz.")
        }
        if let soreness = subjective?.soreness, soreness >= 7 {
            raise(.reduced, "Du hast starken Muskelkater angegeben.")
        }
        if input.needsMedicalClearance {
            raise(.reduced, "Bis zur ärztlichen Freigabe bleibt es leicht.")
        }

        let pain = subjective?.painRegions ?? []
        if !pain.isEmpty {
            let names = pain.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")
            reasons.append((.full, "Übungen für \(names) lässt du heute aus, weil du dort Schmerzen angegeben hast."))
        }
        let ordered = reasons.enumerated()
            .sorted { $0.element.0 != $1.element.0 ? $0.element.0 > $1.element.0 : $0.offset < $1.offset }
            .map(\.element.1)
        return DayGuard(limit: limit, avoidRegions: input.limitations.union(pain), seekHelp: seekHelp, reasons: ordered)
    }
}
