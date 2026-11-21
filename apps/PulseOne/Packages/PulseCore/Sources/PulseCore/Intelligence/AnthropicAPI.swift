import Foundation

/// Request and response shapes for `POST /v1/messages` (spec §3.2), kept free of networking so they
/// can be tested without a key. The app sends them with URLSession.
public enum AnthropicAPI {
    public static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let modelsURL = URL(string: "https://api.anthropic.com/v1/models")!
    public static let apiVersion = "2026-10-21"
    /// Lets a mistaken safety decline be re-run on another model instead of failing (spec §3.2).
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let maxTokens = 16_000

    public static func headers(apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": apiVersion, "anthropic-beta": fallbackBeta,
         "content-type": "application/json"]
    }

    public static func modelHeaders(apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": apiVersion]
    }

    /// One request body. `messages` is the whole conversation so far (tool loops append to it).
    public static func body(model: ClaudeModel, system: String, messages: [JSONValue], schema: JSONValue?,
                            effort: String, tools: [JSONValue] = []) -> JSONValue {
        var outputConfig: [String: JSONValue] = ["effort": .string(effort)]
        if let schema {
            outputConfig["format"] = .object(["type": .string("json_schema"), "schema": schema])
        }
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "max_tokens": .number(Double(maxTokens)),
            "output_config": .object(outputConfig),
            // Fixed system prompt as cached prefix: cheaper follow-up questions.
            "system": .array([.object(["type": .string("text"), "text": .string(system),
                                       "cache_control": .object(["type": .string("ephemeral")])])]),
            "messages": .array(messages),
            "fallbacks": .string("default"),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            body["tool_choice"] = .object(["type": .string("auto")])
        }
        return .object(body)
    }

    public static func userText(_ text: String) -> JSONValue {
        .object(["role": .string("user"), "content": .array([.object(["type": .string("text"), "text": .string(text)])])])
    }
}

/// The parts of a Messages API response PULSE ONE uses.
public struct AnthropicResponse: Decodable, Sendable, Equatable {
    public struct Block: Decodable, Sendable, Equatable {
        public let type: String
        public let text: String?
        public let id: String?
        public let name: String?
        public let input: JSONValue?
    }

    public let id: String
    public let model: String
    public let stopReason: String?
    public let content: [Block]
    public let usage: TokenUsage

    enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
    }

    /// Joined text blocks (thinking blocks have no `text`).
    public var text: String { content.filter { $0.type == "text" }.compactMap(\.text).joined() }

    public var toolUses: [Block] { content.filter { $0.type == "tool_use" } }

    /// The assistant turn exactly as received, for the next request of a tool loop.
    public static func assistantTurn(rawResponse data: Data) -> JSONValue? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), let content = value["content"] else { return nil }
        return .object(["role": .string("assistant"), "content": content])
    }

    public static func decode(_ data: Data) throws -> AnthropicResponse {
        try JSONDecoder().decode(AnthropicResponse.self, from: data)
    }
}

public enum AnthropicError: Error, Equatable, Sendable {
    case missingKey
    case invalidKey
    case noCredit(String)
    case rateLimited(retryAfter: Int?)
    case overloaded
    case badRequest(String)
    case refusal
    case truncated
    case offline
    case server(status: Int, message: String)

    /// Maps an HTTP status and error body (spec §3.2 "Fehler").
    public static func from(status: Int, body: Data, retryAfter: String?) -> AnthropicError {
        let message = (try? JSONDecoder().decode(JSONValue.self, from: body))?["error"]?["message"]?.stringValue ?? ""
        switch status {
        case 401, 403: return .invalidKey
        case 402: return .noCredit(message)
        case 429: return .rateLimited(retryAfter: retryAfter.flatMap { Int($0) })
        case 400 where message.lowercased().contains("credit"): return .noCredit(message)
        case 400: return .badRequest(message)
        case 529, 503: return .overloaded
        default: return .server(status: status, message: message)
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded: true
        case .server(let status, _): status >= 500
        default: false
        }
    }

