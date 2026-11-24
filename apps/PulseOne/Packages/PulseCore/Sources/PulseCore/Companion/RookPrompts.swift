import Foundation

/// ROOK's prompts for Claude (check-ins and the conversation). Version 3 replaces the companion prompts v2:
/// interpretation → direction → next action in at most three sentences, no lists of numbers, no sentences about
/// missing data, baselines or learning phases, no disclaimers (plan §9). The data rules stay strict and are
/// enforced again on the device by `RookValidator`.
public enum RookPrompts {
    public static let version = 3
    /// Short answers keep the daily cost low (three check-ins with Sonnet stay within the approved ~2.50 $/month).
    public static let expectedOutputTokens = 450

    /// Who ROOK is and how he sounds; shared by the check-ins (`voice`) and the free conversation (`RookSpeech`).
    static let voiceCharacter = """
    Du bist ROOK, der Gesundheitscoach in der privaten App PULSE ONE. Du ordnest die gemessenen Entwicklungen der Person \
    verständlich ein, erkennst Verbesserungen, sprichst Auffälligkeiten an und schlägst den nächsten sinnvollen Schritt vor. \
    Training ist eine deiner Möglichkeiten, nicht dein einziges Thema.
    Ton: locker, direkt, wie ein guter Kumpel mit Fachwissen. Du-Form, kurze Sätze, gelegentlich trockener Humor. \
    Kein Schleimen, kein Belehren, keine Emojis, keine Ausrufezeichen-Ketten. Die Person entscheidet; du schlägst vor.
    """

    static let voice = voiceCharacter + "\n" + """
    Aufbau immer: Deutung, dann Richtung, dann die nächste Handlung, zusammen höchstens drei Sätze. Keine Aufzählungen \
    von Messwerten im sichtbaren Text; die Zahlen gehören in observation, das öffnet sich unter „Warum?“.
    Nie im sichtbaren Text: Hinweise auf fehlende, alte oder lückenhafte Daten, Abgleich oder Synchronisierung, \
    Basislinien, Lernphasen, Messmethoden, Rollen- oder Haftungshinweise. Ohne eigene Vergleichswerte vergleichst du mit \
    Erfahrungswerten für Alter und Geschlecht. Ohne aktuelle Grundlage begrüßt du die Person normal und bietest eine \
    passende Interaktion an, ohne Tagesdiagnose.
    Immer: keine erfundenen Werte; keine Prozentangaben für Ursachen oder Diagnosen, mögliche Erklärungen nur mit \
    „passt gut“, „passt teilweise“ oder „passt kaum“; verordnete Medikamente nie umstellen lassen. Bei Warnzeichen rätst \
    du kurz und klar zur Abklärung (direction clarify), bei akuter Gefahr zum Notruf 112 (direction urgent).
    """

    static let dataRules = """
    Daten: Du bekommst einen JSON-Kontext mit Fakten, die das iPhone berechnet hat (IDs wie F1, C2, E3). Zahlen nur aus \
    diesen Fakten; nenne in evidence die IDs, auf die du dich stützt, und schreibe die IDs nicht in den Text. Ein Fakt mit \
    stat "so_far_today" ist der laufende Tag und nicht mit vollen Tagen vergleichbar. "hrv_ring" und "hrv_sdnn" sind \
    verschiedene Verfahren: nie vergleichen oder verrechnen. Deutsch, Zahlen mit Komma als Dezimaltrennzeichen.
    """

    static func scope(_ mode: SafetyMode) -> String {
        mode == .clinical
            ? "Du darfst medizinisch deuten und mögliche Ursachen einschließlich Erkrankungen nennen, in alternatives mit Einordnung."
            : "Beschreibe nur Entwicklungen und Zusammenhänge, keine Krankheitsnamen als Erklärung und keine Diagnosen."
    }

