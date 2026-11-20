import Foundation

/// What a health sample measures (General Directive 3.0 §5). Temperatures are kept apart on purpose:
/// skin temperature, relative deviation and core body temperature are different things.
public enum SampleKind: String, Codable, CaseIterable, Sendable {
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case heartRateVariability = "hrv_sdnn"
    case oxygenSaturation = "spo2"
    case skinTemperature = "skin_temperature"
    case skinTemperatureDeviation = "skin_temperature_deviation"
    case bodyTemperature = "body_temperature"
    case steps
    case activeEnergy = "active_energy"
    case distance
    case sleepDuration = "sleep_duration"
    case trainingDuration = "training_duration"
    case elevationGain = "elevation_gain"
    case deviceBattery = "device_battery"

    /// The one unit every sample of this kind is stored in.
    public var canonicalUnit: SampleUnit {
        switch self {
        case .heartRate, .restingHeartRate: .beatsPerMinute
        case .heartRateVariability: .milliseconds
        case .oxygenSaturation, .deviceBattery: .percent
        case .skinTemperature, .bodyTemperature, .skinTemperatureDeviation: .celsius
        case .steps: .count
        case .activeEnergy: .kilocalories
        case .distance, .elevationGain: .meters
        case .sleepDuration, .trainingDuration: .seconds
        }
    }

    /// Physiologically or technically plausible range in the canonical unit.
    public var plausibleRange: ClosedRange<Double> {
        switch self {
        case .heartRate: 25...240
        case .restingHeartRate: 25...140
        case .heartRateVariability: 1...300
        case .oxygenSaturation: 70...100
        case .skinTemperature: 20...42
        case .skinTemperatureDeviation: -5...5
        case .bodyTemperature: 34...43
        case .steps: 0...100_000
        case .activeEnergy: 0...10_000
        case .distance: 0...300_000
        case .sleepDuration: 0...86_400
        case .trainingDuration: 0...86_400
        case .elevationGain: 0...10_000
        case .deviceBattery: 0...100
        }
    }

    /// Kinds that are summed over a period. Summing two sources of the same period double counts.
    public var isCumulative: Bool {
        switch self {
        case .steps, .activeEnergy, .distance, .elevationGain, .sleepDuration, .trainingDuration: true
        default: false
        }
    }

    public var title: String {
        switch self {
        case .heartRate: "Puls"
        case .restingHeartRate: "Ruhepuls"
        case .heartRateVariability: "HRV"
        case .oxygenSaturation: "Sauerstoffsättigung"
        case .skinTemperature: "Hauttemperatur"
        case .skinTemperatureDeviation: "Abweichung Hauttemperatur"
        case .bodyTemperature: "Körpertemperatur"
        case .steps: "Schritte"
        case .activeEnergy: "Aktive Energie"
        case .distance: "Strecke"
        case .sleepDuration: "Schlafdauer"
        case .trainingDuration: "Trainingsdauer"
        case .elevationGain: "Höhenmeter"
        case .deviceBattery: "Geräte-Akku"
        }
    }
}

/// Units that can arrive from sources. Named `SampleUnit` to avoid Foundation's `Unit`.
public enum SampleUnit: String, Codable, CaseIterable, Sendable {
    case beatsPerMinute = "bpm"
    case milliseconds = "ms"
    case seconds = "s"
    case minutes = "min"
    case hours = "h"
    case percent = "%"
    case fraction = "fraction"
    case celsius = "degC"
    case fahrenheit = "degF"
    case count
    case kilocalories = "kcal"
    case kilojoules = "kJ"
    case meters = "m"
    case kilometers = "km"
    case feet = "ft"
}

/// Which system a value came from.
public enum DataSourceKind: String, Codable, CaseIterable, Sendable {
    case colmiRing = "colmi_ring"
    case appleHealth = "apple_health"
    case ouraCloud = "oura_cloud"
    case bluetoothStandard = "ble_standard"
    case manual
}

/// How the value was obtained, as far as known.
public enum MeasurementMethod: String, Codable, Sendable {
    case liveSensor = "live_sensor"
    case deviceHistory = "device_history"
    case healthStore = "health_store"
    case cloudAPI = "cloud_api"
    case manualEntry = "manual_entry"
    case unknown
}

/// Result of validation. Implausible samples are kept with this flag for diagnosis, never shown as data.
public enum SampleQuality: String, Codable, Sendable {
    case unchecked
    case plausible
    case implausible
}

/// One normalised value (directive Phase A "Datenmodell", §5). Raw packets stay elsewhere and are
/// referenced by `rawDataReference`. Derived metrics and AI interpretations are separate types.
public struct HealthSample: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let profileID: UUID
    public let kind: SampleKind
    public let value: Double
    public let unit: SampleUnit
    public let start: Date
    public let end: Date
    /// IANA identifier of the time zone the measurement was taken in, if known.
    public let timeZoneIdentifier: String?
    public let source: DataSourceKind
    public let deviceID: String
    /// Identifier the source uses for this sample (HealthKit UUID, ring slot, Oura id).
    public let originalSampleID: String
    public let importedAt: Date
    public let quality: SampleQuality
    public let method: MeasurementMethod
    public let rawDataReference: String?

    public init(id: UUID = UUID(), profileID: UUID, kind: SampleKind, value: Double, unit: SampleUnit,
                start: Date, end: Date? = nil, timeZoneIdentifier: String?, source: DataSourceKind,
                deviceID: String, originalSampleID: String, importedAt: Date, quality: SampleQuality,
                method: MeasurementMethod, rawDataReference: String? = nil) {
        self.id = id
        self.profileID = profileID
        self.kind = kind
        self.value = value
        self.unit = unit
        self.start = start
        self.end = end ?? start
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
        self.deviceID = deviceID
        self.originalSampleID = originalSampleID
        self.importedAt = importedAt
        self.quality = quality
        self.method = method
        self.rawDataReference = rawDataReference
    }

    /// Identity across repeated syncs: the same source sample always maps to the same key.
    public var deduplicationKey: String {
        Self.deduplicationKey(source: source, deviceID: deviceID, kind: kind, originalSampleID: originalSampleID)
    }

    public static func deduplicationKey(source: DataSourceKind, deviceID: String, kind: SampleKind,
                                        originalSampleID: String) -> String {
        [source.rawValue, deviceID, kind.rawValue, originalSampleID].joined(separator: "|")
    }
}
