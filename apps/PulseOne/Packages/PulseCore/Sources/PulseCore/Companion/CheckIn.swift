import Foundation

// Aktiver Begleiter (concept AKTIVER-BEGLEITER-KONZEPT.md, stage E-1): the companion looks at the values by
// itself in the morning, at midday and in the evening. Pure rules and data types, no I/O.

/// The three daily check-ins.
public enum CheckInSlot: String, Codable, Sendable, CaseIterable, Comparable {
    case morning, midday, evening

    public var title: String {
        switch self {
        case .morning: "Morgen-Check"
        case .midday: "Mittags-Check"
        case .evening: "Abend-Check"
        }
    }

    public var systemImage: String {
        switch self {
        case .morning: "sunrise"
        case .midday: "sun.max"
        case .evening: "moon.stars"
        }
    }

    private var order: Int {
        switch self {
        case .morning: 0
        case .midday: 1
        case .evening: 2
        }
    }

    public static func < (lhs: CheckInSlot, rhs: CheckInSlot) -> Bool { lhs.order < rhs.order }
}

/// When the check-ins happen. Times are local "hour * 60 + minute".
public struct CheckInSchedule: Codable, Sendable, Equatable {
    /// Morning check-in no later than this, even without a detected wake-up.
    public var morningMinute: Int
    public var middayMinute: Int
    public var eveningMinute: Int

    /// A wake-up is never taken before this local hour (same rule as `WakeDetector`).
    public static let earliestMorningHour = WakeDetector.earliestHour

    public init(morningMinute: Int = 8 * 60, middayMinute: Int = 12 * 60 + 30, eveningMinute: Int = 20 * 60 + 30) {
        self.morningMinute = morningMinute
        self.middayMinute = middayMinute
        self.eveningMinute = eveningMinute
    }

    public static let standard = CheckInSchedule()

    /// Start of `slot` on the day of `now`. The morning starts with the wake-up when one was detected
    /// after 04:00 and before the fixed morning time.
    public func start(of slot: CheckInSlot, on now: Date, wake: Date?, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: now)
        func at(_ minutes: Int) -> Date {
            calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
        }
        switch slot {
        case .morning:
            let fixed = at(morningMinute)
            let earliest = at(Self.earliestMorningHour * 60)
            if let wake, calendar.isDate(wake, inSameDayAs: now), wake >= earliest, wake < fixed { return wake }
            return fixed
        case .midday: return at(middayMinute)
        case .evening: return at(eveningMinute)
        }
    }

    /// The slot that should run now, or nil. A slot is due from its start until the next slot starts
    /// (the evening until midnight) and only if it has not run today. A missed slot is skipped, never
    /// repeated later: a morning report at 15:00 helps nobody.
    public func dueSlot(now: Date, wake: Date?, lastRuns: [CheckInSlot: Date], calendar: Calendar) -> CheckInSlot? {
        for slot in CheckInSlot.allCases.reversed() {
            let begin = start(of: slot, on: now, wake: wake, calendar: calendar)
            guard now >= begin else { continue }
            if let last = lastRuns[slot], calendar.isDate(last, inSameDayAs: now) { return nil }
            return slot
        }
        return nil
    }

    /// Next moment a check-in becomes due after `now` (for the background task and notifications).
    public func nextStart(after now: Date, calendar: Calendar) -> Date {
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for slot in CheckInSlot.allCases {
                let begin = start(of: slot, on: day, wake: nil, calendar: calendar)
                if begin > now { return begin }
            }
        }
        return now.addingTimeInterval(3_600)
    }
}

/// Symbols the companion uses on the day arc, in charts and in messages (concept §6.5).
public enum MarkerSymbol: String, Codable, Sendable, CaseIterable {
    /// ✦ the companion's interpretation
    case insight
    /// ▲ clearly above the usual range
    case above
    /// ▼ clearly below the usual range
    case below
    /// ⚡ training / activation
    case training
    /// ☾ sleep event
    case sleep
    /// ◆ recurring pattern
    case pattern
    /// ✚ own note / event
    case note
    /// ⚠ warning sign, please check
    case warning
    /// ★ best value
    case record

