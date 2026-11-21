import Foundation

/// Reading the history a Colmi ring stores on its own. Pure functions, no Bluetooth.
///
/// Every request and parser follows Gadgetbridge byte for byte (`ColmiR0xDeviceSupport`,
/// `ColmiR0xPacketHandler`, GPL-3.0; only the documented byte layout is reused, the code is our
/// own). Steps also match colmi_r02_client `steps.py` (MIT). Unconfirmed on the R03/R09 until a
/// real ring answered (docs/colmi-protokoll.md).
///
/// The ring clock runs in local wall-clock time, so a day is a local calendar day.
public enum ColmiHistory {
    /// Logs on the UART channel.
    public enum Log: String, Equatable, Sendable {
        case heartRate
        case stress
        case hrv
        case activity
    }

    // MARK: Requests (UART, 16 bytes with checksum)

    /// `15 <uint32 LE>`: the ring's wall-clock seconds of the local midnight of `day`
    /// (Gadgetbridge adds the zone offset to the epoch; colmi_r02_client sends midnight too).
    public static func heartRateLogRequest(day: Date, calendar: Calendar) -> [UInt8] {
        (try? ColmiProtocol.makePacket(.readHeartRateLog, payload: littleEndian(ringMidnight(of: day, calendar: calendar)))) ?? []
    }

    /// Local midnight of `day` as ring wall-clock seconds (epoch plus zone offset).
    public static func ringMidnight(of day: Date, calendar: Calendar) -> UInt32 {
        let midnight = calendar.startOfDay(for: day)
        let offset = calendar.timeZone.secondsFromGMT(for: midnight)
        return UInt32(clamping: max(0, Int(midnight.timeIntervalSince1970) + offset))
    }

    /// `37`: stress values of today.
    public static func stressLogRequest() -> [UInt8] {
        (try? ColmiProtocol.makePacket(.readStressLog)) ?? []
    }

    /// `39 <uint32 LE daysAgo>`.
    public static func hrvLogRequest(daysAgo: Int) -> [UInt8] {
        (try? ColmiProtocol.makePacket(.readHRVLog, payload: littleEndian(UInt32(clamping: max(0, daysAgo))))) ?? []
    }

    /// `43 <daysAgo> 0f 00 5f 01`.
    public static func activityRequest(daysAgo: Int) -> [UInt8] {
        (try? ColmiProtocol.makePacket(.steps, payload: [UInt8(clamping: max(0, daysAgo)), 0x0F, 0x00, 0x5F, 0x01])) ?? []
    }

    // MARK: Big data (second service, no padding, no checksum)

    public static let bigDataService = "DE5BF728-D711-4E47-AF26-65E3012A5DC7"
    public static let bigDataNotify = "DE5BF729-D711-4E47-AF26-65E3012A5DC7"
    public static let bigDataWrite = "DE5BF72A-D711-4E47-AF26-65E3012A5DC7"
    static let bigDataCommand: UInt8 = 0xBC

    public enum BigDataType: UInt8, Sendable {
        case sleep = 0x27
        case spo2 = 0x2A
    }

    /// `bc <type> 01 00 ff 00 ff`.
    public static func bigDataRequest(_ type: BigDataType) -> [UInt8] {
        [bigDataCommand, type.rawValue, 0x01, 0x00, 0xFF, 0x00, 0xFF]
    }

    static func littleEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    static func uint16(_ bytes: [UInt8], _ index: Int) -> Int {
        guard index + 1 < bytes.count else { return 0 }
        return Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
    }
}

// MARK: - Day logs (heart rate, stress, HRV)

/// A value at a minute of the day.
public struct DayLogValue: Equatable, Sendable {
    public let minuteOfDay: Int
    public let value: Int
}

/// Collects the packets of one day log. Layout (Gadgetbridge):
/// packet 0 = header (byte 2 = number of packets), 0xFF = no data,
/// packet 1 carries values from `firstOffset`, later packets from byte 2, up to byte 14.
public struct DayLogAccumulator: Equatable, Sendable {
    public let log: ColmiHistory.Log
    public private(set) var values: [DayLogValue] = []
    public private(set) var isComplete = false
    public private(set) var isEmpty = false
    private var totalPackets: Int?
    private var sawHeader = false
    /// Heart rate only: ring wall-clock midnight of the requested day. Packet 1 carries the day's
    /// timestamp; a packet from another day is a late answer to an earlier request and is refused.
    private let expectedDayStart: UInt32?

    public init(log: ColmiHistory.Log, expectedDayStart: UInt32? = nil) {
        self.log = log
        self.expectedDayStart = expectedDayStart
    }

