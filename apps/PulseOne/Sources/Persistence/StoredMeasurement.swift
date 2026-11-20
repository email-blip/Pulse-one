import Foundation
import PulseCore
import SwiftData

/// A real measurement on disk, with origin. Stays on the device (directive §11).
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
}
