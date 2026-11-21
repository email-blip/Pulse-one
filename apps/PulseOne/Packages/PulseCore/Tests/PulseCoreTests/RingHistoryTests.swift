import Foundation
import Testing
@testable import PulseCore

/// Byte layouts from Gadgetbridge `ColmiR0xDeviceSupport` / `ColmiR0xPacketHandler`.
@Suite("Ring settings and history")
struct RingHistoryTests {
    static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// 2024-11-21 10:00 in Berlin.
    static var today: Date {
        berlin.date(from: DateComponents(year: 2024, month: 11, day: 21, hour: 10))!
    }

    static func packet(_ command: ColmiProtocol.Command, _ payload: [UInt8]) throws -> [UInt8] {
        try ColmiProtocol.makePacket(command, payload: payload)
    }

    static var mapper: RingHistoryMapper { RingHistoryMapper(deviceID: "ring-1", calendar: berlin, today: today) }

    // MARK: Settings

    @Test func heartRateIntervalMatchesGadgetbridge() throws {
        #expect(ColmiProtocol.heartRateIntervalWrite(minutes: 5) == (try Self.packet(.heartRateLogSettings, [2, 1, 5])))
        #expect(ColmiProtocol.heartRateIntervalWrite(minutes: 7) == (try Self.packet(.heartRateLogSettings, [2, 1, 5])))
        #expect(ColmiProtocol.heartRateIntervalWrite(minutes: 90) == (try Self.packet(.heartRateLogSettings, [2, 1, 60])))
        #expect(ColmiProtocol.heartRateIntervalWrite(minutes: 0) == (try Self.packet(.heartRateLogSettings, [2, 2, 0])))
    }

    @Test func togglesAndReadsUseTheDocumentedCommands() throws {
        #expect(ColmiProtocol.toggleWrite(.spo2, enabled: true) == (try Self.packet(.autoSpO2Preference, [2, 1])))
        #expect(ColmiProtocol.toggleWrite(.stress, enabled: false) == (try Self.packet(.autoStressPreference, [2, 0])))
        #expect(ColmiProtocol.toggleWrite(.hrv, enabled: true)?[0] == 0x38)
        #expect(ColmiProtocol.preferenceRead(.heartRate) == (try Self.packet(.heartRateLogSettings, [1])))
        #expect(ColmiProtocol.toggleWrite(.skinTemperature, enabled: true) == nil)
        #expect(ColmiProtocol.toggleWrite(.steps, enabled: true) == nil)
    }

