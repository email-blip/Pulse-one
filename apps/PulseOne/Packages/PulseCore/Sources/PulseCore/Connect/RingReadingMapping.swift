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
                  method: method, identity: .derived)
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
