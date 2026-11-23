import Foundation

/// Routine sentences ROOK never says in normal operation (NEUBAU-PLAN §9): disclaimers about not being a
/// physician, "can't read", "baseline missing", "still learning", "values are missing". Checked in three places:
/// the prompts and sample answers (tests), every UI text in the sources (`scripts/rook-text-guard.py` in CI) and
/// every answer from Claude before it is shown (`cleaned`).
public enum RookTextGuard {
    /// Lowercased fragments. Keep in sync with `FORBIDDEN` in `scripts/rook-text-guard.py`.
    public static let forbidden: [String] = [
        "kein arzt", "keine ärztin", "nicht lesen", "basislinie fehlt", "lernt noch", "fehlen mir",
        "sag ehrlich, was fehlt", "noch nicht abgeglichen", "ich lerne dein normal", "kein medizinprodukt",
    ]

    /// Also never in ROOK's visible or spoken text (UI test `NeubauM1` checks them too). Prompts may still use these
    /// words in their data rules, so the source scan does not include them.
    public static let forbiddenVisible: [String] = forbidden + ["basislinie", "fehlende daten", "synchronisier"]

    /// The forbidden fragments found in `text`; `visible` adds the words that only ROOK's own text must avoid.
    public static func violations(in text: String, visible: Bool = true) -> [String] {
        let lower = text.lowercased()
        return (visible ? forbiddenVisible : forbidden).filter { lower.contains($0) }
    }

    public static func isClean(_ text: String) -> Bool { violations(in: text).isEmpty }

    /// Drops every sentence that contains a forbidden fragment; the other sentences stay word for word.
    public static func cleaned(_ text: String) -> String {
        sentences(text).filter(isClean).joined(separator: " ")
    }

    /// Sentences of a German text, trimmed, without empty ones.
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            let sentence = (substring ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
        }
        return result
    }

    /// At most `limit` sentences (ROOK's visible text has three).
    public static func limited(_ text: String, to limit: Int = 3) -> String {
        sentences(text).prefix(limit).joined(separator: " ")
    }
}
