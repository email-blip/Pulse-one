import Foundation
import Testing
@testable import PulseCore

// Order of guided activation sessions (team A helper, AKTIVIERUNG-KONZEPT.md).

private func block(_ id: String, _ family: ActivationFamily, _ target: ActivationTarget, rounds: Int = 1,
                   rest: Int = 30) -> ActivationBlock {
    ActivationBlock(id: id, exerciseID: "ex.\(id)", family: family, target: target, rounds: rounds, restSeconds: rest)
}

private func plan(format: ActivationFormat, circuitRounds: Int, warmUp: [ActivationBlock],
                  blocks: [ActivationBlock]) -> ActivationPlan {
    ActivationPlan(slot: .morning, dayStamp: "20261121", format: format, readiness: .full, warmUp: warmUp,
                   blocks: blocks, circuitRounds: circuitRounds, estimatedSeconds: 360, reason: "", summary: "")
}

struct ActivationRunTests {
    @Test func circuitRepeatsAllBlocksAfterWarmUp() {
        let warm = block("w", .mobility, .seconds(60), rest: 0)
        let push = block("p", .push, .reps(12))
        let core = block("c", .core, .seconds(40), rest: 45)
        let steps = ActivationRun.steps(for: plan(format: .circuit, circuitRounds: 3, warmUp: [warm], blocks: [push, core]))

        #expect(steps.count == 7)
        #expect(steps.map(\.id) == Array(0..<7))
        #expect(steps[0].isWarmUp)
        #expect(steps[0].restAfter == 0)
        #expect(steps.dropFirst().map(\.block.id) == ["p", "c", "p", "c", "p", "c"])
        #expect(steps.dropFirst().map(\.round) == [1, 1, 2, 2, 3, 3])
        #expect(steps[1].roundCount == 3)
        #expect(steps[2].restAfter == 45)
        #expect(steps.last?.restAfter == 0)
    }

    @Test func setsRunEachBlockBeforeTheNext() {
        let push = block("p", .push, .reps(10), rounds: 2, rest: 60)
        let pull = block("u", .pull, .reps(4), rounds: 2, rest: 60)
        let steps = ActivationRun.steps(for: plan(format: .sets, circuitRounds: 1, warmUp: [], blocks: [push, pull]))

        #expect(steps.map(\.block.id) == ["p", "p", "u", "u"])
        #expect(steps.map(\.round) == [1, 2, 1, 2])
        #expect(steps.allSatisfy { $0.roundCount == 2 })
        #expect(steps.map(\.restAfter) == [60, 60, 60, 0])
    }

    @Test func zeroRoundsStillGiveOneStep() {
        let push = block("p", .push, .reps(8), rounds: 0)
        let steps = ActivationRun.steps(for: plan(format: .circuit, circuitRounds: 0, warmUp: [], blocks: [push]))
        #expect(steps.count == 1)
        #expect(steps.first?.restAfter == 0)
    }

    @Test func emptyPlanHasNoSteps() {
        #expect(ActivationRun.steps(for: plan(format: .gentle, circuitRounds: 1, warmUp: [], blocks: [])).isEmpty)
    }

    @Test func resultsSkipWarmUpAndKeepUnreachedBlocksEmpty() {
        let warm = block("w", .mobility, .seconds(60), rest: 0)
        let push = block("p", .push, .reps(12))
        let core = block("c", .core, .seconds(40))
        let thePlan = plan(format: .circuit, circuitRounds: 2, warmUp: [warm], blocks: [push, core])
        let steps = ActivationRun.steps(for: thePlan)
        // Warm-up, push round 1, core round 1 (30 s), push round 2; then ended early.
        let results = ActivationRun.results(plan: thePlan, steps: steps, done: [0: 60, 1: 12, 2: 30, 3: 11])

        #expect(results.map(\.blockID) == ["p", "c"])
        #expect(results[0].done == [12, 11])
        #expect(results[0].exerciseID == "ex.p")
        #expect(results[1].done == [30])

        let untouched = ActivationRun.results(plan: thePlan, steps: steps, done: [:])
        #expect(untouched.allSatisfy { $0.done.isEmpty })
    }

    @Test func targetValueAndHold() {
        let reps = ActivationRunStep(id: 0, block: block("p", .push, .reps(12)), isWarmUp: false, round: 1,
                                     roundCount: 1, restAfter: 0)
        let hold = ActivationRunStep(id: 1, block: block("c", .core, .seconds(40)), isWarmUp: false, round: 1,
                                     roundCount: 1, restAfter: 0)
        #expect(reps.targetValue == 12)
        #expect(!reps.isHold)
        #expect(hold.targetValue == 40)
        #expect(hold.isHold)
        #expect(ActivationRun.value(of: .reps(-3)) == 0)
    }

    @Test(arguments: [(0.0, 1), (29.0, 1), (95.0, 2), (480.0, 8)])
    func minutesAreRoundedAndAtLeastOne(seconds: Double, expected: Int) {
        let start = Date(timeIntervalSince1970: 1_795_188_773)
        #expect(ActivationRun.minutes(from: start, to: start.addingTimeInterval(seconds)) == expected)
    }
}