    var interval: Int { log == .heartRate ? 5 : 30 }
    /// Heart rate packet 1 holds a timestamp in bytes 2–5.
    var firstOffset: Int { log == .heartRate ? 6 : 3 }
    /// Stress and HRV logs end with packet 4 (Gadgetbridge).
    var fixedLastPacket: Int? { log == .heartRate ? nil : 4 }

    /// Feeds one packet. Returns false when the packet does not belong to this log.
    @discardableResult
    public mutating func feed(_ packet: [UInt8]) -> Bool {
        guard ColmiProtocol.isValid(packet), !isComplete else { return false }
        let number = Int(packet[1])
        if number == 0xFF {
            isEmpty = true
            isComplete = true
            return true
        }
        if number == 0 {
            sawHeader = true
            totalPackets = Int(packet[2])
            if totalPackets == 0 || totalPackets == 1 { isEmpty = true; isComplete = true }
            return true
        }
        // Every log starts with packet 0. Data packets before it are late packets of an earlier
        // request (after a timeout) and would otherwise be booked to this day.
        guard sawHeader else { return false }
        if number == 1, log == .heartRate, let expectedDayStart {
            let stamp = UInt32(packet[2]) | UInt32(packet[3]) << 8 | UInt32(packet[4]) << 16 | UInt32(packet[5]) << 24
            if stamp != 0, stamp / 86_400 != expectedDayStart / 86_400 { return false }
        }
        let start = number == 1 ? firstOffset : 2
        let earlier = number == 1 ? 0 : (15 - firstOffset) * interval + (number - 2) * 13 * interval
        for index in start..<15 where packet[index] != 0 {
            let minute = earlier + (index - start) * interval
            guard minute < 24 * 60 else { continue }
            values.append(DayLogValue(minuteOfDay: minute, value: Int(packet[index])))
        }
        if let totalPackets, number >= totalPackets - 1 { isComplete = true }
        if let fixedLastPacket, number >= fixedLastPacket { isComplete = true }
        return true
    }
}

// MARK: - Activity (steps per 15 minutes)

public struct ActivityEntry: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    /// Quarter hour of the day, 0...95.
    public let quarter: Int
    public let steps: Int
    public let distanceMeters: Int
    /// Raw value; the scale differs between firmware versions, so it is not stored yet.
    public let caloriesRaw: Int

    public init(year: Int, month: Int, day: Int, quarter: Int, steps: Int, distanceMeters: Int, caloriesRaw: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.quarter = quarter
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.caloriesRaw = caloriesRaw
    }

    public func start(calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: quarter / 4, minute: (quarter % 4) * 15))
    }
}

/// Packets of `43`: 0xFF = no data, 0xF0 = header, otherwise one quarter hour per packet:
/// bytes 1–3 date as BCD (yy mm dd), 4 quarter, 5 index, 6 count, 7–8 calories, 9–10 steps, 11–12 distance.
public struct ActivityAccumulator: Equatable, Sendable {
    public private(set) var entries: [ActivityEntry] = []
    public private(set) var isComplete = false

    public init() {}

    @discardableResult
    public mutating func feed(_ packet: [UInt8]) -> Bool {
        guard ColmiProtocol.isValid(packet), !isComplete else { return false }
        switch packet[1] {
        case 0xFF:
            isComplete = true
        case 0xF0:
            break
        default:
            if let year = Self.bcd(packet[1]), let month = Self.bcd(packet[2]), let day = Self.bcd(packet[3]),
               (1...12).contains(month), (1...31).contains(day), packet[4] < 96 {
                entries.append(ActivityEntry(year: 2000 + year, month: month, day: day, quarter: Int(packet[4]),
                                             steps: ColmiHistory.uint16(packet, 9),
                                             distanceMeters: ColmiHistory.uint16(packet, 11),
                                             caloriesRaw: ColmiHistory.uint16(packet, 7)))
            }
            if Int(packet[5]) >= Int(packet[6]) - 1 { isComplete = true }
        }
        return true
    }

    static func bcd(_ byte: UInt8) -> Int? {
        let high = Int(byte >> 4), low = Int(byte & 0x0F)
        guard high < 10, low < 10 else { return nil }
        return high * 10 + low
    }
}

// MARK: - Big data (SpO₂, sleep)

/// Joins notifications of the big-data channel until `length + 6` bytes arrived.
public struct BigDataAssembler: Equatable, Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    /// Returns a complete packet, or nil while more bytes are expected.
    public mutating func feed(_ chunk: [UInt8]) -> [UInt8]? {
        if buffer.isEmpty, chunk.first != ColmiHistory.bigDataCommand { return nil }
        buffer += chunk
        guard buffer.count >= 4 else { return nil }
        let needed = ColmiHistory.uint16(buffer, 2) + 6
        guard buffer.count >= needed else { return nil }
        let packet = buffer
        buffer = []
        return packet
    }

    public mutating func reset() { buffer = [] }
}

