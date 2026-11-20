import Foundation
import Observation
import PulseCore
import SwiftData

/// App-side owner of the device registry and of sync runs (General Directive 3.0 §4).
/// The registry is saved as JSON in Application Support; samples go to SwiftData via `SampleStore`.
@MainActor
@Observable
final class SourcesStore {
    private(set) var registry: DeviceRegistry
    private(set) var syncing: Set<UUID> = []
    let isTestScenario: Bool
    let ownerProfileID: UUID

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let health = HealthKitAdapter()
    @ObservationIgnored var modelContext: ModelContext?

    private init(registry: DeviceRegistry, ownerProfileID: UUID, fileURL: URL?, isTestScenario: Bool) {
        self.registry = registry
        self.ownerProfileID = ownerProfileID
        self.fileURL = fileURL
        self.isTestScenario = isTestScenario
    }

    static func live() -> SourcesStore {
        let owner = Self.ownerID()
        let url = URL.applicationSupportDirectory.appending(path: "devices.json")
        var registry = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DeviceRegistry.self, from: $0) }
            ?? DeviceRegistry()
        if registry.ownerProfileID == nil { registry.ownerProfileID = owner }
        return SourcesStore(registry: registry, ownerProfileID: owner, fileURL: url, isTestScenario: false)
    }

    /// Fixed registry for screenshots; never written to disk.
    static func preview(_ registry: DeviceRegistry, owner: UUID) -> SourcesStore {
        SourcesStore(registry: registry, ownerProfileID: owner, fileURL: nil, isTestScenario: true)
    }

    /// The local profile that owns this iPhone. Real profiles arrive with milestone 3.
    private static func ownerID() -> UUID {
        let key = "profile.ownerID"
        if let text = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: text) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    var devices: [RegisteredDevice] { registry.devices }
    var healthAvailable: Bool { HealthKitAdapter.available }
    var hasHealth: Bool { devices.contains { $0.adapterID == AdapterCatalog.appleHealth.id } }

    // MARK: Ring

    /// Mirrors the ring connection into the registry. Stages only rise with evidence:
    /// connected → compatible (UART service found, ring answered) → data access (first value stored).
    func noteRing(_ snapshot: RingSnapshot) {
        guard !isTestScenario, let identifier = snapshot.deviceIdentifier, let name = snapshot.deviceName else { return }
        let adapter = snapshot.model?.name == "R09" ? AdapterCatalog.colmiR09.id : AdapterCatalog.colmiR03.id
        let id = ensureDevice(adapterID: adapter, sourceIdentifier: identifier, name: name)
        change(id) { device in
            if snapshot.connection.isConnected { device.reach(.connected) }
            if snapshot.connection == .ready || snapshot.connection == .measuring { device.reach(.compatible) }
            if let battery = snapshot.battery { device.batteryPercent = battery.level }
            if let firmware = snapshot.firmware { device.firmware = firmware }
        }
    }

    /// Stores one live value from the ring through the common sync path (deduplicated, normalised).
    func ingest(_ reading: VitalReading) {
        guard !isTestScenario, let context = modelContext else { return }
        let kind: SampleKind = reading.metric == .heartRate ? .heartRate : .deviceBattery
        let unit: SampleUnit = reading.metric == .heartRate ? .beatsPerMinute : .percent
        let raw = RawObservation(kind: kind, value: Double(reading.value), unit: unit, start: reading.timestamp,
                                 timeZoneIdentifier: TimeZone.current.identifier, source: .colmiRing,
                                 deviceID: reading.deviceIdentifier,
                                 originalSampleID: "live-\(Int(reading.timestamp.timeIntervalSince1970 * 1000))-\(kind.rawValue)",
                                 method: .liveSensor)
        let device = devices.first { $0.sourceIdentifier == reading.deviceIdentifier && $0.adapterID.hasPrefix("colmi.") }
        do {
            let plan = try SampleStore(context: context).ingest(SyncBatch(observations: [raw]), deviceID: reading.deviceIdentifier,
                                                                profileID: device?.profileID ?? ownerProfileID)
            if let device, !plan.inserts.isEmpty {
                change(device.id) {
                    $0.reach(.dataAccess)
                    $0.reach(.synced)
                    $0.lastSampleAt = reading.timestamp
                    $0.lastSuccessfulSync = .now
                }
            }
        } catch {
            if let device { change(device.id) { $0.log("Speichern fehlgeschlagen: \(error.localizedDescription)") } }
        }
    }

    // MARK: Apple Health

    func connectHealth() async {
        guard !isTestScenario else { return }
        let id = ensureDevice(adapterID: AdapterCatalog.appleHealth.id, sourceIdentifier: HealthKitAdapter.deviceID,
                              name: "Apple Health")
        do {
            try await health.requestAuthorization()
            change(id) { $0.reach(.connected) }
            await sync(id)
        } catch {
            change(id) { $0.log("Freigabe nicht möglich: \(error.localizedDescription)") }
        }
    }

    func sync(_ id: UUID) async {
        guard !isTestScenario, let device = registry.device(id), device.adapterID == AdapterCatalog.appleHealth.id,
              let context = modelContext, !syncing.contains(id) else { return }
        syncing.insert(id)
        defer { syncing.remove(id) }
        do {
            let batch = try await health.sync(deviceID: HealthKitAdapter.deviceID, cursor: device.syncCursor)
            let plan = try SampleStore(context: context).ingest(batch, deviceID: HealthKitAdapter.deviceID,
                                                                profileID: ownerProfileID)
            change(id) {
                // Health never says whether reading was denied; an empty first import may mean either.
                $0.reach(.compatible)
                if !batch.observations.isEmpty { $0.reach(.dataAccess) }
                $0.reach(.synced)
                $0.syncCursor = batch.nextCursor
                $0.lastSuccessfulSync = .now
                if let latest = batch.observations.map(\.start).max() { $0.lastSampleAt = max(latest, $0.lastSampleAt ?? latest) }
                $0.log("Sync: \(plan.inserts.count) neu, \(plan.updates.count) geändert, \(plan.deletions.count) gelöscht, \(plan.rejected.count) abgelehnt")
            }
        } catch {
            change(id) { $0.log("Sync fehlgeschlagen: \(error.localizedDescription)") }
        }
    }

    // MARK: Registry editing

    func rename(_ id: UUID, to name: String) {
        mutate { try $0.rename(id, to: name) }
    }

    func remove(_ id: UUID) {
        mutate { try $0.remove(id) }
    }

    // MARK: Helpers

    private func ensureDevice(adapterID: String, sourceIdentifier: String, name: String) -> UUID {
        if let existing = devices.first(where: { $0.adapterID == adapterID && $0.sourceIdentifier == sourceIdentifier }) {
            return existing.id
        }
        var copy = registry
        let added = try? copy.add(adapterID: adapterID, sourceIdentifier: sourceIdentifier, name: name,
                                  profileID: ownerProfileID, stage: .discovered)
        registry = copy
        save()
        return added?.id ?? UUID()
    }

    private func change(_ id: UUID, _ edit: (inout RegisteredDevice) -> Void) {
        mutate { try $0.update(id, edit) }
    }

    private func mutate(_ edit: (inout DeviceRegistry) throws -> Void) {
        var copy = registry
        do {
            try edit(&copy)
            registry = copy
            save()
        } catch {
            // Invalid edits (empty name, unknown id) are ignored; the UI prevents them.
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(registry) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
