import Foundation
import Testing
@testable import PulseCore

// Directive 3.1 QA cases: repeated sync, overlapping devices, units, faulty timestamps, interrupted sync,
// profile switch, missing Health permission, existing R03 path (migration of ring readings).

private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let guest = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

private func obs(_ kind: SampleKind = .heartRate, _ value: Double, _ unit: SampleUnit = .beatsPerMinute,
                 at offset: TimeInterval = 0, id: String, source: DataSourceKind = .colmiRing,
                 device: String = "ring-1") -> RawObservation {
    RawObservation(kind: kind, value: value, unit: unit, start: t0.addingTimeInterval(offset),
                   timeZoneIdentifier: "Europe/Berlin", source: source, deviceID: device,
                   originalSampleID: id, method: .deviceHistory)
}

private func reading(_ bpm: Int, at offset: TimeInterval, source: MeasurementSource = .ringLive,
                     device: String = "ring-1") -> VitalReading {
    VitalReading(metric: .heartRate, value: bpm, timestamp: t0.addingTimeInterval(offset), source: source,
                 deviceName: "R03_1A2B", deviceIdentifier: device, model: "R03", firmware: "3.00.10")!
}

/// Applies plans to an in-memory dictionary the way `SampleStore` applies them to SwiftData.
private struct MemoryStore {
    var rows: [String: HealthSample] = [:]

    @discardableResult
    mutating func ingest(_ batch: SyncBatch, profile: UUID = owner, at time: Date = t0) -> SyncPlan {
        let plan = SyncCoordinator.plan(batch: batch, existing: rows, profileID: profile, importedAt: time)
        for s in plan.inserts + plan.updates { rows[s.deduplicationKey] = s }
        for id in plan.deletions { rows = rows.filter { $0.value.id != id } }
        return plan
    }
}

@Suite("Ring readings and migration")
struct RingMigrationTests {
    @Test func liveAndMigratedReadingGetTheSameKey() {
        let r = reading(64, at: 0)
        let live = RawObservation(reading: r, timeZoneIdentifier: "Europe/Berlin")
        // The migration rebuilds the reading from the stored row: new UUID, same content.
        let rebuilt = VitalReading(metric: r.metric, value: r.value, timestamp: r.timestamp, source: r.source,
                                   deviceName: r.deviceName, deviceIdentifier: r.deviceIdentifier,
                                   model: r.model, firmware: r.firmware)!
        let migrated = RawObservation(reading: rebuilt, timeZoneIdentifier: nil)
        #expect(live.deduplicationKey == migrated.deduplicationKey)
        #expect(live.kind == .heartRate && live.unit == .beatsPerMinute && live.method == .liveSensor)
    }

    @Test func historyAndLiveAtTheSameMillisecondStayApart() {
        let live = RawObservation(reading: reading(64, at: 0), timeZoneIdentifier: nil)
        let history = RawObservation(reading: reading(64, at: 0, source: .ringHistory), timeZoneIdentifier: nil)
        #expect(live.deduplicationKey != history.deduplicationKey)
        #expect(history.method == .deviceHistory)
    }

    @Test func migrationAfterDualWriteAddsNothing() {
        // Since M2 the app writes every ring value to both tables. Migrating afterwards must not duplicate.
        var store = MemoryStore()
        let readings = [reading(64, at: 0), reading(66, at: 20), reading(67, at: 40)]
        for r in readings { store.ingest(SyncBatch(observations: [RawObservation(reading: r, timeZoneIdentifier: "Europe/Berlin")])) }
        let migration = store.ingest(SyncBatch(observations: readings.map { RawObservation(reading: $0, timeZoneIdentifier: nil) }))
        #expect(migration.inserts.isEmpty)
        #expect(store.rows.count == 3)
    }

