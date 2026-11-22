import Foundation

/// How soon something should be looked at, from the consultation (owner decision 2026-11-21).
public enum ConsultationUrgency: String, Codable, Sendable, CaseIterable, Comparable {
    case none, routine, soon, today, emergency

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: ConsultationUrgency, b: ConsultationUrgency) -> Bool { a.rank < b.rank }

    public var title: String {
        switch self {
        case .none: "Kein Handlungsbedarf"
        case .routine: "Beim nächsten Arzttermin ansprechen"
        case .soon: "In den nächsten Tagen ärztlich abklären"
        case .today: "Heute ärztlich abklären"
        case .emergency: "Sofort Notruf 112"
        }
    }

    /// The minimum a fixed threshold (S5) demands.
    public init(referral: ReferralLevel) {
        switch referral {
        case .none: self = .none
        case .mention: self = .routine
        case .recommend: self = .soon
        }
    }
}

/// One possible diagnosis or condition and how well it fits the data. No percentages (owner decision
/// 2026-11-22 after Codex P1-005): there is no calibrated model behind such numbers.
public struct DifferentialDiagnosis: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var fit: InsightFit
    public var reasoning: String
    public var supporting: [String]
    public var against: [String]
    public var workup: [String]
    public var evidence: [String]

    public init(name: String, fit: InsightFit, reasoning: String, supporting: [String], against: [String],
                workup: [String], evidence: [String]) {
        self.name = name
        self.fit = fit
        self.reasoning = reasoning
        self.supporting = supporting
        self.against = against
        self.workup = workup
        self.evidence = evidence
    }
}

extension DifferentialDiagnosis {
    private enum CodingKeys: String, CodingKey {
        case name, fit, likelihoodPercent, reasoning, supporting, against, workup, evidence
    }

    /// Reads replies stored before 2026-11-22 too: an old percentage becomes a fit, never shown as a number.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        if let fit = try c.decodeIfPresent(InsightFit.self, forKey: .fit) {
            self.fit = fit
        } else if let percent = try c.decodeIfPresent(Int.self, forKey: .likelihoodPercent) {
            fit = percent >= 50 ? .strong : percent >= 20 ? .partial : .weak
        } else {
            fit = .open
        }
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        supporting = try c.decodeIfPresent([String].self, forKey: .supporting) ?? []
        against = try c.decodeIfPresent([String].self, forKey: .against) ?? []
        workup = try c.decodeIfPresent([String].self, forKey: .workup) ?? []
        evidence = try c.decodeIfPresent([String].self, forKey: .evidence) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(fit, forKey: .fit)
        try c.encode(reasoning, forKey: .reasoning)
        try c.encode(supporting, forKey: .supporting)
        try c.encode(against, forKey: .against)
        try c.encode(workup, forKey: .workup)
        try c.encode(evidence, forKey: .evidence)
    }
}

public enum CareArea: String, Codable, Sendable, CaseIterable {
    case workup, training, rehab, daily, sleep, nutrition, treatment, mind

    public var title: String {
        switch self {
        case .workup: "Abklärung"
        case .training: "Training"
        case .rehab: "Reha und Physiotherapie"
        case .daily: "Tagesgestaltung"
        case .sleep: "Schlaf"
        case .nutrition: "Ernährung"
        case .treatment: "Behandlung"
        case .mind: "Kopf und Stress"
        }
    }

    public var symbol: String {
        switch self {
        case .workup: "stethoscope"
        case .training: "figure.run"
        case .rehab: "figure.cooldown"
        case .daily: "sun.max"
        case .sleep: "moon.zzz"
        case .nutrition: "fork.knife"
        case .treatment: "cross.case"
        case .mind: "brain.head.profile"
        }
    }
}

public enum CarePriority: String, Codable, Sendable, CaseIterable {
    case high, medium, low

    public var title: String {
        switch self {
        case .high: "wichtig"
        case .medium: "sinnvoll"
        case .low: "optional"
        }
    }
}

