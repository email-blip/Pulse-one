import Foundation

/// A dose from the exercise library read into numbers: "3 × 10", "je Seite 30 s", "2 min", "8 ×", "3 × 20 s je Seite".
public struct ExerciseDose: Equatable, Sendable {
    public let sets: Int
    /// Repetitions per set; nil for a timed hold.
    public let repetitions: Int?
    /// Seconds per set; nil for a repetition set.
    public let seconds: Int?
    /// "je Seite": timed holds run once per side, repetitions are counted per side.
    public let perSide: Bool

    public init(sets: Int, repetitions: Int?, seconds: Int?, perSide: Bool) {
        self.sets = sets
        self.repetitions = repetitions
        self.seconds = seconds
        self.perSide = perSide
    }

    public static func parse(_ text: String) -> ExerciseDose {
        let lower = text.lowercased()
        let perSide = lower.contains("je seite")
        let numbers = Self.numbers(in: lower)
        var sets = 1
        var value = numbers.first
        // "3 × 10": the number before × counts sets when a second number follows.
        if let times = lower.firstIndex(of: "×"), numbers.count >= 2,
           lower[..<times].contains(where: \.isNumber), lower[lower.index(after: times)...].contains(where: \.isNumber) {
            sets = max(numbers[0], 1)
            value = numbers[1]
        }
        guard let value, value > 0 else { return ExerciseDose(sets: 1, repetitions: nil, seconds: 30, perSide: perSide) }
        if lower.contains("min") {
            return ExerciseDose(sets: sets, repetitions: nil, seconds: value * 60, perSide: perSide)
        }
        if lower.range(of: #"\d\s*s(\s|$)"#, options: .regularExpression) != nil {
            return ExerciseDose(sets: sets, repetitions: nil, seconds: value, perSide: perSide)
        }
        return ExerciseDose(sets: sets, repetitions: value, seconds: nil, perSide: perSide)
    }

    static func numbers(in text: String) -> [Int] {
        var result: [Int] = []
        var current = ""
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                result.append(Int(current) ?? 0)
                current = ""
            }
        }
        if !current.isEmpty { result.append(Int(current) ?? 0) }
        return result
    }
}

/// Turns the coach's day plan into a `WorkoutSession` (contract): one step per set (and side for timed holds),
/// rest between steps from the planned intensity, no rest after the last step.
public enum WorkoutBuilder {
    /// Rest between sets and exercises in seconds.
    public static func restSeconds(_ intensity: Intensity?) -> Int {
        switch intensity {
        case .recovery, nil: 15
        case .easy: 30
        case .moderate: 45
        case .hard: 60
        }
    }

    /// Seconds a repetition set usually takes; only for the time estimate, never for the timer.
    static let secondsPerRepetition = 4

    public static func steps(for exercises: [Exercise], intensity: Intensity?) -> [WorkoutStep] {
        let rest = restSeconds(intensity)
        var steps: [WorkoutStep] = []
        for exercise in exercises {
            let dose = ExerciseDose.parse(exercise.dose)
            for set in 1...max(dose.sets, 1) {
                let setLabel = dose.sets > 1 ? "Satz \(set) von \(dose.sets)" : nil
                if let seconds = dose.seconds, dose.perSide {
                    for side in ["links", "rechts"] {
                        steps.append(WorkoutStep(id: "\(exercise.id).\(set).\(side)", exerciseID: exercise.id,
                                                 title: exercise.name, variant: [side, setLabel].compactMap { $0 }.joined(separator: " · "),
                                                 workSeconds: seconds, repetitions: nil, restSeconds: rest))
                    }
                } else {
                    let variant = [dose.perSide ? "je Seite" : nil, setLabel].compactMap { $0 }.joined(separator: " · ")
                    steps.append(WorkoutStep(id: "\(exercise.id).\(set)", exerciseID: exercise.id, title: exercise.name,
                                             variant: variant.isEmpty ? nil : variant, workSeconds: dose.seconds,
                                             repetitions: dose.repetitions, restSeconds: rest))
                }
            }
        }
        return lastWithoutRest(steps)
    }

    /// Session for one block of the day. Blocks without exercises (a run, a ride) become one timed step over the
    /// planned minutes. nil for rest days and blocks without time.
    public static func session(for block: DayBlock, id: UUID = UUID()) -> WorkoutSession? {
        if !block.exercises.isEmpty {
            return WorkoutSession(id: id, programID: "coach.\(block.id)", steps: steps(for: block.exercises, intensity: block.intensity))
        }
        guard block.minutes > 0, block.kind == .mainWorkout || block.kind == .recovery else { return nil }
        let step = WorkoutStep(id: "\(block.id).continuous", exerciseID: "continuous", title: block.title,
                               variant: block.intensity?.title, workSeconds: block.minutes * 60, repetitions: nil, restSeconds: 0)
        return WorkoutSession(id: id, programID: "coach.\(block.id)", steps: [step])
    }

    /// The block "Einheit starten" opens: the main block, otherwise the recovery block of the day.
    public static func primaryBlock(of plan: DailyPlan) -> DayBlock? {
        guard plan.decision != .seekHelp, plan.suggested.kind != .rest else { return nil }
        return plan.blocks.first { $0.id == "main" && session(for: $0) != nil }
    }

    /// Rough length in whole minutes (repetitions estimated), for the start button.
    public static func estimatedMinutes(_ steps: [WorkoutStep]) -> Int {
        let seconds = steps.reduce(0) { total, step in
            total + (step.workSeconds ?? (step.repetitions ?? 10) * secondsPerRepetition) + step.restSeconds
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    private static func lastWithoutRest(_ steps: [WorkoutStep]) -> [WorkoutStep] {
        guard let last = steps.last else { return steps }
        var result = steps
        result[result.count - 1] = WorkoutStep(id: last.id, exerciseID: last.exerciseID, title: last.title, variant: last.variant,
                                               workSeconds: last.workSeconds, repetitions: last.repetitions, restSeconds: 0)
        return result
    }
}
