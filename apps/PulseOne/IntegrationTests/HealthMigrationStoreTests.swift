import Foundation
import PulseCore
import SwiftData
import Testing

private struct InjectedSaveFailure: Error {}

/// Codex review P1-003 R3-2: the Health format migration against a real in-memory SwiftData store,
/// with the app's own `StoredSample` and `SampleStore` (unique dedup key, pending changes, rollback).
/// Synthetic values only, no real health data.
@MainActor
@Suite("R3-2 – Health migration in real SwiftData", .serialized)
struct HealthMigrationStoreTests {
    let container: ModelContainer
    let context: ModelContext
    let store: SampleStore
    let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let deviceID = "healthkit"

    init() throws {
        container = try ModelContainer(for: StoredSample.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        context.autosaveEnabled = false
        store = SampleStore(context: context)
    }

    // MARK: Fixtures

    private let formatOneCursor = #"{"HKQuantityTypeIdentifierStepCount":"YW5jaG9y"}"#

    private func formatTwoCursor() -> String? {
        var cursor = HealthImportCursor()
        cursor["HKQuantityTypeIdentifierStepCount"] = "bmV1"
        return cursor.encode()
    }

    private func raw(_ kind: SampleKind, _ value: Double, id: String, daysAgo: Double = 0,
                     detail: String? = nil) -> RawObservation {
        let start = now.addingTimeInterval(-daysAgo * 86_400 - 3_600)
        return RawObservation(kind: kind, value: value, unit: kind == .steps ? .count : .celsius, start: start,
                              end: start.addingTimeInterval(600), timeZoneIdentifier: "Europe/Berlin",
                              source: .appleHealth, deviceID: deviceID, originalSampleID: id, method: .healthStore,
                              originDetail: detail)
    }

    /// A row exactly as format 1 stored it: absolute wrist temperature typed as deviation.
    @discardableResult
    private func insertFormatOneRow(id: String, daysAgo: Double = 0) throws -> UUID {
        let sample = try MeasurementNormalizer.normalize(raw(.skinTemperatureDeviation, 34.6, id: id, daysAgo: daysAgo),
                                                         profileID: owner, importedAt: now.addingTimeInterval(-daysAgo * 86_400))
        #expect(sample.quality == .implausible)
        context.insert(StoredSample(sample))
        try context.save()
        return sample.id
    }

    private func batch(_ observations: [RawObservation]) -> SyncBatch {
        SyncBatch(observations: observations, nextCursor: formatTwoCursor())
    }

    private func rows() throws -> [StoredSample] {
        try context.fetch(FetchDescriptor<StoredSample>(sortBy: [SortDescriptor(\.start)]))
    }

    private func sync(_ batch: SyncBatch, cursor: String?, failSave: Bool = false) -> HealthSyncTransaction.Outcome {
        let failing: (() throws -> Void)? = failSave ? { throw InjectedSaveFailure() } : nil
        return store.syncHealth(batch, deviceID: deviceID, storedCursor: cursor, profiles: .constant(owner),
                                now: now, save: failing).0
    }

    private func key(_ kind: SampleKind, _ id: String) -> String {
        HealthSample.deduplicationKey(source: .appleHealth, deviceID: deviceID, kind: kind, originalSampleID: id)
    }

    // MARK: Tests

    @Test func oldKeyBecomesTheCorrectKeyOnTheSameRow() throws {
        let id = try insertFormatOneRow(id: "wt-1")
        let outcome = sync(batch([]), cursor: formatOneCursor)
        #expect(outcome.committed)
        #expect(outcome.migratedRows == 1)
        let all = try rows()
        #expect(all.count == 1)
        let row = try #require(all.first)
        #expect(row.sampleID == id)
        #expect(row.profileID == owner)
        #expect(row.value == 34.6)
        #expect(row.kindRaw == SampleKind.skinTemperature.rawValue)
        #expect(row.dedupKey == key(.skinTemperature, "wt-1"))
        #expect(row.sample?.quality.usableForAnalysis == true)
        // The old key is gone from the store.
        let oldKey = key(.skinTemperatureDeviation, "wt-1")
        #expect(try context.fetchCount(FetchDescriptor<StoredSample>(predicate: #Predicate { $0.dedupKey == oldKey })) == 0)
    }

    @Test func reimportInTheSameTransactionCreatesNoDuplicate() throws {
        let id = try insertFormatOneRow(id: "wt-1")
        // The re-import delivers the same HealthKit sample, correctly typed, in the same run.
        let outcome = sync(batch([raw(.skinTemperature, 34.6, id: "wt-1", detail: "com.apple.health|Watch|dev-1")]),
                           cursor: formatOneCursor)
        #expect(outcome.committed)
        let all = try rows()
        #expect(all.count == 1)
        #expect(all.first?.sampleID == id)
        #expect(all.first?.originDetail == "com.apple.health|Watch|dev-1")
    }

    @Test func provenDuplicateIsRemovedAndTheCorrectRowStays() throws {
        try insertFormatOneRow(id: "wt-1")
        let right = try MeasurementNormalizer.normalize(raw(.skinTemperature, 34.6, id: "wt-1"),
                                                        profileID: owner, importedAt: now)
        context.insert(StoredSample(right))
        try context.save()
        let outcome = sync(batch([]), cursor: formatOneCursor)
        #expect(outcome.committed)
        #expect(outcome.removedDuplicates == 1)
        let all = try rows()
        #expect(all.map(\.sampleID) == [right.id])
    }

    @Test func rowOlderThanThirtyDaysIsKept() throws {
        let id = try insertFormatOneRow(id: "wt-old", daysAgo: 90)
        let outcome = sync(batch([raw(.steps, 100, id: "s-1")]), cursor: formatOneCursor)
        #expect(outcome.committed)
        let old = try #require(try rows().first { $0.sampleID == id })
        #expect(old.kindRaw == SampleKind.skinTemperature.rawValue)
        #expect(try rows().count == 2)
    }

    @Test func injectedSaveFailureRollsBackThenRetrySucceeds() throws {
        let id = try insertFormatOneRow(id: "wt-1")
        let failed = sync(batch([raw(.steps, 100, id: "s-1")]), cursor: formatOneCursor, failSave: true)
        #expect(!failed.committed)
        #expect(failed.cursor == formatOneCursor)
        // After the real `context.rollback()` nothing staged is left: old type, old key, no new row.
        #expect(!context.hasChanges)
        var all = try rows()
        #expect(all.count == 1)
        #expect(all.first?.sampleID == id)
        #expect(all.first?.kindRaw == SampleKind.skinTemperatureDeviation.rawValue)
        #expect(all.first?.dedupKey == key(.skinTemperatureDeviation, "wt-1"))

        // Restart: the same run is repeated from the old cursor and now succeeds.
        let retried = sync(batch([raw(.steps, 100, id: "s-1")]), cursor: failed.cursor)
        #expect(retried.committed)
        #expect(retried.migratedRows == 1)
        all = try rows()
        #expect(all.count == 2)
        #expect(all.first { $0.sampleID == id }?.kindRaw == SampleKind.skinTemperature.rawValue)
    }

    @Test func repeatingAfterSuccessChangesNothing() throws {
        try insertFormatOneRow(id: "wt-1")
        let first = sync(batch([raw(.steps, 100, id: "s-1")]), cursor: formatOneCursor)
        #expect(first.committed)
        let snapshot = try rows().map { [$0.dedupKey, $0.kindRaw, $0.qualityRaw, "\($0.value)"] }
        let second = sync(batch([raw(.steps, 100, id: "s-1")]), cursor: first.cursor)
        #expect(second.committed)
        #expect(second.migratedRows == 0)
        #expect(try rows().map { [$0.dedupKey, $0.kindRaw, $0.qualityRaw, "\($0.value)"] } == snapshot)
    }

    @Test func otherRowsAreNeverTouched() throws {
        let ring = try MeasurementNormalizer.normalize(
            RawObservation(kind: .skinTemperatureDeviation, value: 0.3, unit: .celsius, start: now.addingTimeInterval(-7_200),
                           timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-1",
                           originalSampleID: "r-1", method: .deviceHistory),
            profileID: owner, importedAt: now)
        context.insert(StoredSample(ring))
        try context.save()
        try insertFormatOneRow(id: "wt-1")
        #expect(sync(batch([]), cursor: formatOneCursor).committed)
        let ringRow = try #require(try rows().first { $0.sampleID == ring.id })
        #expect(ringRow.kindRaw == SampleKind.skinTemperatureDeviation.rawValue)
        #expect(ringRow.dedupKey == ring.deduplicationKey)
    }
}
