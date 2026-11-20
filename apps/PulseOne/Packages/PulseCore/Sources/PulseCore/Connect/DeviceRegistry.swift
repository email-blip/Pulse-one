import Foundation

/// One data source a user added: a ring, Apple Health, an Oura account, a manual log.
public struct RegisteredDevice: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let adapterID: String
    /// Hardware or account identifier from the source (peripheral UUID, Oura user id, "healthkit").
    public let sourceIdentifier: String
    public var name: String
    public var profileID: UUID?
    public private(set) var stage: IntegrationStage
    public var batteryPercent: Int?
    public var firmware: String?
    public var lastSuccessfulSync: Date?
    public var lastSampleAt: Date?
    public var syncCursor: String?
    public private(set) var diagnostics: [String]

    public init(id: UUID = UUID(), adapterID: String, sourceIdentifier: String, name: String,
                profileID: UUID? = nil, stage: IntegrationStage = .discovered) {
        self.id = id
        self.adapterID = adapterID
        self.sourceIdentifier = sourceIdentifier
        self.name = name
        self.profileID = profileID
        self.stage = stage
        self.diagnostics = []
    }

    /// Stages only move forward through evidence; `reset` is the one way back (e.g. after unpairing).
    public mutating func reach(_ newStage: IntegrationStage) {
        stage = max(stage, newStage)
    }

    public mutating func reset(to newStage: IntegrationStage = .discovered) {
        stage = newStage
    }

    /// Keeps the latest 50 diagnosis lines.
    public mutating func log(_ line: String) {
        diagnostics.append(line)
        if diagnostics.count > 50 { diagnostics.removeFirst(diagnostics.count - 50) }
    }
}

public enum RegistryError: Error, Equatable, Sendable {
    case unknownAdapter(String)
    case alreadyRegistered
    case notFound
    case emptyName
    /// Apple Health belongs to the iPhone owner; it must not move to another local profile.
    case healthKitOwnerOnly
}

/// Central list of a user's devices and sources (directive §4 "DeviceRegistry").
public struct DeviceRegistry: Equatable, Codable, Sendable {
    public private(set) var devices: [RegisteredDevice] = []
    /// The profile that owns the iPhone and therefore Apple Health data.
    public var ownerProfileID: UUID?

    public init(ownerProfileID: UUID? = nil) {
        self.ownerProfileID = ownerProfileID
    }

    @discardableResult
    public mutating func add(adapterID: String, sourceIdentifier: String, name: String,
                             profileID: UUID? = nil, stage: IntegrationStage = .discovered) throws -> RegisteredDevice {
        guard AdapterCatalog.descriptor(id: adapterID) != nil else { throw RegistryError.unknownAdapter(adapterID) }
        guard !devices.contains(where: { $0.adapterID == adapterID && $0.sourceIdentifier == sourceIdentifier }) else {
            throw RegistryError.alreadyRegistered
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RegistryError.emptyName }
        let profile = adapterID == AdapterCatalog.appleHealth.id ? (profileID ?? ownerProfileID) : profileID
        try checkOwner(adapterID: adapterID, profileID: profile)
        let device = RegisteredDevice(adapterID: adapterID, sourceIdentifier: sourceIdentifier, name: trimmed,
                                      profileID: profile, stage: stage)
        devices.append(device)
        return device
    }

    public mutating func remove(_ id: UUID) throws {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { throw RegistryError.notFound }
        devices.remove(at: index)
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RegistryError.emptyName }
        try update(id) { $0.name = trimmed }
    }

    public mutating func assign(_ id: UUID, to profileID: UUID?) throws {
        guard let device = device(id) else { throw RegistryError.notFound }
        try checkOwner(adapterID: device.adapterID, profileID: profileID)
        try update(id) { $0.profileID = profileID }
    }

    public mutating func update(_ id: UUID, _ change: (inout RegisteredDevice) -> Void) throws {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { throw RegistryError.notFound }
        change(&devices[index])
    }

    public func device(_ id: UUID) -> RegisteredDevice? { devices.first { $0.id == id } }

    public func devices(for profileID: UUID) -> [RegisteredDevice] { devices.filter { $0.profileID == profileID } }

    private func checkOwner(adapterID: String, profileID: UUID?) throws {
        guard adapterID == AdapterCatalog.appleHealth.id, let profileID, let ownerProfileID else { return }
        if profileID != ownerProfileID { throw RegistryError.healthKitOwnerOnly }
    }
}

extension RegisteredDevice {
    /// A sync ran but nothing ever arrived. For Apple Health this usually means reading was not allowed:
    /// Health never reports a denied read permission, it just returns no data.
    public var syncedWithoutData: Bool { lastSuccessfulSync != nil && stage < .dataAccess }
}
