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
            if snapshot.connection == .ready { device.reach(.compatible) }
            if let battery = snapshot.battery { device.batteryPercent = battery.level }
            if let firmware = snapshot.firmware { device.firmware = firmware }
        }
    }

    /// Stores one live value from the ring through the common sync path (deduplicated, normalised).
    func ingest(_ reading: VitalReading) {
        guard !isTestScenario, let context = modelContext else { return }
        let raw = RawObservation(reading: reading, timeZoneIdentifier: TimeZone.current.identifier)
        let device = ringDevice(reading.deviceIdentifier)
        do {
            let plan = try SampleStore(context: context).ingest(SyncBatch(observations: [raw]), deviceID: reading.deviceIdentifier,
                                                                profiles: device?.timeline ?? .constant(ownerProfileID))
            if let device, !plan.inserts.isEmpty {
                change(device.id) {
                    $0.reach(.dataAccess)
                    $0.reach(.synced)
                    $0.lastSampleAt = reading.timestamp
                    $0.lastSuccessfulSync = .now
                }
            }
            if let device, let error = plan.rejected.first {
                change(device.id) { $0.log("Wert abgelehnt: \(error.label)") }
            }
        } catch {
            if let device { change(device.id) { $0.log("Speichern fehlgeschlagen: \(error.localizedDescription)") } }
        }
    }

    private func ringDevice(_ identifier: String) -> RegisteredDevice? {
        devices.first { $0.sourceIdentifier == identifier && $0.adapterID.hasPrefix("colmi.") }
    }

    // MARK: Migration

    static let migrationMarker = "migration.storedMeasurement.v1"

    /// Copies ring values from the milestone-1 table into the sample store (Directive 3.1 A).
    /// Idempotent through the dedup key, so an interrupted run simply repeats. The marker is set only after
    /// every chunk was saved; `marker == nil` (test scenarios) always runs and records nothing.
    @discardableResult
    func migrateLegacyMeasurements(marker: UserDefaults?) -> MigrationReport? {
        guard let context = modelContext else { return nil }
        if let marker, marker.object(forKey: Self.migrationMarker) != nil { return nil }
        var report = MigrationReport()
        let rows = (try? context.fetch(FetchDescriptor<StoredMeasurement>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        report.read = rows.count
        var byDevice: [String: [RawObservation]] = [:]
        for row in rows {
            guard let reading = row.reading else { report.skipped += 1; continue }
            byDevice[reading.deviceIdentifier, default: []].append(RawObservation(reading: reading, timeZoneIdentifier: TimeZone.current.identifier))
        }
        let store = SampleStore(context: context)
        do {
            for (deviceID, observations) in byDevice.sorted(by: { $0.key < $1.key }) {
                let profiles = ringDevice(deviceID)?.timeline ?? .constant(ownerProfileID)
                var start = 0
                while start < observations.count {
                    let chunk = Array(observations[start..<min(start + 500, observations.count)])
                    let plan = try store.ingest(SyncBatch(observations: chunk), deviceID: deviceID, profiles: profiles)
                    report.inserted += plan.inserts.count
                    report.alreadyPresent += plan.unchanged + plan.updates.count
                    report.skipped += plan.rejected.count
                    start += chunk.count
                }
                if let device = ringDevice(deviceID), !observations.isEmpty {
                    change(device.id) { $0.log("Ältere Messwerte übernommen") }
                }
            }
        } catch {
            return nil   // marker stays unset; the next launch repeats safely
        }
        marker?.set(Date.now, forKey: Self.migrationMarker)
        return report
    }

    // MARK: Imported data

    struct ImportedKind: Identifiable, Equatable {
        let kind: SampleKind
        let count: Int
        let latest: Date?
        var id: String { kind.rawValue }
    }

    /// What is stored for one device, per kind: number of plausible values and the newest one.
    func importedData(deviceID: String) -> [ImportedKind] {
        guard let context = modelContext else { return [] }
        let plausible = SampleQuality.plausible.rawValue
        let valid = SampleQuality.valid.rawValue
        return SampleKind.allCases.compactMap { kind in
            let raw = kind.rawValue
            var descriptor = FetchDescriptor<StoredSample>(
                predicate: #Predicate { $0.deviceID == deviceID && $0.kindRaw == raw
                    && ($0.qualityRaw == plausible || $0.qualityRaw == valid) },
                sortBy: [SortDescriptor(\.start, order: .reverse)])
            let count = (try? context.fetchCount(descriptor)) ?? 0
            guard count > 0 else { return nil }
            descriptor.fetchLimit = 1
            return ImportedKind(kind: kind, count: count, latest: (try? context.fetch(descriptor))?.first?.start)
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
            let stored = HealthImportCursor.decode(device.syncCursor)
            let migrating = device.syncCursor != nil && stored.needsMigration
            if stored.isUnknownFormat {
                change(id) { $0.log("Health-Import: unbekanntes Format \(stored.format), keine Umstellung") }
            }
            let batch = try await health.sync(deviceID: HealthKitAdapter.deviceID, cursor: device.syncCursor)
            // Migration, ingest and save are one transaction: on any error everything is rolled back and
            // the old cursor stays, so the next sync repeats the same run (Codex review P1-003 R2-1).
            // Apple Health belongs to the iPhone owner for all time.
            let (outcome, plan) = SampleStore(context: context).syncHealth(
                batch, deviceID: HealthKitAdapter.deviceID, storedCursor: device.syncCursor,
                profiles: .constant(ownerProfileID))
            guard outcome.committed else {
                change(id) { $0.log("Sync zurückgerollt, nichts gespeichert: \(outcome.error ?? "unbekannt")") }
                return
            }
            if migrating {
                change(id) {
                    $0.log("Health-Import auf Format \(HealthImportCursor.currentFormat) umgestellt: \(outcome.migratedRows) Werte umgetypt, \(outcome.removedDuplicates) Dubletten entfernt")
                }
            }
            change(id) {
                // Health never says whether reading was denied; an empty import may mean either. Stages rise
                // only with evidence, so without any data the source stays "kompatibel" and the screen asks
                // the user to check the permissions (`syncedWithoutData`).
                $0.reach(.compatible)
                if !batch.observations.isEmpty { $0.reach(.dataAccess) }
                if $0.stage >= .dataAccess { $0.reach(.synced) }
                $0.syncCursor = outcome.cursor
                $0.lastSuccessfulSync = .now
                $0.record(batch.reports)
                if let latest = batch.observations.map(\.start).max() { $0.lastSampleAt = max(latest, $0.lastSampleAt ?? latest) }
                $0.log("Sync: \(plan.inserts.count) neu, \(plan.updates.count) geändert, \(plan.deletions.count) gelöscht, \(plan.rejected.count) abgelehnt")
                let failed = batch.reports.filter { $0.error != nil }.map { $0.kind.title }
                if !failed.isEmpty { $0.log("Nicht lesbar: \(failed.joined(separator: ", "))") }
            }
        } catch {
            change(id) { $0.log("Sync fehlgeschlagen: \(error.localizedDescription)") }
        }
    }

    /// Syncs Apple Health when the app starts or returns to the foreground, at most every
    /// `minimumInterval` seconds. Before this, Health data only arrived after tapping the sync button.
    func syncHealthIfDue(now: Date = .now, minimumInterval: TimeInterval = 15 * 60) async {
        guard !isTestScenario, healthAvailable,
              let device = devices.first(where: { $0.adapterID == AdapterCatalog.appleHealth.id }),
              device.stage >= .connected else { return }
        if let last = device.lastSuccessfulSync, now.timeIntervalSince(last) < minimumInterval { return }
        await sync(device.id)
    }

    // MARK: Profiles and preferences

    /// Logged correction of who wore a device in a past period; re-attributes its stored samples.
    func correctAssignment(_ id: UUID, to profile: UUID?, from start: Date, until end: Date, reason: String) {
        guard !isTestScenario else { return }
        mutate { try $0.correctAssignment(id, to: profile, from: start, until: end, reason: reason) }
        guard let context = modelContext, let device = registry.device(id) else { return }
        let changed = (try? SampleStore(context: context).reattribute(deviceID: device.sourceIdentifier,
                                                                      profiles: device.timeline)) ?? 0
        change(id) { $0.log("\(changed) Werte neu zugeordnet") }
    }

    var preferences: SourcePreferences { registry.preferences(for: ownerProfileID) }

    func setPreference(_ choice: SourceChoice, for kind: SampleKind) {
        var copy = registry
        copy.setPreference(choice, for: kind, profile: ownerProfileID)
        registry = copy
        save()
    }

    /// Choices offered for a kind: automatic plus every registered device whose adapter can deliver it.
    func candidates(for kind: SampleKind) -> [(title: String, choice: SourceChoice)] {
        devices.compactMap { device in
            guard let adapter = AdapterCatalog.descriptor(id: device.adapterID),
                  adapter.status(of: kind) != .unsupported,
                  let source = AdapterCatalog.sourceKind(adapterID: device.adapterID) else { return nil }
            return (device.name, .device(SampleOrigin(source: source, deviceID: device.sourceIdentifier)))
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