    /// SF Symbol name.
    public var systemImage: String {
        switch self {
        case .insight: "sparkle"
        case .above: "arrowtriangle.up.fill"
        case .below: "arrowtriangle.down.fill"
        case .training: "bolt.fill"
        case .sleep: "moon.fill"
        case .pattern: "diamond.fill"
        case .note: "plus.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .record: "star.fill"
        }
    }

    /// Spoken name for VoiceOver.
    public var spokenName: String {
        switch self {
        case .insight: "Hinweis"
        case .above: "über deinem üblichen Bereich"
        case .below: "unter deinem üblichen Bereich"
        case .training: "Training"
        case .sleep: "Schlaf"
        case .pattern: "Muster"
        case .note: "Notiz"
        case .warning: "Warnzeichen"
        case .record: "Bestwert"
        }
    }
}

public enum CheckInUrgency: String, Codable, Sendable, CaseIterable, Comparable {
    case none, watch, clarify, urgent

    private var order: Int {
        switch self {
        case .none: 0
        case .watch: 1
        case .clarify: 2
        case .urgent: 3
        }
    }

    public static func < (lhs: CheckInUrgency, rhs: CheckInUrgency) -> Bool { lhs.order < rhs.order }
}

public struct CheckInMarker: Codable, Sendable, Equatable {
    public var symbol: MarkerSymbol
    /// `SampleKind` raw value of the fact the marker belongs to, or "" for the day as a whole.
    public var metric: String
    public var text: String

    public init(symbol: MarkerSymbol, metric: String, text: String) {
        self.symbol = symbol
        self.metric = metric
        self.text = text
    }
}

/// What the companion says at one check-in (Claude's answer or the local fallback).
public struct CheckInMessage: Codable, Sendable, Equatable {
    /// One short line for the notification title, e.g. "Solide Nacht".
    public var headline: String
    /// At most three sentences.
    public var text: String
    /// One concrete next step, may be empty.
    public var suggestion: String
    public var urgency: CheckInUrgency
    public var markers: [CheckInMarker]

    public init(headline: String, text: String, suggestion: String, urgency: CheckInUrgency, markers: [CheckInMarker]) {
        self.headline = headline
        self.text = text
        self.suggestion = suggestion
        self.urgency = urgency
        self.markers = markers
    }

    /// Text for a notification body: message plus suggestion.
    public var notificationBody: String {
        suggestion.isEmpty ? text : text + " " + suggestion
    }
}

// MARK: - Local reading of the context

/// Deviations of today's values from the personal band, computed locally from the analysis context.
public struct CheckInDeviation: Equatable, Sendable {
    public let kind: String
    public let title: String
    public let value: Double
    public let unit: String
    public let median: Double
    public let direction: MarkerSymbol
}

public enum CheckInReader {
    /// A value counts as clearly outside when it lies beyond the band by more than half its width
    /// (at least 3 % of the median, so a very narrow band does not flag noise).
    public static func deviations(in context: HealthAnalysisContext) -> [CheckInDeviation] {
        context.facts.compactMap { fact in
            guard let band = fact.baseline, fact.stat != "so_far_today", fact.stat != "vendor_median" else { return nil }
            let margin = max((band.p75 - band.p25) / 2, abs(band.median) * 0.03)
            let direction: MarkerSymbol
            if fact.value > band.p75 + margin {
                direction = .above
            } else if fact.value < band.p25 - margin {
                direction = .below
            } else {
                return nil
            }
            return CheckInDeviation(kind: fact.kind, title: fact.title, value: fact.value, unit: fact.unit,
                                    median: band.median, direction: direction)
        }
    }

