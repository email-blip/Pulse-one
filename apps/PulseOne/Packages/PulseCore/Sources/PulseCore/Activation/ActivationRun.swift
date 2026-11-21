import Foundation

// Order of a guided activation session: which exercise comes when, which round it is and how long to rest
// afterwards. Pure functions so the app's session view only walks through the list (team A, AKTIVIERUNG-KONZEPT.md).

/// One step of a guided session: one round (or set) of one block.
public struct ActivationRunStep: Equatable, Sendable, Identifiable {
    /// Position in the run, 0-based.
    public let id: Int
    public let block: ActivationBlock
    /// Warm-up steps are shown but never counted for progression.
    public let isWarmUp: Bool
    /// 1-based round of this step (circuit round for `circuit`, set number otherwise).
    public let round: Int
    public let roundCount: Int
    /// Rest after this step in seconds; 0 after the last step.
    public let restAfter: Int

    public init(id: Int, block: ActivationBlock, isWarmUp: Bool, round: Int, roundCount: Int, restAfter: Int) {
        self.id = id
        self.block = block
        self.isWarmUp = isWarmUp
        self.round = round
        self.roundCount = roundCount
        self.restAfter = restAfter
    }

    /// Target of the step as a plain number (reps or seconds).
    public var targetValue: Int { ActivationRun.value(of: block.target) }

    public var isHold: Bool {
        if case .seconds = block.target { return true }
        return false
    }
}

public enum ActivationRun {
    /// Reps or seconds of a target.
    public static func value(of target: ActivationTarget) -> Int {
        switch target {
        case .reps(let reps): max(reps, 0)
        case .seconds(let seconds): max(seconds, 0)
        }
    }

    /// Warm-up blocks (each round once), then the main blocks: a circuit repeats all blocks `circuitRounds`
    /// times; `sets` and `gentle` run each block's rounds before the next block.
    public static func steps(for plan: ActivationPlan) -> [ActivationRunStep] {
        var raw: [(block: ActivationBlock, warmUp: Bool, round: Int, count: Int)] = []
        for block in plan.warmUp {
            let rounds = max(block.rounds, 1)
            for round in 1...rounds { raw.append((block: block, warmUp: true, round: round, count: rounds)) }
        }
        if plan.format == .circuit {
            let circuit = max(plan.circuitRounds, 1)
            for round in 1...circuit {
                for block in plan.blocks {
                    for _ in 1...max(block.rounds, 1) { raw.append((block: block, warmUp: false, round: round, count: circuit)) }
                }
            }
        } else {
            for block in plan.blocks {
                let rounds = max(block.rounds, 1)
                for round in 1...rounds { raw.append((block: block, warmUp: false, round: round, count: rounds)) }
            }
        }
        return raw.enumerated().map { index, item in
            let isLast = index == raw.count - 1
            return ActivationRunStep(id: index, block: item.block, isWarmUp: item.warmUp, round: item.round,
                                     roundCount: item.count, restAfter: isLast ? 0 : max(item.block.restSeconds, 0))
        }
    }

    /// Block results for the main blocks in plan order. `done` maps step ids to what was done; steps that were
    /// never reached are missing, so a block that was never started has an empty `done` list.
    public static func results(plan: ActivationPlan, steps: [ActivationRunStep], done: [Int: Int]) -> [ActivationBlockResult] {
        plan.blocks.map { block in
            let values = steps
                .filter { !$0.isWarmUp && $0.block.id == block.id }
                .sorted { $0.id < $1.id }
                .compactMap { done[$0.id] }
                .map { max($0, 0) }
            return ActivationBlockResult(blockID: block.id, exerciseID: block.exerciseID, family: block.family, done: values)
        }
    }

    /// Whole minutes between start and end, at least 1.
    public static func minutes(from start: Date, to end: Date) -> Int {
        max(Int((end.timeIntervalSince(start) / 60).rounded()), 1)
    }
}
