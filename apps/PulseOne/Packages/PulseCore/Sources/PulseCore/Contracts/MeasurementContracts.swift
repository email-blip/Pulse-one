import Foundation

// Shared contracts of the rebuild (docs/neubau/VERTRAEGE.md). Owner: 00 Leitstand.
// Teams change these types only through the Leitstand.

/// One original measurement as every screen, chart and the coach see it ("Measurement" in the contract;
/// named `MeasurementPoint` because Foundation already has `Measurement`). Built from the one stored
/// `HealthSample` world; there is no second data store.
public struct MeasurementPoint: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    /// Person or animal the value belongs to; nil while unresolved.
    public let subjectID: UUID?
    public let deviceID: String
    public let source: DataSourceKind
    public let kind: SampleKind
    public let value: Double
    public let unit: SampleUnit
    public let method: MeasurementMethod
    /// Real measurement time (start of the slot for interval values).
    public let measuredAt: Date
    /// End of the interval; equal to `measuredAt` for point values.
    public let measuredUntil: Date
    /// When the app received the value from the device (BLE packet, HealthKit delivery).
    public let receivedAt: Date
    /// When the value was written to the store.
    public let importedAt: Date
    public let quality: SampleQuality
    /// Source identifier (ring slot, HealthKit UUID) for tracing back to the original.
    public let originalReference: String

    public init(id: UUID, subjectID: UUID?, deviceID: String, source: DataSourceKind, kind: SampleKind,
                value: Double, unit: SampleUnit, method: MeasurementMethod, measuredAt: Date,
                measuredUntil: Date? = nil, receivedAt: Date, importedAt: Date, quality: SampleQuality,
                originalReference: String) {
        self.id = id
        self.subjectID = subjectID
        self.deviceID = deviceID
        self.source = source
        self.kind = kind
        self.value = value
        self.unit = unit
        self.method = method
        self.measuredAt = measuredAt
        self.measuredUntil = measuredUntil ?? measuredAt
        self.receivedAt = receivedAt
        self.importedAt = importedAt
        self.quality = quality
        self.originalReference = originalReference
    }

    /// The contract view of a stored sample. `receivedAt` falls back to `importedAt` until 01 stores it.
    public init(_ sample: HealthSample, receivedAt: Date? = nil) {
        self.init(id: sample.id, subjectID: sample.profileID, deviceID: sample.deviceID, source: sample.source,
                  kind: sample.kind, value: sample.value, unit: sample.unit, method: sample.method,
                  measuredAt: sample.start, measuredUntil: sample.end, receivedAt: receivedAt ?? sample.importedAt,
                  importedAt: sample.importedAt, quality: sample.quality, originalReference: sample.originalSampleID)
    }

    public var isInterval: Bool { measuredUntil > measuredAt }
}

/// Normalised sleep phase. `unknown` keeps codes the firmware sends that we cannot map; it is drawn
/// separately and never guessed into another phase.
public enum SleepPhase: String, Codable, CaseIterable, Sendable {
    case awake, rem, light, deep, unknown

    /// Colmi `BC 27` codes as documented in docs/colmi-protokoll.md: 2 light, 3 deep, 4 REM, 5 awake.
    public static func colmi(code: Int) -> SleepPhase {
        switch code {
        case 2: .light
        case 3: .deep
        case 4: .rem
        case 5: .awake
        default: .unknown
        }
    }

    public var isAsleep: Bool { self == .rem || self == .light || self == .deep }
}

/// One real interval of the hypnogram, exactly as the device reported it.
public struct SleepSegment: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public let subjectID: UUID?
    /// All segments of one night share the session id.
    public let sessionID: UUID
    public let rawCode: Int
    public let phase: SleepPhase
    public let start: Date
    public let end: Date
    public let source: DataSourceKind
    public let deviceID: String
    public let firmware: String?

    public init(id: UUID = UUID(), subjectID: UUID?, sessionID: UUID, rawCode: Int, phase: SleepPhase,
                start: Date, end: Date, source: DataSourceKind, deviceID: String, firmware: String?) {
        self.id = id
        self.subjectID = subjectID
        self.sessionID = sessionID
        self.rawCode = rawCode
        self.phase = phase
        self.start = start
        self.end = end
        self.source = source
        self.deviceID = deviceID
        self.firmware = firmware
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Time in bed and classified sleep are kept apart (contract §8).
public struct SleepNight: Equatable, Sendable {
    public let sessionID: UUID
    public let segments: [SleepSegment]

    public init(sessionID: UUID, segments: [SleepSegment]) {
        self.sessionID = sessionID
        self.segments = segments.sorted { $0.start < $1.start }
    }

    public var inBed: DateInterval? {
        guard let first = segments.first, let last = segments.max(by: { $0.end < $1.end }) else { return nil }
        return DateInterval(start: first.start, end: last.end)
    }

    /// Sum of the intervals classified as sleep; awake and unknown do not count.
    public var asleep: TimeInterval {
        segments.filter { $0.phase.isAsleep }.reduce(0) { $0 + $1.duration }
    }

    public func duration(of phase: SleepPhase) -> TimeInterval {
        segments.filter { $0.phase == phase }.reduce(0) { $0 + $1.duration }
    }

    /// Uncovered stretches inside the night; shown as gaps, never filled.
    public var gaps: [DateInterval] {
        var result: [DateInterval] = []
        var cursor: Date?
        for segment in segments {
            if let cursor, segment.start > cursor { result.append(DateInterval(start: cursor, end: segment.start)) }
            cursor = max(cursor ?? segment.end, segment.end)
        }
        return result
    }
}
