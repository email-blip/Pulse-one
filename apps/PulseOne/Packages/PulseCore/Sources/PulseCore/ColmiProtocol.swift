import Foundation

/// Colmi/Yawell ring protocol (R02/R03 family). Pure functions, no Bluetooth.
///
/// Source: tahnok/colmi_r02_client (MIT, Wesley Ellis) – packet.py, battery.py, set_time.py,
/// hr.py, real_time.py. Verified there against an R02. For the R03 it stays unconfirmed
/// until a real ring answered (see docs/colmi-protokoll.md).
///
/// Every packet is 16 bytes: `[command, 14 bytes payload, checksum]`,
/// checksum = sum of bytes 0...14 & 0xFF. The ring clock runs in local wall-clock time
/// (Gadgetbridge, anikbharadwaj129/Colmi, reuhenbhalod/DayBreak, stansz/smart-ring; see
/// docs/pulse-one-coordination/OPEN-SOURCE-REVIEW.md §2.2).
public enum ColmiProtocol {
    public static let uartService = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
    /// Phone → ring (write without response).
    public static let uartWrite = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    /// Ring → phone (notify).
    public static let uartNotify = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let deviceInfoService = "180A"
    public static let firmwareRevision = "2A26"
    public static let hardwareRevision = "2A27"

    public static let packetLength = 16

    public enum Command: UInt8, Sendable {
        case setTime = 1
        case battery = 3
        case readHeartRateLog = 21
        case heartRateLogSettings = 22
        case steps = 67
        case realTimeStart = 105
        case realTimeStop = 106
        /// Unsolicited status from the ring; subtype 0x0C carries battery (anikbharadwaj129/Colmi, unverified on the R03).
        case statusPush = 115
    }

    /// Reading types for real-time measurements.
    public enum RealTimeType: UInt8, Sendable {
        case heartRate = 1
        case spo2 = 3
        case hrv = 10
    }

    static let actionStart: UInt8 = 1
    static let actionContinue: UInt8 = 3

    public enum PacketError: Error, Equatable {
        case payloadTooLong
        case invalidDate
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt8 {
        var sum = 0
        for byte in bytes.prefix(packetLength - 1) { sum += Int(byte) }
        return UInt8(sum & 0xFF)
    }

    public static func makePacket(_ command: Command, payload: [UInt8] = []) throws -> [UInt8] {
        guard payload.count <= 14 else { throw PacketError.payloadTooLong }
        var packet = [UInt8](repeating: 0, count: packetLength)
        packet[0] = command.rawValue
        for (index, byte) in payload.enumerated() { packet[index + 1] = byte }
        packet[15] = checksum(packet)
        return packet
    }

    /// True for a 16-byte packet with a valid checksum.
    public static func isValid(_ packet: [UInt8]) -> Bool {
        packet.count == packetLength && checksum(packet) == packet[15]
    }

    public static func hex(_ packet: [UInt8]) -> String {
        packet.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Requests

    public static func batteryRequest() -> [UInt8] {
        // Payload is empty, so makePacket cannot throw.
        (try? makePacket(.battery)) ?? []
    }

    /// Sets the ring clock to the local wall-clock time of `date`. Language byte 1 = English.
    public static func setTimeRequest(_ date: Date, timeZone: TimeZone = .current) throws -> [UInt8] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = c.year, year >= 2000, year < 2100,
              let month = c.month, let day = c.day,
              let hour = c.hour, let minute = c.minute, let second = c.second
        else { throw PacketError.invalidDate }
        return try makePacket(.setTime, payload: [
            bcd(year - 2000), bcd(month), bcd(day), bcd(hour), bcd(minute), bcd(second), 1
        ])
    }

    /// Requests the 5-minute heart rate log of the UTC day starting at `dayStart`.
    public static func heartRateLogRequest(dayStart: Date) -> [UInt8] {
        let s = UInt32(max(0, dayStart.timeIntervalSince1970))
        let payload: [UInt8] = [UInt8(s & 0xFF), UInt8((s >> 8) & 0xFF), UInt8((s >> 16) & 0xFF), UInt8((s >> 24) & 0xFF)]
        return (try? makePacket(.readHeartRateLog, payload: payload)) ?? []
    }

