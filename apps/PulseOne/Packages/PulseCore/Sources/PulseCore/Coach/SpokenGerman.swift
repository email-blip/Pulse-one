import Foundation

/// Turns a written German sentence into what the voice should say: times, units, abbreviations and a few
/// names that German voices otherwise read wrongly. The written text on screen stays unchanged.
public enum SpokenGerman {
    /// Fixed words, longest first so "SpO₂" wins over shorter parts.
    static let lexicon: [(written: String, spoken: String)] = [
        ("Nordic Hamstrings", "Nordik Hämstrings"),
        ("SpO₂", "Sauerstoffsättigung"),
        ("SpO2", "Sauerstoffsättigung"),
        ("90/90", "neunzig neunzig"),
        ("z. B.", "zum Beispiel"),
        ("Ø", "im Schnitt"),
        ("ROOK", "Ruuk"),
        ("R03", "R null drei"),
        ("R09", "R null neun"),
    ]

    /// Patterns in order; units after numbers before bare abbreviations.
    static let rules: [(pattern: String, template: String)] = [
        (#"\bHRV\b"#, "Ha Er Vau"),
        (#"\bRPE\b"#, "Anstrengung"),
        (#"\bca\."#, "circa"),
        (#"(\d)\s?bpm\b"#, "$1 Schläge pro Minute"),
        (#"(\d)\s?ms\b"#, "$1 Millisekunden"),
        (#"\b1\s?min\b"#, "eine Minute"),
        (#"(\d)\s?min\b"#, "$1 Minuten"),
        (#"\b1\s?s\b"#, "eine Sekunde"),
        (#"(\d)\s?s\b"#, "$1 Sekunden"),
        (#"(\d)\s?km\b"#, "$1 Kilometer"),
        (#"(\d)\s?kcal\b"#, "$1 Kilokalorien"),
        (#"(\d)\s?×\s?(\d)"#, "$1 mal $2"),
        (#"(\d)\s?×"#, "$1 mal"),
        (#"(\d)\s?–\s?(\d)"#, "$1 bis $2"),
    ]

    public static func prepare(_ text: String) -> String {
        var result = text
        for entry in lexicon {
            result = result.replacingOccurrences(of: entry.written, with: entry.spoken)
        }
        result = spokenTimes(result)
        for rule in rules {
            result = result.replacingOccurrences(of: rule.pattern, with: rule.template, options: .regularExpression)
        }
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "07:00" → "7 Uhr", "07:30" → "7 Uhr 30", "23:05" → "23 Uhr 5". Ratios like "3:1" stay (no two-digit minutes).
    static func spokenTimes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let hour = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let minute = Int(ns.substring(with: match.range(at: 2))) ?? 0
            result += minute == 0 ? "\(hour) Uhr" : "\(hour) Uhr \(minute)"
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        // "7 Uhr Uhr" when the text already said "07:00 Uhr".
        return result.replacingOccurrences(of: #"Uhr( \d+)? Uhr"#, with: "Uhr$1", options: .regularExpression)
    }
}

/// Which part of the app wants to speak. One queue for all of them (audio coordinator).
public enum SpeechChannel: String, Codable, Sendable {
    case greeting, interpretation, training, alert
}

public struct SpeechItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let channel: SpeechChannel
    /// Health content: not continued over the built-in speaker after headphones were lost.
    public let isSensitive: Bool
    /// Training cues are dropped when the session no longer accepts this token.
    public let workoutToken: WorkoutCueToken?

    public init(id: UUID = UUID(), text: String, channel: SpeechChannel, isSensitive: Bool, workoutToken: WorkoutCueToken? = nil) {
        self.id = id
        self.text = text
        self.channel = channel
        self.isSensitive = isSensitive
        self.workoutToken = workoutToken
    }
}

/// Ordering rules of the one speech queue. Nothing overlaps: the coordinator speaks one item at a time.
public struct SpeechQueue: Sendable, Equatable {
    public private(set) var pending: [SpeechItem] = []

    public init() {}

    public mutating func enqueue(_ item: SpeechItem) {
        switch item.channel {
        case .alert:
            pending.insert(item, at: 0)
        case .training:
            // A newer cue makes every older one stale; time-critical, so it goes before talk.
            pending.removeAll { $0.channel == .training }
            let index = pending.firstIndex { $0.channel != .alert } ?? pending.count
            pending.insert(item, at: index)
        case .greeting:
            guard !pending.contains(where: { $0.channel == .greeting }) else { return }
            pending.append(item)
        case .interpretation:
            pending.removeAll { $0.channel == .interpretation && $0.text == item.text }
            pending.append(item)
        }
    }

    public mutating func next() -> SpeechItem? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    public mutating func removeAll(where shouldRemove: (SpeechItem) -> Bool) {
        pending.removeAll(where: shouldRemove)
    }

    public mutating func clear() { pending.removeAll() }

    public var isEmpty: Bool { pending.isEmpty }
}

/// ROOK greets when the app is opened after a while, not on every tab change.
public enum GreetingPolicy {
    public static let minimumGap: TimeInterval = 4 * 3600

    public static func shouldGreet(lastGreeting: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastGreeting else { return true }
        if !calendar.isDate(lastGreeting, inSameDayAs: now) { return true }
        return now.timeIntervalSince(lastGreeting) >= minimumGap
    }
}