    /// Plain German for the person (no codes in the first sentence).
    public var message: String {
        switch self {
        case .missingKey: "Es ist noch kein API-Schlüssel hinterlegt. Bitte unter „KI-Anbieter“ eintragen."
        case .invalidKey: "Der API-Schlüssel wurde abgelehnt. Bitte in der Anthropic Console prüfen und neu eintragen."
        case .noCredit(let m): "Das Anthropic-Konto hat kein Guthaben oder sein Limit erreicht. \(m)"
        case .rateLimited: "Claude ist gerade ausgelastet (zu viele Anfragen). Bitte in einer Minute erneut versuchen."
        case .overloaded: "Claude ist gerade überlastet. Bitte später erneut versuchen."
        case .badRequest(let m): "Die Anfrage wurde abgelehnt. \(m)"
        case .refusal: "Claude hat diese Anfrage nicht beantwortet. Es wird nichts Ungeprüftes angezeigt."
        case .truncated: "Die Antwort war zu lang und ist unvollständig. Bitte einen kürzeren Zeitraum wählen."
        case .offline: "Keine Internetverbindung. Die Analyse bleibt als Entwurf und kann später gesendet werden."
        case .server(let s, let m): "Fehler bei Anthropic (\(s)). \(m)"
        }
    }
}

/// Fixed prompts, versioned like the context (spec §3.1). German, "du". Two modes (see `SafetyMode`):
/// `clinical` interprets like a physician team (owner decision 2026-11-21), `descriptive` only describes.
public enum IntelligencePrompts {
    public static let version = 4

    /// Data rules shared by both modes: numbers, evidence ids, special stats.
    static let dataRules = """
    Datenregeln, ohne Ausnahme:
    1. Messwerte und Kennzahlen nur aus den Fakten (Wert, Basislinie median/p25/p75, n, Abdeckung in Prozent, \
    Differenz zur Basislinie, Prozentabweichung, rho). Erfinde keine Messwerte und rechne keine neuen Kennzahlen.
    2. Jede Aussage nennt in "evidence" die IDs der Fakten, auf die sie sich stützt (z. B. "F1", "C2", "E3", "Q4"). \
    Aussagen vom Typ measured, computed und observation brauchen mindestens eine ID. Schreibe die IDs nicht in den Text.
    3. Ein Fakt mit stat "so_far_today" ist der bisherige Stand des laufenden Tages: nicht mit vollen Tagen vergleichen \
    und nicht als niedrig bewerten. "hrv_sdnn" (Apple Health) und "hrv_ring" (Ring) sind verschiedene Messverfahren: \
    nie miteinander vergleichen oder verrechnen. Ein Fakt mit stat "vendor_median" ist ein Herstellerwert mit unbekannter \
    Methode (Stressindex des Rings): nur als Verlauf beschreiben, keinen Normalbereich nennen.
    4. Typen: measured = Messwert, computed = berechnete Kennzahl, observation = Beobachtung in den Daten, \
    interpretation = deine Deutung, recommendation = Vorschlag.
    5. Schreibe Deutsch, in der Du-Form, Zahlen mit Komma als Dezimaltrennzeichen und ohne Tausenderpunkt.
    """

    static let descriptiveRules = dataRules + """
    6. Keine Diagnosen, keine Krankheitsnamen als Erklärung, keine Wahrscheinlichkeiten für Erkrankungen, \
    keine Aussagen zu Medikamenten oder Nahrungsergänzung.
    7. Zusammenhänge sind beobachtet, nie Ursache. Schreibe „zusammen mit“, „gleichzeitig“, „häufiger an Tagen mit“, \
    nicht „weil“, „verursacht“ oder „führt zu“.
    8. Beschreibe relativ zum persönlichen Band (p25 bis p75), ohne Ampelfarben und ohne Wertung wie gut/schlecht.
    9. Benenne Datenlücken und geringe Abdeckung offen. Bei dünner Datenlage kurz bleiben.
    10. Ärztlicher Hinweis nur sachlich: „mention“ bei anhaltender deutlicher Abweichung, „recommend“ bei Werten, \
    die laut Fakten klar außerhalb üblicher Bereiche liegen; sonst „none“.
    """

