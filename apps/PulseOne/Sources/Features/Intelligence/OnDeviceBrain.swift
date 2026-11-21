import Foundation
import PulseCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "local brain" (creative lab idea 1): short daily lines, free and offline. Apple's on-device model
/// (iOS 26+, Apple Intelligence on) may rephrase the fixed sentences; its text is used only if it keeps
/// exactly the same numbers and passes the safety rules. Otherwise the fixed sentences stay.
enum OnDeviceBrain {
    struct Lines: Sendable, Equatable {
        let lines: [String]
        /// True when Apple's model phrased them, false for the fixed sentences.
        let rephrased: Bool
    }

    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func summary(_ context: HealthAnalysisContext, allowModel: Bool) async -> Lines {
        let fixed = LocalSentences.summary(context)
        guard allowModel, isModelAvailable, !context.facts.isEmpty else { return Lines(lines: fixed, rephrased: false) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let text = await rephrase(fixed), accepts(text, reference: fixed) {
                return Lines(lines: [text], rephrased: true)
            }
        }
        #endif
        return Lines(lines: fixed, rephrased: false)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func rephrase(_ lines: [String]) async -> String? {
        let prompt = """
        Fasse diese Zeilen in zwei bis drei ruhigen, freundlichen Sätzen auf Deutsch in der Du-Form zusammen. \
        Übernimm jede Zahl genau so, wie sie dasteht, und füge keine neuen Zahlen, Ursachen, Diagnosen oder \
        Ratschläge hinzu.

        \(lines.joined(separator: "\n"))
        """
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    #endif

    /// The model's text may only use numbers from the fixed sentences and must pass S1–S4 without a flag.
    static func accepts(_ text: String, reference: [String]) -> Bool {
        guard !text.isEmpty, text.count < 600 else { return false }
        // The small on-device model only rephrases fixed sentences, so it stays descriptive.
        guard case .allow = SafetyRules.check(text, mode: .descriptive) else { return false }
        let allowed = Set(reference.flatMap(numbers(in:)))
        return numbers(in: text).allSatisfy { allowed.contains($0) }
    }

    /// Digit groups as written ("7,2", "1.234", "58"), normalised to plain strings.
    static func numbers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).replacingOccurrences(of: ".", with: "") }
        }
    }
}
