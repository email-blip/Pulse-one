import Foundation

// Recovery signals without a total score (COACH-ENGINE-SPEC §6.2). Each signal is compared with the
// person's own 30-day band; too little data means "unknown", never "good".

public enum SignalState: String, Codable, Sendable {
    /// Outside the personal band in the way the rule describes.
    case notable
    /// Inside the usual band.
    case usual
    /// Too little data to say.
    case unknown
}

public enum RecoverySignalKind: String, Codable, CaseIterable, Sendable {
    case restingHeartRate, heartRateVariability, sleep, subjective

    public var title: String {
        switch self {
        case .restingHeartRate: "Ruhepuls"
        case .heartRateVariability: "HRV"
        case .sleep: "Schlaf"
        case .subjective: "Dein Empfinden"
        }
    }
}

public struct RecoverySignal: Equatable, Sendable, Identifiable {
    public var id: RecoverySignalKind { kind }
    public let kind: RecoverySignalKind
    public let state: SignalState
    /// Descriptive German sentence; no cause, no diagnosis.
    public let text: String
}

/// One value per calendar day (built from `DailySeries` in the app).
public struct DayValue: Equatable, Sendable {
    public let day: Date
    public let value: Double
    public init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

/// What the person reported, usually in the evening review.
public struct SubjectiveCheck: Codable, Equatable, Sendable {
    /// Muscle soreness 0…10.
    public var soreness: Int?
    public var painRegions: Set<BodyRegion>
    public var feelsSick: Bool
    /// Chest pain, shortness of breath, fainting or dizziness during exertion.
    public var alarmSymptoms: Bool

    public init(soreness: Int? = nil, painRegions: Set<BodyRegion> = [], feelsSick: Bool = false, alarmSymptoms: Bool = false) {
        self.soreness = soreness
        self.painRegions = painRegions
        self.feelsSick = feelsSick
        self.alarmSymptoms = alarmSymptoms
    }
}

/// Personal band from a 30-day window: p25…p75 plus half the interquartile range on each side.
public struct RecoveryBand: Equatable, Sendable {
    public let median: Double
    public let p25: Double
    public let p75: Double
    public let dayCount: Int
    public var iqr: Double { p75 - p25 }
    public var upperLimit: Double { p75 + 0.5 * iqr }
    public var lowerLimit: Double { p25 - 0.5 * iqr }

    /// nil when fewer than `minimumDays` values exist (coverage below 50 % of the window).
    public static func make(_ values: [Double], minimumDays: Int = 15) -> RecoveryBand? {
        guard values.count >= minimumDays else { return nil }
        let sorted = values.sorted()
        return RecoveryBand(median: percentile(sorted, 0.5), p25: percentile(sorted, 0.25), p75: percentile(sorted, 0.75),
                            dayCount: sorted.count)
    }

    /// Linear interpolation between closest ranks; `sorted` must be ascending and non-empty.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }
}

public enum RecoveryAssessment {
    /// Days that count as "recent" (today and the two days before).
    static let recentDays = 3
    /// Length of the comparison window before the recent days.
    static let windowDays = 30

    /// All four signals for `today`. Values must be one per day; sleep in seconds.
    public static func assess(restingHeartRate: [DayValue], heartRateVariability: [DayValue], sleep: [DayValue],
                              subjective: SubjectiveCheck?, today: Date, calendar: Calendar) -> [RecoverySignal] {
        [
            restingHR(restingHeartRate, today: today, calendar: calendar),
            hrv(heartRateVariability, today: today, calendar: calendar),
            sleepSignal(sleep, today: today, calendar: calendar),
            subjectiveSignal(subjective)
        ]
    }