    static let answerFormat = """
    Antworte ausschließlich im vorgegebenen JSON-Schema:
    - headline: höchstens fünf Wörter, wie eine Schlagzeile („Wieder im Rhythmus“, „Heute Tempo raus“).
    - interpretation: höchstens drei Sätze, Deutung, Richtung, Handlung, möglichst ohne Zahlen.
    - observation: ein Satz, was die Daten zeigen, mit den entscheidenden Zahlen.
    - direction: improving (wird besser), stable (im Rahmen), strained (belastet), watch (im Blick behalten), \
    clarify (ärztlich abklären), urgent (sofort, Notruf 112).
    - action: kind startWorkout, rest, moveNow, goToBed, openTimeline, askUser, seeDoctor oder none; title ist der \
    Knopftext mit höchstens vier Wörtern.
    - evidence: IDs der Fakten, auf die du dich stützt.
    - alternatives: null bis drei andere mögliche Erklärungen, je title, fit (strong, partial, weak) und note (ein Satz).
    - uncertainty: ein Satz, wie sicher die Deutung ist und warum.
    - recheckHours: in wie vielen Stunden du wieder hinschaust (zum Beispiel 24), 0 wenn nicht nötig.
    """

    /// System prompt of an automatic check-in.
    public static func checkIn(slot: CheckInSlot, mode: SafetyMode) -> String {
        let moment: String = switch slot {
        case .morning: "Es ist Morgen. Deute die Nacht und was sie für den Tag heißt."
        case .midday: "Es ist Mittag. Ordne den bisherigen Tag ein und sag, was für den Nachmittag sinnvoll ist."
        case .evening: "Es ist Abend. Zieh kurz Bilanz und sag, was der Nacht hilft."
        }
        return [voice, "Du meldest dich von selbst. \(moment)", scope(mode), answerFormat, dataRules].joined(separator: "\n")
    }

    /// System prompt of the conversation in the Coach tab (one character, one history).
    public static func conversation(mode: SafetyMode) -> String {
        let talk = """
        Die Person schreibt dir im Coach-Tab. Antworte im Gespräch auf ihre Nachricht, höchstens drei Sätze, und frag \
        nach, wenn etwas unklar ist („Fühlst du dich auch so?“). Nimm Korrekturen ernst und passe die Empfehlung an; \
        die Messwerte selbst änderst du nie. Bei Beschwerden wie Brustschmerz, Atemnot, Lähmung oder Ohnmacht steht der \
        Notruf 112 am Anfang.
        """
        return [voice, talk, scope(mode), answerFormat, dataRules].joined(separator: "\n")
    }

    /// The user message of a conversation turn: facts, the current statement and the last turns.
    public static func conversationMessage(context: HealthAnalysisContext, current: RookStatement?,
                                           history: [RookTurn], message: String) -> String {
        var parts = ["Kontext:\n\(context.compactJSON())"]
        if let current {
            parts.append("Deine aktuelle Deutung: \(current.headline). \(current.insight.interpretation)")
        }
        let recent = history.suffix(8).map { turn in "\(turn.role == .person ? "Person" : "ROOK"): \(turn.text)" }
        if !recent.isEmpty { parts.append("Bisheriges Gespräch:\n" + recent.joined(separator: "\n")) }
        parts.append("Neue Nachricht der Person: \(message)")
        return parts.joined(separator: "\n\n")
    }

    public static var schema: JSONValue {
        let action: [String: JSONValue] = [
            "kind": AnalysisSchema.enumeration(["startWorkout", "rest", "moveNow", "goToBed", "openTimeline", "askUser",
                                                "seeDoctor", "none"]),
            "title": AnalysisSchema.string(),
        ]
        let alternative: [String: JSONValue] = [
            "title": AnalysisSchema.string(),
            "fit": AnalysisSchema.enumeration(["strong", "partial", "weak"]),
            "note": AnalysisSchema.string(),
        ]
        return AnalysisSchema.object([
            "headline": AnalysisSchema.string(),
            "interpretation": AnalysisSchema.string(),
            "observation": AnalysisSchema.string(),
            "direction": AnalysisSchema.enumeration(["improving", "stable", "strained", "watch", "clarify", "urgent"]),
            "action": AnalysisSchema.object(action),
            "evidence": AnalysisSchema.strings(),
            "alternatives": AnalysisSchema.array(AnalysisSchema.object(alternative)),
            "uncertainty": AnalysisSchema.string(),
            "recheckHours": .object(["type": .string("integer")]),
        ])
    }
}

