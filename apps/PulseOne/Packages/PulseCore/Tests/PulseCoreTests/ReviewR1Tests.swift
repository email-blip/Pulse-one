import Foundation
import Testing
@testable import PulseCore

/// Regression tests for Codex review P1-003 R1 (F1 wrist temperature, F2 HealthKit origins, F3 handshake)
/// and R2 (R2-1 lossless migration, R2-2 device identity, R2-3 ring lifecycle).
private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

private func health(_ kind: SampleKind, _ value: Double, _ unit: SampleUnit, at offset: TimeInterval = 0,
                    id: String, detail: String?) -> RawObservation {
    RawObservation(kind: kind, value: value, unit: unit, start: t0.addingTimeInterval(offset),
                   end: t0.addingTimeInterval(offset + 600), timeZoneIdentifier: "Europe/Berlin",
                   source: .appleHealth, deviceID: "healthkit", originalSampleID: id, method: .healthStore,
                   originDetail: detail)
}

private func stored(_ raw: RawObservation) throws -> HealthSample {
    try MeasurementNormalizer.normalize(raw, profileID: owner, importedAt: t0.addingTimeInterval(3_600))
}

@Suite("Review R1 F1 – wrist temperature is absolute")
struct WristTemperatureTests {
    @Test func absoluteWristValueIsPlausibleSkinTemperature() throws {
        // A realistic sleeping wrist temperature from HealthKit.
        let sample = try stored(health(.skinTemperature, 34.6, .celsius, id: "wt-1", detail: "com.apple.health|Watch"))
        #expect(sample.quality.usableForAnalysis)
        #expect(sample.unit == .celsius)
    }

    @Test func oldMappingAsDeviationWasRejected() throws {
        // What format 1 did: the same value as "deviation" is implausible and lost for analysis.
        let wrong = try stored(health(.skinTemperatureDeviation, 34.6, .celsius, id: "wt-1", detail: nil))
        #expect(wrong.quality == .implausible)
    }

    @Test func oldCursorForcesOneReimportThenStaysStable() {
        let old = #"{"HKQuantityTypeIdentifierStepCount":"YW5jaG9y"}"#
        let decoded = HealthImportCursor.decode(old)
        #expect(decoded.needsMigration)
        #expect(decoded.anchors.isEmpty)

        var fresh = HealthImportCursor.decode(nil)
        #expect(!fresh.needsMigration)
        fresh["HKQuantityTypeIdentifierStepCount"] = "YW5jaG9y"
        let again = HealthImportCursor.decode(fresh.encode())
        #expect(!again.needsMigration)
        #expect(again["HKQuantityTypeIdentifierStepCount"] == "YW5jaG9y")
    }
}

/// In-memory stand-in for the SwiftData context: changes are staged and only become visible on save.
private final class FakeStore {
    var committed: [HealthSample]
    var staged: [HealthSample]
    var failSave = false
    var saves = 0
    var rollbacks = 0

    init(_ rows: [HealthSample]) { committed = rows; staged = rows }

    func stageMigration() -> HealthImportMigration.Plan {
        let keys = Set(staged.filter { $0.kind == .skinTemperature }.map(\.deduplicationKey))
        let plan = HealthImportMigration.plan(stored: staged, existingKeys: keys, healthDeviceID: "healthkit")
        let fixed = Dictionary(uniqueKeysWithValues: plan.retyped.map { ($0.id, $0) })
        staged = staged.compactMap { plan.duplicates.contains($0.id) ? nil : (fixed[$0.id] ?? $0) }
        return plan
    }

    func stageIngest(_ batch: SyncBatch) {
        let existing = Dictionary(staged.map { ($0.deduplicationKey, $0) }) { first, _ in first }
        let plan = SyncCoordinator.plan(batch: batch, existing: existing, profileID: owner,
                                        importedAt: t0.addingTimeInterval(7_200))
        let updates = Dictionary(uniqueKeysWithValues: plan.updates.map { ($0.id, $0) })
        staged = staged.compactMap { plan.deletions.contains($0.id) ? nil : (updates[$0.id] ?? $0) } + plan.inserts
    }