public struct SpO2HourEntry: Equatable, Sendable {
    public let daysAgo: Int
    public let hour: Int
    public let minimum: Int
    public let maximum: Int
}

public enum SleepStage: Int, Sendable {
    case light = 2
    case deep = 3
    case rem = 4
    case awake = 5

    public var title: String {
        switch self {
        case .light: "leicht"
        case .deep: "tief"
        case .rem: "REM"
        case .awake: "wach"
        }
    }
}

public struct SleepSession: Equatable, Sendable {
    public let daysAgo: Int
    /// Minutes after midnight; a start larger than the end lies on the evening before.
    public let startMinute: Int
    public let endMinute: Int
    public let stages: [Stage]

    public struct Stage: Equatable, Sendable {
        public let rawType: Int
        public let minutes: Int
        public var stage: SleepStage? { SleepStage(rawValue: rawType) }
    }

    /// Asleep minutes: all stages except awake; without stages the whole span.
    public var asleepMinutes: Int {
        guard !stages.isEmpty else { return spanMinutes }
        return stages.filter { $0.stage != .awake }.reduce(0) { $0 + $1.minutes }
    }

    public var spanMinutes: Int {
        startMinute > endMinute ? endMinute + 1_440 - startMinute : endMinute - startMinute
    }

    /// Start and end as dates, relative to `today` in the ring's local calendar.
    public func interval(today: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: today)),
              let startDay = startMinute > endMinute ? calendar.date(byAdding: .day, value: -1, to: day) : Optional(day),
              let end = RingHistoryMapper.wallClock(day, minuteOfDay: endMinute, calendar: calendar),
              let start = RingHistoryMapper.wallClock(startDay, minuteOfDay: startMinute, calendar: calendar)
        else { return nil }
        return (start, end)
    }

    public var stageSummary: String {
        var minutes: [SleepStage: Int] = [:]
        for stage in stages { if let kind = stage.stage { minutes[kind, default: 0] += stage.minutes } }
        return [SleepStage.deep, .light, .rem, .awake].compactMap { kind in
            minutes[kind].map { "\(kind.title) \($0) min" }
        }.joined(separator: " · ")
    }
}

extension ColmiHistory {
    /// SpO₂ big data: from byte 6, per day one `daysAgo` byte and 24 × (min, max).
    public static func parseSpO2(_ packet: [UInt8]) -> [SpO2HourEntry] {
        guard packet.count >= 6, packet[0] == bigDataCommand, packet[1] == BigDataType.spo2.rawValue else { return [] }
        let end = min(packet.count, uint16(packet, 2) + 6)
        var entries: [SpO2HourEntry] = []
        var index = 6
        while index < end {
            let daysAgo = Int(packet[index])
            index += 1
            for hour in 0..<24 {
                guard index + 1 < end else { return entries }
                let low = Int(packet[index]), high = Int(packet[index + 1])
                index += 2
                if low > 0, high > 0 { entries.append(SpO2HourEntry(daysAgo: daysAgo, hour: hour, minimum: low, maximum: high)) }
            }
            if daysAgo == 0 { break }
        }
        return entries
    }

    /// Sleep big data: byte 6 = number of days; per day `daysAgo`, `dayBytes`, start (uint16),
    /// end (uint16), then (`dayBytes` − 4) / 2 stages of (type, minutes).
    public static func parseSleep(_ packet: [UInt8]) -> [SleepSession] {
        guard packet.count >= 7, packet[0] == bigDataCommand, packet[1] == BigDataType.sleep.rawValue,
              uint16(packet, 2) >= 2 else { return [] }
        let end = min(packet.count, uint16(packet, 2) + 6)
        var sessions: [SleepSession] = []
        var index = 7
        for _ in 0..<Int(packet[6]) {
            guard index + 5 < end else { break }
            let daysAgo = Int(packet[index])
            let dayBytes = Int(packet[index + 1])
            let start = uint16(packet, index + 2)
            let stop = uint16(packet, index + 4)
            index += 6
            var stages: [SleepSession.Stage] = []
            var consumed = 4
            while consumed < dayBytes, index + 1 < end {
                let minutes = Int(packet[index + 1])
                if minutes > 0 { stages.append(SleepSession.Stage(rawType: Int(packet[index]), minutes: minutes)) }
                index += 2
                consumed += 2
            }
            guard start < 1_440, stop < 1_440 else { continue }
            sessions.append(SleepSession(daysAgo: daysAgo, startMinute: start, endMinute: stop, stages: stages))
        }
        return sessions
    }
}

