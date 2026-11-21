import Foundation

public enum ExperimentCondition: String, Codable, Sendable {
    case a, b
}

/// A small self-experiment (N-of-1), planned by Claude or by hand (creative lab idea 3).
public struct ExperimentPlan: Codable, Sendable, Equatable {
    public var title: String
    public var targetKind: SampleKind
    public var conditionA: String
    public var conditionB: String
    public var blockDays: Int
    public var blocks: Int
    public var washoutDays: Int
    public var notesNeeded: [String]
    public var rationale: String

    public init(title: String, targetKind: SampleKind, conditionA: String, conditionB: String, blockDays: Int,
                blocks: Int, washoutDays: Int, notesNeeded: [String] = [], rationale: String = "") {
        self.title = title
        self.targetKind = targetKind
        self.conditionA = conditionA
        self.conditionB = conditionB
        self.blockDays = blockDays
        self.blocks = blocks
        self.washoutDays = washoutDays
        self.notesNeeded = notesNeeded
        self.rationale = rationale
    }

    /// Clamps what Claude proposed to the allowed ranges (the schema cannot carry min/max).
    public func sanitized() -> ExperimentPlan {
        var copy = self
        copy.blockDays = min(max(blockDays, 3), 7)
        copy.blocks = min(max(blocks, 4), 8)
        if copy.blocks % 2 == 1 { copy.blocks -= 1 }
        copy.washoutDays = min(max(washoutDays, 0), 2)
        if !ExperimentLab.targetKinds.contains(targetKind) { copy.targetKind = .sleepDuration }
        return copy
    }

    /// Total length in days, washout included.
    public var totalDays: Int { blocks * blockDays + (blocks - 1) * washoutDays }
}

public struct ExperimentScheduleDay: Sendable, Equatable {
    public let date: Date
    /// nil on washout days.
    public let condition: ExperimentCondition?
    public let block: Int?
}

public enum ExperimentVerdict: String, Sendable, Equatable {
    case notEnoughData
    case noClearDifference
    case difference
}

public struct ExperimentResult: Sendable, Equatable {
    public let meanA: Double
    public let meanB: Double
    /// B minus A, in the target's display unit.
    public let difference: Double
    public let blockMeansA: [Double]
    public let blockMeansB: [Double]
    /// Exact two-sided permutation p-value over block labels.
    public let pValue: Double
    public let daysUsed: Int
    public let verdict: ExperimentVerdict
    public let unit: String

    /// Sober German summary; Claude may rephrase it, but the numbers come from here.
    public var summary: String {
        let a = FactUnits.text(IntelligenceStats.rounded(meanA, decimals: 1), unit: unit)
        let b = FactUnits.text(IntelligenceStats.rounded(meanB, decimals: 1), unit: unit)
        switch verdict {
        case .notEnoughData:
            return "Noch zu wenige Tage mit Messwerten für eine Auswertung (\(daysUsed) Tage)."
        case .noClearDifference:
            return "Bedingung A: im Mittel \(a), Bedingung B: \(b). Bei deiner üblichen Schwankung ist das kein klarer Unterschied."
        case .difference:
            return "Bedingung A: im Mittel \(a), Bedingung B: \(b). Der Unterschied zeigte sich in den Blöcken recht beständig. "
                + "Das gilt für diesen Zeitraum und ist ein Hinweis, kein Beweis."
        }
    }
}

public enum ExperimentAdmissibility: Equatable, Sendable {
    case ok
    case rejected(String)
}

public enum ExperimentLab {
    /// Measurable targets for everyday experiments.
    public static let targetKinds: [SampleKind] = [.sleepDuration, .restingHeartRate, .heartRateVariability, .steps, .heartRate]

    static let forbidden = SafetyRules.medicationTerms + ["medikation", "tabletten", "dosis", "hormon", "cbd", "kreatin",
                                                           "protein-pulver", "proteinpulver", "eisentablette", "zink", "omega-3"]

    /// Only everyday behaviour; never medication or supplements (creative lab idea 3, DE veto).
    public static func admissibility(of question: String) -> ExperimentAdmissibility {
        let lower = question.lowercased()
        if forbidden.contains(where: { lower.contains($0) }) {
            return .rejected("Selbstversuche mit Medikamenten oder Nahrungsergänzung macht PULSE ONE nicht. "
                             + "Bitte das mit einer Ärztin oder einem Arzt besprechen.")
        }
        if SafetyRules.isEmergency(question) { return .rejected(SafetyRules.emergencyReply) }
        return .ok
    }