    struct SaveFailed: Error {}
    func save() throws {
        if failSave { throw SaveFailed() }
        committed = staged
        saves += 1
    }

    func rollback() { staged = committed; rollbacks += 1 }

    /// One sync exactly as `SourcesStore.sync` runs it.
    func sync(cursor: String?, batch: SyncBatch) -> HealthSyncTransaction.Outcome {
        HealthSyncTransaction.run(storedCursor: cursor, batchCursor: batch.nextCursor,
                                  migrating: HealthImportCursor.decode(cursor).needsMigration && cursor != nil,
                                  migrate: { stageMigration() }, ingest: { stageIngest(batch) },
                                  save: { try save() }, rollback: { rollback() })
    }
}

private let formatOneCursor = #"{"HKQuantityTypeIdentifierStepCount":"YW5jaG9y"}"#

private func formatTwoBatch(_ observations: [RawObservation]) -> SyncBatch {
    var batch = SyncBatch(observations: observations)
    var cursor = HealthImportCursor()
    cursor["HKQuantityTypeIdentifierStepCount"] = "bmV1"
    batch.nextCursor = cursor.encode()
    return batch
}

@Suite("Review R2-1 – Health migration is lossless and atomic")
struct HealthMigrationTests {
    private func oldRow(_ id: String, at offset: TimeInterval = 0) throws -> HealthSample {
        try stored(health(.skinTemperatureDeviation, 34.6, .celsius, at: offset, id: id, detail: nil))
    }

    @Test func wrongRowsAreRetypedInPlaceNotDeleted() throws {
        let wrong = try oldRow("wt-1")
        let steps = try stored(health(.steps, 100, .count, id: "s-1", detail: nil))
        let ringDeviation = try MeasurementNormalizer.normalize(
            RawObservation(kind: .skinTemperatureDeviation, value: 0.3, unit: .celsius, start: t0,
                           timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-1",
                           originalSampleID: "r-1", method: .deviceHistory),
            profileID: owner, importedAt: t0.addingTimeInterval(60))
        let plan = HealthImportMigration.plan(stored: [wrong, steps, ringDeviation], existingKeys: [],
                                              healthDeviceID: "healthkit")
        #expect(plan.duplicates.isEmpty)
        let fixed = try #require(plan.retyped.first)
        #expect(plan.retyped.count == 1)
        #expect(fixed.id == wrong.id)
        #expect(fixed.profileID == owner)
        #expect(fixed.value == 34.6)
        #expect(fixed.start == wrong.start)
        #expect(fixed.kind == .skinTemperature)
        #expect(fixed.quality.usableForAnalysis)
        #expect(fixed.deduplicationKey != wrong.deduplicationKey)
    }

    @Test func onlyAProvenDuplicateIsRemoved() throws {
        let wrong = try oldRow("wt-1")
        let right = try stored(health(.skinTemperature, 34.6, .celsius, id: "wt-1", detail: "x|Watch|dev-1"))
        let plan = HealthImportMigration.plan(stored: [wrong, right], existingKeys: [right.deduplicationKey],
                                              healthDeviceID: "healthkit")
        #expect(plan.retyped.isEmpty)
        #expect(plan.duplicates == [wrong.id])
    }

    @Test func rowOlderThanTheReimportWindowIsKept() throws {
        // 90 days back: the 30-day re-import never delivers it again, so retyping is its only repair.
        let old = try oldRow("wt-old", at: -90 * 86_400)
        let store = FakeStore([old])
        let outcome = store.sync(cursor: formatOneCursor, batch: formatTwoBatch([]))
        #expect(outcome.committed)
        #expect(store.committed.count == 1)
        #expect(store.committed.first?.id == old.id)
        #expect(store.committed.first?.kind == .skinTemperature)
    }

