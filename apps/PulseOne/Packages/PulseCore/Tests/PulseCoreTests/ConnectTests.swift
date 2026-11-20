import Foundation
import Testing
@testable import PulseCore

private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let guest = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

private func raw(_ kind: SampleKind = .heartRate, _ value: Double, _ unit: SampleUnit = .beatsPerMinute,
                 at offset: TimeInterval = 0, id: String, source: DataSourceKind = .colmiRing,
                 device: String = "ring-1") -> RawObservation {
    RawObservation(kind: kind, value: value, unit: unit, start: t0.addingTimeInterval(offset),
                   timeZoneIdentifier: "Europe/Berlin", source: source, deviceID: device,
                   originalSampleID: id, method: .deviceHistory)
}

private func sample(_ r: RawObservation, profile: UUID = owner) throws -> HealthSample {
    try MeasurementNormalizer.normalize(r, profileID: profile, importedAt: t0.addingTimeInterval(3_600))
}

@Suite("Measurement normalizer")
struct NormalizerTests {
    @Test func keepsCanonicalUnitsAndGradesPlausibility() throws {
        let ok = try sample(raw(.heartRate, 62, id: "a"))
        #expect(ok.quality == .plausible)
        #expect(ok.canonicalUnit == .beatsPerMinute)
        #expect(ok.timeZoneIdentifier == "Europe/Berlin")
        let wild = try sample(raw(.heartRate, 400, id: "b"))
        #expect(wild.quality == .implausible)
    }

    @Test func convertsUnits() throws {
        #expect(try sample(raw(.oxygenSaturation, 0.97, .fraction, id: "s")).value == 97)
        let skin = try sample(raw(.skinTemperature, 93.2, .fahrenheit, id: "t")).value
        #expect(abs(skin - 34.0) < 0.001)
        // A deviation of 1.8 °F is 1 °C: no 32-degree offset.
        let deviation = try sample(raw(.skinTemperatureDeviation, 1.8, .fahrenheit, id: "d")).value
        #expect(abs(deviation - 1.0) < 0.001)
        #expect(try sample(raw(.distance, 2.5, .kilometers, id: "k")).value == 2_500)
        #expect(try sample(raw(.sleepDuration, 7.5, .hours, id: "h")).value == 27_000)
    }

    @Test func rejectsIncompatibleUnitsAndBadValues() {
        #expect(throws: NormalizationError.incompatibleUnit(.heartRate, .celsius)) {
            try sample(raw(.heartRate, 60, .celsius, id: "x"))
        }
        #expect(throws: NormalizationError.notANumber) {
            try sample(raw(.heartRate, .nan, id: "n"))
        }
    }
}

@Suite("Sync coordinator")
struct SyncCoordinatorTests {
    @Test func secondSyncOfTheSameDataChangesNothing() throws {
        let batch = SyncBatch(observations: [raw(.heartRate, 60, id: "1"), raw(.heartRate, 61, at: 300, id: "2")])
        let first = SyncCoordinator.plan(batch: batch, existing: [:], profileID: owner, importedAt: t0)
        #expect(first.inserts.count == 2)
        let stored = Dictionary(uniqueKeysWithValues: first.inserts.map { ($0.deduplicationKey, $0) })
        let second = SyncCoordinator.plan(batch: batch, existing: stored, profileID: owner, importedAt: t0.addingTimeInterval(60))
        #expect(second.isEmpty)
        #expect(second.unchanged == 2)
    }

    @Test func duplicatesInsideOneBatchCountOnce() {
        let batch = SyncBatch(observations: [raw(.steps, 100, .count, id: "s1"), raw(.steps, 100, .count, id: "s1")])
        let plan = SyncCoordinator.plan(batch: batch, existing: [:], profileID: owner, importedAt: t0)
        #expect(plan.inserts.count == 1)
    }

