import Foundation

public enum IssueSeverity: String, Codable, Sendable {
    /// The statement was removed and is not shown.
    case rejected
    /// The statement is shown with a visible note.
    case flagged
}

/// One entry of the check log stored with every analysis (spec §3.4).
public struct ValidationIssue: Codable, Sendable, Equatable {
    public let location: String
    public let text: String
    public let rule: String
    public let reason: String
    public let severity: IssueSeverity
}

public struct ValidatedReport: Sendable, Equatable {
    public let report: AnalysisReport
    public let issues: [ValidationIssue]
    /// Texts shown with a note (causal wording, thin coverage).
    public let flagged: [String: String]

    public var rejectedCount: Int { issues.filter { $0.severity == .rejected }.count }
}

public struct ValidatedAnswer: Sendable, Equatable {
    public let answer: QuestionAnswer
    public let issues: [ValidationIssue]
    public let flagged: [String: String]
}

public enum ValidationError: Error, Equatable, Sendable {
    case notJSON
    case schemaMismatch(String)

    public var message: String {
        switch self {
        case .notJSON: "Claude hat kein lesbares Ergebnis geliefert."
        case .schemaMismatch(let detail): "Das Ergebnis passt nicht zum erwarteten Aufbau (\(detail))."
        }
    }
}

/// Step 5 of the pipeline: nothing unchecked reaches the screen. Every number must belong to a cited
/// fact, every id must exist, and the safety rules apply to each sentence.
public struct ResponseValidator: Sendable {
    public let context: HealthAnalysisContext
    public let mode: SafetyMode

    public init(context: HealthAnalysisContext, mode: SafetyMode = .clinical) {
        self.context = context
        self.mode = mode
    }

    /// Integers that are always fine: small counts ("an 3 Tagen") and the period lengths.
    static let alwaysAllowed: Set<Double> = [0, 1, 2, 3, 4, 5, 6, 7, 14, 28, 30, 90, 100]

    public func validateReport(json: String) throws -> ValidatedReport {
        validate(try decode(AnalysisReport.self, from: json))
    }

    public func validateAnswer(json: String) throws -> ValidatedAnswer {
        let answer = try decode(QuestionAnswer.self, from: json)
        var log = Log()
        let statements = check(answer.statements, at: "Antwort", log: &log)
        let followUps = answer.followUps.filter { allowText($0, at: "Nachfragen", log: &log) }
        return ValidatedAnswer(answer: QuestionAnswer(statements: statements, followUps: followUps),
                               issues: log.issues, flagged: log.flagged)
    }

    public func validateHypotheses(json: String) throws -> (board: HypothesisBoard, issues: [ValidationIssue]) {
        let board = try decode(HypothesisBoard.self, from: json)
        var log = Log()
        var kept: [Hypothesis] = []
        for h in board.circumstances {
            let statement = ReportStatement(text: h.text, type: .observation, evidence: h.evidence)
            guard !check([statement], at: "Detektiv", log: &log).isEmpty,
                  allowText(h.counterCheck, at: "Gegenprobe", log: &log) else { continue }
            kept.append(h)
        }
        let note = allowText(board.note, at: "Hinweis", log: &log) ? board.note : ""
        // At most three circumstances (creative lab idea 2); the limit cannot be put in the schema.
        return (HypothesisBoard(circumstances: Array(kept.prefix(3)), note: note), log.issues)
    }

