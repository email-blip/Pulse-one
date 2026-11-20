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
                  originalSampleID: Self.ringSampleID(source: reading.source, timestamp: reading.timestamp, kind: kind),
                  method: method)
    }

    /// The ring has no sample ids of its own: time (milliseconds), origin and kind identify a value.
    public static func ringSampleID(source: MeasurementSource, timestamp: Date, kind: SampleKind) -> String {
        let prefix = source == .ringLive ? "live" : "history"
        let millis = Int64((timestamp.timeIntervalSince1970 * 1_000).rounded())
        return "\(prefix)-\(millis)-\(kind.rawValue)"
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