    @Test func decodesSettingAnswers() throws {
        #expect(ColmiProtocol.decode(try Self.packet(.heartRateLogSettings, [1, 1, 5]))
            == .setting(RingSettingReport(feature: .heartRate, enabled: true, intervalMinutes: 5)))
        #expect(ColmiProtocol.decode(try Self.packet(.heartRateLogSettings, [2])) == .settingWriteAck(.heartRateLogSettings))
        #expect(ColmiProtocol.decode(try Self.packet(.autoHRVPreference, [1, 1]))
            == .setting(RingSettingReport(feature: .hrv, enabled: true, intervalMinutes: nil)))
        #expect(ColmiProtocol.decode(try Self.packet(.autoSpO2Preference, [2, 0]))
            == .setting(RingSettingReport(feature: .spo2, enabled: false, intervalMinutes: nil)))
    }

    @Test func profilesFollowTheConcept() {
        let support = RingFeatureSupport(model: nil)
        let standard = RingMeasurementProfile.standard.packets(for: support)
        #expect(standard.first == ColmiProtocol.heartRateIntervalWrite(minutes: 5))
        #expect(standard.count == 4)
        #expect(standard.contains(ColmiProtocol.toggleWrite(.spo2, enabled: true)!))
        let minimal = RingMeasurementProfile.minimal.packets(for: support)
        #expect(minimal.first == ColmiProtocol.heartRateIntervalWrite(minutes: 30))
        #expect(minimal.contains(ColmiProtocol.toggleWrite(.hrv, enabled: false)!))
        #expect(RingMeasurementProfile.batterySaver.isEnabled(.hrv))
        #expect(!RingMeasurementProfile.batterySaver.isEnabled(.spo2))
        #expect(RingMeasurementProfile.standard.summary.contains("Puls alle 5 Minuten"))
    }

    @Test func profileSkipsFeaturesTheRingLacks() {
        var support = RingFeatureSupport(model: nil)
        support.markSilent(.spo2)
        let packets = RingMeasurementProfile.standard.packets(for: support)
        #expect(packets.count == 3)
        #expect(!packets.contains { $0[0] == 0x2C })
    }

    @Test func capabilitiesComeFromEvidenceNotModelNames() {
        let r03 = RingFeatureSupport(model: ColmiModel.detect(advertisedName: "R03_1A2B"))
        #expect(r03.state(of: .skinTemperature) == nil)
        #expect(!r03.visibleFeatures.contains(.skinTemperature))
        var r09 = RingFeatureSupport(model: ColmiModel.detect(advertisedName: "R09_1A2B"))
        #expect(r09.state(of: .skinTemperature) == .waitingForTest)
        #expect(!r09.mayUse(.skinTemperature))
        #expect(r09.visibleFeatures.contains(.skinTemperature))
        r09.markAnswered(.hrv)
        r09.markSilent(.hrv)
        #expect(r09.state(of: .hrv) == .answered)
        r09.markSilent(.stress)
        #expect(!r09.visibleFeatures.contains(.stress))
    }

    // MARK: Day logs

    @Test func heartRateLogRequestUsesLocalMidnightWallClock() {
        let packet = ColmiHistory.heartRateLogRequest(day: Self.today, calendar: Self.berlin)
        // 2024-11-21 00:00 as wall clock = 1732147200 = 0x67 3E 78 00
        #expect(Array(packet[0...4]) == [0x15, 0x00, 0x78, 0x3E, 0x67])
        #expect(ColmiProtocol.isValid(packet))
    }

    @Test func heartRateLogCollectsFiveMinuteValues() throws {
        var log = DayLogAccumulator(log: .heartRate)
        #expect(log.feed(try Self.packet(.readHeartRateLog, [0, 3])))
        var first: [UInt8] = [1, 0, 0, 0, 0, 60, 0, 62, 0, 0, 0, 0, 0, 0]
        first[13] = 70
        #expect(log.feed(try Self.packet(.readHeartRateLog, first)))
        #expect(!log.isComplete)
        log.feed(try Self.packet(.readHeartRateLog, [2, 58]))
        #expect(log.isComplete)
        #expect(log.values == [DayLogValue(minuteOfDay: 0, value: 60), DayLogValue(minuteOfDay: 10, value: 62),
                               DayLogValue(minuteOfDay: 40, value: 70), DayLogValue(minuteOfDay: 45, value: 58)])
    }

    @Test func emptyLogEndsAtOnce() throws {
        var log = DayLogAccumulator(log: .heartRate)
        log.feed(try Self.packet(.readHeartRateLog, [0xFF]))
        #expect(log.isComplete && log.isEmpty && log.values.isEmpty)
    }

    @Test func hrvLogUsesThirtyMinutesAndEndsWithPacketFour() throws {
        var log = DayLogAccumulator(log: .hrv)
        log.feed(try Self.packet(.readHRVLog, [0, 5]))
        log.feed(try Self.packet(.readHRVLog, [1, 0, 40, 41]))
        log.feed(try Self.packet(.readHRVLog, [2, 35]))
        #expect(log.values == [DayLogValue(minuteOfDay: 0, value: 40), DayLogValue(minuteOfDay: 30, value: 41),
                               DayLogValue(minuteOfDay: 360, value: 35)])
        log.feed(try Self.packet(.readHRVLog, [3]))
        #expect(!log.isComplete)
        log.feed(try Self.packet(.readHRVLog, [4]))
        #expect(log.isComplete)
    }

    @Test func mapperDropsFutureMinutesAndUsesStableIDs() throws {
        var log = DayLogAccumulator(log: .heartRate)
        log.feed(try Self.packet(.readHeartRateLog, [0, 2]))
        log.feed(try Self.packet(.readHeartRateLog, [1, 0, 0, 0, 0, 60, 0, 0, 0, 0, 0, 0, 0, 0]))
        var late = DayLogAccumulator(log: .heartRate)
        late.feed(try Self.packet(.readHeartRateLog, [0, 0x0F]))
        var bytes = [UInt8](repeating: 0, count: 14)
        bytes[0] = 13
        bytes[1] = 77   // minute 9*5 + 11*13*5 = 760 = 12:40, after "now" (10:00)
        late.feed(try Self.packet(.readHeartRateLog, bytes))
        let today = Self.mapper.dayLog(log, daysAgo: 0)
        #expect(today.count == 1)
        #expect(today.first?.method == .deviceHistory)
        #expect(today.first?.start == Self.berlin.startOfDay(for: Self.today))
        #expect(Self.mapper.dayLog(late, daysAgo: 0).isEmpty)
        #expect(Self.mapper.dayLog(late, daysAgo: 1).count == 1)
        #expect(Self.mapper.dayLog(log, daysAgo: 0) == today)
    }

    // MARK: Activity

    @Test func activityPacketDecodesBCDDateAndQuarter() throws {
        var activity = ActivityAccumulator()
        activity.feed(try Self.packet(.steps, [0xF0, 1]))
        // 2024-11-21, quarter 33 (08:15), packet 0 of 1, calories 25, steps 528, distance 100 m
        activity.feed(try Self.packet(.steps, [0x24, 0x11, 0x21, 33, 0, 1, 25, 0, 0x10, 0x02, 100, 0]))
        #expect(activity.isComplete)
        let entry = try #require(activity.entries.first)
        #expect(entry.steps == 528 && entry.distanceMeters == 100)
        #expect(entry.start(calendar: Self.berlin) == Self.berlin.date(from: DateComponents(year: 2024, month: 11, day: 21, hour: 8, minute: 15)))
        let raws = Self.mapper.activity(activity.entries)
        #expect(raws.map(\.kind) == [.steps, .distance])
        #expect(raws.first?.end?.timeIntervalSince(raws.first!.start) == 900)
    }

    @Test func activityStopsOnEmptyMarker() throws {
        var activity = ActivityAccumulator()
        activity.feed(try Self.packet(.steps, [0xFF]))
        #expect(activity.isComplete && activity.entries.isEmpty)
    }

    // MARK: Big data

    static func spo2Packet() -> [UInt8] {
        var body: [UInt8] = [1]
        body += [UInt8](repeating: 0, count: 48)
        body[1 + 2 * 22] = 95; body[2 + 2 * 22] = 98     // yesterday 22:00
        body.append(0)
        var today = [UInt8](repeating: 0, count: 48)
        today[2 * 3] = 96; today[2 * 3 + 1] = 99          // today 03:00
        body += today
        let length = body.count
        return [0xBC, 0x2A, UInt8(length & 0xFF), UInt8(length >> 8), 0, 0] + body
    }

    @Test func assemblerJoinsChunks() {
        let packet = Self.spo2Packet()
        var assembler = BigDataAssembler()
        #expect(assembler.feed(Array(packet[0..<40])) == nil)
        #expect(assembler.feed(Array(packet[40...])) == packet)
        #expect(assembler.feed([0x01, 0x02]) == nil)
    }

    @Test func spo2ParsesHoursOfSeveralDays() {
        let entries = ColmiHistory.parseSpO2(Self.spo2Packet())
        #expect(entries == [SpO2HourEntry(daysAgo: 1, hour: 22, minimum: 95, maximum: 98),
                            SpO2HourEntry(daysAgo: 0, hour: 3, minimum: 96, maximum: 99)])
        let raws = Self.mapper.spo2(entries)
        #expect(raws.map(\.value) == [97, 98])
        #expect(raws.first?.rawDataReference == "min 95 % · max 98 %")
    }

    @Test func sleepParsesSessionOverMidnight() throws {
        // one day: daysAgo 0, 8 day bytes, start 23:00 (1380), end 07:00 (420), deep 90 min, awake 10 min
        let body: [UInt8] = [1, 0, 8, 0x64, 0x05, 0xA4, 0x01, 3, 90, 5, 10]
        let packet: [UInt8] = [0xBC, 0x27, UInt8(body.count), 0, 0, 0] + body
        let sessions = ColmiHistory.parseSleep(packet)
        let session = try #require(sessions.first)
        #expect(session.asleepMinutes == 90)
        #expect(session.spanMinutes == 480)
        #expect(session.stageSummary == "tief 90 min · wach 10 min")
        let span = try #require(session.interval(today: Self.today, calendar: Self.berlin))
        #expect(span.end == Self.berlin.date(from: DateComponents(year: 2024, month: 11, day: 21, hour: 7)))
        #expect(span.start == Self.berlin.date(from: DateComponents(year: 2024, month: 11, day: 20, hour: 23)))
        #expect(Self.mapper.sleep(sessions).first?.value == 5_400)
    }

    @Test func malformedBigDataGivesNothing() {
        #expect(ColmiHistory.parseSleep([0xBC, 0x27, 1, 0, 0, 0]).isEmpty)
        #expect(ColmiHistory.parseSpO2([0xBC, 0x2A, 200, 0, 0, 0, 0, 90]).isEmpty)
    }

    // MARK: Sync order

    @Test func syncRunsStepsInOrderAndSkipsSilentFeatures() throws {
        var sync = RingHistorySync(days: 1, support: RingFeatureSupport(model: nil), hasBigDataChannel: false, mapper: Self.mapper)
        #expect(sync.support.state(of: .spo2) == .unsupported)
        let first = try #require(sync.start())
        #expect(first.step == .activity(daysAgo: 0))
        let second = try #require(sync.handle(.history(.activity, try Self.packet(.steps, [0xFF]))))
        #expect(second.step == .heartRate(daysAgo: 0))
        #expect(sync.handle(.history(.heartRate, try Self.packet(.readHeartRateLog, [0, 2]))) == nil)
        let third = try #require(sync.handle(.history(.heartRate, try Self.packet(.readHeartRateLog, [1, 0, 0, 0, 0, 61]))))
        #expect(third.step == .stress)
        let fourth = try #require(sync.timeout())
        #expect(fourth.step == .hrv(daysAgo: 0))
        #expect(sync.report.silent.contains(.stress))
        #expect(sync.handle(.history(.hrv, try Self.packet(.readHRVLog, [0xFF]))) == nil)
        #expect(sync.isFinished)
        #expect(sync.observations.count == 1)
        #expect(sync.support.state(of: .heartRate) == .answered)
        #expect(sync.report.summary.contains("Puls: 1"))
    }

    @Test func silentFeatureSkipsItsOtherDays() throws {
        var sync = RingHistorySync(days: 3, support: RingFeatureSupport(model: nil), hasBigDataChannel: true, mapper: Self.mapper)
        _ = sync.start()                       // activity 0
        _ = sync.timeout()                     // steps silent → heart rate 0
        #expect(sync.current == .heartRate(daysAgo: 0))
        #expect(sync.report.silent == [.steps])
    }

    @Test func bigDataStepsUseTheSecondChannel() throws {
        var support = RingFeatureSupport(model: nil)
        for feature in [RingFeature.steps, .heartRate, .stress, .hrv] { support.markSilent(feature) }
        var sync = RingHistorySync(days: 1, support: support, hasBigDataChannel: true, mapper: Self.mapper)
        let first = try #require(sync.start())
        #expect(first.channel == .bigData && first.packet == ColmiHistory.bigDataRequest(.spo2))
        let next = try #require(sync.handleBigData(Self.spo2Packet()))
        #expect(next.step == .sleep)
        #expect(sync.observations.count == 2)
    }

    @Test func scheduleFetchesSinceLastSync() {
        let schedule = RingSyncSchedule()
        let now = Self.today
        #expect(schedule.isDue(lastSync: nil, now: now))
        #expect(!schedule.isDue(lastSync: now.addingTimeInterval(-3_600), now: now))
        #expect(schedule.isDue(lastSync: now.addingTimeInterval(-7 * 3_600), now: now))
        #expect(schedule.days(lastSync: nil, now: now, calendar: Self.berlin) == 7)
        #expect(schedule.days(lastSync: now.addingTimeInterval(-3_600), now: now, calendar: Self.berlin) == 2)
        #expect(schedule.days(lastSync: now.addingTimeInterval(-30 * 86_400), now: now, calendar: Self.berlin) == 7)
    }
}