    func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else { throw ValidationError.notJSON }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch DecodingError.dataCorrupted {
            throw ValidationError.notJSON
        } catch {
            throw ValidationError.schemaMismatch(String(describing: error).prefix(120).description)
        }
    }

    struct Log {
        var issues: [ValidationIssue] = []
        var flagged: [String: String] = [:]
    }

    public func validate(_ report: AnalysisReport) -> ValidatedReport {
        var log = Log()
        var result = report
        result.summary = check(report.summary, at: "Zusammenfassung", log: &log)
        result.dataSituation = check(report.dataSituation, at: "Datenlage", log: &log)
        result.sections = report.sections.compactMap { section in
            let kept = check(section.statements, at: section.title, log: &log)
            return kept.isEmpty ? nil : ReportSection(kind: section.kind, title: section.title, statements: kept)
        }
        result.uncertainties = check(report.uncertainties, at: "Unsicherheiten", log: &log)
        result.openQuestions = report.openQuestions.filter { allowText($0, at: "Offene Fragen", log: &log) }
        result.actions = report.actions.filter { action in
            let statement = ReportStatement(text: action.text, type: .recommendation, evidence: action.evidence)
            return !check([statement], at: "Vorschläge", log: &log).isEmpty
        }
        result.medicalReferral = referral(report.medicalReferral, log: &log)
        return ValidatedReport(report: result, issues: log.issues, flagged: log.flagged)
    }

    /// Claude's referral, raised to the S5 minimum when local thresholds require it.
    func referral(_ given: MedicalReferral, log: inout Log) -> MedicalReferral {
        var current = given
        let unknown = given.evidence.filter { !context.allIDs.contains($0) }
        if !unknown.isEmpty || (given.level != .none && !allowText(given.reason, at: "Ärztlicher Hinweis", log: &log)) {
            current = MedicalReferral(level: .none, reason: "", evidence: [])
        }
        if let required = SafetyRules.requiredReferral(facts: context.facts), required.level > current.level {
            log.issues.append(ValidationIssue(location: "Ärztlicher Hinweis", text: required.reason, rule: "S5",
                                              reason: "Hinweis durch feste Schwelle ergänzt", severity: .flagged))
            current = required
        }
        return current
    }

    func allowText(_ text: String, at location: String, log: inout Log) -> Bool {
        switch SafetyRules.check(text, mode: mode) {
        case .reject(let rule, let reason):
            log.issues.append(ValidationIssue(location: location, text: text, rule: rule, reason: reason, severity: .rejected))
            return false
        case .flag(let rule, let reason):
            log.issues.append(ValidationIssue(location: location, text: text, rule: rule, reason: reason, severity: .flagged))
            log.flagged[text] = reason
            return true
        case .allow:
            return true
        }
    }

    func check(_ statements: [ReportStatement], at location: String, log: inout Log) -> [ReportStatement] {
        statements.filter { s in
            func reject(_ rule: String, _ reason: String) -> Bool {
                log.issues.append(ValidationIssue(location: location, text: s.text, rule: rule, reason: reason, severity: .rejected))
                return false
            }
            let unknown = s.evidence.filter { !context.allIDs.contains($0) }
            if !unknown.isEmpty { return reject("ID", "unbekannte Beleg-ID \(unknown.joined(separator: ", "))") }
            if s.type.needsEvidence, s.evidence.isEmpty { return reject("Beleg", "Aussage ohne Beleg") }
            // Measured values must match the facts in every mode. In clinical mode an interpretation may
            // also name medical reference values ("über 100 bpm"), which are not facts.
            let numbers = mode == .descriptive || s.type.needsEvidence ? Self.numbers(in: s.text) : []
            if !numbers.isEmpty {
                let allowed = context.citableNumbers(for: s.evidence)
                for number in numbers where !Self.matches(number, allowed: allowed) {
                    return reject("Zahl", "Zahl \(Self.display(number.value)) passt zu keinem zitierten Beleg")
                }
            }
            guard allowText(s.text, at: location, log: &log) else { return false }
            let thin = s.evidence.compactMap { id in context.facts.first { $0.id == id } }.contains { $0.coverage < 0.5 }
            let hedged = ["wenig", "lücke", "unvollständig", "unsicher", "abdeckung", "nur an", "vorsichtig", "dünn"]
                .contains { s.text.lowercased().contains($0) }
            if thin, !hedged, s.type != .measured {
                log.issues.append(ValidationIssue(location: location, text: s.text, rule: "Abdeckung",
                                                  reason: "beruht auf Tagen mit wenig Daten", severity: .flagged))
                if log.flagged[s.text] == nil { log.flagged[s.text] = "Beruht auf wenigen Tagen mit Daten." }
            }
            return true
        }
    }

    /// A number as written, with its shown precision (decimals).
    struct WrittenNumber: Equatable {
        let value: Double
        let decimals: Int
    }

    /// Finds numbers in German text. Ids (F1, C2, E3), dates and clock times are ignored; "8.432" with a
    /// three-digit group is read as 8432, "6,1" as 6.1.
    static func numbers(in text: String) -> [WrittenNumber] {
        var cleaned = text
        let ignored = [
            #"\b[FCEQ]\d+\b"#,
            #"\d{4}-\d{2}-\d{2}"#,
            #"\b\d{1,2}\.\d{1,2}\.(\d{2,4})?"#,
            #"\b\d{1,2}:\d{2}\b"#,
            #"\b(19|20)\d{2}\b"#,
            #"SpO₂|SpO2|VO₂max|VO2max|O₂"#,
        ]
        for pattern in ignored {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let pattern = #"\d{1,3}(?:[.\x{00A0}\x{202F}]\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        return regex.matches(in: cleaned, range: range).compactMap { match in
            guard let r = Range(match.range, in: cleaned) else { return nil }
            var token = String(cleaned[r])
            let grouped = token.range(of: #"^\d{1,3}(?:[.\x{00A0}\x{202F}]\d{3})+"#, options: .regularExpression) != nil
            if grouped {
                token = token.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: "\u{202F}", with: "")
            }
            token = token.replacingOccurrences(of: ",", with: ".")
            let decimals = token.split(separator: ".").dropFirst().first?.count ?? 0
            return Double(token).map { WrittenNumber(value: $0, decimals: decimals) }
        }
    }

    /// Tolerance ±1 in the last shown digit (spec §3.4); integers up to 7 and the period lengths always pass.
    static func matches(_ number: WrittenNumber, allowed: [Double]) -> Bool {
        if number.decimals == 0, alwaysAllowed.contains(number.value) { return true }
        let step = pow(10, -Double(number.decimals))
        return allowed.contains { abs($0 - number.value) <= step + 1e-9 }
    }

    static func display(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
