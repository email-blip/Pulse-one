import Foundation
import PulseCore
import SwiftData
import Testing

/// Test team R1 against a real in-memory SwiftData store: ring history rows stored with the old
/// value-bearing id are folded into one row per slot, and a later sync updates that row.
/// Synthetic values only, no real health data.
@MainActor
@Suite("R1 – ring history ids in real SwiftData", .serialized)
struct RingHistoryIDStoreTests {
    let container: ModelContainer
    let context: ModelContext
    let store: SampleStore
    let deviceID = "ring-1"

    init() throws {
        container = try ModelContainer(for: StoredSample.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        context.autosaveEnabled = false
        store = SampleStore(context: context)
    }

    var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    var slot: Date { berlin.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 8, minute: 15))! }

    private func insertLegacy(_ steps: Double, importedAfter minutes: Double) throws {
        let millis = Int64(slot.timeIntervalSince1970 * 1_000)
        let sample = HealthSample(profileID: nil, kind: .steps, value: steps, unit: .count, start: slot,
                                  end: slot.addingTimeInterval(900), timeZoneIdentifier: "Europe/Berlin",
                                  source: .colmiRing, deviceID: deviceID,
                                  originalSampleID: "history-\(millis)-i15-steps-v\(Int(steps))",
                                  importedAt: slot.addingTimeInterval(minutes * 60), quality: .valid,
                                  method: .deviceHistory, identity: .derived)
        context.insert(StoredSample(sample))
        try context.save()
    }

    private func rows() throws -> [StoredSample] { try context.fetch(FetchDescriptor<StoredSample>()) }

    @Test func duplicatesFoldIntoOneRowAndTheNextSyncUpdatesIt() throws {
        try insertLegacy(100, importedAfter: 10)
        try insertLegacy(250, importedAfter: 30)
        #expect(try rows().count == 2)

        let plan = try store.migrateRingHistoryIDs(deviceID: deviceID, fallbackZone: berlin.timeZone)
        #expect(plan.duplicates.count == 1)
        let kept = try rows()
        #expect(kept.count == 1)
        #expect(kept.first?.value == 250)
        #expect(kept.first?.originalSampleID == "history-wc202611200815-i15-steps")

        #expect(try store.migrateRingHistoryIDs(deviceID: deviceID, fallbackZone: berlin.timeZone).isEmpty)

        let mapper = RingHistoryMapper(deviceID: deviceID, calendar: berlin, today: slot.addingTimeInterval(3_600))
        let entry = ActivityEntry(year: 2026, month: 11, day: 20, quarter: 33, steps: 310, distanceMeters: 0, caloriesRaw: 0)
        let next = try store.ingest(SyncBatch(observations: mapper.activity([entry])), deviceID: deviceID,
                                    profiles: .constant(nil), now: slot.addingTimeInterval(3_600))
        #expect(next.inserts.isEmpty)
        #expect(next.updates.count == 1)
        #expect(try rows().map(\.value) == [310])
    }
}