    @Test func failedWristQueryStillRepairsAndLaterImportDoesNotDuplicate() throws {
        let old = try oldRow("wt-1")
        let store = FakeStore([old])
        // Wrist query failed: the batch has no wrist samples, only a report with the error.
        var batch = formatTwoBatch([])
        batch.reports = [SyncTypeReport(kind: .skinTemperature, added: 0, deleted: 0, at: t0, error: "locked")]
        let first = store.sync(cursor: formatOneCursor, batch: batch)
        #expect(first.committed)
        #expect(first.migratedRows == 1)
        #expect(HealthImportCursor.decode(first.cursor)["HKAppleSleepingWristTemperature"] == nil)
        // Next sync delivers the wrist value: the retyped row is updated, not inserted twice.
        let second = store.sync(cursor: first.cursor, batch: formatTwoBatch([
            health(.skinTemperature, 34.6, .celsius, id: "wt-1", detail: "x|Watch|dev-1")]))
        #expect(second.committed)
        #expect(store.committed.count == 1)
        #expect(store.committed.first?.id == old.id)
        #expect(store.committed.first?.originDetail == "x|Watch|dev-1")
    }

    @Test func saveFailureRollsBackAndKeepsTheOldCursor() throws {
        let old = try oldRow("wt-1")
        let store = FakeStore([old])
        store.failSave = true
        let outcome = store.sync(cursor: formatOneCursor, batch: formatTwoBatch([
            health(.steps, 100, .count, id: "s-1", detail: "x|iPhone|dev-1")]))
        #expect(!outcome.committed)
        #expect(outcome.cursor == formatOneCursor)
        #expect(store.rollbacks == 1)
        #expect(store.staged == [old])
        #expect(store.committed == [old])
    }

    @Test func restartAfterFailureRepeatsAndSecondRunIsANoOp() throws {
        let old = try oldRow("wt-1")
        let store = FakeStore([old])
        store.failSave = true
        let failed = store.sync(cursor: formatOneCursor, batch: formatTwoBatch([]))
        // App restarts: same stored cursor, the run is repeated in full.
        store.failSave = false
        let repeated = store.sync(cursor: failed.cursor, batch: formatTwoBatch([]))
        #expect(repeated.committed)
        #expect(repeated.migratedRows == 1)
        let afterFirst = store.committed
        // Another run with the new cursor: no migration, nothing changes.
        let again = store.sync(cursor: repeated.cursor, batch: formatTwoBatch([]))
        #expect(again.committed)
        #expect(again.migratedRows == 0)
        #expect(store.committed == afterFirst)
        #expect(HealthImportMigration.plan(stored: store.committed, existingKeys: [], healthDeviceID: "healthkit").isEmpty)
    }

    @Test func unknownNewerFormatIsNotMigratedAndKeepsItsAnchors() {
        let newer = #"{"_format":"7","HKQuantityTypeIdentifierStepCount":"YW5jaG9y"}"#
        let cursor = HealthImportCursor.decode(newer)
        #expect(cursor.isUnknownFormat)
        #expect(!cursor.needsMigration)
        #expect(cursor["HKQuantityTypeIdentifierStepCount"] == "YW5jaG9y")
        #expect(HealthImportCursor.decode(cursor.encode()).format == 7)
    }
}

@Suite("Review R1 F2 – HealthKit origins are kept and not summed twice")
struct HealthOriginTests {
    @Test func overlappingIPhoneAndWatchStepsCountOnce() throws {
        let phone = try stored(health(.steps, 100, .count, id: "p-1", detail: "com.apple.health.A|iPhone|dev-a"))
        let watch = try stored(health(.steps, 120, .count, at: 60, id: "w-1", detail: "com.apple.health.B|Watch|dev-b"))
        let total = try #require(DataSourceResolver.resolveTotal([phone, watch], policy: SourcePolicy()))
        #expect(total.total == 120)
        #expect(total.sampleIDs == [watch.id])
    }

    @Test func samplesOfOneOriginInOneHourStillAddUp() throws {
        let a = try stored(health(.steps, 100, .count, id: "p-1", detail: "com.apple.health.A|iPhone|dev-a"))
        let b = try stored(health(.steps, 50, .count, at: 900, id: "p-2", detail: "com.apple.health.A|iPhone|dev-a"))
        let total = try #require(DataSourceResolver.resolveTotal([a, b], policy: SourcePolicy()))
        #expect(total.total == 150)
    }

