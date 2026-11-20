import Foundation

/// How far an integration has really got (directive Phase A). A Bluetooth connection alone is
/// stage `.connected`, not a working integration.
public enum IntegrationStage: Int, Codable, CaseIterable, Comparable, Sendable {
    case discovered = 0
    case connected = 1
    case compatible = 2
    case dataAccess = 3
    case synced = 4
    case qualityChecked = 5

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .discovered: "Gerät entdeckt"
        case .connected: "Gerät verbunden"
        case .compatible: "Gerät kompatibel"
        case .dataAccess: "Datenzugriff verfügbar"
        case .synced: "Synchronisierung erfolgreich"
        case .qualityChecked: "Datenqualität geprüft"
        }
    }
}

/// Support status of one measurement kind on one adapter (capability matrix).
public enum SupportStatus: String, Codable, Sendable {
    /// Proven on real hardware or with real data in this app.
    case confirmed
    /// Code exists, never run against the real source.
    case implementedUntested = "implemented_untested"
    /// Claimed by vendor or community, protocol not known or not verified.
    case protocolUnknown = "protocol_unknown"
    /// Planned for this adapter, no code yet.
    case planned
    /// The source does not offer it.
    case unsupported

    public var label: String {
        switch self {
        case .confirmed: "bestätigt"
        case .implementedUntested: "implementiert, ungetestet"
        case .protocolUnknown: "Protokoll unbekannt"
        case .planned: "geplant"
        case .unsupported: "nicht unterstützt"
        }
    }

    /// Only these may feed real data into the store.
    public var mayDeliverData: Bool { self == .confirmed || self == .implementedUntested }
}

public enum ConnectionMethod: String, Codable, Sendable {
    case bluetoothLE = "ble"
    case healthKit = "healthkit"
    case cloudOAuth = "cloud_oauth"
    case manual
}

/// Category keeps animal wearables away from human health logic (directive §4).
public enum DeviceCategory: String, Codable, Sendable {
    case smartRing = "smart_ring"
    case chestStrap = "chest_strap"
    case armband
    case phone
    case cloudService = "cloud_service"
    case manualInput = "manual_input"
    case otherHuman = "other_human"
    case animal
}

/// Static description every adapter must provide (directive Phase A, "Jeder Adapter muss definieren").
public struct AdapterDescriptor: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: DeviceCategory
    public let supportedDevices: [String]
    public let connection: ConnectionMethod
    public let requiredPermissions: [String]
    public let needsPairing: Bool
    public let kinds: [SampleKind: SupportStatus]
    public let supportsHistory: SupportStatus
    public let supportsLive: SupportStatus
    public let reconnects: Bool
    public let firmwareNote: String
    public let knownLimitations: [String]

    public init(id: String, title: String, category: DeviceCategory, supportedDevices: [String],
                connection: ConnectionMethod, requiredPermissions: [String], needsPairing: Bool,
                kinds: [SampleKind: SupportStatus], supportsHistory: SupportStatus, supportsLive: SupportStatus,
                reconnects: Bool, firmwareNote: String, knownLimitations: [String] = []) {
        self.id = id
        self.title = title
        self.category = category
        self.supportedDevices = supportedDevices
        self.connection = connection
        self.requiredPermissions = requiredPermissions
        self.needsPairing = needsPairing
        self.kinds = kinds
        self.supportsHistory = supportsHistory
        self.supportsLive = supportsLive
        self.reconnects = reconnects
        self.firmwareNote = firmwareNote
        self.knownLimitations = knownLimitations
    }

    public func status(of kind: SampleKind) -> SupportStatus { kinds[kind] ?? .unsupported }

    /// Kinds this adapter may currently store.
    public var deliverableKinds: [SampleKind] {
        SampleKind.allCases.filter { status(of: $0).mayDeliverData }
    }
}

/// Errors an adapter can report; shown as diagnosis, never as data.
public enum AdapterError: Error, Equatable, Sendable {
    case permissionDenied
    case notAvailable
    case notConnected
    case timeout
    case protocolMismatch(String)
    case authorizationExpired
    case rateLimited
    case unsupported(SampleKind)
}

/// Result of one sync run: new observations plus source ids that the source reports as deleted.
public struct SyncBatch: Equatable, Sendable {
    public var observations: [RawObservation]
    public var deletedOriginalIDs: [String]
    /// Opaque position (HealthKit anchor, ring cursor, API "next" token) for the next incremental sync.
    public var nextCursor: String?
    /// One line per data type, so a single failing type is visible instead of failing the whole sync.
    public var reports: [SyncTypeReport]

    public init(observations: [RawObservation] = [], deletedOriginalIDs: [String] = [], nextCursor: String? = nil,
                reports: [SyncTypeReport] = []) {
        self.observations = observations
        self.deletedOriginalIDs = deletedOriginalIDs
        self.nextCursor = nextCursor
        self.reports = reports
    }
}

/// Result of importing one data type in one sync run (architecture 5.0, HealthKit per-type status).
public struct SyncTypeReport: Equatable, Sendable, Codable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: SampleKind
    public let added: Int
    public let deleted: Int
    public let at: Date
    /// Set when this type could not be read; other types are still imported.
    public let error: String?

    public init(kind: SampleKind, added: Int, deleted: Int, at: Date, error: String? = nil) {
        self.kind = kind
        self.added = added
        self.deleted = deleted
        self.at = at
        self.error = error
    }

    /// German one-line summary for the data sources screen.
    public var summary: String {
        if let error { return "Fehler: \(error)" }
        if added == 0 && deleted == 0 { return "keine neuen Werte" }
        if deleted == 0 { return "\(added) neu" }
        return "\(added) neu, \(deleted) entfernt"
    }
}

/// Common interface of all data sources (directive §4 "DeviceAdapter").
public protocol DeviceAdapter: Sendable {
    var descriptor: AdapterDescriptor { get }
    /// Fetches everything after `cursor` for one device. Must be safe to call repeatedly.
    func sync(deviceID: String, cursor: String?) async throws -> SyncBatch
}