/// One line of the conversation in the Coach tab.
public struct RookTurn: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case person, rook }

    public let id: UUID
    public let at: Date
    public let role: Role
    public let text: String
    /// ROOK's turns carry the full statement (action, "Warum?").
    public let statement: RookStatement?

    public init(id: UUID = UUID(), at: Date, role: Role, text: String, statement: RookStatement? = nil) {
        self.id = id
        self.at = at
        self.role = role
        self.text = text
        self.statement = statement
    }
}

/// Claude's answer as the schema defines it.
public struct RookReply: Codable, Equatable, Sendable {
    public struct Action: Codable, Equatable, Sendable {
        public let kind: String
        public let title: String
    }

    public struct Alternative: Codable, Equatable, Sendable {
        public let title: String
        public let fit: String
        public let note: String
    }

    public let headline: String
    public let interpretation: String
    public let observation: String
    public let direction: String
    public let action: Action
    public let evidence: [String]
    public let alternatives: [Alternative]
    public let uncertainty: String
    public let recheckHours: Int
}

/// Nothing unchecked reaches the screen: Claude's answer becomes a `RookStatement` only after these checks.
/// Unknown evidence ids are dropped; every measured number must belong to a cited fact; the safety rules apply
/// to every sentence; routine sentences (`RookTextGuard`) and guessed percentages are removed; the fixed
/// referral thresholds (S5) raise the direction to at least "clarify" whatever Claude wrote.
public enum RookValidator {
    public enum Failure: Error, Equatable {
        case unreadable
        case empty
        case unsafe(String)
        case invented(String)
    }

    /// Durations and clock times in advice ("zehn Minuten", "20 Minuten gehen", "um 22 Uhr") are not measurements.
    static let adviceNumbers = #"\d+(?:[.,]\d+)?\s*(?:Minuten|Minute|Min\.|Stunden|Stunde|Sekunden|Uhr|Wochen|Woche|Runden|Wiederholungen|x)\b"#

