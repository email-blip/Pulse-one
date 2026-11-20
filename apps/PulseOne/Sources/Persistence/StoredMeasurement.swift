import Foundation
import PulseCore
import SwiftData

/// A real measurement on disk, with origin. Stays on the device (directive §11).
/// Legacy table from milestone 1. Since milestone 2 every ring value is also written to `StoredSample`,
/// and `SourcesStore.migrateLegacyMeasurements` copies older rows there once. Rows are kept, not deleted,
/// so the step can be checked and repeated; the Heart Chamber and the history card still read them.
@Model
final class StoredMeasurement {
    var metricRaw: String
    var value: Int
    var unit: String
    var timestamp: Date
    var sourceRaw: String
    var deviceName: String
    var deviceIdentifier: String
    var ringModel: String?
    var firmware: String?

    init(_ m: VitalReading) {
        metricRaw = m.metric.rawValue
        value = m.value
        unit = m.unit
        timestamp = m.timestamp
        sourceRaw = m.source.rawValue
        deviceName = m.deviceName
        deviceIdentifier = m.deviceIdentifier
        ringModel = m.model
        firmware = m.firmware
    }

    var metric: Metric? { Metric(rawValue: metricRaw) }

    /// The row as a reading again; nil for a metric or origin this version does not know, or an implausible value.
    var reading: VitalReading? {
        guard let metric, let source = MeasurementSource(rawValue: sourceRaw) else { return nil }
        return VitalReading(metric: metric, value: value, timestamp: timestamp, source: source, deviceName: deviceName,
                            deviceIdentifier: deviceIdentifier, model: ringModel, firmware: firmware)
    }
}
