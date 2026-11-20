import Foundation

/// A bounded log of the Bluetooth conversation with the ring, for diagnosis on the real device
/// (directive 4.0 §3). Records every packet sent and received, the discovered services and
/// characteristics, and connection events. The export never contains the CoreBluetooth
/// identifier or the ring's serial suffix; it does contain the measured values of the session,
/// which the user sees before sharing.
public struct BLETrace: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case sent = "TX"
        case received = "RX"
        case event = "--"
    }

    public struct Entry: Equatable, Sendable {
        public let time: Date
        public let direction: Direction
        /// Short characteristic or service name, e.g. "6E400003".
        public let channel: String
        public let text: String

        public init(time: Date, direction: Direction, channel: String, text: String) {
            self.time = time
            self.direction = direction
            self.channel = channel
            self.text = text
        }
    }

    public static let capacity = 1500

    public private(set) var entries: [Entry] = []
    /// Entries dropped because the log was full (oldest first).
    public private(set) var dropped = 0

    public init() {}

    public mutating func add(_ direction: Direction, channel: String = "", _ text: String, at time: Date = .now) {
        entries.append(Entry(time: time, direction: direction, channel: Self.shortUUID(channel), text: text))
        if entries.count > Self.capacity {
            entries.removeFirst()
            dropped += 1
        }
    }

    public mutating func clear() {
        entries = []
        dropped = 0
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" → "6E400003"; 16-bit UUIDs stay as they are.
    public static func shortUUID(_ uuid: String) -> String {
        uuid.split(separator: "-").first.map(String.init) ?? uuid
    }

    /// "R03_9903" → "R03_xxxx": keeps the model, hides the per-ring suffix.
    public static func redactedName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "unbekannt" }
        guard let separator = name.lastIndex(where: { $0 == "_" || $0 == " " }) else { return name }
        return String(name[...separator]) + "xxxx"
    }

    /// Removes anything that looks like a UUID (CoreBluetooth identifiers) from free text.
    public static func redactIdentifiers(_ text: String) -> String {
        text.replacingOccurrences(
            of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            with: "<id>", options: .regularExpression)
    }

    /// Plain-text report for sharing. Times are seconds relative to the first entry plus one
    /// absolute UTC start time, so the timezone and wall clock of the user are not needed.
    public func report(appVersion: String, systemVersion: String, deviceName: String?, firmware: String?) -> String {
        var lines = [
            "PULSE ONE · Bluetooth-Diagnose",
            "Format 1 · App \(appVersion) · iOS \(systemVersion)",
            "Ring: \(Self.redactedName(deviceName)) · Firmware: \(firmware ?? "unbekannt")",
            "Hinweis: enthält die Rohdaten dieser Sitzung (auch Pulswerte), keine Geräte-ID.",
        ]
        if let first = entries.first?.time {
            lines.append("Start (UTC): \(first.ISO8601Format()) · Einträge: \(entries.count) · verworfen: \(dropped)")
            lines.append("")
            lines.append("t[s]      Richtung Kanal     Inhalt")
            for entry in entries {
                let t = String(format: "%8.3f", entry.time.timeIntervalSince(first))
                let channel = entry.channel.padding(toLength: 10, withPad: " ", startingAt: 0)
                lines.append("\(t)  \(entry.direction.rawValue)       \(channel) \(Self.redactIdentifiers(entry.text))")
            }
        } else {
            lines.append("Keine Einträge.")
        }
        return lines.joined(separator: "\n")
    }
}
