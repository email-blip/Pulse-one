import Foundation

// Begleiter "Aktivierung": plans one short bodyweight session for a slot (AKTIVIERUNG-KONZEPT §3).
// Pure and deterministic: no randomness, rotation by day index.
//
// Block semantics:
// - `circuit`: `plan.circuitRounds` rounds of all blocks; every block has `rounds == 1`; the last block
//   carries the rest between circuit rounds in `restSeconds`, the others 0.
// - `gentle`: mobility and breathing blocks, one round each, no rest, `circuitRounds == 1`.
// A small set-up allowance of 5 s per block and round is part of `estimatedSeconds`.

public enum ActivationPlanner {
    /// Seconds of set-up per block and round (getting into position, tapping "Geschafft").
    static let transitionSeconds: Int = 5
    static let snackSeconds: Int = 150

    public static func plan(_ input: ActivationInput) -> ActivationPlan {
        let stamp: String = dayStamp(input.now, calendar: input.calendar)
        let ready: ActivationReadiness = readiness(dayType: input.dayType, infectionLevel: input.infectionLevel)
        var budget: Int = budgetSeconds(slot: input.slot, settings: input.settings)
        let eveningShortened: Bool = input.slot == .evening && input.doneToday.count >= 2
        if eveningShortened {
            let reduced: Int = Int(Double(budget) * 0.7)
            budget = max(180, reduced)
        }
        if ready == .gentle {
            return gentlePlan(input, stamp: stamp, readiness: ready, budget: budget,
                              reason: "Deine Nachtwerte weichen heute ab: heute nur sanft bewegen.")
        }
        let factor: Double = readinessFactor(input.dayType)
        let dayIndex: Int = input.calendar.ordinality(of: .day, in: .era, for: input.now) ?? 0
        let families: [ActivationFamily] = slotFamilies(input.slot, dayIndex: dayIndex)

        let warmUp: [ActivationBlock] = input.slot == .morning ? warmUpBlocks(input) : []
        var warmUpSeconds: Int = 0
        for block in warmUp { warmUpSeconds += plainSeconds(block.target) }

        let isSnack: Bool = input.slot == .snack
        let rest: Int
        if isSnack {
            rest = 0
        } else if input.slot == .morning && budget >= 600 {
            rest = 45
        } else {
            rest = 30
        }
        let available: Int = max(60, budget - warmUpSeconds)
        let limit: Double = Double(budget) * 1.1

        var scale: Double = 1.0
        var picks: [Pick] = []
        var rounds: Int = 1
        var total: Int = warmUpSeconds
        for _ in 0..<8 {
            picks = makePicks(families, input: input, factor: factor * scale, dayIndex: dayIndex)
            var work: Int = 0
            for pick in picks { work += workSeconds(pick) }
            if isSnack {
                rounds = 1
            } else {
                let fit: Int = (available + rest) / max(1, work + rest)
                rounds = min(5, max(2, fit))
            }
            total = warmUpSeconds + rounds * work + (rounds - 1) * rest
            if Double(total) <= limit { break }
            scale *= 0.8
        }

        if picks.isEmpty {
            return gentlePlan(input, stamp: stamp, readiness: ready, budget: budget,
                              reason: "Heute nur Beweglichkeit, passend zu deinen Angaben.")
        }

        var blocks: [ActivationBlock] = []
        for (index, pick) in picks.enumerated() {
            let isLast: Bool = index == picks.count - 1
            let blockRest: Int = isLast && rounds > 1 ? rest : 0
            let block = ActivationBlock(id: "\(input.slot.rawValue).\(index).\(pick.exerciseID)",
                                        exerciseID: pick.exerciseID, family: pick.family, target: pick.target,
                                        rounds: 1, restSeconds: blockRest)
            blocks.append(block)
        }

        let reason: String = reasonText(slot: input.slot, dayType: input.dayType, readiness: ready,
                                        eveningShortened: eveningShortened)
        let summary: String = ActivationText.summary(blocks: blocks, rounds: rounds, seconds: total, gentle: false)
        return ActivationPlan(slot: input.slot, dayStamp: stamp, format: .circuit, readiness: ready, warmUp: warmUp,
                              blocks: blocks, circuitRounds: rounds, estimatedSeconds: total, reason: reason,
                              summary: summary)
    }

