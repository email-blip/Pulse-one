import Foundation

/// A ring seen during scanning.
public struct DiscoveredRing: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let model: ColmiModel?

    public init(id: UUID, name: String, rssi: Int, model: ColmiModel?) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.model = model
    }

    /// Signal strength in plain words.
    public var signalLabel: String {
        switch rssi {
        case (-60)...: "sehr nah"
        case (-75)..<(-60): "in der Nähe"
        default: "weit entfernt"
        }
    }
}

/// Everything the connect screen shows, as one value. Produced by the Bluetooth layer.
public struct RingSnapshot: Equatable, Sendable {
    public var bluetooth: BluetoothAvailability = .unknown
    public var connection: ConnectionState = .idle
    public var discovered: [DiscoveredRing] = []
    public var deviceName: String?
    public var deviceIdentifier: String?
    public var model: ColmiModel?
    public var firmware: String?
    public var battery: ColmiProtocol.Battery?
    /// Phase of the current or last live measurement, shown separately from the connection.
    public var measurement: MeasurementPhase = .idle
    /// Newest valid live value of the running measurement (nil when no measurement delivers values).
    public var liveHeartRate: Int?
    public var lastHeartRate: VitalReading?
    public var capabilities = CapabilityTracker()
    public var unknownPackets: [String] = []
    public var lastError: String?
    /// Name of the ring connected last time, for one-tap reconnect.
    public var rememberedRing: String?

    public init() {}

    /// Keeps the list sorted by signal and free of duplicates.
    public mutating func upsert(_ ring: DiscoveredRing) {
        discovered.removeAll { $0.id == ring.id }
        discovered.append(ring)
        discovered.sort { $0.rssi > $1.rssi }
    }

    public var firmwareNote: String? {
        guard let firmware else { return nil }
        return TestedFirmware.isTested(firmware) ? "Firmware \(firmware) · getestet" : "Firmware \(firmware) · noch nicht getestet"
    }

    public mutating func logUnknown(_ hex: String) {
        if unknownPackets.count < 50 { unknownPackets.append(hex) }
    }
}
