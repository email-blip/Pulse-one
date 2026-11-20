import Foundation

/// Why a live measurement ended without a usable value.
public enum MeasurementFailure: Equatable, Sendable {
    /// The ring never answered the start command.
    case noResponse
    /// The ring answered, but only with "no value yet" (0) until the time limit.
    case noValidValue
    /// The ring reported an error code in its answer.
    case ringError(code: Int)

    public var message: String {
        switch self {
        case .noResponse:
            "Der Ring hat auf den Messbefehl nicht geantwortet."
        case .noValidValue:
            "Der Ring hat geantwortet, aber keinen gültigen Puls geliefert. Ring enger anlegen, Hand ruhig halten und erneut messen."
        case .ringError(let code):
            "Der Ring meldet einen Messfehler (Code \(code)). Ring enger anlegen und erneut messen."
        }
    }
}

/// The visible phases of one live measurement (directive 4.0 §3). "Läuft" is shown only after
/// the ring itself answered; a value is shown only after the ring sent one.
public enum MeasurementPhase: Equatable, Sendable {
    case idle
    /// Start command sent, no answer from the ring yet.
    case requested(at: Date)
    /// The ring answered and is measuring, but has no valid value yet.
    case running(since: Date)
    /// The ring delivers valid values; `value` is the newest one.
    case receiving(value: Int, at: Date, since: Date)
    /// Ended normally after at least one valid value.
    case finished(value: Int, at: Date)
    case failed(MeasurementFailure, at: Date)
    /// The Bluetooth connection dropped while measuring.
    case connectionLost(at: Date)

    public var isActive: Bool {
        switch self {
        case .requested, .running, .receiving: true
        default: false
        }
    }

    public var title: String {
        switch self {
        case .idle: "Keine Messung"
        case .requested: "Messung angefordert"
        case .running: "Messung läuft"
        case .receiving: "Messwert empfangen"
        case .finished: "Messung beendet"
        case .failed: "Messung fehlgeschlagen"
        case .connectionLost: "Verbindung verloren"
        }
    }

    public var detail: String {
        switch self {
        case .idle: "Tippe auf „Puls jetzt messen“."
        case .requested: "Befehl gesendet. Warte auf die Antwort des Rings …"
        case .running: "Der Ring misst. Der Sensor sucht noch deinen Puls. Hand ruhig halten."
        case .receiving: "Der Ring liefert Werte. Die Messung endet nach einer Minute von selbst."
        case .finished: "Letzter gültiger Wert vom Ring."
        case .failed(let failure, _): failure.message
        case .connectionLost: "Die Bluetooth-Verbindung ist während der Messung abgebrochen."
        }
    }

    /// The newest valid value, if the ring sent one in this measurement.
    public var value: (bpm: Int, at: Date)? {
        switch self {
        case .receiving(let value, let at, _), .finished(let value, let at): (value, at)
        default: nil
        }
    }
}

/// Pure state machine for one live heart-rate measurement. No Bluetooth, no clock:
/// the caller feeds events with timestamps, which keeps every transition testable.
public struct LiveMeasurement: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case start(Date)
        /// A real-time answer from the ring; value 0 means "measuring, no value yet".
        case ringValue(Int, Date)
        case ringError(code: Int, Date)
        case tick(Date)
        case stop(Date)
        case disconnected(Date)
    }

    /// Seconds to wait for any answer to the start command.
    public let responseTimeout: TimeInterval
    /// Seconds after the first answer to wait for a valid value.
    public let valueTimeout: TimeInterval
    /// Total length of a measurement, to protect the ring battery.
    public let maxDuration: TimeInterval

    public private(set) var phase: MeasurementPhase = .idle
    private var startedAt: Date?

    public init(responseTimeout: TimeInterval = 10, valueTimeout: TimeInterval = 30, maxDuration: TimeInterval = 60) {
        self.responseTimeout = responseTimeout
        self.valueTimeout = valueTimeout
        self.maxDuration = maxDuration
    }

    /// Plausible human heart rate; anything outside is not shown as a measurement.
    public static let plausibleRange = 25...230

    public mutating func handle(_ event: Event) {
        switch (event, phase) {
        case (.start(let now), _):
            startedAt = now
            phase = .requested(at: now)

        case (.ringValue(let value, let now), .requested), (.ringValue(let value, let now), .running):
            let since = runningSince ?? now
            if Self.plausibleRange.contains(value) {
                phase = .receiving(value: value, at: now, since: since)
            } else {
                phase = .running(since: since)
            }
        case (.ringValue(let value, let now), .receiving(_, _, let since)):
            if Self.plausibleRange.contains(value) { phase = .receiving(value: value, at: now, since: since) }

        case (.ringError(let code, let now), _) where phase.isActive:
            phase = .failed(.ringError(code: code), at: now)

        case (.tick(let now), .requested(let at)):
            if now.timeIntervalSince(at) >= responseTimeout { phase = .failed(.noResponse, at: now) }
        case (.tick(let now), .running(let since)):
            if now.timeIntervalSince(since) >= valueTimeout { phase = .failed(.noValidValue, at: now) }
        case (.tick(let now), .receiving(let value, let at, _)):
            if let startedAt, now.timeIntervalSince(startedAt) >= maxDuration { phase = .finished(value: value, at: at) }

        case (.stop, .receiving(let value, let at, _)):
            phase = .finished(value: value, at: at)
        case (.stop, .requested), (.stop, .running):
            phase = .idle

        case (.disconnected(let now), _) where phase.isActive:
            phase = .connectionLost(at: now)

        default:
            break
        }
    }

    private var runningSince: Date? {
        if case .running(let since) = phase { return since }
        return nil
    }
}
