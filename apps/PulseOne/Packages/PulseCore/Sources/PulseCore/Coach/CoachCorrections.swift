import Foundation

/// What the person's own words (corrections given to ROOK, team 04's `UserCorrection`) change in today's plan.
public struct CorrectionEffect: Equatable, Sendable {
    public var feelsSick = false
    public var skipToday = false
    public var easier = false
    public var minutesLimit: Int?
    public var avoidRegions: Set<BodyRegion> = []

    public init() {}

    public var isEmpty: Bool { self == CorrectionEffect() }

    /// Plan changes in the order the coach applies them; sickness is handled as a subjective check instead.
    public var intents: [CoachIntent] {
        guard !feelsSick else { return [] }
        if skipToday { return [.skipToday] }
        var result: [CoachIntent] = []
        if easier { result.append(.easier) }
        if let minutesLimit { result.append(.timeLimit(minutes: minutesLimit)) }
        return result
    }

    /// Adds sickness and body regions to the day's subjective check (the planner's hard rules then apply).
    public func merged(into check: SubjectiveCheck?) -> SubjectiveCheck? {
        guard feelsSick || !avoidRegions.isEmpty else { return check }
        var result = check ?? SubjectiveCheck()
        if feelsSick { result.feelsSick = true }
        result.painRegions.formUnion(avoidRegions)
        return result
    }
}

public enum CoachCorrections {
    static let sick = ["krank", "erkält", "fieber", "grippe", "infekt", "halsschmerz"]
    static let skip = ["heute nicht", "keine zeit", "aussetzen", "kein training", "lass heute"]
    static let tired = ["müde", "erschöpft", "kaputt", "platt", "schlecht geschlafen", "gestresst", "leichter"]
    static let regions: [(words: [String], region: BodyRegion)] = [
        (["knie"], .knee), (["rücken", "kreuz"], .back), (["schulter"], .shoulder), (["nacken"], .neck),
        (["hüfte"], .hip), (["fuß", "knöchel", "sprunggelenk", "ferse"], .ankleFoot),
        (["ellbogen", "handgelenk"], .elbowWrist),
    ]

    /// Corrections given on `day` (others are ignored: yesterday's "Ich bin krank" is not today's).
    public static func effect(of corrections: [UserCorrection], on day: Date, calendar: Calendar) -> CorrectionEffect {
        var effect = CorrectionEffect()
        for correction in corrections where calendar.isDate(correction.at, inSameDayAs: day) {
            let text = correction.text.lowercased()
            if sick.contains(where: { text.contains($0) }) { effect.feelsSick = true }
            if skip.contains(where: { text.contains($0) }) { effect.skipToday = true }
            if tired.contains(where: { text.contains($0) }) { effect.easier = true }
            if let minutes = minutesLimit(in: text) { effect.minutesLimit = min(effect.minutesLimit ?? minutes, minutes) }
            for entry in regions where entry.words.contains(where: { text.contains($0) }) {
                effect.avoidRegions.insert(entry.region)
            }
        }
        return effect
    }

    /// "nur 15 Minuten", "20 min": a number followed by min/minuten; written numbers up to 30 in steps of 5.
    static func minutesLimit(in text: String) -> Int? {
        let words = ["zehn": 10, "fünfzehn": 15, "zwanzig": 20, "fünfundzwanzig": 25, "dreißig": 30, "fünf": 5]
        if let range = text.range(of: #"(\d+)\s*min"#, options: .regularExpression) {
            let digits = text[range].prefix { $0.isNumber }
            if let value = Int(digits), value > 0 { return value }
        }
        for (word, value) in words.sorted(by: { $0.key.count > $1.key.count }) where text.contains(word + " min") {
            return value
        }
        return nil
    }
}