    /// Alternating blocks A B A B …, washout days in between (not evaluated).
    public static func schedule(_ plan: ExperimentPlan, start: Date, calendar: Calendar) -> [ExperimentScheduleDay] {
        var days: [ExperimentScheduleDay] = []
        var offset = 0
        let first = calendar.startOfDay(for: start)
        for block in 0..<plan.blocks {
            let condition: ExperimentCondition = block % 2 == 0 ? .a : .b
            for _ in 0..<plan.blockDays {
                if let date = calendar.date(byAdding: .day, value: offset, to: first) {
                    days.append(ExperimentScheduleDay(date: date, condition: condition, block: block))
                }
                offset += 1
            }
            if block < plan.blocks - 1 {
                for _ in 0..<plan.washoutDays {
                    if let date = calendar.date(byAdding: .day, value: offset, to: first) {
                        days.append(ExperimentScheduleDay(date: date, condition: nil, block: nil))
                    }
                    offset += 1
                }
            }
        }
        return days
    }

    /// Days per condition needed to see a difference of `effect` at the usual spread `sd`
    /// (two-sided 5 %, power 80 %): n = 2 (1.96 + 0.84)² sd² / effect². Honest, often long.
    public static func requiredDaysPerCondition(sd: Double, effect: Double) -> Int? {
        guard sd > 0, effect > 0 else { return nil }
        let n = 2 * pow(1.96 + 0.84, 2) * sd * sd / (effect * effect)
        return max(3, Int(n.rounded(.up)))
    }

    /// Evaluates on block means (more robust to day-to-day autocorrelation than single days).
    /// `values` are daily values in the canonical unit, keyed by start of day.
    public static func evaluate(_ plan: ExperimentPlan, start: Date, values: [Date: Double],
                                calendar: Calendar) -> ExperimentResult {
        let unit = FactUnits.display(plan.targetKind, 0).unit
        var blockValues: [Int: [Double]] = [:]
        var blockCondition: [Int: ExperimentCondition] = [:]
        for day in schedule(plan, start: start, calendar: calendar) {
            guard let block = day.block, let condition = day.condition else { continue }
            blockCondition[block] = condition
            if let v = values[calendar.startOfDay(for: day.date)] {
                blockValues[block, default: []].append(FactUnits.display(plan.targetKind, v).value)
            }
        }
        // A block counts when at least half of its days have data.
        let minimum = max(1, plan.blockDays / 2)
        let used = blockValues.filter { $0.value.count >= minimum }
        let meansA = used.filter { blockCondition[$0.key] == .a }.compactMap { IntelligenceStats.mean($0.value) }
        let meansB = used.filter { blockCondition[$0.key] == .b }.compactMap { IntelligenceStats.mean($0.value) }
        let daysUsed = used.values.reduce(0) { $0 + $1.count }
        guard meansA.count >= 2, meansB.count >= 2,
              let ma = IntelligenceStats.mean(meansA), let mb = IntelligenceStats.mean(meansB) else {
            return ExperimentResult(meanA: IntelligenceStats.mean(meansA) ?? 0, meanB: IntelligenceStats.mean(meansB) ?? 0,
                                    difference: 0, blockMeansA: meansA, blockMeansB: meansB, pValue: 1,
                                    daysUsed: daysUsed, verdict: .notEnoughData, unit: unit)
        }
        let p = permutationPValue(meansA, meansB)
        return ExperimentResult(meanA: ma, meanB: mb, difference: mb - ma, blockMeansA: meansA, blockMeansB: meansB,
                                pValue: p, daysUsed: daysUsed, verdict: p <= 0.1 ? .difference : .noClearDifference,
                                unit: unit)
    }

    /// Exact two-sided permutation test over all ways to label the blocks.
    public static func permutationPValue(_ a: [Double], _ b: [Double]) -> Double {
        let all = a + b
        let n = all.count
        guard n <= 16, !a.isEmpty, !b.isEmpty else { return 1 }
        let observed = abs((IntelligenceStats.mean(b) ?? 0) - (IntelligenceStats.mean(a) ?? 0))
        var extreme = 0
        var total = 0
        for mask in 0..<(1 << n) where mask.nonzeroBitCount == a.count {
            var sa = 0.0, sb = 0.0
            for i in 0..<n {
                if mask & (1 << i) != 0 { sa += all[i] } else { sb += all[i] }
            }
            let diff = abs(sb / Double(b.count) - sa / Double(a.count))
            if diff >= observed - 1e-9 { extreme += 1 }
            total += 1
        }
        return total == 0 ? 1 : Double(extreme) / Double(total)
    }
}
