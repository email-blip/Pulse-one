import Foundation

/// Collects the multi-packet 5-minute heart rate log of one UTC day.
///
/// Packet 0: `[21, 0, packetCount, rangeMin]`; packet 1: `[21, 1, ts(4, LE, UTC s), 9 values]`;
/// packets 2..n-1: `[21, k, 13 values]`. Sub type 255 = no data for that day.
/// Slots with value 0 (no measurement) are dropped.
public struct HeartRateLogParser: Sendable {
    public struct Slot: Equatable, Sendable {
        public let start: Date
        public let bpm: Int
    }

    public enum Result: Equatable, Sendable {
        case pending
        case done([Slot])
        case noData
    }

    public static let slotsPerDay = 288
    public static let slotSeconds: TimeInterval = 300

    private var size = 0
    private var dayStart: Date?
    private var raw: [UInt8] = []

    public init() {}

    public mutating func parse(_ p: [UInt8]) -> Result {
        guard p.count == ColmiProtocol.packetLength else { return .pending }
        let sub = Int(p[1])
        if sub == 255 { reset(); return .noData }
        if sub == 0 {
            reset()
            size = Int(p[2])
            raw = [UInt8](repeating: 0, count: max(size * 13, Self.slotsPerDay))
            if size <= 1 { reset(); return .noData }
            return .pending
        }
        guard size > 0 else { return .pending }  // stray packet without header
        if sub == 1 {
            let s = UInt32(p[2]) | UInt32(p[3]) << 8 | UInt32(p[4]) << 16 | UInt32(p[5]) << 24
            dayStart = Date(timeIntervalSince1970: TimeInterval(s))
            for i in 0..<9 { raw[i] = p[6 + i] }
        } else {
            let offset = 9 + (sub - 2) * 13
            for i in 0..<13 where offset + i < raw.count { raw[offset + i] = p[2 + i] }
        }
        guard sub == size - 1 else { return .pending }
        defer { reset() }
        guard let dayStart else { return .noData }
        let slots = raw.prefix(Self.slotsPerDay).enumerated().compactMap { index, bpm -> Slot? in
            bpm > 0 ? Slot(start: dayStart.addingTimeInterval(Double(index) * Self.slotSeconds), bpm: Int(bpm)) : nil
        }
        return .done(slots)
    }

    private mutating func reset() {
        size = 0
        dayStart = nil
        raw = []
    }
}
