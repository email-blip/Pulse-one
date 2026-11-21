import Foundation
import Testing
@testable import PulseCore

/// Test team findings R1 (double counting), R6 (daylight saving), R7 (time-zone change),
/// R9 (late packet after a timeout).
@Suite("Ring history identity")
struct RingHistoryIdentityTests {
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static let berlin = calendar("Europe/Berlin")

    static func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func packet(_ command: ColmiProtocol.Command, _ payload: [UInt8]) throws -> [UInt8] {
        try ColmiProtocol.makePacket(command, payload: payload)
    }

    static func entry(steps: Int) -> ActivityEntry {
        ActivityEntry(year: 2024, month: 11, day: 21, quarter: 33, steps: steps, distanceMeters: 0, caloriesRaw: 0)
    }

    // MARK: R1

    @Test func growingStepSlotKeepsItsIdentity() {
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: Self.date(Self.berlin, 2024, 11, 21, 10))
        let early = mapper.activity([Self.entry(steps: 100)])
        let later = mapper.activity([Self.entry(steps: 250)])
        #expect(early.first?.originalSampleID == later.first?.originalSampleID)
        #expect(early.first?.originalSampleID == "history-wc202411210815-i15-steps")
    }

    @Test func secondSyncUpdatesTheSlotInsteadOfAddingIt() throws {
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: Self.date(Self.berlin, 2024, 11, 21, 10))
        let now = Self.date(Self.berlin, 2024, 11, 21, 9)
        let first = SyncCoordinator.plan(batch: SyncBatch(observations: mapper.activity([Self.entry(steps: 100)])),
                                         existing: [:], profileID: nil, importedAt: now)
        let stored = try #require(first.inserts.first)
        let second = SyncCoordinator.plan(batch: SyncBatch(observations: mapper.activity([Self.entry(steps: 250)])),
                                          existing: [stored.deduplicationKey: stored], profileID: nil,
                                          importedAt: now.addingTimeInterval(600))
        #expect(second.inserts.isEmpty)
        #expect(second.updates.map(\.value) == [250])
        #expect(second.updates.first?.id == stored.id)
    }

    @Test func aGrowingNightIsOneSample() throws {
        let today = Self.date(Self.berlin, 2024, 11, 21, 10)
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: today)
        let short = SleepSession(daysAgo: 0, startMinute: 1_380, endMinute: 300, stages: [.init(rawType: 3, minutes: 300)])
        let long = SleepSession(daysAgo: 0, startMinute: 1_380, endMinute: 420, stages: [.init(rawType: 3, minutes: 420)])
        let a = try #require(mapper.sleep([short]).first)
        let b = try #require(mapper.sleep([long]).first)
        #expect(a.originalSampleID == b.originalSampleID)
        #expect(a.originalSampleID == "history-night20241121-sleep_duration")
    }

    // MARK: R6

    @Test func minutesAfterTheClockChangeStayWallClock() {
        // 2024-10-27: Berlin falls back at 03:00. 10:00 on the ring is 10:00 local, not 09:00.
        let today = Self.date(Self.berlin, 2024, 10, 27, 23)
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: today)
        var log = DayLogAccumulator(log: .stress)
        log.feed(try! Self.packet(.readStressLog, [0, 5]))
        var bytes = [UInt8](repeating: 0, count: 14)
        bytes[0] = 2
        log.feed(try! Self.packet(.readStressLog, [1, 0, 40]))
        // Packet 2 starts at minute (15 - 3) * 30 = 360 = 06:00; index 2 + 8 → 10:00.
        bytes[1 + 8] = 33
        log.feed(try! Self.packet(.readStressLog, bytes))
        let starts = mapper.dayLog(log, daysAgo: 0).map(\.start)
        #expect(starts.contains(Self.date(Self.berlin, 2024, 10, 27, 0)))
        #expect(starts.contains(Self.date(Self.berlin, 2024, 10, 27, 10)))
    }

    @Test func sleepOnTheSpringForwardNightKeepsWallClock() throws {
        // 2024-03-31: Berlin jumps from 02:00 to 03:00. Wake-up 07:00 stays 07:00.
        let today = Self.date(Self.berlin, 2024, 3, 31, 12)
        let session = SleepSession(daysAgo: 0, startMinute: 1_380, endMinute: 420, stages: [])
        let span = try #require(session.interval(today: today, calendar: Self.berlin))
        #expect(span.end == Self.date(Self.berlin, 2024, 3, 31, 7))
        #expect(span.start == Self.date(Self.berlin, 2024, 3, 30, 23))
        #expect(span.end.timeIntervalSince(span.start) == 7 * 3_600)
    }

    // MARK: R7

    @Test func timeZoneChangeKeepsTheSlotID() {
        let newYork = Self.calendar("America/New_York")
        let inBerlin = RawObservation.ringHistorySampleID(kind: .heartRate, slotStart: Self.date(Self.berlin, 2024, 11, 20, 8),
                                                          interval: 5, calendar: Self.berlin)
        let inNewYork = RawObservation.ringHistorySampleID(kind: .heartRate, slotStart: Self.date(newYork, 2024, 11, 20, 8),
                                                           interval: 5, calendar: newYork)
        #expect(inBerlin == inNewYork)
    }

    // MARK: R9

    @Test func dataBeforeTheHeaderIsALatePacket() throws {
        var log = DayLogAccumulator(log: .hrv)
        #expect(!log.feed(try Self.packet(.readHRVLog, [2, 35])))
        #expect(log.values.isEmpty)
        #expect(log.feed(try Self.packet(.readHRVLog, [0, 5])))
        #expect(log.feed(try Self.packet(.readHRVLog, [1, 0, 40])))
        #expect(log.values.count == 1)
    }

    @Test func heartRateFromAnotherDayIsRefused() throws {
        let berlin = Self.berlin
        let today = Self.date(berlin, 2024, 11, 21, 10)
        let yesterday = ColmiHistory.ringMidnight(of: today.addingTimeInterval(-86_400), calendar: berlin)
        let todayStart = ColmiHistory.ringMidnight(of: today, calendar: berlin)
        var log = DayLogAccumulator(log: .heartRate, expectedDayStart: yesterday)
        log.feed(try Self.packet(.readHeartRateLog, [0, 3]))
        func first(_ stamp: UInt32) -> [UInt8] {
            [1, UInt8(stamp & 0xFF), UInt8((stamp >> 8) & 0xFF), UInt8((stamp >> 16) & 0xFF), UInt8(stamp >> 24), 60]
        }
        #expect(!log.feed(try Self.packet(.readHeartRateLog, first(todayStart))))
        #expect(log.values.isEmpty)
        #expect(log.feed(try Self.packet(.readHeartRateLog, first(yesterday))))
        #expect(log.values.count == 1)
    }

    @Test func lateTodayPacketIsNotBookedToYesterday() throws {
        let today = Self.date(Self.berlin, 2024, 11, 21, 10)
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: today)
        var support = RingFeatureSupport(model: nil)
        support.markSilent(.steps)
        var sync = RingHistorySync(days: 2, support: support, hasBigDataChannel: false, mapper: mapper)
        _ = sync.start()
        #expect(sync.current == .heartRate(daysAgo: 0))
        _ = sync.handle(.history(.heartRate, try Self.packet(.readHeartRateLog, [0, 3])))
        _ = sync.timeout()                       // day 0 answered partly → day 1
        #expect(sync.current == .heartRate(daysAgo: 1))
        let todayStart = ColmiHistory.ringMidnight(of: today, calendar: Self.berlin)
        let late: [UInt8] = [1, UInt8(todayStart & 0xFF), UInt8((todayStart >> 8) & 0xFF),
                             UInt8((todayStart >> 16) & 0xFF), UInt8(todayStart >> 24), 70]
        _ = sync.handle(.history(.heartRate, try Self.packet(.readHeartRateLog, late)))
        #expect(sync.observations.isEmpty)
    }

    // MARK: Migration of stored rows

    static func legacy(_ value: Double, importedAt: Date, id: String) -> HealthSample {
        let start = date(berlin, 2024, 11, 21, 8, 15)
        return HealthSample(profileID: nil, kind: .steps, value: value, unit: .count, start: start,
                            end: start.addingTimeInterval(900), timeZoneIdentifier: "Europe/Berlin", source: .colmiRing,
                            deviceID: "ring-1", originalSampleID: id, importedAt: importedAt, quality: .valid,
                            method: .deviceHistory, identity: .derived)
    }

    @Test func migrationKeepsTheNewestCopyOfEachSlot() {
        let start = Self.date(Self.berlin, 2024, 11, 21, 8, 15)
        let millis = Int64(start.timeIntervalSince1970 * 1_000)
        let old = Self.legacy(100, importedAt: start.addingTimeInterval(600), id: "history-\(millis)-i15-steps-v100")
        let new = Self.legacy(250, importedAt: start.addingTimeInterval(1_800), id: "history-\(millis)-i15-steps-v250")
        let plan = RingHistoryIDMigration.plan(stored: [old, new], existingKeys: [], fallbackZone: TimeZone(identifier: "UTC")!)
        #expect(plan.rekeyed.map(\.id) == [new.id])
        #expect(plan.rekeyed.first?.originalSampleID == "history-wc202411210815-i15-steps")
        #expect(plan.rekeyed.first?.value == 250)
        #expect(plan.duplicates == [old.id])

        let again = RingHistoryIDMigration.plan(stored: plan.rekeyed, existingKeys: Set(plan.rekeyed.map(\.deduplicationKey)),
                                                fallbackZone: TimeZone(identifier: "UTC")!)
        #expect(again.isEmpty)
    }

    @Test func migrationLeavesLiveAndOtherRowsAlone() {
        let start = Self.date(Self.berlin, 2024, 11, 21, 8)
        let live = HealthSample(profileID: nil, kind: .heartRate, value: 60, unit: .beatsPerMinute, start: start,
                                timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-1",
                                originalSampleID: "live-1-heartRate-v60", importedAt: start, quality: .valid,
                                method: .liveSensor, identity: .derived)
        #expect(!RingHistoryIDMigration.isLegacy(live))
        #expect(RingHistoryIDMigration.plan(stored: [live], existingKeys: [], fallbackZone: .current).isEmpty)
    }
}