    @Test func changedSourceValueUpdatesInPlace() throws {
        let old = try sample(raw(.steps, 100, .count, id: "s1"))
        let batch = SyncBatch(observations: [raw(.steps, 120, .count, id: "s1")])
        let plan = SyncCoordinator.plan(batch: batch, existing: [old.deduplicationKey: old], profileID: owner, importedAt: t0)
        #expect(plan.inserts.isEmpty)
        #expect(plan.updates.count == 1)
        #expect(plan.updates.first?.id == old.id)
        #expect(plan.updates.first?.value == 120)
    }

    @Test func deletionsFromTheSourceRemoveStoredSamples() throws {
        let old = try sample(raw(.heartRate, 70, id: "hk-1", source: .appleHealth, device: "healthkit"))
        let batch = SyncBatch(deletedOriginalIDs: ["hk-1"])
        let plan = SyncCoordinator.plan(batch: batch, existing: [old.deduplicationKey: old], profileID: owner, importedAt: t0)
        #expect(plan.deletions == [old.id])
    }

    @Test func invalidObservationsAreReportedNotStored() {
        let batch = SyncBatch(observations: [raw(.heartRate, 60, .meters, id: "bad")])
        let plan = SyncCoordinator.plan(batch: batch, existing: [:], profileID: owner, importedAt: t0)
        #expect(plan.inserts.isEmpty)
        #expect(plan.rejected == [.incompatibleUnit(.heartRate, .meters)])
    }
}

@Suite("Data source resolver")
struct DataSourceResolverTests {
    @Test func neverAveragesPointValuesAcrossSources() throws {
        let ring = try sample(raw(.heartRate, 60, id: "r", source: .colmiRing))
        let health = try sample(raw(.heartRate, 70, at: 10, id: "h", source: .appleHealth, device: "healthkit"))
        let resolved = DataSourceResolver.resolvePoints([ring, health])
        #expect(resolved.map(\.value) == [60])
        let preferHealth = DataSourceResolver.resolvePoints([ring, health], priority: [.appleHealth, .colmiRing])
        #expect(preferHealth.map(\.value) == [70])
    }

    @Test func totalsComeFromOneSourceOnly() throws {
        let ringSteps = try [100.0, 200].enumerated().map {
            try sample(raw(.steps, $1, .count, at: Double($0) * 900, id: "r\($0)", source: .colmiRing))
        }
        let phoneSteps = try sample(raw(.steps, 5_000, .count, id: "p", source: .appleHealth, device: "healthkit"))
        let total = DataSourceResolver.resolveTotal(ringSteps + [phoneSteps], priority: [.appleHealth, .colmiRing])
        #expect(total?.total == 5_000)
        #expect(total?.source == .appleHealth)
    }

    @Test func implausibleSamplesAreIgnored() throws {
        let wild = try sample(raw(.heartRate, 300, id: "w"))
        #expect(DataSourceResolver.resolvePoints([wild]).isEmpty)
    }
}

@Suite("Device registry and adapters")
struct DeviceRegistryTests {
    @Test func addRenameAssignRemove() throws {
        var registry = DeviceRegistry(ownerProfileID: owner)
        let ring = try registry.add(adapterID: "colmi.r03", sourceIdentifier: "peripheral-1", name: "R03_1A2B", profileID: owner)
        try registry.rename(ring.id, to: "  Mein Ring ")
        #expect(registry.device(ring.id)?.name == "Mein Ring")
        try registry.assign(ring.id, to: guest)
        #expect(registry.devices(for: guest).count == 1)
        try registry.remove(ring.id)
        #expect(registry.devices.isEmpty)
    }