// MARK: - Into the common store

/// Turns parsed history into `RawObservation`s with stable derived ids, so a repeated sync
/// never stores a value twice (same rule as live values, `RawObservation.ringSampleID`).
public struct RingHistoryMapper: Sendable {
    public let deviceID: String
    public let calendar: Calendar
    public let today: Date

    public init(deviceID: String, calendar: Calendar, today: Date) {
        self.deviceID = deviceID
        self.calendar = calendar
        self.today = today
    }

    var zone: String { calendar.timeZone.identifier }

    public func dayLog(_ accumulator: DayLogAccumulator, daysAgo: Int) -> [RawObservation] {
        let kind: SampleKind
        switch accumulator.log {
        case .heartRate: kind = .heartRate
        case .hrv: kind = .ringHRV
        case .stress: kind = .ringStress
        case .activity: return []
        }
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: today)) else { return [] }
        return accumulator.values.compactMap { entry in
            guard let start = RingHistoryMapper.wallClock(day, minuteOfDay: entry.minuteOfDay, calendar: calendar),
                  start <= today else { return nil }
            return observation(kind, Double(entry.value), start: start, end: nil, interval: accumulator.interval)
        }
    }

    public func activity(_ entries: [ActivityEntry]) -> [RawObservation] {
        entries.flatMap { entry -> [RawObservation] in
            guard let start = entry.start(calendar: calendar), let end = calendar.date(byAdding: .minute, value: 15, to: start) else { return [] }
            var result: [RawObservation] = []
            if entry.steps > 0 { result.append(observation(.steps, Double(entry.steps), start: start, end: end, interval: 15)) }
            if entry.distanceMeters > 0 {
                result.append(observation(.distance, Double(entry.distanceMeters), start: start, end: end, interval: 15))
            }
            return result
        }
    }

    /// One value per hour: the midpoint of the ring's minimum and maximum (as Gadgetbridge stores it);
    /// the range is kept in `rawDataReference`.
    public func spo2(_ entries: [SpO2HourEntry]) -> [RawObservation] {
        entries.compactMap { entry in
            guard let day = calendar.date(byAdding: .day, value: -entry.daysAgo, to: calendar.startOfDay(for: today)),
                  let start = RingHistoryMapper.wallClock(day, minuteOfDay: entry.hour * 60, calendar: calendar),
                  let end = calendar.date(byAdding: .hour, value: 1, to: start), start <= today else { return nil }
            let mid = (Double(entry.minimum + entry.maximum) / 2).rounded()
            var raw = observation(.oxygenSaturation, mid, start: start, end: end, interval: 60)
            raw.rawDataReference = "min \(entry.minimum) % · max \(entry.maximum) %"
            return raw
        }
    }

    public func sleep(_ sessions: [SleepSession]) -> [RawObservation] {
        sessions.compactMap { session in
            guard session.asleepMinutes > 0, let span = session.interval(today: today, calendar: calendar) else { return nil }
            var raw = observation(.sleepDuration, Double(session.asleepMinutes * 60), start: span.start, end: span.end,
                                  interval: session.spanMinutes)
            // One sleep session per night on the ring: the night (wake day) is the identity, so a night that
            // grows between two syncs replaces the earlier version instead of being stored twice.
            raw.originalSampleID = RawObservation.ringHistorySampleID(kind: .sleepDuration, nightEnding: span.end,
                                                                      calendar: calendar)
            raw.rawDataReference = session.stageSummary.isEmpty ? nil : session.stageSummary
            return raw
        }
    }

    func observation(_ kind: SampleKind, _ value: Double, start: Date, end: Date?, interval: Int) -> RawObservation {
        RawObservation(kind: kind, value: value, unit: kind.canonicalUnit, start: start, end: end,
                       timeZoneIdentifier: zone, source: .colmiRing, deviceID: deviceID,
                       originalSampleID: RawObservation.ringHistorySampleID(kind: kind, slotStart: start, interval: interval,
                                                                            calendar: calendar),
                       method: .deviceHistory, identity: .derived)
    }

    /// Ring wall-clock time `minuteOfDay` on `day`, built from date components so a daylight-saving day
    /// does not shift the later hours (adding elapsed minutes to midnight would).
    static func wallClock(_ day: Date, minuteOfDay: Int, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = minuteOfDay / 60
        parts.minute = minuteOfDay % 60
        return calendar.date(from: parts)
    }
}
