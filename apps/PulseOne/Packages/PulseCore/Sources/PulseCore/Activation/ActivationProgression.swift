import Foundation

// Double progression for the activation ladders (AKTIVIERUNG-KONZEPT §1, Trainingswissenschaft):
// target met → best set up, missed or "zu schwer" → down; at the ladder threshold the next allowed step.

public enum ActivationProgression {
    public static func update(_ profile: ActivationProfile, with result: ActivationResult, coach: CoachPreferences,
                              now: Date) -> ActivationProfile {
        let plan: ActivationPlan = result.plan
        if plan.format == .gentle { return profile }
        var updated: ActivationProfile = profile
        let warmUpIDs: Set<String> = Set(plan.warmUp.map { $0.id })
        for blockResult in result.results {
            if blockResult.done.isEmpty { continue }
            if warmUpIDs.contains(blockResult.blockID) { continue }
            if blockResult.family == .mobility { continue }
            guard let block = plan.blocks.first(where: { $0.id == blockResult.blockID }) else { continue }
            let base: ActivationLevel = baseLevel(blockResult, block: block, profile: updated, coach: coach, now: now)
            let expectedRounds: Int = max(1, block.rounds * max(1, plan.circuitRounds))
            let next: ActivationLevel = step(base, block: block, done: blockResult.done, expectedRounds: expectedRounds,
                                             feedback: result.feedback, coach: coach, now: now)
            updated.levels[blockResult.family] = next
        }
        return updated
    }

    /// A short German line for the end screen, nil when nothing notable changed.
    public static func progressText(_ old: ActivationLevel?, _ new: ActivationLevel) -> String? {
        guard let old else { return nil }
        let name: String = ActivationLibrary.exercise(new.exerciseID)?.name ?? new.exerciseID
        if old.exerciseID != new.exerciseID {
            let ladder: [String] = ActivationLibrary.ladder(new.family)
            let oldIndex: Int = ladder.firstIndex(of: old.exerciseID) ?? -1
            let newIndex: Int = ladder.firstIndex(of: new.exerciseID) ?? -1
            if newIndex > oldIndex { return "Nächste Stufe: \(name)." }
            return "Angepasste Stufe: \(name)."
        }
        if new.best > old.best {
            if ActivationLibrary.isHold(new.exerciseID) {
                return "Neue beste Haltezeit \(name): \(new.best) s."
            }
            return "Neuer bester Satz \(name): \(new.best)."
        }
        return nil
    }

    // MARK: - Internals

    static func targetValue(_ target: ActivationTarget) -> Int {
        switch target {
        case .reps(let reps): return reps
        case .seconds(let seconds): return seconds
        }
    }

    /// The stored level when it matches the exercise that was done, otherwise a level inferred from the target.
    static func baseLevel(_ blockResult: ActivationBlockResult, block: ActivationBlock, profile: ActivationProfile,
                          coach: CoachPreferences, now: Date) -> ActivationLevel {
        if let stored = profile.levels[blockResult.family], stored.exerciseID == blockResult.exerciseID {
            return stored
        }
        let start: ActivationLevel = ActivationLibrary.startLevel(blockResult.family, coach: coach, now: now)
        if start.exerciseID == blockResult.exerciseID { return start }
        let target: Int = targetValue(block.target)
        let inferred: Int = Int((Double(target) / 0.55).rounded())
        let maxDone: Int = blockResult.done.max() ?? 0
        return ActivationLevel(family: blockResult.family, exerciseID: blockResult.exerciseID,
                               best: max(1, max(inferred, maxDone)), updatedAt: now)
    }

    static func step(_ level: ActivationLevel, block: ActivationBlock, done: [Int], expectedRounds: Int,
                     feedback: ActivationFeedback?, coach: CoachPreferences, now: Date) -> ActivationLevel {
        let hold: Bool = ActivationLibrary.isHold(level.exerciseID)
        let target: Int = targetValue(block.target)
        let below: Bool = done.contains { $0 < target } || feedback == .tooHard
        let met: Bool = !below && done.count >= expectedRounds

        var best: Int = level.best
        if met {
            let easy: Bool = feedback == .tooEasy
            if hold {
                best += easy ? 10 : 5
            } else {
                best += easy ? 2 : 1
            }
        } else if below {
            if hold {
                best = max(10, best - 5)
            } else {
                best = max(1, best - 1)
            }
        }
        let maxDone: Int = done.max() ?? 0
        if maxDone > level.best { best = max(best, maxDone) }

        let allowed: [String] = ActivationLibrary.allowedLadder(level.family, coach: coach)
        guard let index = allowed.firstIndex(of: level.exerciseID) else {
            return ActivationLevel(family: level.family, exerciseID: level.exerciseID, best: best, updatedAt: now)
        }
        let threshold: Int = ActivationLibrary.promoteThreshold(level.exerciseID, family: level.family)
        if best >= threshold && index + 1 < allowed.count {
            let nextID: String = allowed[index + 1]
            let nextBest: Int = promotedStart(nextID, family: level.family)
            return ActivationLevel(family: level.family, exerciseID: nextID, best: nextBest, updatedAt: now)
        }
        let tooLow: Bool = hold ? (below && best <= 10) : best < 3
        if tooLow && index > 0 {
            let previousID: String = allowed[index - 1]
            let previousThreshold: Int = ActivationLibrary.promoteThreshold(previousID, family: level.family)
            let previousBest: Int = max(1, Int(Double(previousThreshold) * 0.7))
            return ActivationLevel(family: level.family, exerciseID: previousID, best: previousBest, updatedAt: now)
        }
        return ActivationLevel(family: level.family, exerciseID: level.exerciseID, best: best, updatedAt: now)
    }

    /// Start of a newly reached step: 20 s for holds, otherwise half its own threshold (at least 3).
    static func promotedStart(_ id: String, family: ActivationFamily) -> Int {
        if ActivationLibrary.isHold(id) { return 20 }
        let threshold: Int = ActivationLibrary.promoteThreshold(id, family: family)
        let half: Int = Int(Double(threshold) * 0.5)
        return max(3, half)
    }
}
