import Foundation

/// Bluetooth radio availability as reported by the system.
public enum BluetoothAvailability: Equatable, Sendable {
    case unknown, ready, poweredOff, unauthorized, unsupported

    public var label: String {
        switch self {
        case .unknown: "Bluetooth wird geprüft"
        case .ready: "Bluetooth bereit"
        case .poweredOff: "Bluetooth ist ausgeschaltet"
        case .unauthorized: "Bluetooth-Zugriff nicht erlaubt"
        case .unsupported: "Dieses Gerät unterstützt kein Bluetooth LE"
        }
    }
}

/// The ring connection as the user sees it. Every state has a plain German label,
/// so the screen always says what is happening (directive §10.5, §15.6).
public enum ConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting(name: String)
    case discovering
    case ready
    case measuring
    case reconnecting(attempt: Int)
    case disconnected
    case failed(message: String)

    public var label: String {
        switch self {
        case .idle: "Nicht verbunden"
        case .scanning: "Suche nach Ringen …"
        case .connecting(let name): "Verbinde mit \(name) …"
        case .discovering: "Prüfe Ring-Dienste …"
        case .ready: "Verbunden"
        case .measuring: "Verbunden · misst Puls"
        case .reconnecting(let attempt): "Verbindung verloren · neuer Versuch \(attempt)"
        case .disconnected: "Getrennt"
        case .failed(let message): message
        }
    }

    public var isConnected: Bool {
        switch self {
        case .ready, .measuring: true
        default: false
        }
    }

    public var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .discovering, .reconnecting: true
        default: false
        }
    }
}

/// When to retry after an unexpected disconnect. User-initiated disconnects never retry.
public struct ReconnectPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int = 5, baseDelay: TimeInterval = 2, maxDelay: TimeInterval = 30) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Delay before attempt `attempt` (1-based), or nil when the policy gives up.
    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= maxAttempts else { return nil }
        return min(maxDelay, baseDelay * pow(2, Double(attempt - 1)))
    }
}
