import Foundation

/// A keyword from the evening note (creative lab idea 4). Sensors know nothing about stress, alcohol
/// or a cold; these self-reported tags make correlations, detective and experiments meaningful.
public enum ContextTag: String, Codable, CaseIterable, Sendable {
    case stress
    case caffeine
    case alcohol
    case training
    case lateMeal = "late_meal"
    case screen
    case feelingIll = "feeling_ill"
    case poorSleep = "poor_sleep"
    case travel
    case relaxed

    public var title: String {
        switch self {
        case .stress: "Stress"
        case .caffeine: "Koffein"
        case .alcohol: "Alkohol"
        case .training: "Training"
        case .lateMeal: "Spätes Essen"
        case .screen: "Bildschirm spät"
        case .feelingIll: "Krankheitsgefühl"
        case .poorSleep: "Schlecht geschlafen"
        case .travel: "Unterwegs"
        case .relaxed: "Entspannt"
        }
    }

    public var symbol: String {
        switch self {
        case .stress: "bolt.heart"
        case .caffeine: "cup.and.saucer"
        case .alcohol: "wineglass"
        case .training: "figure.run"
        case .lateMeal: "fork.knife"
        case .screen: "iphone"
        case .feelingIll: "thermometer.medium"
        case .poorSleep: "moon.zzz"
        case .travel: "airplane"
        case .relaxed: "leaf"
        }
    }
}

/// A self-reported note with its confirmed tags. The free text never leaves the device; only the tags
/// may go into an analysis context, and only with the "notes" consent.
public struct ContextEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let tags: [ContextTag]
    /// 1 (sehr schlecht) to 5 (sehr gut), nil if not said.
    public let mood: Int?
    public let text: String

    public init(id: UUID = UUID(), date: Date, tags: [ContextTag], mood: Int?, text: String) {
        self.id = id
        self.date = date
        self.tags = tags
        self.mood = mood.map { min(max($0, 1), 5) }
        self.text = text
    }

    /// Short label for contexts and lists, built from tags only (no free text).
    public var tagLabel: String {
        var parts = tags.map(\.title)
        if let mood { parts.append("Stimmung \(mood)/5") }
        return parts.isEmpty ? "Notiz ohne Stichworte" : parts.joined(separator: ", ")
    }
}

/// Result of reading a note; the user confirms or corrects it before it is saved.
public struct ParsedNote: Equatable, Sendable {
    public let tags: [ContextTag]
    public let mood: Int?
}

/// Rule-based keyword extraction in German. It is the fallback for the on-device model and the
/// reference its output is checked against. Content only: nothing is read from how a voice sounds.
public enum EveningNoteParser {
    /// Stems: a word matches when it equals the stem, starts with it (4+ letters) or ends with it
    /// (6+ letters, for compounds like "Milchkaffee" without "Preise" becoming "Reise").
    static let stems: [(ContextTag, [String])] = [
        (.stress, ["stress", "gestresst", "hektik", "hektisch", "ärger", "geärgert", "angespannt", "streit"]),
        (.caffeine, ["kaffee", "espresso", "cappuccino", "koffein", "cola", "energy", "latte"]),
        (.alcohol, ["bier", "biere", "wein", "alkohol", "sekt", "schnaps", "cocktail", "aperol", "gin", "whisky"]),
        (.training, ["training", "trainiert", "laufen", "gelaufen", "joggen", "gejoggt", "rad", "fahrrad", "radfahren", "radtour",
                     "fitness", "schwimmen", "geschwommen", "rudern", "gerudert", "fußball", "reiten", "geritten",
                     "yoga", "wandern", "gewandert", "workout", "gym", "kraft", "tennis", "klettern", "spinning"]),
        (.screen, ["handy", "bildschirm", "serie", "netflix", "fernsehen", "fernseher", "tv", "zocken", "gezockt",
                   "tablet", "laptop"]),
        (.feelingIll, ["krank", "erkältet", "erkältung", "halsschmerzen", "kopfschmerzen", "fieber", "schnupfen",
                       "husten", "schlapp", "grippe", "übel", "migräne"]),
        (.travel, ["reise", "flug", "geflogen", "zug", "hotel", "unterwegs", "dienstreise", "urlaub"]),
        (.relaxed, ["entspannt", "erholt", "ausgeruht", "gemütlich", "sauna", "meditiert", "meditation"]),
    ]

    static let phrases: [(ContextTag, [String])] = [
        (.lateMeal, ["spät gegessen", "spätes essen", "spät essen", "spät zu abend", "nachts gegessen",
                     "abendessen spät", "spät noch gegessen", "um mitternacht gegessen"]),
        (.poorSleep, ["schlecht geschlafen", "kaum geschlafen", "wenig geschlafen", "wach gelegen",
                      "nicht geschlafen", "unruhig geschlafen", "nicht einschlafen"]),
    ]

    static let negations: Set<String> = ["kein", "keine", "keinen", "keiner", "ohne", "nicht", "nichts"]

    public static func parse(_ text: String) -> ParsedNote {
        let lower = text.lowercased()
        let words = lower.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        var found: [ContextTag] = []
        for (tag, list) in phrases where list.contains(where: { lower.contains($0) }) && !found.contains(tag) {
            found.append(tag)
        }
        for (index, word) in words.enumerated() {
            for (tag, list) in stems where !found.contains(tag) {
                guard list.contains(where: { matches(word, stem: $0) }) else { continue }
                // "kein Kaffee", "ohne Alkohol": a negation in the two words before cancels the tag.
                let window = words[max(0, index - 2)..<index]
                if window.contains(where: { negations.contains($0) }) { continue }
                // "gut geschlafen" style phrases never make "poor sleep"; plain stems here are safe.
                found.append(tag)
            }
        }
        return ParsedNote(tags: ContextTag.allCases.filter { found.contains($0) }, mood: mood(in: lower, words: words))
    }

    static func matches(_ word: String, stem: String) -> Bool {
        if word == stem { return true }
        if stem.count >= 4, word.hasPrefix(stem) { return true }
        return stem.count >= 6 && word.hasSuffix(stem)
    }

    /// "Stimmung 4" wins; otherwise a few plain words. nil when nothing is said about mood.
    static func mood(in lower: String, words: [String]) -> Int? {
        if let range = lower.range(of: #"stimmung\D{0,4}([1-5])"#, options: .regularExpression),
           let digit = lower[range].last?.wholeNumberValue {
            return digit
        }
        let veryGood: Set<String> = ["super", "großartig", "fantastisch", "glücklich", "toll"]
        let good: Set<String> = ["gut", "zufrieden", "fröhlich", "prima"]
        let bad: Set<String> = ["schlecht", "mies", "traurig", "genervt", "gereizt", "niedergeschlagen"]
        let veryBad: Set<String> = ["furchtbar", "schrecklich", "katastrophal"]
        // "schlecht geschlafen" talks about sleep, not mood.
        let filtered = words.enumerated().filter { index, word in
            !(index + 1 < words.count && words[index + 1].hasPrefix("geschlafen"))
                && !(index > 0 && negations.contains(words[index - 1]))
        }.map(\.element)
        if filtered.contains(where: veryBad.contains) { return 1 }
        if filtered.contains(where: bad.contains) { return 2 }
        if filtered.contains(where: veryGood.contains) { return 5 }
        if filtered.contains(where: good.contains) { return 4 }
        return nil
    }
}