    public static func readiness(dayType: CompanionDayType, infectionLevel: InfectionLevel) -> ActivationReadiness {
        if dayType == .unusualPattern || infectionLevel >= .pattern { return .gentle }
        switch dayType {
        case .shortNight, .notEnoughData: return .reduced
        case .recovered, .normal, .unusualPattern: return .full
        }
    }

    /// yyyyMMdd in the given calendar.
    public static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let parts: DateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let year: Int = parts.year ?? 0
        let month: Int = parts.month ?? 0
        let day: Int = parts.day ?? 0
        return String(format: "%04d%02d%02d", year, month, day)
    }

    /// Time budget of a slot before the evening shortening.
    public static func budgetSeconds(slot: ActivationSlot, settings: ActivationSettings) -> Int {
        switch slot {
        case .morning:
            let minutes: Int = clamp(settings.morningMinutes, ActivationSettings.morningRange)
            return minutes * 60
        case .midday, .evening:
            let minutes: Int = clamp(settings.shortMinutes, ActivationSettings.shortRange)
            return minutes * 60
        case .snack:
            return snackSeconds
        }
    }

    // MARK: - Internals

    struct Pick: Equatable {
        let family: ActivationFamily
        let exerciseID: String
        let target: ActivationTarget
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func readinessFactor(_ dayType: CompanionDayType) -> Double {
        switch dayType {
        case .shortNight: 0.7
        case .notEnoughData: 0.9
        case .recovered, .normal, .unusualPattern: 1.0
        }
    }

    static func slotFamilies(_ slot: ActivationSlot, dayIndex: Int) -> [ActivationFamily] {
        switch slot {
        case .morning:
            let accessory: ActivationFamily = dayIndex % 2 == 0 ? .legs : .cardio
            return [.push, .core, .pull, accessory]
        case .midday:
            return [.legs, .cardio, .push]
        case .evening:
            return [.core, .pull, .mobility]
        case .snack:
            return [.cardio, .legs]
        }
    }

    /// The person's level for a family if it is still allowed, otherwise the start level.
    static func currentLevel(_ family: ActivationFamily, input: ActivationInput) -> ActivationLevel? {
        let allowed: [String] = ActivationLibrary.allowedLadder(family, coach: input.coach)
        if allowed.isEmpty { return nil }
        if let stored = input.profile.levels[family], allowed.contains(stored.exerciseID) {
            return stored
        }
        let start: ActivationLevel = ActivationLibrary.startLevel(family, coach: input.coach, now: input.now)
        return allowed.contains(start.exerciseID) ? start : nil
    }

    static func makePicks(_ families: [ActivationFamily], input: ActivationInput, factor: Double,
                          dayIndex: Int) -> [Pick] {
        var picks: [Pick] = []
        for family in families {
            if family == .mobility {
                if let id = mobilityPick(input.coach, dayIndex: dayIndex) {
                    picks.append(Pick(family: .mobility, exerciseID: id, target: .seconds(30)))
                }
                continue
            }
            guard let level = currentLevel(family, input: input) else { continue }
            let target: ActivationTarget = targetFor(level, factor: factor)
            picks.append(Pick(family: family, exerciseID: level.exerciseID, target: target))
        }
        return picks
    }

    static func mobilityPick(_ coach: CoachPreferences, dayIndex: Int) -> String? {
        let allowed: [String] = ActivationLibrary.allowedLadder(.mobility, coach: coach)
        let moving: [String] = allowed.filter { $0 != "breathing-box" }
        let pool: [String] = moving.isEmpty ? allowed : moving
        if pool.isEmpty { return nil }
        let index: Int = abs(dayIndex) % pool.count
        return pool[index]
    }

    /// About 55 % of the best clean set, scaled by readiness. Holds in 5 s steps, at least 10 s.
    static func targetFor(_ level: ActivationLevel, factor: Double) -> ActivationTarget {
        let raw: Double = Double(level.best) * 0.55 * factor
        if ActivationLibrary.isHold(level.exerciseID) {
            let steps: Double = (raw / 5.0).rounded()
            let seconds: Int = max(10, Int(steps) * 5)
            return .seconds(seconds)
        }
        let reps: Int = max(1, Int(raw.rounded()))
        return .reps(reps)
    }

    static func perRepSeconds(_ family: ActivationFamily) -> Double {
        switch family {
        case .push: 2.5
        case .pull: 4.0
        case .legs: 2.5
        case .cardio: 1.0
        case .core: 2.5
        case .mobility: 1.0
        }
    }

    static func plainSeconds(_ target: ActivationTarget) -> Int {
        switch target {
        case .seconds(let seconds): return seconds
        case .reps(let reps): return reps
        }
    }

    static func workSeconds(_ pick: Pick) -> Int {
        let base: Int
        switch pick.target {
        case .seconds(let seconds):
            base = seconds
        case .reps(let reps):
            let raw: Double = Double(reps) * perRepSeconds(pick.family)
            base = Int(raw.rounded(.up))
        }
        return base + transitionSeconds
    }

    /// One minute: arm and hip circles (whatever the limitations allow), otherwise marching.
    static func warmUpBlocks(_ input: ActivationInput) -> [ActivationBlock] {
        var ids: [String] = []
        for id in ["arm-circles", "hip-circles"] {
            if let exercise = ActivationLibrary.exercise(id), ActivationLibrary.isAllowed(exercise, coach: input.coach) {
                ids.append(id)
            }
        }
        if ids.isEmpty { ids = ["marching"] }
        let each: Int = 60 / ids.count
        var blocks: [ActivationBlock] = []
        for (index, id) in ids.enumerated() {
            let family: ActivationFamily = id == "marching" ? .cardio : .mobility
            blocks.append(ActivationBlock(id: "\(input.slot.rawValue).w\(index).\(id)", exerciseID: id, family: family,
                                          target: .seconds(each), rounds: 1, restSeconds: 0))
        }
        return blocks
    }

    static func gentlePlan(_ input: ActivationInput, stamp: String, readiness: ActivationReadiness, budget: Int,
                           reason: String) -> ActivationPlan {
        var ids: [String] = ActivationLibrary.allowedLadder(.mobility, coach: input.coach)
        if ids.isEmpty { ids = ["breathing-box"] }
        let count: Int = ids.count
        let usable: Int = budget - transitionSeconds * count
        let raw: Int = usable / max(1, count)
        let rounded: Int = (raw / 5) * 5
        let each: Int = min(120, max(20, rounded))
        var blocks: [ActivationBlock] = []
        var total: Int = 0
        for (index, id) in ids.enumerated() {
            blocks.append(ActivationBlock(id: "\(input.slot.rawValue).\(index).\(id)", exerciseID: id, family: .mobility,
                                          target: .seconds(each), rounds: 1, restSeconds: 0))
            total += each + transitionSeconds
        }
        let summary: String = ActivationText.summary(blocks: blocks, rounds: 1, seconds: total, gentle: true)
        return ActivationPlan(slot: input.slot, dayStamp: stamp, format: .gentle, readiness: readiness, warmUp: [],
                              blocks: blocks, circuitRounds: 1, estimatedSeconds: total, reason: reason,
                              summary: summary)
    }

    static func reasonText(slot: ActivationSlot, dayType: CompanionDayType, readiness: ActivationReadiness,
                           eveningShortened: Bool) -> String {
        if dayType == .shortNight { return "Kurze Nacht: heute etwas weniger." }
        if dayType == .notEnoughData { return "Noch wenige Nachtwerte: heute etwas vorsichtiger dosiert." }
        if eveningShortened { return "Heute schon viel bewegt: abends etwas kürzer." }
        if slot == .snack { return "Eine Weile wenig Bewegung: kurz den Kreislauf in Schwung bringen." }
        if dayType == .recovered { return "Erholte Nacht hinter dir: volle Runde." }
        if slot == .morning { return "Normaler Start in den Tag: volle Runde." }
        return "Dein Tag läuft normal: volle Runde."
    }
}