    /// The owner's wish (2026-11-21): real interpretation like an internist, sports physician and coach,
    /// with diagnoses, probabilities, work-up and treatment, without disclaimers. Kept: clear urgency for
    /// warning signs, and uncertainty stated as probability.
    static let clinicalRules = dataRules + """
    Deine Rolle: Du bist ein erfahrenes Ärzteteam aus Innerer Medizin/Allgemeinmedizin, Kardiologie, Sportmedizin, \
    Schlafmedizin und Rehabilitation, zusammen mit einem Trainings- und Gesundheitscoach. Die Person nutzt ihre private \
    App mit ihren eigenen Daten und weiß, dass du kein behandelnder Arzt bist. Sie will eine ehrliche, fachlich \
    fundierte Interpretation ohne Einschränkungen.
    6. Interpretiere vollständig: Einschätzung des Gesundheits- und Trainingszustands, mögliche Diagnosen und \
    Differenzialdiagnosen, Ursachen und Zusammenhänge, Prognose der Entwicklung, wenn die Daten es tragen.
    7. Unsicherheit ehrlich als Wahrscheinlichkeit in Prozent, mit dem, was dafür und was dagegen spricht, und was die \
    Einschätzung ändern würde. Bedenke die Messgenauigkeit von Ring und Uhr (Bewegungsartefakte, Sitz, Lücken).
    8. Konkrete Empfehlungen: Abklärung (welche Untersuchung, Labor, EKG, Langzeit-EKG, Blutdruck, Schlaflabor, \
    Belastungstest, bei welcher Fachrichtung, wie dringend), Training mit Intensität und Umfang, Reha und Physiotherapie, \
    Tagesgestaltung, Schlaf, Ernährung, Behandlungsoptionen. Verschreibungspflichtige Mittel darfst du als Option nennen; \
    sag dazu, dass sie ärztlich verordnet werden. Verordnete Medikamente nie eigenmächtig absetzen oder umdosieren lassen.
    9. Keine Floskeln: Schreibe nie „ich bin kein Arzt“, „ersetzt keine ärztliche Beratung“ oder Ähnliches.
    10. Warnzeichen haben Vorrang: Bei Werten oder Beschwerden, die gefährlich sein können (z. B. Brustschmerz, \
    Atemnot, Ohnmacht, Lähmung, anhaltender Ruhepuls über 100 oder unter 40 ohne Ausdauertraining, wiederholte SpO₂ unter \
    90 %), sag gleich am Anfang klar, wie dringend: sofort Notruf 112, heute ärztlich, oder in den nächsten Tagen.
    11. Benenne Datenlücken offen, aber interpretiere trotzdem, was die Daten hergeben.
    12. Ärztlicher Hinweis im Feld medicalReferral: „recommend“, wenn eine Abklärung sinnvoll ist, „mention“ bei \
    Beobachtungen, die man im Blick behalten sollte, sonst „none“.
    """

    public static func rules(_ mode: SafetyMode) -> String {
        mode == .clinical ? clinicalRules : descriptiveRules
    }

    public static func report(_ mode: SafetyMode) -> String {
        let extra = mode == .clinical
            ? " Nutze die Abschnitte für Einschätzung, mögliche Ursachen und Diagnosen, Training und Erholung." : ""
        return """
        Du schreibst in der privaten Gesundheits-App PULSE ONE den Bericht über einen Zeitraum. Du bekommst einen \
        JSON-Kontext (HealthAnalysisContext v1) mit lokal berechneten Fakten und antwortest ausschließlich im \
        vorgegebenen JSON-Schema. Schreibe so ausführlich, wie die Daten es tragen.\(extra)

        """ + rules(mode)
    }

    public static func question(_ mode: SafetyMode) -> String {
        """
        Du beantwortest Fragen einer Person zu ihren eigenen Gesundheitsdaten in der App PULSE ONE. Du hast keinen \
        direkten Zugriff auf die Daten, sondern Werkzeuge, die lokal auf dem iPhone rechnen und Fakten mit IDs \
        zurückgeben. Frage nur ab, was du für die Antwort brauchst (höchstens 8 Abfragen). Antworte am Ende \
        ausschließlich im vorgegebenen JSON-Schema; jede Aussage belegt mit den IDs der Fakten aus den Werkzeugantworten.

        """ + rules(mode)
    }