    @Test func differentHoursMayUseDifferentDevices() throws {
        let phone = try stored(health(.steps, 100, .count, id: "p-1", detail: "x|iPhone|dev-1"))
        let watch = try stored(health(.steps, 80, .count, at: 3_600, id: "w-1", detail: "x|Watch|dev-2"))
        let total = try #require(DataSourceResolver.resolveTotal([phone, watch], policy: SourcePolicy()))
        #expect(total.total == 180)
    }

    @Test func ringAndHealthAreNeverAddedInTheSameHour() throws {
        let health = try stored(health(.steps, 100, .count, id: "p-1", detail: "x|iPhone|dev-1"))
        let ring = try MeasurementNormalizer.normalize(
            RawObservation(kind: .steps, value: 90, unit: .count, start: t0, end: t0.addingTimeInterval(600),
                           timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-1",
                           originalSampleID: "r-1", method: .deviceHistory),
            profileID: owner, importedAt: t0.addingTimeInterval(3_600))
        let total = try #require(DataSourceResolver.resolveTotal([health, ring], policy: SourcePolicy()))
        #expect(total.total == 100 || total.total == 90)
        #expect(total.sampleCount == 1)
    }

    @Test func resyncFillsOriginOnExistingRowWithoutDuplicate() throws {
        let before = try stored(health(.steps, 100, .count, id: "p-1", detail: nil))
        let batch = SyncBatch(observations: [health(.steps, 100, .count, id: "p-1", detail: "x|iPhone|dev-1")])
        let plan = SyncCoordinator.plan(batch: batch, existing: [before.deduplicationKey: before],
                                        profileID: owner, importedAt: t0.addingTimeInterval(3_600))
        #expect(plan.inserts.isEmpty)
        #expect(plan.updates.count == 1)
        #expect(plan.updates.first?.id == before.id)
        #expect(plan.updates.first?.originDetail == "x|iPhone|dev-1")
    }

    @Test func laterDeletionInHealthRemovesTheRow() throws {
        let row = try stored(health(.steps, 100, .count, id: "p-1", detail: "x|iPhone|dev-1"))
        let plan = SyncCoordinator.plan(batch: SyncBatch(deletedOriginalIDs: ["p-1"]),
                                        existing: [row.deduplicationKey: row], profileID: owner,
                                        importedAt: t0.addingTimeInterval(3_600))
        #expect(plan.deletions == [row.id])
    }
}

@Suite("Review R2-2 – one origin is one device, totals say when they are provisional")
struct HealthDeviceIdentityTests {
    @Test func sameAppSameModelDifferentDevicesStayApart() {
        let a = HealthOrigin.detail(bundle: "com.apple.health", model: "iPhone", localIdentifier: "A1B2")
        let b = HealthOrigin.detail(bundle: "com.apple.health", model: "iPhone", localIdentifier: "C3D4")
        #expect(a != b)
        #expect(HealthOrigin.identifiesDevice(a))
        // Stable across calls, and the raw identifier is not stored.
        #expect(a == HealthOrigin.detail(bundle: "com.apple.health", model: "iPhone", localIdentifier: "A1B2"))
        #expect(!a.contains("A1B2"))
    }

    @Test func missingIdentityStaysUnknown() {
        let none = HealthOrigin.detail(bundle: "com.apple.health", model: "iPhone", localIdentifier: nil)
        let empty = HealthOrigin.detail(bundle: "com.apple.health", model: nil, localIdentifier: "")
        #expect(none == "com.apple.health|iPhone|unbekannt")
        #expect(empty == "com.apple.health|unbekannt|unbekannt")
        #expect(!HealthOrigin.identifiesDevice(none))
        #expect(!HealthOrigin.identifiesDevice(nil))
        #expect(!HealthOrigin.identifiesDevice("com.apple.health|iPhone"))
    }