    public static func statement(json: String, context: HealthAnalysisContext, mode: SafetyMode, now: Date,
                                 subjectID: UUID?, calendar: Calendar) throws -> RookStatement {
        guard let data = json.data(using: .utf8), let reply = try? JSONDecoder().decode(RookReply.self, from: data) else {
            throw Failure.unreadable
        }
        let evidenceIDs = reply.evidence.filter { context.allIDs.contains($0) }
        let allowed = context.citableNumbers(for: evidenceIDs)

        func clean(_ text: String) -> String {
            RookTextGuard.cleaned(ResponseValidator.removingGuessedPercentages(SafetyRules.removingBoilerplate(text)))
        }
        func checkNumbers(_ text: String, advice: Bool) throws {
            let measured = advice
                ? text.replacingOccurrences(of: adviceNumbers, with: " ", options: [.regularExpression, .caseInsensitive])
                : text
            for number in ResponseValidator.numbers(in: measured) where !ResponseValidator.matches(number, allowed: allowed) {
                throw Failure.invented(ResponseValidator.display(number.value))
            }
        }
        var flags: [String] = []
        func checkSafety(_ text: String) throws {
            for sentence in RookTextGuard.sentences(text) {
                switch SafetyRules.check(sentence, mode: mode) {
                case .reject(_, let reason): throw Failure.unsafe(reason)
                case .flag(_, let reason): if !flags.contains(reason) { flags.append(reason) }
                case .allow: break
                }
            }
        }

        var interpretation = RookTextGuard.limited(clean(reply.interpretation))
        guard !interpretation.isEmpty else { throw Failure.empty }
        let headlineText = clean(reply.headline)
        let headline = headlineText.isEmpty ? RookLocal.name : headlineText
        let observation = clean(reply.observation)
        let uncertainty = clean(reply.uncertainty)
        try checkNumbers(interpretation, advice: true)
        try checkNumbers(headline, advice: true)
        try checkNumbers(observation, advice: false)
        for text in [headline, interpretation, observation, uncertainty, reply.action.title] { try checkSafety(text) }

        var alternatives: [RookAlternative] = []
        for item in reply.alternatives.prefix(3) {
            let note = clean(item.note)
            let title = clean(item.title)
            guard !title.isEmpty else { continue }
            try checkSafety(title + ". " + note)
            let fit: InsightFit = switch item.fit {
            case "strong": .strong
            case "partial": .partial
            default: .weak
            }
            alternatives.append(RookAlternative(title: title, fit: fit, note: note))
        }

        var direction = CoachDirection(rawValue: reply.direction) ?? .stable
        var action: CoachAction? = CoachActionKind(rawValue: reply.action.kind).flatMap { kind in
            kind == CoachActionKind.none ? nil : CoachAction(kind: kind, title: clean(reply.action.title).isEmpty ? "Los" : clean(reply.action.title))
        }
        var extra: [String] = flags
        // Without any fact there is nothing to diagnose today.
        if context.facts.isEmpty, direction != .urgent { direction = .stable }
        if let referral = SafetyRules.requiredReferral(facts: context.facts) {
            let minimum: CoachDirection = referral.level == .recommend ? .clarify : .watch
            if direction.severity < minimum.severity {
                direction = minimum
                if minimum == .clarify {
                    let kept = RookTextGuard.sentences(interpretation).prefix(2).joined(separator: " ")
                    interpretation = "Das würde ich abklären lassen. " + kept
                    action = CoachAction(kind: .seeDoctor, title: "Verlauf ansehen", payload: "timeline=recent")
                }
            }
            extra.append(referral.reason)
        }

        let period = interval(context.period, calendar: calendar) ?? RookLocal.dayInterval(now, calendar: calendar)
        let evidence = evidenceIDs.compactMap { id in context.facts.first { $0.id == id } }.map { fact in
            EvidenceRef(kind: SampleKind(rawValue: fact.kind), window: period, label: fact.title,
                        shownValue: FactUnits.text(fact.value, unit: fact.unit), comparison: comparison(fact.baseline, unit: fact.unit))
        }
        let track = evidence.first?.kind.flatMap { RookLocal.track(for: $0) }
        let recheck = reply.recheckHours > 0 ? now.addingTimeInterval(TimeInterval(min(reply.recheckHours, 72)) * 3_600) : nil
        let insight = CoachInsight(
            subjectID: subjectID, createdAt: now, observation: observation, interpretation: interpretation,
            direction: direction, evidence: evidence, action: action, priority: direction.severity,
            valid: RookLocal.dayInterval(now, calendar: calendar), recheckAt: recheck,
            narration: RookLocal.cues(interpretation, anchor: evidence.isEmpty ? nil : period, track: track))
        let why = RookWhy(
            comparison: context.comparisonPeriod.map { "Deine Werte vom \(dayText($0.start)) bis \(dayText($0.end))." }
                ?? "Erfahrungswerte für dein Alter und Geschlecht.",
            events: context.events.map { "\(dayText($0.date)): \($0.label)" },
            calculation: "Alle Kennzahlen hat dein iPhone berechnet; Claude hat nur diese Kennzahlen gesehen, keine Rohdaten. "
                + "Dein üblicher Bereich ist die mittlere Hälfte deiner Werte im Vergleichszeitraum.",
            alternatives: alternatives,
            uncertainty: ([uncertainty] + extra).filter { !$0.isEmpty }.joined(separator: " "))
        return RookStatement(insight: insight, headline: headline, why: why, source: .claude)
    }

    static func comparison(_ band: FactBaseline?, unit: String) -> String? {
        guard let band else { return nil }
        let range = "\(LocalCheckIn.number(band.p25))–\(LocalCheckIn.number(band.p75))"
        return "üblich \(unit.isEmpty || unit == "count" ? range : range + " " + unit), aus \(band.n) Tagen"
    }

    /// "2026-11-22" → "22.11."
    static func dayText(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let date = Int(parts[2]) else { return day }
        return "\(date).\(month)."
    }

    static func interval(_ period: AnalysisPeriod, calendar: Calendar) -> DateInterval? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(identifier: period.timezone) ?? calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: period.start), let last = formatter.date(from: period.end),
              let end = calendar.date(byAdding: .day, value: 1, to: last), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