    @Test func interruptedMigrationResumesWithoutDuplicates() {
        var store = MemoryStore()
        let all = (0..<10).map { RawObservation(reading: reading(60 + $0, at: Double($0) * 30), timeZoneIdentifier: nil) }
        store.ingest(SyncBatch(observations: Array(all.prefix(4))))      // app killed after the first part
        let resumed = store.ingest(SyncBatch(observations: all))
        #expect(resumed.inserts.count == 6)
        #expect(resumed.unchanged == 4)
        #expect(store.rows.count == 10)
    }
}

@Suite("Directive 3.1 QA")
struct DirectiveQATests {
    @Test func repeatedSyncIsIdempotent() {
        var store = MemoryStore()
        let batch = SyncBatch(observations: [obs(.steps, 500, .count, id: "a"), obs(.heartRate, 61, id: "b")])
        store.ingest(batch)
        for _ in 0..<3 { #expect(store.ingest(batch).isEmpty) }
        #expect(store.rows.count == 2)
    }

    @Test func twoDevicesOfTheSameSourceAreStoredApartAndResolvedByPriority() throws {
        var store = MemoryStore()
        store.ingest(SyncBatch(observations: [obs(.heartRate, 60, id: "slot-1", device: "ring-a"),
                                              obs(.heartRate, 72, at: 5, id: "slot-1", device: "ring-b")]))
        // Same original id on two rings: two different samples, nothing overwritten.
        #expect(store.rows.count == 2)
        let samples = Array(store.rows.values)
        #expect(DataSourceResolver.resolvePoints(samples, devicePriority: ["ring-b"]).map(\.value) == [72])
        // Without a device priority the choice is stable (device id order), never an average.
        #expect(DataSourceResolver.resolvePoints(samples).map(\.value) == [60])
        let steps = [obs(.steps, 4_000, .count, id: "d", device: "ring-a"), obs(.steps, 4_500, .count, id: "d", device: "ring-b")]
        var stepStore = MemoryStore()
        stepStore.ingest(SyncBatch(observations: steps))
        let total = try #require(DataSourceResolver.resolveTotal(Array(stepStore.rows.values), devicePriority: ["ring-b"]))
        #expect(total.total == 4_500)
        #expect(total.origin == SampleOrigin(source: .colmiRing, deviceID: "ring-b"))
    }

    @Test func differentUnitsEndUpCanonical() {
        var store = MemoryStore()
        store.ingest(SyncBatch(observations: [obs(.activeEnergy, 418.4, .kilojoules, id: "e", source: .appleHealth, device: "healthkit"),
                                              obs(.trainingDuration, 45, .minutes, id: "t", source: .appleHealth, device: "healthkit"),
                                              obs(.elevationGain, 1_000, .feet, id: "h", source: .appleHealth, device: "healthkit")]))
        let byKind = Dictionary(uniqueKeysWithValues: store.rows.values.map { ($0.kind, $0) })
        #expect(abs((byKind[.activeEnergy]?.value ?? 0) - 100) < 0.001)
        #expect(byKind[.activeEnergy]?.unit == .kilocalories)
        #expect(byKind[.trainingDuration]?.value == 2_700)
        #expect(abs((byKind[.elevationGain]?.value ?? 0) - 304.8) < 0.001)
    }

    @Test func faultyTimestampsAreRejectedNotStored() {
        let unsetClock = RawObservation(kind: .heartRate, value: 60, unit: .beatsPerMinute,
                                        start: Date(timeIntervalSince1970: 0), source: .colmiRing, deviceID: "ring-1",
                                        originalSampleID: "1970", method: .deviceHistory)
        let batch = SyncBatch(observations: [unsetClock,
                                             obs(.heartRate, 60, at: 3 * 3_600, id: "future"),
                                             obs(.heartRate, 60, at: 5 * 60, id: "small-skew"),
                                             RawObservation(kind: .sleepDuration, value: 60, unit: .seconds, start: t0,
                                                            end: t0.addingTimeInterval(-60), source: .appleHealth,
                                                            deviceID: "healthkit", originalSampleID: "backwards",
                                                            method: .healthStore)])
        let plan = SyncCoordinator.plan(batch: batch, existing: [:], profileID: owner, importedAt: t0)
        #expect(plan.inserts.map(\.originalSampleID) == ["small-skew"])
        #expect(Set(plan.rejected.map { "\($0)" }) == ["timestampTooOld", "timestampInFuture", "endBeforeStart"])
    }

    @Test func profileSwitchMovesResyncedSamplesWithoutDuplicates() {
        var store = MemoryStore()
        let batch = SyncBatch(observations: [obs(.heartRate, 60, id: "x"), obs(.heartRate, 62, at: 60, id: "y")])
        store.ingest(batch, profile: owner)
        let switched = store.ingest(batch, profile: guest)
        #expect(switched.inserts.isEmpty)
        #expect(switched.updates.count == 2)
        #expect(store.rows.count == 2)
        #expect(store.rows.values.allSatisfy { $0.profileID == guest })
    }

    @Test func healthSyncWithoutDataIsFlagged() throws {
        var registry = DeviceRegistry(ownerProfileID: owner)
        let health = try registry.add(adapterID: AdapterCatalog.appleHealth.id, sourceIdentifier: "healthkit",
                                      name: "Apple Health", profileID: owner)
        #expect(registry.device(health.id)?.syncedWithoutData == false)   // never synced: no hint yet
        try registry.update(health.id) { $0.reach(.compatible); $0.lastSuccessfulSync = t0 }
        #expect(registry.device(health.id)?.syncedWithoutData == true)
        try registry.update(health.id) { $0.reach(.dataAccess) }
        #expect(registry.device(health.id)?.syncedWithoutData == false)
    }
}

@Suite("Daily series")
struct DailySeriesTests {
    private var berlin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func normalized(_ r: RawObservation) throws -> HealthSample {
        try MeasurementNormalizer.normalize(r, profileID: owner, importedAt: t0.addingTimeInterval(7 * 86_400))
    }

