import Foundation
import Testing
@testable import PulseCore

@Suite("Colmi packets")
struct ColmiProtocolTests {
    @Test func batteryRequestMatchesReference() {
        // Reference from colmi_r02_client: battery request = 03 00 … 00 03
        let packet = ColmiProtocol.batteryRequest()
        #expect(packet.count == 16)
        #expect(packet[0] == 3)
        #expect(packet[15] == 3)
        #expect(ColmiProtocol.isValid(packet))
    }

    @Test func payloadTooLongThrows() {
        #expect(throws: ColmiProtocol.PacketError.payloadTooLong) {
            try ColmiProtocol.makePacket(.battery, payload: [UInt8](repeating: 1, count: 15))
        }
    }

    @Test func checksumWrapsAround() throws {
        let packet = try ColmiProtocol.makePacket(.battery, payload: [UInt8](repeating: 0xFF, count: 14))
        #expect(packet[15] == UInt8((3 + 14 * 255) & 0xFF))
        #expect(ColmiProtocol.isValid(packet))
    }

    @Test func invalidPacketsAreRejected() {
        var packet = ColmiProtocol.batteryRequest()
        packet[15] &+= 1
        #expect(!ColmiProtocol.isValid(packet))
        #expect(!ColmiProtocol.isValid([3, 0, 0]))
    }

    @Test func setTimeUsesLocalWallClockAndBCD() throws {
        // 2026-11-20 15:32:53 UTC = 16:32:53 in Berlin (CET)
        let date = Date(timeIntervalSince1970: 1_795_188_773)
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let packet = try ColmiProtocol.setTimeRequest(date, timeZone: berlin)
        #expect(Array(packet[0...7]) == [1, 0x26, 0x11, 0x20, 0x16, 0x32, 0x53, 1])
        #expect(ColmiProtocol.isValid(packet))
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(try ColmiProtocol.setTimeRequest(date, timeZone: utc)[4] == 0x15)
    }

    @Test func statusPushCarriesBattery() throws {
        let packet = try ColmiProtocol.makePacket(.statusPush, payload: [0x0C, 87, 1])
        #expect(ColmiProtocol.decode(packet) == .battery(.init(level: 87, charging: true)))
        let other = try ColmiProtocol.makePacket(.statusPush, payload: [0x12])
        #expect(ColmiProtocol.decode(other) == .unknown(hex: ColmiProtocol.hex(other)))
    }

    @Test func statusPushAnnouncesNewData() {
        // Seen on the R03 (firmware 3.00.28) about a minute after connecting, 2026-11-23.
        let packet: [UInt8] = [0x73, 0x01] + Array(repeating: 0, count: 13) + [0x74]
        #expect(ColmiProtocol.decode(packet) == .newData(0x01))
    }

    @Test func setTimeRejectsDatesBefore2000() {
        #expect(throws: ColmiProtocol.PacketError.invalidDate) {
            try ColmiProtocol.setTimeRequest(Date(timeIntervalSince1970: 0))
        }
    }

    @Test func realTimeRequests() {
        #expect(Array(ColmiProtocol.realTimeStart(.heartRate)[0...2]) == [105, 1, 1])
        #expect(Array(ColmiProtocol.realTimeContinue(.heartRate)[0...2]) == [105, 1, 3])
        #expect(Array(ColmiProtocol.realTimeStop(.heartRate)[0...3]) == [106, 1, 0, 0])
    }

    /// Byte for byte as in the references: colmi_r02_client (variant A) and Gadgetbridge (variant B).
    @Test func heartRateStartVariants() {
        let a = ColmiProtocol.HeartRateStartMode.realTime.startPacket
        let b = ColmiProtocol.HeartRateStartMode.manual.startPacket
        #expect(ColmiProtocol.hex(a) == "6901010000000000000000000000006b")
        #expect(ColmiProtocol.hex(b) == "6901000000000000000000000000006a")
        #expect(ColmiProtocol.HeartRateStartMode.realTime.sendsStop)
        #expect(ColmiProtocol.HeartRateStartMode.manual.sendsStop == false)
    }

    @Test func heartRateLogRequestIsLittleEndianSeconds() {
        let packet = ColmiProtocol.heartRateLogRequest(dayStart: Date(timeIntervalSince1970: 0x0102_0304))
        #expect(Array(packet[0...4]) == [21, 0x04, 0x03, 0x02, 0x01])
    }

    @Test func decodesBattery() throws {
        let packet = try ColmiProtocol.makePacket(.battery, payload: [64, 1])
        #expect(ColmiProtocol.decode(packet) == .battery(.init(level: 64, charging: true)))
    }

    @Test func decodesRealTimeValueAndError() throws {
        let ok = try ColmiProtocol.makePacket(.realTimeStart, payload: [1, 0, 72])
        #expect(ColmiProtocol.decode(ok) == .realTime(.value(type: 1, value: 72)))
        let error = try ColmiProtocol.makePacket(.realTimeStart, payload: [1, 2, 0])
        #expect(ColmiProtocol.decode(error) == .realTime(.error(type: 1, code: 2)))
    }

    /// Seen on the R03 (2026-11-21): stop acknowledgement and packet-size announcement.
    @Test func decodesStopAckAndPacketSize() {
        let stop: [UInt8] = [0x6a, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x6b]
        #expect(ColmiProtocol.decode(stop) == .realTimeStopAck)
        let size: [UInt8] = [0x2f, 0xf4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x23]
        #expect(ColmiProtocol.decode(size) == .packetSize(244))
    }

    @Test func unknownCommandsStayVisible() {
        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = 0x7F
        packet[15] = ColmiProtocol.checksum(packet)
        #expect(ColmiProtocol.decode(packet) == .unknown(hex: ColmiProtocol.hex(packet)))
        #expect(ColmiProtocol.decode([1, 2]) == .unknown(hex: "0102"))
    }
}

@Suite("Heart rate log")
struct HeartRateLogParserTests {
    private func packet(_ bytes: [UInt8]) -> [UInt8] {
        var p = bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
        p[15] = ColmiProtocol.checksum(p)
        return p
    }

    @Test func noDataMarker() {
        var parser = HeartRateLogParser()
        #expect(parser.parse(packet([21, 255])) == .noData)
    }

    @Test func assemblesSlotsAndDropsEmptyOnes() {
        var parser = HeartRateLogParser()
        let day: UInt32 = 1_795_132_800 // 2026-11-20 00:00 UTC
        #expect(parser.parse(packet([21, 0, 3, 5])) == .pending)
        let ts = [UInt8(day & 0xFF), UInt8((day >> 8) & 0xFF), UInt8((day >> 16) & 0xFF), UInt8(day >> 24)]
        #expect(parser.parse(packet([21, 1] + ts + [60, 0, 62, 0, 0, 0, 0, 0, 0])) == .pending)
        let result = parser.parse(packet([21, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 70]))
        let start = Date(timeIntervalSince1970: TimeInterval(day))
        #expect(result == .done([
            .init(start: start, bpm: 60),
            .init(start: start.addingTimeInterval(600), bpm: 62),
            .init(start: start.addingTimeInterval(21 * 300), bpm: 70)
        ]))
    }

    @Test func strayPacketWithoutHeaderIsIgnored() {
        var parser = HeartRateLogParser()
        #expect(parser.parse(packet([21, 2, 80])) == .pending)
    }
}
