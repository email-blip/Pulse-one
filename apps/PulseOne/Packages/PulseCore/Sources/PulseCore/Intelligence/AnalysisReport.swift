import Foundation

/// Statement types shown visibly apart (Sanierung 4.0 §8, design system §6).
public enum StatementType: String, Codable, CaseIterable, Sendable {
    case measured
    case computed
    case observation
    case interpretation
    case recommendation

    public var title: String {
        switch self {
        case .measured: "Messwert"
        case .computed: "Berechnet"
        case .observation: "Beobachtung"
        case .interpretation: "Deutung von Claude"
        case .recommendation: "Vorschlag"
        }
    }

    public var symbol: String {
        switch self {
        case .measured: "waveform.path.ecg"
        case .computed: "function"
        case .observation: "eye"
        case .interpretation: "sparkles"
        case .recommendation: "lightbulb"
        }
    }

    /// Measured, computed and observed statements must cite at least one fact.
    public var needsEvidence: Bool { self == .measured || self == .computed || self == .observation }
}

public struct ReportStatement: Codable, Sendable, Equatable, Hashable {
    public let text: String
    public let type: StatementType
    public let evidence: [String]

    public init(text: String, type: StatementType, evidence: [String]) {
        self.text = text
        self.type = type
        self.evidence = evidence
    }
}

public enum ReportSectionKind: String, Codable, CaseIterable, Sendable {
    case keyDevelopments = "key_developments"
    case statisticalChanges = "statistical_changes"
    case notablePatterns = "notable_patterns"
    case possibleFactors = "possible_factors"
    case relationships
    case periodComparison = "period_comparison"
    case personalProgress = "personal_progress"
    case movementRecovery = "movement_recovery"
}

public struct ReportSection: Codable, Sendable, Equatable {
    public let kind: ReportSectionKind
    public let title: String
    public let statements: [ReportStatement]
}

public enum ActionDomain: String, Codable, CaseIterable, Sendable {
    case movement, recovery, sleep, nutrition, measurement, doctor

    public var title: String {
        switch self {
        case .movement: "Bewegung"
        case .recovery: "Erholung"
        case .sleep: "Schlaf"
        case .nutrition: "Ernährung"
        case .measurement: "Messung"
        case .doctor: "Ärztliche Abklärung"
        }
    }
}

public struct ReportAction: Codable, Sendable, Equatable {
    public let text: String
    public let domain: ActionDomain
    public let evidence: [String]
}

public enum ReferralLevel: String, Codable, Sendable, Comparable {
    case none, mention, recommend

    var rank: Int { self == .none ? 0 : self == .mention ? 1 : 2 }
    public static func < (a: ReferralLevel, b: ReferralLevel) -> Bool { a.rank < b.rank }
}

public struct MedicalReferral: Codable, Sendable, Equatable {
    public let level: ReferralLevel
    public let reason: String
    public let evidence: [String]

    public init(level: ReferralLevel, reason: String, evidence: [String]) {
        self.level = level
        self.reason = reason
        self.evidence = evidence
    }
}

/// AnalysisReport v1 (spec §3.3).
public struct AnalysisReport: Codable, Sendable, Equatable {
    public var summary: [ReportStatement]
    public var dataSituation: [ReportStatement]
    public var sections: [ReportSection]
    public var openQuestions: [String]
    public var uncertainties: [ReportStatement]
    public var actions: [ReportAction]
    public var medicalReferral: MedicalReferral

    public static let schemaVersion = 1
}

/// Answer to a question about one's own data (spec §5), checked like a report.
public struct QuestionAnswer: Codable, Sendable, Equatable {
    public var statements: [ReportStatement]
    public var followUps: [String]
}

/// Detective hypothesis board (creative lab idea 2): at most three accompanying circumstances.
public enum HypothesisFit: String, Codable, Sendable {
    case good, partial, weak

    public var title: String {
        switch self {
        case .good: "passt gut"
        case .partial: "passt teilweise"
        case .weak: "passt kaum"
        }
    }
}

public struct Hypothesis: Codable, Sendable, Equatable {
    public let text: String
    public let fit: HypothesisFit
    public let counterCheck: String
    public let evidence: [String]
}

public struct HypothesisBoard: Codable, Sendable, Equatable {
    public var circumstances: [Hypothesis]
    public var note: String
}

/// JSON schemas for `output_config.format` (spec §3.2). Written out without `$ref`, and without
/// min/max keywords, which structured outputs do not support; limits are checked by the validator.
public enum AnalysisSchema {
    static func string() -> JSONValue { .object(["type": .string("string")]) }
    static func strings() -> JSONValue { array(string()) }
    static func enumeration(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map { JSONValue.string($0) })])
    }
    static func object(_ properties: [String: JSONValue]) -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array(properties.keys.sorted().map { JSONValue.string($0) }),
            "properties": .object(properties),
        ])
    }

    static func array(_ items: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": items])
    }

    static var statementList: JSONValue {
        let properties: [String: JSONValue] = [
            "text": string(),
            "type": enumeration(StatementType.allCases.map(\.rawValue)),
            "evidence": strings(),
        ]
        return array(object(properties))
    }

    public static var reportV1: JSONValue {
        let section: [String: JSONValue] = [
            "kind": enumeration(ReportSectionKind.allCases.map(\.rawValue)),
            "title": string(),
            "statements": statementList,
        ]
        let action: [String: JSONValue] = [
            "text": string(),
            "domain": enumeration(ActionDomain.allCases.map(\.rawValue)),
            "evidence": strings(),
        ]
        let referral: [String: JSONValue] = [
            "level": enumeration(["none", "mention", "recommend"]),
            "reason": string(),
            "evidence": strings(),
        ]
        let report: [String: JSONValue] = [
            "summary": statementList,
            "dataSituation": statementList,
            "sections": array(object(section)),
            "openQuestions": strings(),
            "uncertainties": statementList,
            "actions": array(object(action)),
            "medicalReferral": object(referral),
        ]
        return object(report)
    }

    public static var questionV1: JSONValue {
        let properties: [String: JSONValue] = ["statements": statementList, "followUps": strings()]
        return object(properties)
    }

    public static var hypothesesV1: JSONValue {
        let hypothesis: [String: JSONValue] = [
            "text": string(),
            "fit": enumeration(["good", "partial", "weak"]),
            "counterCheck": string(),
            "evidence": strings(),
        ]
        let properties: [String: JSONValue] = ["circumstances": array(object(hypothesis)), "note": string()]
        return object(properties)
    }

    public static var experimentPlanV1: JSONValue {
        let integer: JSONValue = .object(["type": .string("integer")])
        let properties: [String: JSONValue] = [
            "title": string(),
            "targetKind": enumeration(ExperimentLab.targetKinds.map(\.rawValue)),
            "conditionA": string(),
            "conditionB": string(),
            "blockDays": integer,
            "blocks": integer,
            "washoutDays": integer,
            "notesNeeded": strings(),
            "rationale": string(),
        ]
        return object(properties)
    }
}
