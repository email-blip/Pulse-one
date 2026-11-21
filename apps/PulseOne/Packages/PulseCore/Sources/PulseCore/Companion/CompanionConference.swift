import Foundation

// Pure logic of the "Expertenrunde" (BEGLEITER-KREATIVTEAM.md §5): cost estimate for the send preview,
// local safety check of every reply, splitting the synthesis into its sections, and the canned replies
// the test transport uses. The app sends the requests with the Analyse module's Claude client.

/// One role's reply as shown and stored. A reply that failed the local check is never kept: `text` is
/// then `CompanionConference.withheldNotice` and `withheld` is true.
public struct ConferenceStatement: Codable, Equatable, Sendable, Identifiable {
    public let roleID: String
    public let title: String
    /// SF Symbol name of the role.
    public let symbol: String
    public let text: String
    public let withheld: Bool

    public var id: String { roleID }

    public init(roleID: String, title: String, symbol: String, text: String, withheld: Bool) {
        self.roleID = roleID
        self.title = title
        self.symbol = symbol
        self.text = text
        self.withheld = withheld
    }

    public init(role: ConferenceRole, text: String, withheld: Bool) {
        self.init(roleID: role.id, title: role.title, symbol: role.symbol, text: text, withheld: withheld)
    }
}

/// One block of the synthesis ("Beobachtungen", "Hier sind wir uns nicht einig", "Vorschläge", "Offene Frage").
/// `title` is empty for text before the first heading.
public struct ConferenceSection: Equatable, Sendable, Identifiable {
    public let index: Int
    public let title: String
    public let body: String
    public let isDisagreement: Bool

    public var id: Int { index }

    public init(index: Int, title: String, body: String, isDisagreement: Bool) {
        self.index = index
        self.title = title
        self.body = body
        self.isDisagreement = isDisagreement
    }
}

public enum CompanionConference {
    public static let withheldNotice = "Diese Antwort wurde zurückgehalten, weil sie eine unzulässige Aussage enthielt."
    public static let emptyNotice = "Diese Rolle hat keine Antwort geliefert."
    /// What the synthesis gets instead of a withheld role reply (the rejected text never goes back to Claude).
    public static let withheldForSynthesis = "Kein Beitrag."

    /// Headings the synthesis prompt asks for, in order.
    public static let sectionTitles = ["Beobachtungen", CompanionPrompts.disagreementHeading, "Vorschläge", "Offene Frage"]

    /// Consent categories the round cannot do without (heart and sleep are the core of the fact list).
    public static let requiredConsent: [ConsentCategory] = [.heart, .sleep]
    /// Every health category the fact list can touch; optional ones are only included when switched on.
    public static let possibleConsent: [ConsentCategory] = [.heart, .sleep, .spo2, .body, .activity]

    /// Categories whose values `CompanionPrompts.minimalFacts(_:consent:)` includes with this consent.
    public static func sentCategories(consent: Set<ConsentCategory>) -> [ConsentCategory] {
        possibleConsent.filter { consent.contains($0) }
    }

    /// The round needs a night to talk about: sleep duration or a night resting pulse.
    public static func hasNightData(_ day: CompanionDay) -> Bool {
        day.night.sleepDuration != nil || day.night.nightRestingHeartRate != nil
    }

    /// Effort per request (spec: short texts need little depth; the synthesis a bit more).
    public static let roleEffort = "low"
    public static let synthesisEffort = "medium"

    /// Rough output per request for the preview, including adaptive thinking. The real count comes back in `usage`.
    public static let expectedRoleOutputTokens = 600
    public static let expectedSynthesisOutputTokens = 1_500
    static let assumedStatementCharacters = 500
    static let requestOverheadCharacters = 400

    /// Four role rounds plus the synthesis.
    public static var requestCount: Int { CompanionPrompts.conferenceRoles.count + 1 }

    public static var expectedOutputTokens: Int {
        CompanionPrompts.conferenceRoles.count * expectedRoleOutputTokens + expectedSynthesisOutputTokens
    }

    /// Characters of all five requests (system prompts, facts, and assumed role statements for the synthesis).
    public static func inputCharacters(facts: String) -> Int {
        var total = 0
        var placeholders: [(ConferenceRole, String)] = []
        let placeholder = String(repeating: "x", count: assumedStatementCharacters)
        for role in CompanionPrompts.conferenceRoles {
            let round = CompanionPrompts.conferenceRound(role: role, facts: facts)
            total += round.system.count + round.user.count + requestOverheadCharacters
            placeholders.append((role, placeholder))
        }
        let synthesis = CompanionPrompts.conferenceSynthesis(facts: facts, statements: placeholders)
        total += synthesis.system.count + synthesis.user.count + requestOverheadCharacters
        return total
    }

    /// Estimated cost of one whole round with `model`.
    public static func estimate(facts: String, model: ClaudeModel) -> CostEstimate {
        CostEstimator.estimate(inputCharacters: inputCharacters(facts: facts), expectedOutputTokens: expectedOutputTokens,
                               model: model)
    }

    /// Required consent categories that are switched off, in `requiredConsent` order.
    public static func missingConsent(in consent: Set<ConsentCategory>) -> [ConsentCategory] {
        requiredConsent.filter { !consent.contains($0) }
    }

    // MARK: - Safety

    /// True when the text passes the companion phrase list and no sentence is rejected by `SafetyRules`
    /// (diagnosis, disease risk, medication). Causal wording (S4) is only a flag there and stays allowed.
    public static func isAllowed(_ text: String) -> Bool {
        guard CompanionSafety.violations(in: text).isEmpty else { return false }
        for sentence in sentences(of: text) {
            // Descriptive rules as before; loosening the Expertenrunde is up to the Begleiter team.
            if case .reject = SafetyRules.check(sentence, mode: .descriptive) { return false }
        }
        return true
    }

