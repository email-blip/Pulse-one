import Foundation

/// ROOK in free conversation, spoken or typed: talks like a person, not in report format. The answer is plain
/// speakable text (no Markdown, no lists), streamed sentence by sentence so speech output can start after the
/// first sentence. The same memory serves voice and typing.
public enum RookSpeech {
    public static let promptVersion = 4
    /// Spoken answers stay short; this caps cost and the time until ROOK has finished talking.
    public static let maxOutputTokens = 400
    /// Turns of earlier conversation sent along (the full history stays on the iPhone).
    public static let historyTurns = 16

    /// System prompt: ROOK's character, the conversation rules and today's figures as context.
    public static func system(mode: SafetyMode, context: HealthAnalysisContext, current: RookStatement?) -> String {
        let talk = """
        Du sprichst gerade frei mit der Person, meist per Sprache. Antworte so, wie ein Mensch im Gespräch antwortet: \
        natürlich, direkt, auf das eingehen, was sie gerade gesagt hat. Meist ein bis drei kurze Sätze, nur wenn sie \
        ausdrücklich mehr wissen will etwas länger. Deine Antwort wird vorgelesen: kein Markdown, keine Aufzählungen, \
        keine Überschriften, keine Emojis, keine Abkürzungen wie „z. B.“ oder „ca.“, Zahlen so, wie man sie sagt. \
        Wenn du etwas wissen musst, stell genau eine Frage, und zwar am Ende. Smalltalk ist erlaubt, du musst nicht \
        jedes Mal auf Messwerte kommen. Erzählt die Person, dass sie krank ist, wenig Zeit hat oder sich anders fühlt, \
        nimm das ernst und pass deinen Vorschlag für heute an. Bei Brustschmerz, Atemnot, Lähmung, Sprachstörung oder \
        Ohnmacht sagst du zuerst, dass sie sofort den Notruf 112 wählen soll.
        """
        let rules = """
        Zahlen nur aus dem Kontext unten, nichts erfinden. Keine Prozentangaben für Ursachen oder Diagnosen, mögliche \
        Erklärungen mit „passt gut“, „passt teilweise“ oder „passt kaum“. Verordnete Medikamente nie umstellen lassen. \
        "hrv_ring" und "hrv_sdnn" sind verschiedene Verfahren und werden nie verglichen. Nie erwähnen: fehlende oder \
        alte Daten, Abgleich, Basislinien, Lernphasen, Rollen- oder Haftungshinweise.
        """
        var parts = [RookPrompts.voiceCharacter, talk, RookPrompts.scope(mode), rules]
        if let current {
            parts.append("Deine Deutung von heute, die die Person auf dem Bildschirm sieht: \(current.headline). "
                         + current.insight.interpretation)
        }
        parts.append("Kontext, auf dem iPhone berechnet:\n\(context.compactJSON())")
        return parts.joined(separator: "\n\n")
    }

    /// The conversation as Messages API turns: strictly alternating, starting with the person, ending with the new
    /// message. Earlier ROOK lines before the first person line are dropped; same-role lines are joined.
    public static func messages(history: [RookTurn], message: String) -> [JSONValue] {
        var turns: [(role: RookTurn.Role, text: String)] = []
        for turn in history.suffix(historyTurns) where !turn.text.isEmpty {
            if turns.isEmpty, turn.role == .rook { continue }
            if let last = turns.last, last.role == turn.role {
                turns[turns.count - 1].text += "\n" + turn.text
            } else {
                turns.append((turn.role, turn.text))
            }
        }
        if let last = turns.last, last.role == .person {
            turns[turns.count - 1].text += "\n" + message
        } else {
            turns.append((.person, message))
        }
        return turns.map { turn in
            .object(["role": .string(turn.role == .person ? "user" : "assistant"),
                     "content": .array([.object(["type": .string("text"), "text": .string(turn.text)])])])
        }
    }

