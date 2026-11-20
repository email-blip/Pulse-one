import Foundation

/// One data source a user added: a ring, Apple Health, an Oura account, a manual log.
public struct RegisteredDevice: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let adapterID: String
    /// Hardware or account identifier from the source (peripheral UUID, Oura user id, "healthkit").
    public let sourceIdentifier: String
    public var name: String
    /// The current profile (the running assignment). History lives in `assignments`.
    public private(set) var profileID: UUID?
    /// Who wore the device when (Review 3.2 §2). Samples take the profile valid at their time.
    public internal(set) var assignments: [DeviceAssignment]
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
        // The first assignment also covers the device memory from before it was added (a ring keeps
        // about 7 days); the reason says so.
        self.assignments = [DeviceAssignment(profileID: profileID, from: .distantPast,
                                             reason: "Erstzuordnung beim Hinzufügen (gilt auch für den Gerätespeicher davor)",
                                             recordedAt: .now)]
        self.stage = stage
        self.diagnostics = []
    }

    private enum CodingKeys: String, CodingKey {
        case id, adapterID, sourceIdentifier, name, profileID, assignments, stage, batteryPercent, firmware
        case lastSuccessfulSync, lastSampleAt, syncCursor, diagnostics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        adapterID = try c.decode(String.self, forKey: .adapterID)
        sourceIdentifier = try c.decode(String.self, forKey: .sourceIdentifier)
        name = try c.decode(String.self, forKey: .name)
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
        // Registries from before Review 3.2 have no history: one open period, marked as migrated.
        assignments = try c.decodeIfPresent([DeviceAssignment].self, forKey: .assignments)
            ?? [DeviceAssignment(profileID: profileID, from: .distantPast,
                                 reason: "Übernommen aus Version ohne Zuordnungsverlauf", recordedAt: .now)]
        stage = try c.decode(IntegrationStage.self, forKey: .stage)
        batteryPercent = try c.decodeIfPresent(Int.self, forKey: .batteryPercent)
        firmware = try c.decodeIfPresent(String.self, forKey: .firmware)
        lastSuccessfulSync = try c.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
        lastSampleAt = try c.decodeIfPresent(Date.self, forKey: .lastSampleAt)
        syncCursor = try c.decodeIfPresent(String.self, forKey: .syncCursor)
        diagnostics = try c.decodeIfPresent([String].self, forKey: .diagnostics) ?? []
    }

    public var timeline: ProfileTimeline { ProfileTimeline(assignments) }

    mutating func setCurrentProfile(_ profile: UUID?) { profileID = profile }

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
    case invalidAssignment(AssignmentError)
}

/// Central list of a user's devices and sources (directive §4 "DeviceRegistry").
public struct DeviceRegistry: Equatable, Codable, Sendable {
    public private(set) var devices: [RegisteredDevice] = []
    /// The profile that owns the iPhone and therefore Apple Health data.
    public var ownerProfileID: UUID?
    /// Preferred source per kind, per profile (Review 3.2 §4). Missing = automatic.
    public private(set) var preferences: [UUID: SourcePreferences] = [:]

    public init(ownerProfileID: UUID? = nil) {
        self.ownerProfileID = ownerProfileID
    }

    private enum CodingKeys: String, CodingKey { case devices, ownerProfileID, preferences }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decodeIfPresent([RegisteredDevice].self, forKey: .devices) ?? []
        ownerProfileID = try c.decodeIfPresent(UUID.self, forKey: .ownerProfileID)
        preferences = try c.decodeIfPresent([UUID: SourcePreferences].self, forKey: .preferences) ?? [:]
    }

    public func preferences(for profile: UUID) -> SourcePreferences { preferences[profile] ?? SourcePreferences() }

    public mutating func setPreference(_ choice: SourceChoice, for kind: SampleKind, profile: UUID) {
        var p = preferences(for: profile)
        p.set(choice, for: kind)
        preferences[profile] = p
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

    /// Hands a device to another profile from `date` on (Review 3.2 §2). Earlier samples keep their profile.
    public mutating func assign(_ id: UUID, to profileID: UUID?, from date: Date = .now,
                                reason: String = "Gerät neu zugeordnet", now: Date = .now) throws {
        guard let device = device(id) else { throw RegistryError.notFound }
        try checkOwner(adapterID: device.adapterID, profileID: profileID)
        var assignments = device.assignments
        do { try assignments.handOver(to: profileID, from: date, reason: reason, now: now) } catch let e as AssignmentError {
            throw RegistryError.invalidAssignment(e)
        }
        try update(id) { $0.assignments = assignments; $0.setCurrentProfile(profileID) }
    }

    /// Manual, logged correction of who wore a device in a past period. The caller must re-attribute the
    /// stored samples of that period (`SyncCoordinator.reattribute`).
    public mutating func correctAssignment(_ id: UUID, to profileID: UUID?, from start: Date, until end: Date,
                                           reason: String, now: Date = .now) throws {
        guard let device = device(id) else { throw RegistryError.notFound }
        try checkOwner(adapterID: device.adapterID, profileID: profileID)
        var assignments = device.assignments
        do { try assignments.correct(to: profileID, from: start, until: end, reason: reason, now: now) } catch let e as AssignmentError {
            throw RegistryError.invalidAssignment(e)
        }
        let current = ProfileTimeline(assignments).profile(at: now)
        try update(id) {
            $0.assignments = assignments
            $0.setCurrentProfile(current)
            $0.log("Zuordnung korrigiert: \(reason)")
        }
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
