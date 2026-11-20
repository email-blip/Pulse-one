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
    case respiratoryRate = "respiratory_rate"
    case basalEnergy = "basal_energy"
    case vo2Max = "vo2max"
    case bodyMass = "body_mass"
    case height

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
        case .respiratoryRate: .breathsPerMinute
        case .basalEnergy: .kilocalories
        case .vo2Max: .millilitersPerKilogramMinute
        case .bodyMass: .kilograms
        case .height: .meters
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
        case .respiratoryRate: 4...60
        case .basalEnergy: 0...10_000
        case .vo2Max: 10...95
        case .bodyMass: 20...400
        case .height: 0.5...2.6
        }
    }

    /// Kinds that are summed over a period. Summing two sources of the same period double counts.
    public var isCumulative: Bool { aggregation == .cumulative || aggregation == .interval }

    /// How values of this kind combine over a day (Review 3.2 §6).
    public var aggregation: SampleAggregation {
        switch self {
        case .heartRate, .heartRateVariability, .oxygenSaturation, .skinTemperature, .bodyTemperature, .deviceBattery,
             .respiratoryRate, .bodyMass, .height: .point
        case .sleepDuration, .trainingDuration: .interval
        case .steps, .activeEnergy, .distance, .elevationGain, .basalEnergy: .cumulative
        case .restingHeartRate, .skinTemperatureDeviation, .vo2Max: .derived
        }
    }

    /// Where and how a temperature is measured; temperatures from different sites are never mixed.
    public var measurementSite: String? {
        switch self {
        case .skinTemperature: "Haut (absolut, Finger oder Handgelenk)"
        case .skinTemperatureDeviation: "Haut (Abweichung vom persönlichen Mittel, nachts)"
        case .bodyTemperature: "Körperkern (Thermometer)"
        default: nil
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
        case .respiratoryRate: "Atemfrequenz"
        case .basalEnergy: "Ruheenergie"
        case .vo2Max: "VO₂max"
        case .bodyMass: "Gewicht"
        case .height: "Größe"
        }
    }
}

/// How samples of a kind combine over time.
public enum SampleAggregation: String, Codable, Sendable {
    /// Single readings (pulse, SpO₂): averaged after choosing one source per minute.
    case point
    /// Time spans (sleep, training): overlapping spans are merged, never added twice.
    case interval
    /// Counters per period (steps, energy): summed per hour from one source per hour.
    case cumulative
    /// Values a source already computed (resting pulse, temperature deviation): one source per day.
    case derived
    /// Manufacturer scores (readiness, sleep score): kept apart, never mixed between vendors.
    case vendorScore
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
    case breathsPerMinute = "breaths/min"
    case kilograms = "kg"
    case millilitersPerKilogramMinute = "ml/kg/min"
}

/// Which system a value came from.
public enum DataSourceKind: String, Codable, CaseIterable, Sendable {
    case colmiRing = "colmi_ring"
    case appleHealth = "apple_health"
    case ouraCloud = "oura_cloud"
    case bluetoothStandard = "ble_standard"
    case manual

    public var title: String {
        switch self {
        case .colmiRing: "Ring"
        case .appleHealth: "Apple Health"
        case .ouraCloud: "Oura"
        case .bluetoothStandard: "Pulsgurt"
        case .manual: "Eingabe"
        }
    }
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

extension MeasurementMethod {
    /// Within one device, which measuring path wins when both describe the same minute.
    public static let preference: [MeasurementMethod] = [.liveSensor, .deviceHistory, .healthStore, .cloudAPI, .manualEntry, .unknown]
}

/// How a sample is identified across syncs (Review 3.2 §3).
public enum SampleIdentity: String, Codable, Sendable {
    /// A: the source gave its own id (HealthKit UUID, Oura id).
    case sourceID = "source_id"
    /// B: no source id; a documented combination of device, kind, path, time, interval and value.
    case derived
}

/// Result of validation (Review 3.2 §5). Only `valid` and `plausible` feed analyses and the coach;
/// everything else is kept for diagnosis with its reason.
public enum SampleQuality: String, Codable, Sendable, CaseIterable {
    case unchecked
    /// Plausible and from a source confirmed on real hardware.
    case valid
    /// Plausible, but the source is not yet confirmed on real hardware.
    case plausible
    case implausible
    /// An interval without a usable end, or a value missing a needed part.
    case incomplete
    /// Time zone unknown or device clock slightly ahead.
    case timeUncertain = "time_uncertain"
    /// The device itself reported a measuring fault.
    case technicalError = "technical_error"

    public var usableForAnalysis: Bool { self == .valid || self == .plausible }

    public var label: String {
        switch self {
        case .unchecked: "ungeprüft"
        case .valid: "gültig"
        case .plausible: "plausibel, unbestätigt"
        case .implausible: "unplausibel"
        case .incomplete: "unvollständig"
        case .timeUncertain: "zeitlich unsicher"
        case .technicalError: "technisch fehlerhaft"
        }
    }
}

/// One normalised value (directive Phase A "Datenmodell", §5). Raw packets stay elsewhere and are
/// referenced by `rawDataReference`. Derived metrics and AI interpretations are separate types.
public struct HealthSample: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// The person who wore or carried the device at `start`; nil while that period is unresolved.
    public let profileID: UUID?
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
    /// Why the quality was given, in German, for the diagnosis.
    public let qualityReason: String?
    public let method: MeasurementMethod
    public let identity: SampleIdentity
    public let rawDataReference: String?

    public init(id: UUID = UUID(), profileID: UUID?, kind: SampleKind, value: Double, unit: SampleUnit,
                start: Date, end: Date? = nil, timeZoneIdentifier: String?, source: DataSourceKind,
                deviceID: String, originalSampleID: String, importedAt: Date, quality: SampleQuality,
                qualityReason: String? = nil, method: MeasurementMethod, identity: SampleIdentity = .sourceID,
                rawDataReference: String? = nil) {
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
        self.qualityReason = qualityReason
        self.method = method
        self.identity = identity
        self.rawDataReference = rawDataReference
    }

    /// The same sample attributed to another profile (explicit correction only, never by a sync).
    public func attributed(to profile: UUID?) -> HealthSample {
        HealthSample(id: id, profileID: profile, kind: kind, value: value, unit: unit, start: start, end: end,
                     timeZoneIdentifier: timeZoneIdentifier, source: source, deviceID: deviceID,
                     originalSampleID: originalSampleID, importedAt: importedAt, quality: quality,
                     qualityReason: qualityReason, method: method, identity: identity, rawDataReference: rawDataReference)
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