    /// Makes one sentence speakable and safe: strips Markdown and list marks, guessed percentages and the
    /// forbidden phrases; returns nil when nothing sayable is left or the sentence breaks a safety rule.
    public static func speakable(_ sentence: String, mode: SafetyMode) -> String? {
        var text = sentence
        for mark in ["**", "__", "`", "#"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        text = ResponseValidator.removingGuessedPercentages(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, RookTextGuard.isClean(text) else { return nil }
        if case .reject = SafetyRules.check(text, mode: mode) { return nil }
        return text
    }
}

/// Cuts streamed text into finished sentences, so speech can start before Claude is done. A sentence ends at
/// ".", "!" or "?" followed by whitespace, or at a line break; "z. B.", "Dr." and decimal numbers do not end one.
public struct RookSentenceBuffer: Sendable {
    private var pending = ""
    private static let abbreviations = ["z. b.", "z.b.", "d. h.", "d.h.", "u. a.", "ca.", "dr.", "bzw.", "evtl.", "ggf.",
                                        "usw.", "inkl.", "min.", "std.", "nr.", "vs."]

    public init() {}

    /// Adds a piece of streamed text and returns the sentences it completed.
    public mutating func append(_ delta: String) -> [String] {
        pending += delta
        var sentences: [String] = []
        while let end = nextEnd() {
            let sentence = String(pending[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[end...])
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences
    }

    /// The rest after the stream ended.
    public mutating func finish() -> String? {
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return rest.isEmpty ? nil : rest
    }

    /// Index just after the first finished sentence, or nil.
    private func nextEnd() -> String.Index? {
        var index = pending.startIndex
        while index < pending.endIndex {
            let character = pending[index]
            let next = pending.index(after: index)
            if character == "\n" { return next }
            if ".!?".contains(character) {
                guard next < pending.endIndex else { return nil }
                // Swallow closing quotes or brackets that belong to the sentence.
                var end = next
                while end < pending.endIndex, "“”\"')»".contains(pending[end]) { end = pending.index(after: end) }
                guard end < pending.endIndex else { return nil }
                if pending[end].isWhitespace, !endsWithAbbreviation(upTo: next) {
                    // Wait for the next word: a lowercase start means the dot belonged to a date or abbreviation.
                    guard let start = pending[end...].firstIndex(where: { !$0.isWhitespace }) else { return nil }
                    if !pending[start].isLowercase { return end }
                }
            }
            index = next
        }
        return nil
    }

    private func endsWithAbbreviation(upTo end: String.Index) -> Bool {
        let head = pending[..<end].lowercased()
        if Self.abbreviations.contains(where: { head.hasSuffix(" " + $0) || head == $0 }) { return true }
        // A single letter before the dot ("z.", "d.") is an abbreviation, not a sentence.
        let letters = head.dropLast()
        guard let last = letters.last, last.isLetter else { return false }
        let before = letters.dropLast().last
        return before == nil || before == " " || before == "."
    }
}

/// One event of a streamed Messages API answer (server-sent events).
public enum AnthropicStreamEvent: Sendable, Equatable {
    case started(model: String, usage: TokenUsage)
    case text(String)
    case finished(stopReason: String?, outputTokens: Int)
    case failed(String)
}

/// Reads the `data:` lines of a streamed answer. Unknown events (pings, thinking, signatures) are skipped.
public enum AnthropicStreamParser {
    public static func event(fromLine line: String) -> AnthropicStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .string(let type)? = json["type"] else { return nil }
        switch type {
        case "message_start":
            guard let message = json["message"] else { return nil }
            var model = ""
            if case .string(let id)? = message["model"] { model = id }
            var usage = TokenUsage()
            if let raw = message["usage"], let encoded = try? raw.encoded(),
               let decoded = try? JSONDecoder().decode(TokenUsage.self, from: encoded) {
                usage = decoded
            }
            return .started(model: model, usage: usage)
        case "content_block_delta":
            guard let delta = json["delta"], case .string("text_delta")? = delta["type"],
                  case .string(let text)? = delta["text"] else { return nil }
            return .text(text)
        case "message_delta":
            var stop: String?
            if case .string(let reason)? = json["delta"]?["stop_reason"] { stop = reason }
            var output = 0
            if case .number(let tokens)? = json["usage"]?["output_tokens"] { output = Int(tokens) }
            return .finished(stopReason: stop, outputTokens: output)
        case "error":
            var message = "Fehler beim Streamen"
            if case .string(let text)? = json["error"]?["message"] { message = text }
            return .failed(message)
        default:
            return nil
        }
    }
}

public extension AnthropicAPI {
    /// Turns a request body into a streamed one, optionally with a smaller output cap.
    static func streaming(_ body: JSONValue, maxTokens: Int? = nil) -> JSONValue {
        guard case .object(var fields) = body else { return body }
        fields["stream"] = .bool(true)
        if let maxTokens { fields["max_tokens"] = .number(Double(maxTokens)) }
        return .object(fields)
    }
}
