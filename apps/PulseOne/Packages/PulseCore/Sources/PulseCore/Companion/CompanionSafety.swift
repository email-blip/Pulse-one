import Foundation

/// Local safety net for every companion text (own sentences, engine sentences and AI rewrites).
/// The companion describes trends relative to the personal band; it never diagnoses, never
/// rules an illness out, never recommends therapy or medication and never promises effects.
public enum CompanionSafety {
    /// Forbidden phrases, matched case-insensitively as substrings.
    /// "diagnose:" (with colon) catches "Diagnose: …" while the required "Das ist keine Diagnose." stays allowed.
    public static let forbiddenPhrases: [String] = [
        "du bist nicht krank",
        "bist nicht krank",
        "du bist gesund",
        "sehen gesund aus",
        "nicht erkrankt",
        "diagnose:",
        "du hast eine",
        "infektion festgestellt",
        "erkrankung festgestellt",
        "therapie",
        "medikament",
        "garantiert",
        "heilt",
        "stärkt dein immunsystem",
        "dein immunsystem kämpft"
    ]

    /// Returns the forbidden phrases found in `text` (in the order of `forbiddenPhrases`), empty when the text is fine.
    public static func violations(in text: String) -> [String] {
        forbiddenPhrases.filter { phrase in
            text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The text itself when it passes, nil when it contains a forbidden phrase.
    public static func sanitize(_ text: String) -> String? {
        violations(in: text).isEmpty ? text : nil
    }
}
