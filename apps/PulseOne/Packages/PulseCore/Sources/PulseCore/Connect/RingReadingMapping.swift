import Foundation

/// The one mapping from a ring reading (`VitalReading`, also the shape of legacy `StoredMeasurement` rows)
/// to the normalised pipeline. The live path and the migration of old rows both use it, so the same
/// reading always gets the same `deduplicationKey` and a migrated value can never appear twice.
extension RawObservation {
    public init(reading: VitalReading, timeZoneIdentifier: String?) {
        let kind: SampleKind = reading.metric == .heartRate ? .heartRate : .deviceBattery
        let unit: SampleUnit = reading.metric == .heartRate ? .beatsPerMinute : .percent
        let method: MeasurementMethod = reading.source == .ringLive ? .liveSensor : .deviceHistory
        self.init(kind: kind, value: Double(reading.value), unit: unit, start: reading.timestamp,
                  timeZoneIdentifier: timeZoneIdentifier, source: .colmiRing, deviceID: reading.deviceIdentifier,
                  originalSampleID: Self.ringSampleID(source: reading.source, timestamp: reading.timestamp, kind: kind,
                                                      value: reading.value, interval: nil),
                  method: method, identity: .derived, receivedAt: reading.source == .ringLive ? reading.timestamp : nil)
    }

    /// Derived identity (Review 3.2 §3 B). The ring has no sample ids, and a timestamp alone is not unique
    /// (limited resolution, two readings at once). The id therefore combines path (live/history),
    /// time in milliseconds, the log interval when known, kind and value:
    /// - the same reading imported again gets the same id (no duplicate),
    /// - two different readings at the same time get different ids (both kept),
    /// - a live value and the history entry of the same minute stay two samples (overlap is handled
    ///   when evaluating, `DataSourceResolver`), never deleted.
    /// Limit: if a firmware update changes timestamp rounding, old and new history ids differ; the
    /// evaluation then still counts each minute only once, but the store holds both.
    public static func ringSampleID(source: MeasurementSource, timestamp: Date, kind: SampleKind,
                                    value: Int, interval: Int?) -> String {
        let prefix = source == .ringLive ? "live" : "history"
        let millis = Int64((timestamp.timeIntervalSince1970 * 1_000).rounded())
        let span = interval.map { "-i\($0)" } ?? ""
        return "\(prefix)-\(millis)\(span)-\(kind.rawValue)-v\(value)"
    }

    /// Identity of a ring history value: the slot, not the value. The ring keeps one value per slot
    /// (minute of a day log, quarter hour of steps, hour of SpO₂), but a slot that is still open grows
    /// between two syncs (steps of the current quarter hour). With the value in the id every sync stored
    /// the slot again (test team R1); without it the newer value replaces the older one.
    ///
    /// The slot is written as ring wall-clock time (`yyyyMMddHHmm` in the calendar's zone), because the
    /// ring itself only knows wall-clock time. After a time-zone change the same slot keeps its id (R7),
    /// where the absolute time would have produced a second copy of every overlapping day.
    public static func ringHistorySampleID(kind: SampleKind, slotStart: Date, interval: Int?, calendar: Calendar) -> String {
        let span = interval.map { "-i\($0)" } ?? ""
        return "history-wc\(wallClockStamp(slotStart, calendar: calendar, withTime: true))\(span)-\(kind.rawValue)"
    }

    /// Ring sleep: one session per night, identified by the day it ends on.
    public static func ringHistorySampleID(kind: SampleKind, nightEnding end: Date, calendar: Calendar) -> String {
        "history-night\(wallClockStamp(end, calendar: calendar, withTime: false))-\(kind.rawValue)"
    }

    static func wallClockStamp(_ date: Date, calendar: Calendar, withTime: Bool) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return withTime ? day + String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0) : day
    }
}

/// One-time repair of ring history rows stored with the old value-bearing id
/// (`history-<millis>[-i<n>]-<kind>-v<value>`). Each old row gets its slot id; where several old rows
/// share a slot (the duplicates of R1), the most recently imported one stays and the others are removed.
/// A row whose slot id is already stored is a proven duplicate and is removed. Live rows, other sources
/// and rows already in the new format are never selected. A second run finds nothing to do.
public enum RingHistoryIDMigration {
    public struct Plan: Equatable, Sendable {
        /// Kept rows with their new `originalSampleID`, same `id`.
        public var rekeyed: [HealthSample] = []
        public var duplicates: [UUID] = []

        public init() {}
        public var isEmpty: Bool { rekeyed.isEmpty && duplicates.isEmpty }
    }

    public static func isLegacy(_ sample: HealthSample) -> Bool {
        sample.source == .colmiRing && sample.method == .deviceHistory && sample.identity == .derived
            && sample.originalSampleID.hasPrefix("history-") && !sample.originalSampleID.hasPrefix("history-wc")
            && !sample.originalSampleID.hasPrefix("history-night")
    }

    /// The new id for an old row; nil when the old id cannot be read.
    public static func newID(for sample: HealthSample, fallbackZone: TimeZone) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sample.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? fallbackZone
        if sample.kind == .sleepDuration {
            return RawObservation.ringHistorySampleID(kind: .sleepDuration, nightEnding: sample.end, calendar: calendar)
        }
        let parts = sample.originalSampleID.split(separator: "-")
        let interval = parts.first { $0.hasPrefix("i") }.flatMap { Int($0.dropFirst()) }
        return RawObservation.ringHistorySampleID(kind: sample.kind, slotStart: sample.start, interval: interval,
                                                  calendar: calendar)
    }

    /// - Parameters:
    ///   - stored: ring rows of one device (others are ignored).
    ///   - existingKeys: dedup keys already stored for this device.
    public static func plan(stored: [HealthSample], existingKeys: Set<String>, fallbackZone: TimeZone) -> Plan {
        var plan = Plan()
        var taken = existingKeys
        let legacy = stored.filter(isLegacy)
        // Newest import first: for a growing slot it holds the most complete value.
        let ordered = legacy.sorted { ($0.importedAt, $0.value, $0.id.uuidString) > ($1.importedAt, $1.value, $1.id.uuidString) }
        for old in ordered {
            guard let id = newID(for: old, fallbackZone: fallbackZone) else { continue }
            let fixed = old.withOriginalSampleID(id)
            if taken.contains(fixed.deduplicationKey) {
                plan.duplicates.append(old.id)
            } else {
                taken.insert(fixed.deduplicationKey)
                plan.rekeyed.append(fixed)
            }
        }
        plan.duplicates.sort { $0.uuidString < $1.uuidString }
        return plan
    }
}

extension HealthSample {
    func withOriginalSampleID(_ newID: String) -> HealthSample {
        HealthSample(id: id, profileID: profileID, kind: kind, value: value, unit: unit, start: start, end: end,
                     timeZoneIdentifier: timeZoneIdentifier, source: source, deviceID: deviceID,
                     originalSampleID: newID, importedAt: importedAt, quality: quality, qualityReason: qualityReason,
                     method: method, identity: identity, rawDataReference: rawDataReference, originDetail: originDetail,
                     receivedAt: receivedAt)
    }
}

/// Result of moving legacy rows into the sample store.
public struct MigrationReport: Equatable, Sendable {
    public var read = 0
    public var inserted = 0
    public var alreadyPresent = 0
    /// Rows with a metric or origin this version does not know, or that failed validation.
    public var skipped = 0

    public init() {}
}