public struct CareRecommendation: Codable, Sendable, Equatable, Hashable {
    public var area: CareArea
    public var priority: CarePriority
    public var text: String
    public var evidence: [String]

    public init(area: CareArea, priority: CarePriority, text: String, evidence: [String]) {
        self.area = area
        self.priority = priority
        self.text = text
        self.evidence = evidence
    }
}

/// One answer of the consultation ("Sprechstunde").
public struct ConsultationReply: Codable, Sendable, Equatable {
    public var reply: String
    public var assessment: [ReportStatement]
    public var differentials: [DifferentialDiagnosis]
    public var recommendations: [CareRecommendation]
    public var anamnesisQuestions: [String]
    public var urgency: ConsultationUrgency
    public var urgencyReason: String
    public var memory: String

    public init(reply: String, assessment: [ReportStatement], differentials: [DifferentialDiagnosis],
                recommendations: [CareRecommendation], anamnesisQuestions: [String], urgency: ConsultationUrgency,
                urgencyReason: String, memory: String) {
        self.reply = reply
        self.assessment = assessment
        self.differentials = differentials
        self.recommendations = recommendations
        self.anamnesisQuestions = anamnesisQuestions
        self.urgency = urgency
        self.urgencyReason = urgencyReason
        self.memory = memory
    }

    public static let memoryLimit = 1_500
}

public struct ValidatedConsultation: Sendable, Equatable {
    public let reply: ConsultationReply
    public let issues: [ValidationIssue]
    public let flagged: [String: String]
}

extension AnalysisSchema {
    public static var consultationV1: JSONValue {
        let integer: JSONValue = .object(["type": .string("integer")])
        let differential: [String: JSONValue] = [
            "name": string(),
            "fit": enumeration(["strong", "partial", "weak"]),
            "reasoning": string(),
            "supporting": strings(),
            "against": strings(),
            "workup": strings(),
            "evidence": strings(),
        ]
        let recommendation: [String: JSONValue] = [
            "area": enumeration(CareArea.allCases.map(\.rawValue)),
            "priority": enumeration(CarePriority.allCases.map(\.rawValue)),
            "text": string(),
            "evidence": strings(),
        ]
        let properties: [String: JSONValue] = [
            "reply": string(),
            "assessment": statementList,
            "differentials": array(object(differential)),
            "recommendations": array(object(recommendation)),
            "anamnesisQuestions": strings(),
            "urgency": enumeration(ConsultationUrgency.allCases.map(\.rawValue)),
            "urgencyReason": string(),
            "memory": string(),
        ]
        return object(properties)
    }
}