    @Test func twoPhonesOfTheSameModelAreNotMerged() throws {
        let a = HealthOrigin.detail(bundle: "com.apple.health", model: "iPhone", localIdentifier: "A1B2")
        let b = HealthOrigin.detail(bundle: "com.apple.health", model: "iPhone", localIdentifier: "C3D4")
        let one = try stored(health(.steps, 100, .count, id: "a-1", detail: a))
        let two = try stored(health(.steps, 70, .count, at: 60, id: "b-1", detail: b))
        let total = try #require(DataSourceResolver.resolveTotal([one, two], policy: SourcePolicy()))
        // Overlap rule (provisional): one device per hour, and the result says so.
        #expect(total.total == 100)
        #expect(total.caveats.contains(.overlapDropped))
        #expect(total.isProvisional)
    }

    @Test func healthTotalsAreAlwaysMarkedProvisional() throws {
        let only = try stored(health(.steps, 100, .count, id: "p-1", detail: "x|iPhone|dev-1"))
        let total = try #require(DataSourceResolver.resolveTotal([only], policy: SourcePolicy()))
        #expect(total.caveats == [.healthRawSamples])
    }

    @Test func historicRowsWithoutOriginAreNotTreatedAsSolved() throws {
        let a = try stored(health(.steps, 100, .count, id: "p-1", detail: nil))
        let b = try stored(health(.steps, 60, .count, at: 60, id: "p-2", detail: nil))
        let total = try #require(DataSourceResolver.resolveTotal([a, b], policy: SourcePolicy()))
        // Without a device they cannot be separated: both count, and the total says the origin is unknown.
        #expect(total.total == 160)
        #expect(total.caveats.contains(.unknownOrigin))
    }

    @Test func dailyValueKeepsTheCaveats() throws {
        let a = try stored(health(.steps, 100, .count, id: "p-1", detail: nil))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = try #require(DailySeries.build([a], kind: .steps, calendar: calendar).first)
        #expect(day.isProvisional)
        #expect(day.caveats == [.healthRawSamples, .unknownOrigin])
    }

    @Test func ringTotalsCarryNoHealthCaveat() throws {
        let ring = try MeasurementNormalizer.normalize(
            RawObservation(kind: .steps, value: 90, unit: .count, start: t0, end: t0.addingTimeInterval(600),
                           timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-1",
                           originalSampleID: "r-1", method: .deviceHistory),
            profileID: owner, importedAt: t0.addingTimeInterval(3_600))
        let total = try #require(DataSourceResolver.resolveTotal([ring], policy: SourcePolicy()))
        #expect(total.caveats.isEmpty)
    }
}

@Suite("Review R1 F3 / R2-3 / R3-1 – ring handshake and lifecycle")
struct RingHandshakeTests {
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func connected() -> RingHandshake {
        var h = RingHandshake()
        #expect(h.handle(.connectRequested(at(0))) == .connectNow)
        h.handle(.connected(at(1)))
        return h
    }

    func ready() -> RingHandshake {
        var h = connected()
        h.handle(.servicesDiscovered(hasUART: true, error: nil))
        h.handle(.uartCharacteristics(hasWrite: true, hasNotify: true, error: nil))
        h.handle(.notifyState(isOn: true, error: nil))
        return h
    }

    @Test func fullChainBecomesReady() {
        var h = connected()
        h.handle(.servicesDiscovered(hasUART: true, error: nil))
        #expect(h.acceptsCharacteristics)
        h.handle(.uartCharacteristics(hasWrite: true, hasNotify: true, error: nil))
        #expect(!h.isReady)
        h.handle(.notifyState(isOn: true, error: nil))
        #expect(h.isReady)
    }

    @Test func connectWithoutAnswerTimesOut() {
        var h = RingHandshake(connectTimeout: 15)
        h.handle(.connectRequested(at(0)))
        h.handle(.tick(at(14)))
        #expect(h.needsTimer)
        h.handle(.tick(at(15)))
        #expect(h.failure == .connectTimeout)
    }

