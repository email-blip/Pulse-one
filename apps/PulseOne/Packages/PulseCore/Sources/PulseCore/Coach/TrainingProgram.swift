import Foundation

// Multi-week programs (COACH-ENGINE-SPEC §6.3): 4-week mesocycle, 3 build weeks + 1 lighter week.
// Hard limits the engine enforces and nobody (Claude included) can override:
// - planned weekly load at most +10 % over the previous week (beginners +5 %), except after a lighter week;
// - at most 2 hard sessions in a row and at least 1 rest day per week;
// - the daily time budget is never exceeded; intensity never above the person's cap.

public enum SessionKind: String, Codable, Sendable {
    case main, recovery, rest
}

public struct PlannedSession: Codable, Equatable, Sendable {
    public var kind: SessionKind
    /// nil for rest days and for "no sport" everyday movement.
    public var sport: Sport?
    public var minutes: Int
    public var intensity: Intensity

    public init(kind: SessionKind, sport: Sport?, minutes: Int, intensity: Intensity) {
        self.kind = kind
        self.sport = sport
        self.minutes = minutes
        self.intensity = intensity
    }

    public static let rest = PlannedSession(kind: .rest, sport: nil, minutes: 0, intensity: .recovery)

    /// Planned minutes × planned RPE.
    public var plannedLoad: Double { kind == .rest ? 0 : Double(minutes) * intensity.plannedRPE }

    public var title: String {
        switch kind {
        case .rest: "Ruhetag"
        case .recovery: "Erholung"
        case .main: sport?.title ?? "Alltagsbewegung"
        }
    }

    public var focus: String {
        switch kind {
        case .rest: "Kein Training. Gehen und lockere Bewegung sind willkommen."
        case .recovery: "Lockeres Gehen, Mobilität und Dehnen."
        case .main: sport?.sessionFocus ?? "Zügig gehen, Treppen nehmen, ein paar Kraftübungen mit eigenem Gewicht."
        }
    }
}

public struct WeekPlan: Codable, Equatable, Sendable {
    /// 0-based within the program.
    public let index: Int
    public let isLighter: Bool
    /// Exactly 7 entries, the first is the program's start weekday.
    public var days: [PlannedSession]

    public var plannedLoad: Double { days.map(\.plannedLoad).reduce(0, +) }
    public var trainingDays: Int { days.filter { $0.kind != .rest }.count }

    /// Every session already at 10 minutes and the lowest intensity: nothing left to reduce.
    public var isAtMinimum: Bool {
        days.allSatisfy { $0.kind == .rest || ($0.minutes <= 10 && $0.intensity == .recovery) }
    }
}

public struct TrainingProgram: Codable, Equatable, Sendable {
    /// Start of the first day.
    public let start: Date
    public var weeks: [WeekPlan]

    /// The planned session for `date`, or nil outside the program.
    public func session(on date: Date, calendar: Calendar) -> PlannedSession? {
        guard let position = position(of: date, calendar: calendar) else { return nil }
        return weeks[position.week].days[position.day]
    }

    /// Week and day index of `date`, or nil outside the program.
    public func position(of date: Date, calendar: Calendar) -> (week: Int, day: Int)? {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: date)
        guard let offset = calendar.dateComponents([.day], from: from, to: to).day, offset >= 0 else { return nil }
        let week = offset / 7
        guard week < weeks.count else { return nil }
        return (week, offset % 7)
    }
}

public enum ProgramBuilder {
    public static let buildWeeks = 3

    /// Builds a 4-week program. `recentWeeklyLoad` (4-week mean from the training log) caps the first
    /// week; without history the program starts conservatively.
    public static func build(preferences raw: CoachPreferences, start: Date, recentWeeklyLoad: Double?,
                             calendar: Calendar) -> TrainingProgram {
        let p = raw.sanitized
        let dayStart = calendar.startOfDay(for: start)
        let slots = trainingSlots(count: p.trainingDaysPerWeek)
        let hardSlots = hardSlotIndexes(slots: slots, preferences: p)
        let rise = p.level.maxWeeklyIncrease
        // Week 1 starts below the budget so there is room to build within the time limit.
        let baseFactor = recentWeeklyLoad == nil ? 0.8 : 0.85
        var weeks: [WeekPlan] = []
        var previousLoad: Double?
        for index in 0...buildWeeks {
            let lighter = index == buildWeeks
            let factor = lighter ? baseFactor * 0.65 : baseFactor * pow(1 + rise * 0.9, Double(index))
            var days = Array(repeating: PlannedSession.rest, count: 7)
            for (n, slot) in slots.enumerated() {
                let sport = sportFor(slotNumber: n, preferences: p)
                var intensity: Intensity = hardSlots.contains(n) && index > 0 ? .hard : (n % 2 == 0 ? .moderate : .easy)
                if p.level == .beginner && index == 0 { intensity = min(intensity, .easy) }
                if lighter { intensity = min(intensity, .easy) }
                if sport == nil { intensity = min(intensity, .easy) }
                intensity = min(intensity, p.intensityCap)
                let minutes = clampMinutes(Double(p.minutesPerSession) * factor, budget: p.minutesPerSession)
                days[slot] = PlannedSession(kind: .main, sport: sport, minutes: minutes, intensity: intensity)
            }
            var week = WeekPlan(index: index, isLighter: lighter, days: days)
            // Enforce the rise limit against the previous week (and the history for week 1).
            let reference: Double? = index == 0 ? recentWeeklyLoad : (lighter ? nil : previousLoad)
            if let reference, reference > 0 {
                let cap = reference * (1 + rise)
                week = scaled(week, toAtMost: cap, budget: p.minutesPerSession)
            }
            previousLoad = week.plannedLoad
            weeks.append(week)
        }
        return TrainingProgram(start: dayStart, weeks: weeks)
    }