    @Test func rejectsDuplicatesUnknownAdaptersAndEmptyNames() throws {
        var registry = DeviceRegistry()
        try registry.add(adapterID: "colmi.r03", sourceIdentifier: "p1", name: "R03")
        #expect(throws: RegistryError.alreadyRegistered) {
            try registry.add(adapterID: "colmi.r03", sourceIdentifier: "p1", name: "R03")
        }
        #expect(throws: RegistryError.unknownAdapter("acme.x")) {
            try registry.add(adapterID: "acme.x", sourceIdentifier: "p2", name: "X")
        }
        #expect(throws: RegistryError.emptyName) {
            try registry.add(adapterID: "manual", sourceIdentifier: "m", name: "   ")
        }
    }

    @Test func appleHealthStaysWithTheOwner() throws {
        var registry = DeviceRegistry(ownerProfileID: owner)
        let health = try registry.add(adapterID: "apple.health", sourceIdentifier: "healthkit", name: "Apple Health")
        #expect(health.profileID == owner)
        #expect(throws: RegistryError.healthKitOwnerOnly) { try registry.assign(health.id, to: guest) }
        #expect(throws: RegistryError.healthKitOwnerOnly) {
            var other = DeviceRegistry(ownerProfileID: owner)
            try other.add(adapterID: "apple.health", sourceIdentifier: "healthkit", name: "Health", profileID: guest)
        }
    }

    @Test func stagesOnlyMoveForward() {
        var device = RegisteredDevice(adapterID: "colmi.r03", sourceIdentifier: "p", name: "R03")
        device.reach(.compatible)
        device.reach(.connected)
        #expect(device.stage == .compatible)
        device.reset()
        #expect(device.stage == .discovered)
    }

    @Test func catalogMatchesTheCapabilityMatrix() {
        let r03 = AdapterCatalog.colmiR03
        #expect(r03.status(of: .heartRate) == .implementedUntested)
        #expect(r03.status(of: .skinTemperature) == .unsupported)
        #expect(r03.deliverableKinds == [.heartRate, .deviceBattery])
        // Nothing is confirmed before a real-hardware test.
        for adapter in AdapterCatalog.all {
            #expect(!adapter.kinds.values.contains(.confirmed), "\(adapter.id)")
        }
        // R09 is prepared only: it may not deliver data yet.
        #expect(AdapterCatalog.colmiR09.deliverableKinds.isEmpty)
        #expect(Set(AdapterCatalog.all.map(\.id)).count == AdapterCatalog.all.count)
    }
}

@Suite("Per-type sync reports")
struct SyncTypeReportTests {
    @Test func summarisesEachOutcome() {
        #expect(SyncTypeReport(kind: .steps, added: 0, deleted: 0, at: t0).summary == "keine neuen Werte")
        #expect(SyncTypeReport(kind: .steps, added: 12, deleted: 0, at: t0).summary == "12 neu")
        #expect(SyncTypeReport(kind: .steps, added: 3, deleted: 1, at: t0).summary == "3 neu, 1 entfernt")
        #expect(SyncTypeReport(kind: .vo2Max, added: 0, deleted: 0, at: t0, error: "locked").summary == "Fehler: locked")
    }

    @Test func newestRunWinsPerTypeAndOthersStay() throws {
        var device = RegisteredDevice(adapterID: "apple.health", sourceIdentifier: "healthkit", name: "Apple Health")
        device.record([SyncTypeReport(kind: .steps, added: 5, deleted: 0, at: t0),
                       SyncTypeReport(kind: .heartRate, added: 2, deleted: 0, at: t0)])
        device.record([SyncTypeReport(kind: .steps, added: 0, deleted: 0, at: t0.addingTimeInterval(60), error: "x")])
        #expect(device.typeReports.count == 2)
        #expect(device.typeReports.first { $0.kind == .steps }?.error == "x")
        #expect(device.typeReports.first { $0.kind == .heartRate }?.added == 2)
        let decoded = try JSONDecoder().decode(RegisteredDevice.self, from: JSONEncoder().encode(device))
        #expect(decoded.typeReports == device.typeReports)
    }

    @Test func newHealthKindsHaveUnitsAndRanges() {
        #expect(SampleKind.vo2Max.canonicalUnit == .millilitersPerKilogramMinute)
        #expect(SampleKind.bodyMass.canonicalUnit == .kilograms)
        #expect(SampleKind.respiratoryRate.canonicalUnit == .breathsPerMinute)
    }
}