    /// Signals that, together, point to strain or a beginning infection (concept §6.7, Apple Vitals rule:
    /// only two or more at once count).
    static let strainSignals: [(kind: String, direction: MarkerSymbol)] = [
        (SampleKind.restingHeartRate.rawValue, .above),
        (SampleKind.heartRateVariability.rawValue, .below),
        (SampleKind.ringHRV.rawValue, .below),
        (SampleKind.respiratoryRate.rawValue, .above),
        (SampleKind.skinTemperatureDeviation.rawValue, .above),
        (SampleKind.oxygenSaturation.rawValue, .below),
    ]

    /// A single strain signal far from the usual value: resting pulse at least 8 bpm above, or HRV at least
    /// 30 % below the median.
    public static func strongSingle(_ deviations: [CheckInDeviation]) -> CheckInDeviation? {
        deviations.first { deviation in
            if deviation.kind == SampleKind.restingHeartRate.rawValue { return deviation.value - deviation.median >= 8 }
            let hrvKinds = [SampleKind.ringHRV.rawValue, SampleKind.heartRateVariability.rawValue]
            if hrvKinds.contains(deviation.kind), deviation.median > 0 {
                return (deviation.value - deviation.median) / deviation.median <= -0.3
            }
            return false
        }
    }

    /// Number of strain signals among the deviations.
    public static func strainCount(_ deviations: [CheckInDeviation]) -> Int {
        deviations.filter { deviation in
            strainSignals.contains { $0.kind == deviation.kind && $0.direction == deviation.direction }
        }.count
    }
}

// MARK: - Local fallback text

/// The message without Claude (no key, offline, budget used up, or an answer that failed the safety check).
public enum LocalCheckIn {
    public static func compose(slot: CheckInSlot, context: HealthAnalysisContext, name: String) -> CheckInMessage {
        let deviations = CheckInReader.deviations(in: context)
        let strain = CheckInReader.strainCount(deviations)
        // P1-005: one clearly changed value can be enough, two at once are not required for every hint.
        let strong = CheckInReader.strongSingle(deviations)
        var markers = deviations.prefix(4).map { deviation in
            CheckInMarker(symbol: deviation.direction, metric: deviation.kind,
                          text: "\(deviation.title) \(number(deviation.value)) \(deviation.unit), üblich \(number(deviation.median))")
        }
        let headline: String
        let text: String
        var urgency = CheckInUrgency.none
        if context.facts.isEmpty {
            // ROOK (plan §9): without values a normal greeting and an offer, never a report about missing data.
            headline = "Hallo"
            text = "Wie fühlst du dich heute? Sag es mir kurz, dann planen wir den Tag zusammen."
        } else if strain >= 2 || strong != nil {
            headline = "Dein Körper arbeitet"
            let what = strain >= 2 ? "\(strain) Werte weichen gleichzeitig ab" : "\(strong?.title ?? "Ein Wert") weicht deutlich ab"
            text = "\(what). Mögliche Gründe: beginnender Infekt, zu wenig Erholung, Alkohol oder Stress. Nimm heute Tempo raus."
            urgency = .watch
            markers.insert(CheckInMarker(symbol: .warning, metric: "", text: what), at: 0)
        } else if let first = deviations.first {
            headline = first.direction == .above ? "\(first.title) erhöht" : "\(first.title) niedrig"
            text = "\(first.title) liegt heute klar \(first.direction == .above ? "über" : "unter") deinem Üblichen, der Rest passt. "
                + "Kein Drama, aber ich behalte es im Blick."
        } else {
            headline = slot == .evening ? "Ruhiger Tag" : "Alles im Rahmen"
            text = "Alles in deinem Rahmen, nichts zieht gerade an dir."
        }
        return CheckInMessage(headline: headline, text: text, suggestion: suggestion(for: slot, strain: urgency == .watch ? 1 : 0),
                              urgency: urgency, markers: markers)
    }