    @Test func missingNotifyAckTimesOut() {
        var h = connected()
        h.handle(.servicesDiscovered(hasUART: true, error: nil))
        h.handle(.uartCharacteristics(hasWrite: true, hasNotify: true, error: nil))
        h.handle(.tick(at(15)))
        #expect(h.needsTimer)
        h.handle(.tick(at(16)))
        #expect(h.failure == .handshakeTimeout)
    }

    @Test func missingWriteOrNotifyFails() {
        var noWrite = connected()
        noWrite.handle(.servicesDiscovered(hasUART: true, error: nil))
        noWrite.handle(.uartCharacteristics(hasWrite: false, hasNotify: true, error: nil))
        #expect(noWrite.failure == .missingWrite)

        var noNotify = connected()
        noNotify.handle(.servicesDiscovered(hasUART: true, error: nil))
        noNotify.handle(.uartCharacteristics(hasWrite: true, hasNotify: false, error: nil))
        #expect(noNotify.failure == .missingNotify)
    }

    @Test func discoveryErrorsFail() {
        var services = connected()
        services.handle(.servicesDiscovered(hasUART: true, error: "Timeout"))
        #expect(services.failure == .serviceDiscoveryFailed("Timeout"))

        var noUART = connected()
        noUART.handle(.servicesDiscovered(hasUART: false, error: nil))
        #expect(noUART.failure == .noUARTService)

        var characteristics = connected()
        characteristics.handle(.servicesDiscovered(hasUART: true, error: nil))
        characteristics.handle(.uartCharacteristics(hasWrite: true, hasNotify: true, error: "GATT 133"))
        #expect(characteristics.failure == .characteristicDiscoveryFailed("GATT 133"))
    }

    @Test func notifyRefusedFails() {
        var h = connected()
        h.handle(.servicesDiscovered(hasUART: true, error: nil))
        h.handle(.uartCharacteristics(hasWrite: true, hasNotify: true, error: nil))
        h.handle(.notifyState(isOn: false, error: "Not permitted"))
        #expect(h.failure == .notifyRejected("Not permitted"))
    }

    @Test func notifyBeforeCharacteristicsDoesNotMakeReady() {
        var h = connected()
        h.handle(.notifyState(isOn: true, error: nil))
        #expect(!h.isReady)
        #expect(!h.acceptsCharacteristics)
    }

    @Test func readyStaysReadyOnTicks() {
        var h = ready()
        h.handle(.tick(at(500)))
        #expect(h.isReady)
    }

    // R2-3: late callbacks of the same ring

    @Test func lateDidConnectAfterManualDisconnectIsRejected() {
        var h = ready()
        h.handle(.cancelRequested(at(10)))
        #expect(h.handle(.connected(at(11))) == .rejectConnection)
        #expect(!h.isReady)
        h.handle(.disconnected(at(12)))
        #expect(h.step == .idle)
        #expect(h.handle(.connected(at(13))) == .rejectConnection)
        #expect(h.step == .idle)
    }

    @Test func newConnectWaitsForTheOldLinkAndLateCallbacksCannotFinishIt() {
        var h = ready()
        h.handle(.cancelRequested(at(10)))                         // disconnect A
        #expect(h.handle(.connectRequested(at(10.5))) == .none)     // connect B queued, nothing sent yet
        // Late callbacks of A while B waits: none may set ready or start B's discovery.
        h.handle(.notifyState(isOn: true, error: nil))
        h.handle(.uartCharacteristics(hasWrite: true, hasNotify: true, error: nil))
        #expect(h.handle(.connected(at(10.8))) == .rejectConnection)
        #expect(!h.isReady)
        // The disconnect callback of A releases B.
        #expect(h.handle(.disconnected(at(11))) == .connectNow)
        #expect(h.step == .connecting(since: at(11)))
        // A notify ack that arrives now still belongs to no expected step.
        h.handle(.notifyState(isOn: true, error: nil))
        #expect(!h.isReady)
        h.handle(.connected(at(12)))
        #expect(h.step == .discoveringServices(since: at(12)))
    }

    // R3-1: no blind reconnect after the ack timeout (Codex counterexample)

