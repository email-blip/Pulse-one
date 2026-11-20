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
    public var identity: SampleIdentity
    /// A fault the device itself reported for this reading (e.g. "Sensor ohne Hautkontakt").
    public var deviceFlag: String?
    public var rawDataReference: String?
    /// Origin inside an aggregating source, e.g. the app and device that wrote a HealthKit sample
    /// (`HealthOrigin`: "bundle|model|device hash"). Keeps devices apart in the resolver.
    public var originDetail: String?

    public init(kind: SampleKind, value: Double, unit: SampleUnit, start: Date, end: Date? = nil,
                timeZoneIdentifier: String? = nil, source: DataSourceKind, deviceID: String,
                originalSampleID: String, method: MeasurementMethod, identity: SampleIdentity = .sourceID,
                deviceFlag: String? = nil, rawDataReference: String? = nil, originDetail: String? = nil) {
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
        self.identity = identity
        self.deviceFlag = deviceFlag
        self.rawDataReference = rawDataReference
        self.originDetail = originDetail
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
    /// Later than the import time plus `MeasurementNormalizer.futureTolerance` (wrong device clock).
    case timestampInFuture
    /// Before `MeasurementNormalizer.earliestPlausibleDate`, typically a ring whose clock was never set.
    case timestampTooOld
}

/// Converts units to the canonical unit of each kind and grades plausibility (directive §5).
public enum MeasurementNormalizer {
    /// Allowed clock difference between a device and the iPhone.
    public static let futureTolerance: TimeInterval = 10 * 60
    /// 2010-01-01 UTC. Earlier timestamps come from unset clocks (1970, 2000), not from real measurements.
    public static let earliestPlausibleDate = Date(timeIntervalSince1970: 1_262_304_000)

    /// - Parameters:
    ///   - profileID: owner at `raw.start` from the device's assignment timeline; nil = unresolved.
    ///   - sourceConfirmed: the adapter's support for this kind was confirmed on real hardware.
    public static func normalize(_ raw: RawObservation, profileID: UUID?, importedAt: Date,
                                 sourceConfirmed: Bool = false) throws -> HealthSample {
        guard raw.value.isFinite else { throw NormalizationError.notANumber }
        if let end = raw.end, end < raw.start { throw NormalizationError.endBeforeStart }
        if raw.start < earliestPlausibleDate { throw NormalizationError.timestampTooOld }
        if raw.start > importedAt.addingTimeInterval(futureTolerance) { throw NormalizationError.timestampInFuture }
        let value = try convert(raw.value, from: raw.unit, to: raw.kind.canonicalUnit, kind: raw.kind)
        let (quality, reason) = grade(raw, value: value, importedAt: importedAt, sourceConfirmed: sourceConfirmed)
        return HealthSample(profileID: profileID, kind: raw.kind, value: value, unit: raw.kind.canonicalUnit,
                            start: raw.start, end: raw.end, timeZoneIdentifier: raw.timeZoneIdentifier,
                            source: raw.source, deviceID: raw.deviceID, originalSampleID: raw.originalSampleID,
                            importedAt: importedAt, quality: quality, qualityReason: reason, method: raw.method,
                            identity: raw.identity, rawDataReference: raw.rawDataReference,
                            originDetail: raw.originDetail)
    }

    /// First matching rule wins; the order is part of the contract (tested).
    static func grade(_ raw: RawObservation, value: Double, importedAt: Date,
                      sourceConfirmed: Bool) -> (SampleQuality, String) {
        if let flag = raw.deviceFlag { return (.technicalError, "Gerät meldet Fehler: \(flag)") }
        let range = raw.kind.plausibleRange
        if !range.contains(value) {
            return (.implausible, "Außerhalb \(range.lowerBound.formatted())–\(range.upperBound.formatted()) \(raw.kind.canonicalUnit.rawValue)")
        }
        if raw.kind.aggregation == .interval, (raw.end ?? raw.start) <= raw.start {
            return (.incomplete, "Zeitraum ohne Ende")
        }
        if raw.start > importedAt { return (.timeUncertain, "Zeitstempel liegt in der Zukunft (Geräteuhr geht vor)") }
        if raw.timeZoneIdentifier == nil { return (.timeUncertain, "Zeitzone unbekannt") }
        if sourceConfirmed { return (.valid, "Quelle am Gerät bestätigt") }
        return (.plausible, "Quelle noch nicht am Gerät bestätigt")
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

extension NormalizationError {
    /// Short German text for the device diagnosis.
    public var label: String {
        switch self {
        case let .incompatibleUnit(kind, unit): "\(kind.title): Einheit \(unit.rawValue) passt nicht"
        case .notANumber: "Wert ist keine Zahl"
        case .endBeforeStart: "Ende liegt vor dem Beginn"
        case .timestampInFuture: "Zeitstempel liegt in der Zukunft (Uhr des Geräts prüfen)"
        case .timestampTooOld: "Zeitstempel vor 2010 (Uhr des Geräts nicht gestellt)"
        }
    }
}