    @Test func cumulativeDaysUseOneOriginOnly() throws {
        let samples = try [obs(.steps, 1_000, .count, id: "r1"), obs(.steps, 2_000, .count, at: 600, id: "r2"),
                           obs(.steps, 9_000, .count, id: "h", source: .appleHealth, device: "healthkit"),
                           obs(.steps, 500, .count, at: 86_400, id: "r3")].map(normalized)
        let days = DailySeries.build(samples, kind: .steps, calendar: berlin)
        #expect(days.map(\.value) == [3_000, 500])
        #expect(days.first?.origins == [SampleOrigin(source: .colmiRing, deviceID: "ring-1")])
        #expect(days.first?.sampleCount == 2)
    }

    @Test func pointDaysAverageResolvedValuesAndSkipImplausible() throws {
        let samples = try [obs(.heartRate, 60, id: "a"), obs(.heartRate, 70, at: 120, id: "b"),
                           obs(.heartRate, 400, at: 240, id: "wild")].map(normalized)
        let day = try #require(DailySeries.build(samples, kind: .heartRate, calendar: berlin).first)
        #expect(day.value == 65)
        #expect(day.minimum == 60 && day.maximum == 70)
        #expect(day.sampleCount == 2)
    }

    @Test func daysFollowTheCalendarTimeZone() throws {
        // 23:30 in Berlin and 00:30 the next day are two days, although only an hour apart.
        let comps = DateComponents(timeZone: TimeZone(identifier: "Europe/Berlin"), year: 2026, month: 11, day: 19, hour: 23, minute: 30)
        let late = try #require(berlin.date(from: comps))
        let samples = try [0.0, 3_600].enumerated().map { i, off in
            try MeasurementNormalizer.normalize(
                RawObservation(kind: .steps, value: 100, unit: .count, start: late.addingTimeInterval(off),
                               source: .colmiRing, deviceID: "ring-1", originalSampleID: "s\(i)", method: .deviceHistory),
                profileID: owner, importedAt: late.addingTimeInterval(7_200))
        }
        #expect(DailySeries.build(samples, kind: .steps, calendar: berlin).count == 2)
    }
}