    /// Splits values into the recent days and the comparison window before them.
    static func split(_ values: [DayValue], today: Date, calendar: Calendar) -> (recent: [DayValue], window: [Double]) {
        let todayStart = calendar.startOfDay(for: today)
        guard let recentStart = calendar.date(byAdding: .day, value: -(recentDays - 1), to: todayStart),
              let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: recentStart),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return ([], []) }
        let recent = values.filter { $0.day >= recentStart && $0.day < tomorrow }.sorted { $0.day < $1.day }
        let window = values.filter { $0.day >= windowStart && $0.day < recentStart }.map(\.value)
        return (recent, window)
    }

    static func restingHR(_ values: [DayValue], today: Date, calendar: Calendar) -> RecoverySignal {
        let (recent, window) = split(values, today: today, calendar: calendar)
        guard let band = RecoveryBand.make(window), recent.count >= 2 else {
            return RecoverySignal(kind: .restingHeartRate, state: .unknown,
                                  text: "Noch zu wenige Ruhepuls-Tage für deinen üblichen Bereich (\(window.count) von 15).")
        }
        let above = recent.filter { $0.value > band.upperLimit }.count
        if above >= 2 {
            return RecoverySignal(kind: .restingHeartRate, state: .notable,
                                  text: "Dein Ruhepuls liegt an \(above) der letzten \(recent.count) Tage über deinem üblichen Bereich "
                                      + "(bis \(Int(band.upperLimit.rounded())) bpm).")
        }
        return RecoverySignal(kind: .restingHeartRate, state: .usual,
                              text: "Dein Ruhepuls liegt in deinem üblichen Bereich (um \(Int(band.median.rounded())) bpm).")
    }

    static func hrv(_ values: [DayValue], today: Date, calendar: Calendar) -> RecoverySignal {
        let (recent, window) = split(values, today: today, calendar: calendar)
        guard let band = RecoveryBand.make(window), recent.count >= 2 else {
            return RecoverySignal(kind: .heartRateVariability, state: .unknown,
                                  text: "Noch zu wenige HRV-Tage für deinen üblichen Bereich (\(window.count) von 15).")
        }
        let below = recent.filter { $0.value < band.lowerLimit }.count
        if below >= 2 {
            return RecoverySignal(kind: .heartRateVariability, state: .notable,
                                  text: "Deine HRV liegt an \(below) der letzten \(recent.count) Tage unter deinem üblichen Bereich "
                                      + "(ab \(Int(band.lowerLimit.rounded())) ms).")
        }
        return RecoverySignal(kind: .heartRateVariability, state: .usual,
                              text: "Deine HRV liegt in deinem üblichen Bereich (um \(Int(band.median.rounded())) ms).")
    }

    static func sleepSignal(_ values: [DayValue], today: Date, calendar: Calendar) -> RecoverySignal {
        let (recent, window) = split(values, today: today, calendar: calendar)
        guard let band = RecoveryBand.make(window), recent.count >= 2 else {
            return RecoverySignal(kind: .sleep, state: .unknown,
                                  text: "Noch zu wenige Nächte für deine übliche Schlafdauer (\(window.count) von 15).")
        }
        let short = recent.filter { $0.value < band.median - 3_600 }.count
        if short >= 2 {
            return RecoverySignal(kind: .sleep, state: .notable,
                                  text: "Du hast in \(short) der letzten \(recent.count) Nächte mindestens eine Stunde kürzer geschlafen "
                                      + "als üblich (\(hoursText(band.median))).")
        }
        return RecoverySignal(kind: .sleep, state: .usual,
                              text: "Deine Schlafdauer liegt im üblichen Rahmen (um \(hoursText(band.median))).")
    }

    static func subjectiveSignal(_ check: SubjectiveCheck?) -> RecoverySignal {
        guard let check else {
            return RecoverySignal(kind: .subjective, state: .unknown, text: "Noch kein Rückblick von dir für gestern.")
        }
        if check.alarmSymptoms {
            return RecoverySignal(kind: .subjective, state: .notable, text: "Du hast Beschwerden bei Belastung angegeben.")
        }
        if check.feelsSick {
            return RecoverySignal(kind: .subjective, state: .notable, text: "Du fühlst dich krank.")
        }
        if !check.painRegions.isEmpty {
            let regions = check.painRegions.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")
            return RecoverySignal(kind: .subjective, state: .notable, text: "Du hast Schmerzen angegeben: \(regions).")
        }
        if let soreness = check.soreness, soreness >= 7 {
            return RecoverySignal(kind: .subjective, state: .notable, text: "Du hast starken Muskelkater angegeben (\(soreness) von 10).")
        }
        return RecoverySignal(kind: .subjective, state: .usual, text: "Du hast dich im Rückblick gut gefühlt.")
    }

    static func hoursText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }
}

/// What the engine does with the signals (spec §6.2). Ordered from mildest to strongest.
public enum ReadinessDecision: Equatable, Sendable {
    case asPlanned
    /// One signal: offer one step lower; the person decides.
    case offerLighter
    /// Two or more signals: main activity easy or a recovery session.
    case easyOrRecovery
    /// Feeling sick: no training today.
    case rest
    /// Alarm symptoms: no training, seek medical help.
    case seekHelp

    public var title: String {
        switch self {
        case .asPlanned: "Plan wie vorgesehen"
        case .offerLighter: "Eine Stufe leichter möglich"
        case .easyOrRecovery: "Heute locker oder Erholung"
        case .rest: "Heute kein Training"
        case .seekHelp: "Heute kein Training – bitte abklären"
        }
    }

    public var explanation: String {
        switch self {
        case .asPlanned:
            "Kein Signal liegt außerhalb deines üblichen Bereichs."
        case .offerLighter:
            "Ein Signal liegt außerhalb deines üblichen Bereichs. Du kannst die Einheit eine Stufe leichter machen; du entscheidest."
        case .easyOrRecovery:
            "Mehrere Signale liegen außerhalb deines üblichen Bereichs. Der Coach schlägt heute eine lockere Einheit oder Erholung vor."
        case .rest:
            "Wenn du dich krank fühlst, pausiert der Coach das Training. Ruhige Bewegung nur, wenn sie angenehm ist."
        case .seekHelp:
            "Brustschmerz, Atemnot, Schwindel oder Ohnmacht bei Belastung sollten ärztlich abgeklärt werden. "
                + "Bei akuten Beschwerden sofort den Notruf 112 wählen."
        }
    }
}

public enum CoachRules {
    /// Turns signals into the day's decision. Unknown signals count neither for nor against training.
    public static func decide(signals: [RecoverySignal], subjective: SubjectiveCheck?) -> ReadinessDecision {
        if subjective?.alarmSymptoms == true { return .seekHelp }
        if subjective?.feelsSick == true { return .rest }
        let notable = signals.filter { $0.state == .notable }.count
        switch notable {
        case 0: return .asPlanned
        case 1: return .offerLighter
        default: return .easyOrRecovery
        }
    }

    /// A note when most signals are unknown, so a plain plan is not read as "everything is fine".
    public static func coverageNote(_ signals: [RecoverySignal]) -> String? {
        let measured = signals.filter { $0.kind != .subjective }
        let unknown = measured.filter { $0.state == .unknown }.count
        guard unknown > 0 else { return nil }
        return "\(unknown) von \(measured.count) Messsignalen sind noch unbekannt. Der Plan stützt sich deshalb vor allem auf deinen Rückblick."
    }
}