    static func suggestion(for slot: CheckInSlot, strain: Int) -> String {
        if strain >= 1 { return "Heute lieber locker bewegen statt hart trainieren." }
        switch slot {
        case .morning: return "Starte mit deiner Aktivierung."
        case .midday: return "Zehn Minuten draußen gehen tut jetzt gut."
        case .evening: return "Bildschirm bald weg, damit die Nacht gut wird."
        }
    }

    static func number(_ value: Double) -> String {
        let rounded = abs(value) >= 10 ? value.rounded() : (value * 10).rounded() / 10
        let formatted = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return formatted.replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Claude

// The prompts and the answer check live in `RookPrompts` and `RookValidator` (ROOK, prompt version 3). The
// companion prompts v2 (asking to list what is missing, "measured: …" lists) were removed with the rebuild (Auftrag 04).

// MARK: - When to ask Claude and when to notify (P1-005)

/// Decides whether a check-in needs a new Claude call and whether it is worth a notification.
/// Nothing new → no call, no push. Stale data are never presented as the current night.
public enum CheckInPolicy {
    /// Data older than this do not describe the current day or night.
    public static let staleAfter: TimeInterval = 18 * 3_600
    public static let maxPushesPerDay = 2
    public static let minimumPushGap: TimeInterval = 3 * 3_600
    /// No notifications from 22:00 to 07:00 unless something needs action now.
    public static let quietHours: (start: Int, end: Int) = (22, 7)

    /// Stable summary of the facts; equal fingerprints mean nothing new was measured.
    public static func fingerprint(_ context: HealthAnalysisContext) -> String {
        context.facts.map { "\($0.kind)|\($0.stat)|\(($0.value * 10).rounded() / 10)|\($0.n)" }.sorted().joined(separator: ";")
    }

    public static func isStale(newestSample: Date?, now: Date) -> Bool {
        guard let newestSample else { return true }
        return now.timeIntervalSince(newestSample) > staleAfter
    }

    /// The local text when the data are stale: a normal greeting and an offer (ROOK, plan §9). Old values are
    /// never interpreted as the current day, and ROOK does not report about syncing.
    public static func staleMessage(newestSample: Date?, now: Date, calendar: Calendar = .current) -> CheckInMessage {
        let hello = RookLocal.salutation(at: now, slot: nil, calendar: calendar)
        return CheckInMessage(headline: hello, text: "Wie fühlst du dich heute? Sag es mir kurz, dann planen wir den Tag zusammen.",
                              suggestion: "", urgency: .none, markers: [])
    }

    public static func shouldCallClaude(fingerprint: String, lastFingerprint: String?, stale: Bool, hasFacts: Bool) -> Bool {
        hasFacts && !stale && fingerprint != lastFingerprint
    }

    /// A notification only for something new that matters: a higher urgency than before, a new clearly changed
    /// value, or the first fresh night of the day. Daily limit, minimum gap and quiet hours apply; an urgent
    /// or clarify message ignores gap and quiet hours.
    public static func shouldNotify(_ message: CheckInMessage, previous: CheckInMessage?, freshNight: Bool,
                                    pushesToday: [Date], now: Date, calendar: Calendar) -> Bool {
        let important = message.urgency >= .clarify
        if !important {
            let hour = calendar.component(.hour, from: now)
            if hour >= quietHours.start || hour < quietHours.end { return false }
            if pushesToday.count >= maxPushesPerDay { return false }
            if let last = pushesToday.max(), now.timeIntervalSince(last) < minimumPushGap { return false }
        }
        if message.urgency > (previous?.urgency ?? .none) { return true }
        let changed: Set<MarkerSymbol> = [.above, .below, .warning]
        let before = Set((previous?.markers ?? []).filter { changed.contains($0.symbol) }.map { "\($0.symbol.rawValue)|\($0.metric)" })
        let current = Set(message.markers.filter { changed.contains($0.symbol) }.map { "\($0.symbol.rawValue)|\($0.metric)" })
        if !current.subtracting(before).isEmpty { return true }
        return freshNight
    }
}