    /// Spreads `count` training days over 7 so that rest days fall between them where possible.
    public static func trainingSlots(count: Int) -> [Int] {
        switch min(max(count, 0), 6) {
        case 0: []
        case 1: [1]
        case 2: [1, 4]
        case 3: [0, 2, 4]
        case 4: [0, 1, 3, 5]
        case 5: [0, 1, 3, 4, 5]
        default: [0, 1, 2, 3, 4, 5]
        }
    }

    /// Which slot numbers may be hard: 80/20 rule, never two adjacent days.
    static func hardSlotIndexes(slots: [Int], preferences p: CoachPreferences) -> Set<Int> {
        guard slots.count >= 3, p.intensityCap == .hard else { return [] }
        let wanted = (p.level == .trained || p.level == .performance) && slots.count >= 5 ? 2 : 1
        var chosen: [Int] = []
        // Prefer later slots in the week; skip a slot directly after an already hard day.
        for n in stride(from: slots.count - 1, through: 0, by: -1) where chosen.count < wanted {
            let adjacent = chosen.contains { abs(slots[$0] - slots[n]) <= 1 }
            if !adjacent { chosen.append(n) }
        }
        return Set(chosen)
    }

    static func sportFor(slotNumber n: Int, preferences p: CoachPreferences) -> Sport? {
        guard !p.sports.isEmpty else { return nil }
        return p.sports[n % p.sports.count]
    }

    static func clampMinutes(_ value: Double, budget: Int) -> Int {
        min(max(Int(value.rounded()), 10), budget)
    }

    /// Scales minutes down until the week's planned load is at most `cap` (minimum 10 minutes per session).
    static func scaled(_ week: WeekPlan, toAtMost cap: Double, budget: Int) -> WeekPlan {
        guard week.plannedLoad > cap, week.plannedLoad > 0 else { return week }
        let factor = cap / week.plannedLoad
        var result = week
        for i in result.days.indices where result.days[i].kind != .rest {
            let m = Double(result.days[i].minutes) * factor
            result.days[i].minutes = min(max(Int(m.rounded(.down)), 10), budget)
        }
        // At the 10-minute floor the load can still be above the cap: lower intensity until it fits.
        var guardCount = 0
        while result.plannedLoad > cap, guardCount < 24 {
            guard let i = result.days.indices.filter({ result.days[$0].kind != .rest && result.days[$0].intensity > .recovery })
                .max(by: { result.days[$0].intensity < result.days[$1].intensity }) else { break }
            result.days[i].intensity = result.days[i].intensity.lowered()
            guardCount += 1
        }
        return result
    }
}

public enum ProgramRules {
    /// Violations of the hard limits, in German; empty when the program is within limits.
    public static func violations(_ program: TrainingProgram, preferences raw: CoachPreferences,
                                  recentWeeklyLoad: Double?) -> [String] {
        let p = raw.sanitized
        var result: [String] = []
        var previous: (load: Double, lighter: Bool)? = recentWeeklyLoad.map { (load: $0, lighter: false) }
        for week in program.weeks {
            if week.days.count != 7 { result.append("Woche \(week.index + 1) hat nicht 7 Tage.") }
            if week.trainingDays > 6 { result.append("Woche \(week.index + 1) hat keinen Ruhetag.") }
            if let prev = previous, !prev.lighter, prev.load > 0, !week.isLighter,
               week.plannedLoad > prev.load * (1 + p.level.maxWeeklyIncrease) + 0.5, !week.isAtMinimum {
                result.append("Woche \(week.index + 1) steigt stärker als erlaubt.")
            }
            var hardRun = 0
            for day in week.days {
                hardRun = day.intensity == .hard && day.kind == .main ? hardRun + 1 : 0
                if hardRun > 2 { result.append("Woche \(week.index + 1) hat mehr als 2 harte Tage in Folge.") }
                if day.minutes > p.minutesPerSession { result.append("Woche \(week.index + 1) überschreitet das Zeitbudget.") }
                if day.kind != .rest, day.intensity > p.intensityCap {
                    result.append("Woche \(week.index + 1) plant intensiver als erlaubt.")
                }
            }
            previous = (load: week.plannedLoad, lighter: week.isLighter)
        }
        return result
    }
}
