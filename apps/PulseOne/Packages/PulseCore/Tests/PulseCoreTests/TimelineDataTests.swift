import Foundation
import Testing
@testable import PulseCore

/// Team 01, M1: sleep segments with real times, track queries, received time, scenarios.
@Suite("Sleep segments and timeline queries")
struct TimelineDataTests {
    static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func bytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return result
    }

    /// The `BC 27` answer of Johannes' R03 (firmware RY03_3.00.28_250401), 2026-11-23 09:55 Berlin.
    static let realSleepPacket = bytes(
        "bc277d00c6420302227700c4010210040f032202" + "17031a04120310040e021f041a032e0210040b05" +
        "0a021f01321b0073020214040c0322040e031504" + "0e021e0315022303350418023a0316021a030705" +
        "0402270412033505030234031e020a00222f008f" + "01020c04100502041203150224030c0226032302" +
        "1a0321041d022b031b0204")

    // MARK: Real ring night

    @Test func realR03NightBecomesSegmentsWithRealTimes() throws {
        let now = Self.date(2026, 11, 23, 10)
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: now)
        let sessions = ColmiHistory.parseSleep(Self.realSleepPacket)
        #expect(sessions.count == 3)
        let segments = mapper.sleepSegments(sessions, firmware: "RY03_3.00.28_250401")
        #expect(segments.count == 15 + 23 + 15)
        let nights = SleepSegmentSync.nights(segments)
        #expect(nights.count == 3)
        let last = try #require(nights.last)
        // 00:47 to 06:39: the stage minutes add up exactly to the session (352 min), without gaps.
        #expect(last.inBed == DateInterval(start: Self.date(2026, 11, 23, 0, 47), end: Self.date(2026, 11, 23, 6, 39)))
        #expect(last.gaps.isEmpty)
        #expect(last.segments.first?.phase == .light)
        #expect(last.segments.first?.end == Self.date(2026, 11, 23, 0, 59))
        #expect(last.segments[1].phase == .rem)
        #expect(last.segments[2].phase == .awake)
        #expect(last.duration(of: .awake) == 2 * 60)
        #expect(last.asleep == 350 * 60)
        #expect(last.segments.allSatisfy { $0.firmware == "RY03_3.00.28_250401" && $0.source == .colmiRing })
        // REM is reported by this firmware and kept.
        #expect(segments.contains { $0.phase == .rem })
    }

    @Test func nightThatStartsBeforeMidnightBelongsToTheWakeDay() throws {
        let now = Self.date(2026, 11, 23, 8)
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: now)
        let packet = TimelineScenarios.sleepPacket([(daysAgo: 0, start: 23 * 60, end: 60, stages: [(2, 90), (3, 30)])])
        let segments = mapper.sleepSegments(ColmiHistory.parseSleep(packet))
        #expect(segments.first?.start == Self.date(2026, 11, 22, 23))
        #expect(segments.last?.end == Self.date(2026, 11, 23, 1))
        #expect(Set(segments.map(\.sessionID)) == [mapper.sleepSessionID(nightEnding: Self.date(2026, 11, 23, 1))])
    }

    @Test func unknownCodeStaysUnknownWithItsRawCode() {
        let data = TimelineScenarios.make(.unknownPhaseCode, calendar: Self.berlin)
        let unknown = data.segments.filter { $0.phase == .unknown }
        #expect(unknown.count == 1)
        #expect(unknown.first?.rawCode == 7)
        let night = SleepNight(sessionID: data.segments[0].sessionID, segments: data.segments)
        #expect(night.asleep == Double(460 - 10 - 5) * 60)
    }

    @Test func segmentIDsAreStableAcrossSyncs() {
        let now = Self.date(2026, 11, 23, 10)
        let a = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: now)
            .sleepSegments(ColmiHistory.parseSleep(Self.realSleepPacket))
        let b = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: now.addingTimeInterval(1_800))
            .sleepSegments(ColmiHistory.parseSleep(Self.realSleepPacket))
        #expect(a.map(\.id) == b.map(\.id))
        let other = RingHistoryMapper(deviceID: "ring-2", calendar: Self.berlin, today: now)
            .sleepSegments(ColmiHistory.parseSleep(Self.realSleepPacket))
        #expect(Set(a.map(\.sessionID)).isDisjoint(with: Set(other.map(\.sessionID))))
    }

    @Test func historySyncCollectsSegments() {
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: Self.date(2026, 11, 23, 10))
        var sync = RingHistorySync(days: 1, support: RingFeatureSupport(model: nil), hasBigDataChannel: true, mapper: mapper)
        var request = sync.start()
        while let step = request?.step, step != .sleep { request = sync.timeout() }
        _ = sync.handleBigData(Array(Self.realSleepPacket.prefix(40)))
        _ = sync.handleBigData(Array(Self.realSleepPacket.dropFirst(40)))
        #expect(sync.sleepSegments.count == 53)
        #expect(sync.observations.filter { $0.kind == .sleepDuration }.count == 3)
    }

    // MARK: Sync plan

    @Test func repeatedSyncChangesNothingAndAGrowingNightReplacesTheOld() {
        let data = TimelineScenarios.make(.fullNight, calendar: Self.berlin)
        let again = SleepSegmentSync.plan(incoming: data.segments, existing: data.segments)
        #expect(again.isEmpty)
        #expect(again.unchangedSessions == 1)
        let shorter = Array(data.segments.dropLast(2))
        let grown = SleepSegmentSync.plan(incoming: data.segments, existing: shorter)
        #expect(grown.replacedSessions == [data.segments[0].sessionID])
        #expect(grown.inserts.count == data.segments.count)
        let first = SleepSegmentSync.plan(incoming: data.segments + data.segments, existing: [])
        #expect(first.inserts.count == data.segments.count)
    }

    @Test func duplicateSyncScenarioStoresEverythingOnce() {
        let once = TimelineScenarios.make(.fullNight, calendar: Self.berlin)
        let twice = TimelineScenarios.make(.duplicateSync, calendar: Self.berlin)
        #expect(twice.points.count == once.points.count)
        #expect(twice.segments.count == once.segments.count)
        #expect(Set(twice.points.map(\.id)).count == twice.points.count)
    }

    // MARK: Queries

    @Test func shortWindowsKeepOriginalPointsLongWindowsAggregate() throws {
        let data = TimelineScenarios.make(.fullNight, calendar: Self.berlin)
        let day = DateInterval(start: data.now.addingTimeInterval(-24 * 3600), end: data.now)
        let original = TimelineQuery.series(for: .heartRate, in: day, from: data.points, now: data.now, calendar: Self.berlin)
        let pulse = try #require(original.first)
        #expect(pulse.resolution == .original)
        #expect(pulse.points.count == 24 * 12 + 1)
        let week = DateInterval(start: data.now.addingTimeInterval(-7 * 86_400), end: data.now)
        let hourly = try #require(TimelineQuery.series(for: .heartRate, in: week, from: data.points, now: data.now, calendar: Self.berlin).first)
        #expect(hourly.resolution == .hourly)
        #expect(hourly.isAggregated)
        #expect(hourly.buckets.allSatisfy { $0.count >= 1 && $0.minimum <= $0.mean && $0.mean <= $0.maximum })
        let month = DateInterval(start: data.now.addingTimeInterval(-30 * 86_400), end: data.now)
        #expect(TimelineQuery.resolution(for: month) == .daily)
    }

    @Test func stepsAggregateAsSumsAndHRVKeepsMethodsApart() throws {
        let data = TimelineScenarios.make(.fullNight, calendar: Self.berlin)
        let week = DateInterval(start: data.now.addingTimeInterval(-7 * 86_400), end: data.now)
        let steps = try #require(TimelineQuery.series(for: .movement, in: week, from: data.points, now: data.now, calendar: Self.berlin)
            .first { $0.kind == .steps })
        let bucket = try #require(steps.buckets.first)
        #expect(bucket.representative == bucket.sum)
        let hrv = TimelineQuery.series(for: .hrv, in: week, from: data.points, now: data.now, calendar: Self.berlin)
        #expect(hrv.map(\.kind) == [.ringHRV])
    }

    @Test func gapsStayGaps() throws {
        let data = TimelineScenarios.make(.nightWithGap, calendar: Self.berlin)
        let night = try #require(TimelineQuery.nights(in: DateInterval(start: data.now.addingTimeInterval(-12 * 3600), end: data.now),
                                                     from: data.segments).first)
        #expect(night.gaps == [DateInterval(start: Self.date(2026, 11, 23, 1, 40), end: Self.date(2026, 11, 23, 2, 50))])
        let window = DateInterval(start: Self.date(2026, 11, 23, 0), end: Self.date(2026, 11, 23, 6))
        let holes = TimelineQuery.gaps(in: data.points, kind: .heartRate, window: window, maximumGap: 15 * 60)
        #expect(holes.count == 1)
        #expect(holes.first.map { $0.duration >= 70 * 60 } == true)
        // The 02:00 bucket only holds the two real points after the hole (02:50, 02:55); nothing is filled in.
        let buckets = TimelineQuery.buckets(data.points.filter { $0.kind == .heartRate }, kind: .heartRate,
                                            resolution: .hourly, calendar: Self.berlin)
        #expect(buckets.first { $0.interval.start == Self.date(2026, 11, 23, 2) }?.count == 2)
    }

    @Test func latestValueComesWithItsOwnTime() throws {
        let data = TimelineScenarios.make(.staleValue, calendar: Self.berlin)
        let latest = try #require(TimelineQuery.latest(.heartRate, in: data.points, now: data.now))
        #expect(data.now.timeIntervalSince(latest.measuredAt) >= 18 * 3600)
        #expect(TimelineQuery.latest(.oxygenSaturation, in: data.points, now: data.now) == nil)
    }

    @Test func batterySaverHasSparserPulseAndNoSpO2() {
        let full = TimelineScenarios.make(.fullNight, calendar: Self.berlin)
        let saver = TimelineScenarios.make(.batterySaverProfile, calendar: Self.berlin)
        let count = { (data: TimelineScenarioData, kind: SampleKind) in data.points.filter { $0.kind == kind }.count }
        #expect(count(saver, .heartRate) * 3 <= count(full, .heartRate) + 3)
        #expect(count(saver, .oxygenSaturation) == 0)
        #expect(count(saver, .ringStress) == 0)
    }

    @Test func irregularSpacingKeepsEveryOriginalTime() throws {
        let data = TimelineScenarios.make(.irregularSpacing, calendar: Self.berlin)
        let day = DateInterval(start: data.now.addingTimeInterval(-24 * 3600), end: data.now)
        let pulse = try #require(TimelineQuery.series(for: .heartRate, in: day, from: data.points, now: data.now, calendar: Self.berlin).first)
        let distances = Set(zip(pulse.points, pulse.points.dropFirst()).map { Int($1.measuredAt.timeIntervalSince($0.measuredAt) / 60) })
        #expect(distances.count > 3)
        let cursor = pulse.points[10].measuredAt.addingTimeInterval(30)
        #expect(TimelineState.nearest(to: cursor, in: pulse.points, tolerance: 60) == pulse.points[10])
    }

    @Test func daylightSavingNightKeepsRealDurations() throws {
        let data = TimelineScenarios.make(.daylightSavingNight, calendar: Self.berlin)
        let night = try #require(SleepSegmentSync.nights(data.segments).first)
        let bed = try #require(night.inBed)
        #expect(bed.start == Self.date(2026, 3, 28, 23, 30))
        #expect(bed.end == Self.date(2026, 3, 29, 7))
        #expect(bed.duration == 390 * 60)
        #expect(night.gaps.isEmpty)
        // Hourly buckets follow the local clock: there is no bucket starting at 02:00 that night.
        let buckets = TimelineQuery.buckets(data.points.filter { $0.kind == .heartRate }, kind: .heartRate,
                                            resolution: .hourly, calendar: Self.berlin)
        #expect(buckets.contains { $0.interval.start == Self.date(2026, 3, 29, 3) })
        #expect(Set(buckets.map(\.interval.start)).count == buckets.count)
    }

    // MARK: Received time

    @Test func receivedTimeIsKeptAndSurvivesARepeatedSync() throws {
        let received = Self.date(2026, 11, 23, 9)
        let raw = RawObservation(kind: .heartRate, value: 60, unit: .beatsPerMinute, start: received.addingTimeInterval(-600),
                                 timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-1",
                                 originalSampleID: "a", method: .deviceHistory, receivedAt: received)
        let first = SyncCoordinator.plan(batch: SyncBatch(observations: [raw]), existing: [:], profiles: .constant(nil),
                                         importedAt: received.addingTimeInterval(5))
        let stored = try #require(first.inserts.first)
        #expect(stored.receivedAt == received)
        #expect(MeasurementPoint(stored, receivedAt: stored.receivedAt).receivedAt == received)
        var changed = raw
        changed.value = 61
        changed.receivedAt = received.addingTimeInterval(3_600)
        let second = SyncCoordinator.plan(batch: SyncBatch(observations: [changed]), existing: [stored.deduplicationKey: stored],
                                          profiles: .constant(nil), importedAt: received.addingTimeInterval(3_605))
        #expect(second.updates.first?.receivedAt == received)
        let mapper = RingHistoryMapper(deviceID: "ring-1", calendar: Self.berlin, today: received)
        #expect(mapper.observation(.heartRate, 60, start: received.addingTimeInterval(-300), end: nil, interval: 5).receivedAt == received)
    }

    @Test func everyScenarioIsMarkedAsTestData() {
        for scenario in TimelineScenario.allCases {
            let data = TimelineScenarios.make(scenario, calendar: Self.berlin)
            #expect(!data.points.isEmpty, "\(scenario)")
            #expect(!data.segments.isEmpty, "\(scenario)")
            #expect(data.points.allSatisfy { $0.deviceID == TimelineScenarios.deviceID }, "\(scenario)")
            #expect(data.segments.allSatisfy { $0.deviceID == TimelineScenarios.deviceID }, "\(scenario)")
        }
    }

    @Test func uiTestNightFillsTheRequestedWindow() throws {
        let now = TimelineScenarios.defaultNow(calendar: Self.berlin)
        let segments = TimelineScenarios.sleepNight(startMinute: 22 * 60 + 40, endMinute: 6 * 60 + 55, now: now,
                                                    calendar: Self.berlin, unknownCode: true)
        let night = try #require(SleepSegmentSync.nights(segments).first)
        let bed = try #require(night.inBed)
        #expect(bed.duration == 495 * 60)
        #expect(Self.berlin.component(.hour, from: bed.start) == 22 && Self.berlin.component(.minute, from: bed.start) == 40)
        #expect(Self.berlin.component(.hour, from: bed.end) == 6 && Self.berlin.component(.minute, from: bed.end) == 55)
        #expect(segments.contains { $0.phase == .unknown && $0.rawCode == 7 })
        #expect(zip(segments, segments.dropFirst()).allSatisfy { $0.end == $1.start })
    }

    @Test func stableIDsAreDeterministic() {
        #expect(StableID.uuid("a") == StableID.uuid("a"))
        #expect(StableID.uuid("a") != StableID.uuid("b"))
    }
}
