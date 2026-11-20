import Foundation

/// What a value measures. Units are fixed per metric.
public enum Metric: String, Codable, CaseIterable, Sendable {
    case heartRate = "heart_rate"
    case battery

    public var unit: String {
        switch self {
        case .heartRate: "bpm"
        case .battery: "%"
        }
    }

    public var title: String {
        switch self {
        case .heartRate: "Puls"
        case .battery: "Ring-Akku"
        }
    }

    /// Physiologically plausible range; values outside are rejected, not stored.
    public var plausibleRange: ClosedRange<Int> {
        switch self {
        case .heartRate: 25...240
        case .battery: 0...100
        }
    }
}

/// How the value reached the app.
public enum MeasurementSource: String, Codable, Sendable {
    /// Read live from a connected ring.
    case ringLive = "ring_live"
    /// Downloaded from the ring's stored history.
    case ringHistory = "ring_history"
}

/// One real value with timestamp and origin (directive §10.7, §11).
/// There is intentionally no "simulated" source: PULSE ONE never stores invented values.
public struct VitalReading: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let metric: Metric
    public let value: Int
    public let timestamp: Date
    public let source: MeasurementSource
    public let deviceName: String
    public let deviceIdentifier: String
    public let model: String?
    public let firmware: String?

    public init?(metric: Metric, value: Int, timestamp: Date, source: MeasurementSource,
                 deviceName: String, deviceIdentifier: String, model: String?, firmware: String?,
                 id: UUID = UUID()) {
        guard metric.plausibleRange.contains(value) else { return nil }
        self.id = id
        self.metric = metric
        self.value = value
        self.timestamp = timestamp
        self.source = source
        self.deviceName = deviceName
        self.deviceIdentifier = deviceIdentifier
        self.model = model
        self.firmware = firmware
    }

    public var unit: String { metric.unit }
}