    /// The reply as it may be shown: trimmed, or the withheld notice when it failed the check.
    public static func screen(_ reply: String) -> (text: String, withheld: Bool) {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (emptyNotice, false) }
        return isAllowed(trimmed) ? (trimmed, false) : (withheldNotice, true)
    }

    static func sentences(of text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Synthesis sections

    /// Splits the synthesis at the known headings (with or without Markdown marks or a trailing colon).
    /// Text without any heading comes back as one untitled section.
    public static func sections(of synthesis: String) -> [ConferenceSection] {
        var parts: [(title: String, lines: [String])] = [(title: "", lines: [])]
        for line in synthesis.components(separatedBy: "\n") {
            if let title = heading(in: line) {
                parts.append((title: title, lines: []))
            } else {
                parts[parts.count - 1].lines.append(line)
            }
        }
        var result: [ConferenceSection] = []
        for part in parts {
            let body = part.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if part.title.isEmpty && body.isEmpty { continue }
            result.append(ConferenceSection(index: result.count, title: part.title, body: body,
                                            isDisagreement: part.title == CompanionPrompts.disagreementHeading))
        }
        return result
    }

    /// The canonical heading when `line` is one of `sectionTitles`, else nil.
    static func heading(in line: String) -> String? {
        let marks = CharacterSet(charactersIn: "#*_:„“\"").union(.whitespaces)
        let stripped = line.trimmingCharacters(in: marks)
        guard !stripped.isEmpty, stripped.count <= 40 else { return nil }
        return sectionTitles.first { title in
            stripped.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    // MARK: - Test replies

    /// Canned reply for the test transport (UI tests and screenshots, never a real answer): the synthesis
    /// when the system prompt is the moderation, else the statement of the role named in it.
    public static func mockReply(system: String) -> String {
        if system.contains(CompanionPrompts.disagreementHeading) { return sampleSynthesis }
        for role in CompanionPrompts.conferenceRoles where system.contains("„\(role.title)“") {
            return sampleStatements[role.id] ?? emptyNotice
        }
        return "In der Testansicht antwortet Claude nicht wirklich."
    }

    /// Sample statements matching the companion test data (ordinary night, values inside the personal band).
    public static let sampleStatements: [String: String] = [
        "heart": "Dein Nachtruhepuls lag mit 55 Schlägen pro Minute in deinem üblichen Bereich. Die Ring-HRV von 46 ms liegt ebenfalls im üblichen Bereich, die Ring-Methode lese ich nur als Verlauf. Für heute würde ich eher bei lockerer Bewegung bleiben, bis die Werte ein paar Tage stabil sind.",
        "sleep": "Mit 7 h 12 min hast du im Bereich deiner üblichen Nächte geschlafen. Die Sauerstoffsättigung von 97 % in der Nacht ist beim Ring nur ein grober Wert. Versuch heute Abend eine ähnliche Zubettgehzeit wie gestern.",
        "sport": "Deine Erholungswerte liegen im üblichen Bereich. Eine lockere bis mittlere Einheit passt heute gut in den Nachmittag. Wenn sich der Puls ungewohnt hoch anfühlt, hör lieber früher auf.",
        "nutrition": "Zu Mahlzeiten und Koffein liegen heute keine Notizen vor, dazu kann ich wenig sagen. Ein großes Glas Wasser am Morgen und der letzte Kaffee vor dem frühen Nachmittag sind einfache Alltagsschritte."
    ]

    public static let sampleSynthesis = """
    Beobachtungen
    - Nachtruhepuls 55 Schläge pro Minute, im üblichen Bereich.
    - Schlafdauer 7 h 12 min, im üblichen Bereich.
    - Ring-HRV 46 ms, im üblichen Bereich, nur als Verlauf lesbar.

    Hier sind wir uns nicht einig
    Sport sieht Raum für eine mittlere Einheit, Herz würde eher locker bleiben. Beides ist vertretbar: Wenn du trainierst, starte locker und steigere nur, wenn es sich leicht anfühlt.

    Vorschläge
    - Bewegung am Nachmittag, locker bis mittel.
    - Letzter Kaffee vor dem frühen Nachmittag.
    - Eine ähnliche Zubettgehzeit wie gestern.

    Offene Frage
    Wie fühlst du dich heute im Vergleich zu deinen Werten?
    """

    /// Fact list shown with the stored sample round (test view only).
    public static let sampleFacts = """
    Tagestyp: Normaler Start
    Schlafdauer: 7 h 12 min, im üblichen Bereich
    Nachtruhepuls: 55 Schläge pro Minute, im üblichen Bereich
    HRV (Ring-Methode, nicht mit SDNN vergleichbar): 46 ms, im üblichen Bereich
    Sauerstoffsättigung Nacht (Mittel): 97 %
    """
}

extension SendPreview {
    /// Preview of one expert round: the fact list is the payload; the estimate covers all five requests.
    public static func conference(facts: String, consent: Set<ConsentCategory>, model: ClaudeModel,
                                  sendBudget: SendBudget) -> SendPreview {
        let sent = CompanionConference.sentCategories(consent: consent)
        return SendPreview(title: CompanionPrompts.conferenceTitle, periodText: "heute",
                           categoriesSent: sent,
                           categoriesWithheld: ConsentCategory.allCases.filter { !sent.contains($0) },
                           alwaysWithheld: neverSent,
                           factCount: facts.split(separator: "\n").count,
                           estimate: CompanionConference.estimate(facts: facts, model: model),
                           model: model, sendsRemaining: sendBudget.remaining, payload: facts)
    }
}