    public static func realTimeStart(_ type: RealTimeType) -> [UInt8] {
        (try? makePacket(.realTimeStart, payload: [type.rawValue, actionStart])) ?? []
    }

    /// Single heart-rate measurement as Gadgetbridge sends it (`ColmiR0xDeviceSupport.onHeartRateTest`):
    /// command 0x69 with payload [0x01] only, no action byte, no continue and no stop.
    public static func manualHeartRateStart() -> [UInt8] {
        (try? makePacket(.realTimeStart, payload: [RealTimeType.heartRate.rawValue])) ?? []
    }

    /// How a heart-rate measurement is started. Both variants are taken byte for byte from a
    /// reference implementation; which one the R03 needs is checked on the real ring.
    public enum HeartRateStartMode: String, Sendable, CaseIterable {
        /// colmi_r02_client `real_time.py`: start 69 01 01, stop 6A 01 00 00.
        case realTime
        /// Gadgetbridge `onHeartRateTest`: 69 01, nothing else.
        case manual

        public var startPacket: [UInt8] {
            switch self {
            case .realTime: ColmiProtocol.realTimeStart(.heartRate)
            case .manual: ColmiProtocol.manualHeartRateStart()
            }
        }

        /// Only colmi_r02_client sends a stop command after the measurement.
        public var sendsStop: Bool { self == .realTime }

        public var traceLabel: String {
            switch self {
            case .realTime: "Variante A, Echtzeit 69 01 01"
            case .manual: "Variante B, Einzelmessung 69 01"
            }
        }
    }

    /// Defined in colmi_r02_client but sent by neither reference client; kept for tests only.
    public static func realTimeContinue(_ type: RealTimeType) -> [UInt8] {
        (try? makePacket(.realTimeStart, payload: [type.rawValue, actionContinue])) ?? []
    }

    public static func realTimeStop(_ type: RealTimeType) -> [UInt8] {
        (try? makePacket(.realTimeStop, payload: [type.rawValue, 0, 0])) ?? []
    }

    // MARK: Responses

    public struct Battery: Equatable, Sendable {
        public let level: Int
        public let charging: Bool

        public init(level: Int, charging: Bool) {
            self.level = level
            self.charging = charging
        }
    }

    public enum RealTimeReading: Equatable, Sendable {
        case value(type: UInt8, value: Int)
        case error(type: UInt8, code: Int)
    }

    /// A decoded notification from the ring. Anything not understood stays `.unknown`
    /// with its hex dump, so firmware changes are visible instead of crashing.
    public enum Response: Equatable, Sendable {
        case battery(Battery)
        case realTime(RealTimeReading)
        case setTimeAck
        case heartRateLog([UInt8])
        case unknown(hex: String)
    }

    public static func decode(_ packet: [UInt8]) -> Response {
        guard isValid(packet), let command = Command(rawValue: packet[0]) else {
            return .unknown(hex: hex(packet))
        }
        switch command {
        case .battery:
            return .battery(Battery(level: Int(packet[1]), charging: packet[2] != 0))
        case .realTimeStart:
            return packet[2] != 0
                ? .realTime(.error(type: packet[1], code: Int(packet[2])))
                : .realTime(.value(type: packet[1], value: Int(packet[3])))
        case .setTime:
            return .setTimeAck
        case .readHeartRateLog:
            return .heartRateLog(packet)
        case .statusPush where packet[1] == 0x0C:
            return .battery(Battery(level: Int(packet[2]), charging: packet[3] == 1))
        case .heartRateLogSettings, .steps, .realTimeStop, .statusPush:
            return .unknown(hex: hex(packet))
        }
    }

    static func bcd(_ value: Int) -> UInt8 {
        UInt8(((value / 10) << 4) | (value % 10))
    }
}