    @Test func missingCancelAckAbortsTheQueuedConnectInsteadOfConnectingBlindly() {
        var h = ready()
        h.handle(.cancelRequested(at(10)))
        #expect(h.handle(.connectRequested(at(10.5))) == .none)
        #expect(h.handle(.tick(at(11.9))) == .none)
        // Limit reached without proof of release: abort and explain, nothing is sent.
        #expect(h.handle(.tick(at(12))) == .none)
        #expect(h.failure == .releaseTimeout)
        #expect(h.releasePending)
        #expect(h.needsTimer)                                   // the driver keeps watching the old link
        // Codex' case: the old disconnect arrives late. It proves the release but starts nothing by itself.
        #expect(h.handle(.disconnected(at(12.1))) == .none)
        #expect(!h.releasePending)
        #expect(h.failure == .releaseTimeout)
        // Only the user's next request connects, now on a released link.
        #expect(h.handle(.connectRequested(at(13))) == .connectNow)
        #expect(h.step == .connecting(since: at(13)))
    }

    @Test func strayDisconnectDoesNotResetANewAttempt() {
        var h = ready()
        h.handle(.cancelRequested(at(10)))
        h.handle(.disconnected(at(10.5)))                       // proof of release
        #expect(h.handle(.connectRequested(at(11))) == .connectNow)
        h.handle(.disconnected(at(11.2)))                       // a second, stray callback of the old link
        #expect(h.step == .connecting(since: at(11)))
        h.handle(.connected(at(12)))
        #expect(h.step == .discoveringServices(since: at(12)))
    }

    @Test func observedReleaseStartsTheQueuedConnect() {
        var h = ready()
        h.handle(.cancelRequested(at(10)))
        h.handle(.connectRequested(at(10.5)))
        // No callback, but the driver saw `CBPeripheral.state == .disconnected` (or Bluetooth off).
        #expect(h.handle(.released(at(11))) == .connectNow)
        #expect(h.step == .connecting(since: at(11)))
    }

    @Test func requestWhileReleaseIsStillUnprovenRetriesTheCancel() {
        var h = ready()
        h.handle(.cancelRequested(at(10)))
        h.handle(.connectRequested(at(10.5)))
        h.handle(.tick(at(12)))
        #expect(h.failure == .releaseTimeout)
        #expect(h.handle(.connectRequested(at(20))) == .retryCancel)
        #expect(h.step == .cancelling(since: at(20), reconnect: true))
        #expect(h.handle(.connected(at(20.5))) == .rejectConnection)
        #expect(h.handle(.released(at(21))) == .connectNow)
    }

    @Test func connectFailureEndsTheAttempt() {
        var h = RingHandshake()
        h.handle(.connectRequested(at(0)))
        h.handle(.connectFailed)
        #expect(h.step == .idle)
        #expect(!h.needsTimer)
    }

    @Test func failedHandshakeKeepsItsMessageWhileTheLinkIsReleased() {
        var h = connected()
        h.handle(.servicesDiscovered(hasUART: false, error: nil))
        h.handle(.cancelRequested(at(2)))                       // the driver drops the useless link
        #expect(h.failure == .noUARTService)
        #expect(h.releasePending)
        h.handle(.disconnected(at(2.5)))
        #expect(h.failure == .noUARTService)
        #expect(!h.releasePending)
    }

    @Test func automaticReconnectAcceptsTheReturningRing() {
        var h = ready()
        h.handle(.disconnected(at(20)))          // ring walked out of range
        #expect(h.step == .idle)
        h.handle(.reconnectScheduled)
        #expect(!h.needsTimer)                    // CoreBluetooth waits without a limit
        h.handle(.connected(at(60)))
        #expect(h.step == .discoveringServices(since: at(60)))
    }

    @Test func failureStaysVisibleUntilTheNextRequest() {
        var h = connected()
        h.handle(.servicesDiscovered(hasUART: false, error: nil))
        h.handle(.disconnected(at(5)))
        #expect(h.failure == .noUARTService)
        h.handle(.connectRequested(at(6)))
        #expect(h.step == .connecting(since: at(6)))
    }
}
