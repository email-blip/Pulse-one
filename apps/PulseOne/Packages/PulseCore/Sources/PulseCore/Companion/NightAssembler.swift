import Foundation

/// One night value of one kind with the label of the source or method it came from.
public struct NightValue: Equatable, Sendable {
    public var day: Date
    public var value: Double
    /// Source or method label, e.g. "Ring-HRV" or "SDNN · Apple Health". Values with different labels are
    /// never compared with each other.
    public var source: String

    public init(day: Date, value: Double, source: String) {
        self.day = day
        self.value = value
        self.source = source
    }
}

/// Builds the nights for an insight without mixing sources: per kind, the source of the newest value wins
/// and older values from another source are left out of the comparison (Codex P1-005, source change).
public enum NightAssembler {
    public struct Result: Equatable, Sendable {
        public var nights: [NightPoint]
        public var restingHeartRateSource: String?
        public var hrvSource: String?
        public var sleepSource: String?
        /// Nights left out because they came from a different source than the newest value.
        public var droppedForSourceChange: Int

        public var sourceChanged: Bool { droppedForSourceChange > 0 }
    }

    public static func assemble(restingHeartRate: [NightValue], hrv: [NightValue], sleepHours: [NightValue],
                                calendar: Calendar) -> Result {
        var dropped = 0
        func pick(_ values: [NightValue]) -> (values: [Date: Double], source: String?) {
            guard let newest = values.max(by: { $0.day < $1.day }) else { return ([:], nil) }
            var result: [Date: Double] = [:]
            for value in values {
                guard value.source == newest.source else {
                    dropped += 1
                    continue
                }
                result[calendar.startOfDay(for: value.day)] = value.value
            }
            return (result, newest.source)
        }
        let rhr = pick(restingHeartRate)
        let variability = pick(hrv)
        let sleep = pick(sleepHours)
        let days = Set(rhr.values.keys).union(variability.values.keys).union(sleep.values.keys).sorted()
        let nights = days.map { day in
            NightPoint(date: day, restingHeartRate: rhr.values[day], hrv: variability.values[day], sleepHours: sleep.values[day])
        }
        return Result(nights: nights, restingHeartRateSource: rhr.source, hrvSource: variability.source,
                      sleepSource: sleep.source, droppedForSourceChange: dropped)
    }

    /// Origin line for the insight; names a source change so the comparison is never silently mixed.
    public static func originText(_ result: Result) -> String {
        let sources = [result.restingHeartRateSource, result.sleepSource].compactMap { $0 }
        var text = Array(Set(sources)).sorted().joined(separator: " + ")
        if text.isEmpty { text = "Keine Quelle" }
        if result.sourceChanged {
            text += " · Quelle gewechselt: verglichen wird nur mit Nächten derselben Quelle"
        }
        return text
    }
}