extension ResponseValidator {
    /// Checks a consultation answer: ids must exist, measured statements must match their facts,
    /// disclaimers are dropped, differentials are ordered by fit, and the urgency never falls below the fixed
    /// thresholds (S5) or an emergency the person described (S6).
    public func validateConsultation(json: String, userText: String) throws -> ValidatedConsultation {
        let raw = try decode(ConsultationReply.self, from: json)
        var log = Log()
        var result = raw
        result.reply = SafetyRules.removingBoilerplate(raw.reply)
        if result.reply != raw.reply.trimmingCharacters(in: .whitespacesAndNewlines) {
            log.issues.append(ValidationIssue(location: "Antwort", text: raw.reply, rule: "S7",
                                              reason: "Floskel entfernt", severity: .flagged))
        }
        result.assessment = check(raw.assessment, at: "Einschätzung", log: &log)
        var differentials: [DifferentialDiagnosis] = []
        for d in raw.differentials where !d.name.trimmingCharacters(in: .whitespaces).isEmpty {
            var kept = d
            kept.evidence = knownIDs(d.evidence, at: "Diagnosen", text: d.name, log: &log)
            kept.reasoning = SafetyRules.removingBoilerplate(d.reasoning)
            differentials.append(kept)
        }
        result.differentials = differentials.enumerated()
            .sorted { $0.element.fit != $1.element.fit ? $0.element.fit > $1.element.fit : $0.offset < $1.offset }
            .map(\.element)
        var recommendations: [CareRecommendation] = []
        for r in raw.recommendations where allowText(r.text, at: "Empfehlungen", log: &log) {
            var kept = r
            kept.evidence = knownIDs(r.evidence, at: "Empfehlungen", text: r.text, log: &log)
            recommendations.append(kept)
        }
        result.recommendations = recommendations
        result.anamnesisQuestions = raw.anamnesisQuestions.filter { !SafetyRules.isBoilerplate($0) }
        result.memory = String(raw.memory.prefix(ConsultationReply.memoryLimit))

        var minimum = ConsultationUrgency(referral: SafetyRules.requiredReferral(facts: context.facts)?.level ?? ReferralLevel.none)
        if SafetyRules.isEmergency(userText) { minimum = max(minimum, .today) }
        if minimum > raw.urgency {
            log.issues.append(ValidationIssue(location: "Dringlichkeit", text: raw.urgency.title, rule: minimum >= .today ? "S6" : "S5",
                                              reason: "Dringlichkeit durch feste Schwelle angehoben", severity: .flagged))
            result.urgency = minimum
            if result.urgencyReason.isEmpty {
                result.urgencyReason = minimum >= .today ? SafetyRules.consultationEmergencyNotice
                    : SafetyRules.requiredReferral(facts: context.facts)?.reason ?? ""
            }
        }
        return ValidatedConsultation(reply: result, issues: log.issues, flagged: log.flagged)
    }

    /// Unknown ids are dropped (the content stays), and the drop is logged.
    func knownIDs(_ ids: [String], at location: String, text: String, log: inout Log) -> [String] {
        let unknown = ids.filter { !context.allIDs.contains($0) }
        if !unknown.isEmpty {
            log.issues.append(ValidationIssue(location: location, text: text, rule: "ID",
                                              reason: "unbekannte Beleg-ID \(unknown.joined(separator: ", ")) entfernt",
                                              severity: .flagged))
        }
        return ids.filter { context.allIDs.contains($0) }
    }
}

/// What the consultation sends and keeps: the opening context, earlier memory, and helpers to merge facts.
public enum ConsultationBuilder {
    /// First user turn: context JSON, memory of earlier consultations, and the person's message.
    public static func opening(context: HealthAnalysisContext, memory: [String], message: String) -> String {
        var parts = ["Kontext (HealthAnalysisContext v1):", context.compactJSON()]
        let earlier = memory.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if earlier.isEmpty {
            parts.append("Gedächtnis früherer Gespräche: keines, dies ist das erste Gespräch.")
        } else {
            parts.append("Gedächtnis früherer Gespräche (neuestes zuerst):")
            parts += earlier.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }
        parts.append("Nachricht der Person: " + (message.isEmpty ? startMessage : message))
        return parts.joined(separator: "\n")
    }

    public static let startMessage = "Bitte schau dir meine Daten an, gib mir eine erste ärztliche Einschätzung und stell mir die Fragen, die du für die Anamnese brauchst."

    /// The base context plus everything tools handed out, so one validator checks every answer.
    public static func merged(_ base: HealthAnalysisContext, facts: [AnalysisFact], correlations: [CorrelationFact],
                              events: [ContextEventFact]) -> HealthAnalysisContext {
        func adding<T: Identifiable>(_ list: [T], _ more: [T]) -> [T] where T.ID == String {
            let ids = Set(list.map(\.id))
            return list + more.filter { !ids.contains($0.id) }
        }
        return HealthAnalysisContext(analysisType: "consultation", generatedAt: base.generatedAt, period: base.period,
                                     comparisonPeriod: base.comparisonPeriod, profile: base.profile,
                                     consentedCategories: base.consentedCategories,
                                     facts: adding(base.facts, facts), correlations: adding(base.correlations, correlations),
                                     events: adding(base.events, events), dataGaps: base.dataGaps)
    }
}
