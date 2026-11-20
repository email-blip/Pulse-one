import Foundation

/// A value as a source delivered it, before unit conversion and validation.
public struct RawObservation: Equatable, Sendable {
    public var kind: SampleKind
    public var value: Double
    public var unit: SampleUnit
    public var start: Date
    public var end: Date?
    public var timeZoneIdentifier: String?
    public var source: DataSourceKind
    public var deviceID: String
    public var originalSampleID: String
    public var method: MeasurementMethod
    public var rawDataReference: String?

    public init(kind: SampleKind, value: Double, unit: SampleUnit, start: Date, end: Date? = nil,
                timeZoneIdentifier: String? = nil, source: DataSourceKind, deviceID: String,
                originalSampleID: String, method: MeasurementMethod, rawDataReference: String? = nil) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
        self.deviceID = deviceID
        self.originalSampleID = originalSampleID
        self.method = method
        self.rawDataReference = rawDataReference
    }
}

extension RawObservation {
    /// Same key the normalised sample will have; lets the store look up existing rows before syncing.
    public var deduplicationKey: String {
        HealthSample.deduplicationKey(source: source, deviceID: deviceID, kind: kind, originalSampleID: originalSampleID)
    }
}

public enum NormalizationError: Error, Equatable, Sendable {
    case incompatibleUnit(SampleKind, SampleUnit)
    case notANumber
    case endBeforeStart
}

/// Converts units to the canonical unit of each kind and grades plausibility (directive §5).
public enum MeasurementNormalizer {
    public static func normalize(_ raw: RawObservation, profileID: UUID, importedAt: Date) throws -> HealthSample {
        guard raw.value.isFinite else { throw NormalizationError.notANumber }
        if let end = raw.end, end < raw.start { throw NormalizationError.endBeforeStart }
        let value = try convert(raw.value, from: raw.unit, to: raw.kind.canonicalUnit, kind: raw.kind)
        let quality: SampleQuality = raw.kind.plausibleRange.contains(value) ? .plausible : .implausible
        return HealthSample(profileID: profileID, kind: raw.kind, value: value, unit: raw.kind.canonicalUnit,
                            start: raw.start, end: raw.end, timeZoneIdentifier: raw.timeZoneIdentifier,
                            source: raw.source, deviceID: raw.deviceID, originalSampleID: raw.originalSampleID,
                            importedAt: importedAt, quality: quality, method: raw.method,
                            rawDataReference: raw.rawDataReference)
    }

    /// Unit conversion. A temperature deviation converts by scale only (no 32 °F offset).
    public static func convert(_ value: Double, from: SampleUnit, to: SampleUnit, kind: SampleKind) throws -> Double {
        if from == to { return value }
        switch (from, to) {
        case (.fraction, .percent): return value * 100
        case (.fahrenheit, .celsius):
            return kind == .skinTemperatureDeviation ? value * 5 / 9 : (value - 32) * 5 / 9
        case (.kilojoules, .kilocalories): return value / 4.184
        case (.kilometers, .meters): return value * 1_000
        case (.feet, .meters): return value * 0.3048
        case (.minutes, .seconds): return value * 60
        case (.hours, .seconds): return value * 3_600
        case (.seconds, .milliseconds): return value * 1_000
        default: throw NormalizationError.incompatibleUnit(kind, from)
        }
    }
}
