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

/// Fixed prompts, versioned like the context (spec §3.1). German, "du", descriptive only.
public enum IntelligencePrompts {
    public static let version = 3

    static let rules = """
    Regeln, ohne Ausnahme:
    1. Verwende nur Zahlen, die in den Fakten stehen (Wert, Basislinie median/p25/p75, n, Abdeckung in Prozent, \
    Differenz zur Basislinie, Prozentabweichung, rho). Erfinde keine Messwerte und rechne keine neuen Kennzahlen.
    2. Jede Aussage nennt in "evidence" die IDs der Fakten, auf die sie sich stützt (z. B. "F1", "C2", "E3"). \
    Aussagen vom Typ measured, computed und observation brauchen mindestens eine ID. Schreibe die IDs nicht in den Text.
    Ein Fakt mit stat "so_far_today" ist der bisherige Stand des laufenden Tages: nicht mit vollen Tagen vergleichen \
    und nicht als niedrig bewerten.
    "hrv_sdnn" und "hrv_ring" sind verschiedene Messverfahren: Werte nie miteinander vergleichen, verrechnen oder \
    als dieselbe Größe behandeln. Ein Fakt mit stat "vendor_median" ist ein Herstellerwert mit unbekannter Methode \
    (Stressindex des Rings): nur als Verlauf beschreiben, nicht bewerten, keinen Normalbereich nennen, keine Ursachen.
    3. Typen: measured = Messwert, computed = berechnete Kennzahl, observation = Beobachtung in den Daten, \
    interpretation = deine Deutung, recommendation = Vorschlag für den Alltag.
    4. Keine Diagnosen, keine Krankheitsnamen als Erklärung, keine Wahrscheinlichkeiten für Erkrankungen, \
    keine Aussagen zu Medikamenten oder Nahrungsergänzung. PULSE ONE ist kein Medizinprodukt.
    5. Zusammenhänge sind beobachtet, nie Ursache. Schreibe „zusammen mit“, „gleichzeitig“, „häufiger an Tagen mit“, \
    nicht „weil“, „verursacht“ oder „führt zu“.
    6. Beschreibe relativ zum persönlichen Band (p25 bis p75), ohne Ampelfarben und ohne Wertung wie gut/schlecht.
    7. Benenne Datenlücken und geringe Abdeckung offen. Bei dünner Datenlage kurz bleiben.
    8. Schreibe Deutsch, in der Du-Form, Zahlen mit Komma als Dezimaltrennzeichen und ohne Tausenderpunkt.
    9. Ärztlicher Hinweis nur sachlich: „mention“ bei anhaltender deutlicher Abweichung, „recommend“ bei Werten, \
    die laut Fakten klar außerhalb üblicher Bereiche liegen; sonst „none“.
    """

    public static let report = """
    Du bist der Analyse-Assistent der privaten Gesundheits-App PULSE ONE. Du bekommst einen JSON-Kontext \
    (HealthAnalysisContext v1) mit lokal berechneten Fakten über einen Zeitraum und antwortest ausschließlich im \
    vorgegebenen JSON-Schema. Schreibe so ausführlich, wie die Daten es tragen.

    """ + rules

    public static let question = """
    Du beantwortest Fragen einer Person zu ihren eigenen Gesundheitsdaten in der App PULSE ONE. Du hast keinen \
    direkten Zugriff auf die Daten, sondern Werkzeuge, die lokal auf dem iPhone rechnen und Fakten mit IDs \
    zurückgeben. Frage nur ab, was du für die Antwort brauchst (höchstens 8 Abfragen). Antworte am Ende \
    ausschließlich im vorgegebenen JSON-Schema; jede Aussage belegt mit den IDs der Fakten aus den Werkzeugantworten.

    """ + rules

    public static let detective = """
    Du hilfst in PULSE ONE beim „Körper-Detektiv“: Ein Wert liegt außerhalb des persönlichen Bandes. Du bekommst \
    die Abweichung, frühere ähnliche Tage (Analogtage) und was danach in den eigenen Notizen stand. Nenne höchstens \
    drei mögliche Begleitumstände, jeweils mit einer Gegenprobe („Wenn es am Schlaf liegt, sollte …“) und einer \
    Einschätzung good/partial/weak. Keine Krankheitsnamen als Erklärung, nur eigene Notizen und Messwerte.

    """ + rules

    public static let experiment = """
    Du planst in PULSE ONE einen kleinen Selbstversuch (N-of-1) zu einer Alltagsfrage. Wähle einen Zielmesswert \
    aus der erlaubten Liste, zwei Bedingungen A und B, Blocklänge 3 bis 7 Tage, eine gerade Zahl von Blöcken \
    (4 bis 8), 0 bis 2 Auswaschtage und die Notizen, die täglich nötig sind. Nur Alltagsverhalten wie Koffein, \
    Bildschirm, Abendessen, Training oder Zubettgehzeit; nie Medikamente oder Nahrungsergänzung. \
    Antworte ausschließlich im vorgegebenen JSON-Schema, Deutsch, Du-Form.
    """
}