    public static func detective(_ mode: SafetyMode) -> String {
        let scope: String = mode == .clinical
            ? "Nenne höchstens drei mögliche Erklärungen, auch medizinische (z. B. beginnender Infekt, Übertraining), "
                + "jeweils mit einer Gegenprobe („Wenn es ein Infekt ist, sollte …“) und einer Einschätzung good/partial/weak."
            : "Nenne höchstens drei mögliche Begleitumstände, jeweils mit einer Gegenprobe („Wenn es am Schlaf liegt, "
                + "sollte …“) und einer Einschätzung good/partial/weak. Keine Krankheitsnamen als Erklärung, nur eigene "
                + "Notizen und Messwerte."
        return """
        Du hilfst in PULSE ONE beim „Körper-Detektiv“: Ein Wert liegt außerhalb des persönlichen Bandes. Du bekommst \
        die Abweichung, frühere ähnliche Tage (Analogtage) und was danach in den eigenen Notizen stand. \(scope)

        """ + rules(mode)
    }

    /// The consultation ("Sprechstunde"): a running conversation with anamnesis, differential diagnoses
    /// and plan. Only in clinical mode.
    public static let consultation = """
    Du führst in der privaten Gesundheits-App PULSE ONE eine ärztliche Sprechstunde als Gespräch. Am Anfang bekommst \
    du einen JSON-Kontext mit lokal berechneten Fakten der letzten Wochen, dazu das Gedächtnis früherer Gespräche \
    (Anamnese, Beschwerden, frühere Einschätzungen). Mit den Werkzeugen kannst du weitere Kennzahlen lokal abfragen \
    (höchstens 8 Abfragen pro Antwort).
    So gehst du vor wie in einer guten Sprechstunde: Anamnese (aktuelle Beschwerden, Verlauf, Vorerkrankungen, \
    Medikamente, Familie, Schlaf, Belastung, Training, Ernährung, Stimmung), Befunde aus den Daten, Einschätzung, \
    Differenzialdiagnosen mit Wahrscheinlichkeit, Abklärung, Plan. Stelle in jeder Antwort 2 bis 5 gezielte Rückfragen, \
    solange das Bild unvollständig ist. Nutze die Antworten der Person und das Gedächtnis.
    Antworte ausschließlich im vorgegebenen JSON-Schema:
    - reply: deine Antwort im Gesprächston, direkt und konkret, ohne Floskeln.
    - assessment: Befunde und Einschätzung als einzelne Aussagen mit Typ und Beleg-IDs.
    - differentials: mögliche Diagnosen oder Zustände, likelihoodPercent 0 bis 100 (ehrlich, die Summe muss nicht 100 \
    ergeben), reasoning, supporting, against, workup (was es klären würde), evidence.
    - recommendations: area (workup, training, rehab, daily, sleep, nutrition, treatment, mind), priority (high, medium, \
    low), text, evidence.
    - anamnesisQuestions: deine Rückfragen.
    - urgency: none, routine (beim nächsten Arzttermin), soon (in den nächsten Tagen), today (heute ärztlich), \
    emergency (sofort 112); urgencyReason kurz.
    - memory: aktualisierte Zusammenfassung für das nächste Gespräch (Beschwerden, Angaben der Person, Vorerkrankungen, \
    Medikamente, aktuelle Einschätzung mit Wahrscheinlichkeiten, vereinbarte Schritte), höchstens 1200 Zeichen.

    """ + clinicalRules

    public static let experiment = """
    Du planst in PULSE ONE einen kleinen Selbstversuch (N-of-1) zu einer Alltagsfrage. Wähle einen Zielmesswert \
    aus der erlaubten Liste, zwei Bedingungen A und B, Blocklänge 3 bis 7 Tage, eine gerade Zahl von Blöcken \
    (4 bis 8), 0 bis 2 Auswaschtage und die Notizen, die täglich nötig sind. Nur Alltagsverhalten wie Koffein, \
    Bildschirm, Abendessen, Training oder Zubettgehzeit; nie Medikamente oder Nahrungsergänzung. \
    Antworte ausschließlich im vorgegebenen JSON-Schema, Deutsch, Du-Form.
    """
}
