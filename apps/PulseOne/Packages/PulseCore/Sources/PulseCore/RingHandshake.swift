import Foundation

/// Why connecting to a ring stopped before it was ready to measure.
public enum HandshakeFailure: Equatable, Sendable {
    /// The ring did not accept the connection in time (out of range, or connected to the QRing app).
    case connectTimeout
    /// Connected, but service discovery, characteristic discovery or the notify subscription never finished.
    case handshakeTimeout
    case serviceDiscoveryFailed(String)
    /// The device has no Colmi UART service.
    case noUARTService
    case characteristicDiscoveryFailed(String)
    /// UART service without the write characteristic (6E400002): commands could not be sent.
    case missingWrite
    /// UART service without the notify characteristic (6E400003): answers could not be received.
    case missingNotify
    /// The ring refused or dropped the notify subscription.
    case notifyRejected(String)
    /// The previous link was not confirmed as released in time, so no new connect was sent.
    case releaseTimeout

    public var message: String {
        switch self {
        case .connectTimeout:
            "Der Ring antwortet nicht. Ist er in der Nähe und nicht gerade mit der QRing-App verbunden?"
        case .handshakeTimeout:
            "Verbunden, aber der Ring hat die Einrichtung nicht abgeschlossen. Bitte trennen und neu verbinden."
        case .serviceDiscoveryFailed(let reason):
            "Die Dienste des Rings konnten nicht gelesen werden (\(reason))."
        case .noUARTService:
            "Dieses Gerät bietet den Colmi-Datendienst nicht an. Ist es wirklich ein Colmi-Ring?"
        case .characteristicDiscoveryFailed(let reason):
            "Die Datenkanäle des Rings konnten nicht gelesen werden (\(reason))."
        case .missingWrite:
            "Der Ring bietet keinen Kanal für Befehle an. Bitte trennen und neu verbinden."
        case .missingNotify:
            "Der Ring bietet keinen Kanal für Antworten an. Bitte trennen und neu verbinden."
        case .notifyRejected(let reason):
            "Der Ring sendet keine Daten (\(reason)). Bitte trennen und neu verbinden."
        case .releaseTimeout:
            "Die alte Verbindung zum Ring ist noch nicht beendet. Bitte gleich noch einmal tippen oder Bluetooth kurz aus- und einschalten."
        }
    }
}

/// Pure state machine for the lifecycle of one ring connection (Codex review P1-003 F3, R2-3, R3-1).
///
/// "Ready" requires the whole chain: connected → UART service → write and notify characteristics →
/// notify switched on. Every waiting step has a time limit.
///
/// Link release is tracked separately from the step. `cancelPeripheralConnection` does not block and
/// open operations may still finish (Apple documentation), so after a cancel the old link counts as
/// released only on evidence: the disconnect callback for that peripheral (`disconnected`), or the
/// driver observing `CBPeripheral.state == .disconnected` or Bluetooth switching off (`released`).
/// While a release is pending no connect is sent. A connect requested meanwhile waits up to
/// `cancelAckTimeout`; without evidence by then it is aborted with `releaseTimeout` (never sent
/// blindly), and the user's next tap retries the cancel. A `didConnect` nobody asked for is rejected.
/// CoreBluetooth gives no session id; the driver additionally checks characteristic object identity.
public struct RingHandshake: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case idle
        case connecting(since: Date)
        /// Automatic reconnect: CoreBluetooth keeps the request open until the ring is back, no limit.
        case waitingForReconnect
        case discoveringServices(since: Date)
        case discoveringCharacteristics(since: Date)
        case subscribing(since: Date)
        case ready
        /// Cancel sent, waiting for proof that the link is released; `reconnect` = a connect is queued.
        case cancelling(since: Date, reconnect: Bool)
        case failed(HandshakeFailure)
    }

    public enum Event: Equatable, Sendable {
        case connectRequested(Date)
        case reconnectScheduled
        case connected(Date)
        /// `didFailToConnect` for the current attempt.
        case connectFailed
        case servicesDiscovered(hasUART: Bool, error: String?)
        case uartCharacteristics(hasWrite: Bool, hasNotify: Bool, error: String?)
        case notifyState(isOn: Bool, error: String?)
        case cancelRequested(Date)
        /// `didDisconnectPeripheral` for the ring.
        case disconnected(Date)
        /// Other evidence that the old link is gone (peripheral state `.disconnected`, Bluetooth off).
        case released(Date)
        case tick(Date)
    }

    /// What the Bluetooth driver has to do after an event.
    public enum Action: Equatable, Sendable {
        case none
        /// Call `connect` now (fresh request, or the queued one after the old link was released).
        case connectNow
        /// A connection arrived that no step expects (late callback after a cancel): cancel it.
        case rejectConnection
        /// Release still unproven on a new request: send the cancel again and wait once more.
        case retryCancel
    }

    public let connectTimeout: TimeInterval
    /// Time from "connected" until notify is on.
    public let handshakeTimeout: TimeInterval
    /// Longest wait for proof of release before a queued connect is aborted.
    public let cancelAckTimeout: TimeInterval
    public private(set) var step: Step = .idle
    /// Since when a cancelled link waits for proof of release; nil = nothing pending.
    public private(set) var releasePendingSince: Date?

    public init(connectTimeout: TimeInterval = 15, handshakeTimeout: TimeInterval = 15, cancelAckTimeout: TimeInterval = 2) {
        self.connectTimeout = connectTimeout
        self.handshakeTimeout = handshakeTimeout
        self.cancelAckTimeout = cancelAckTimeout
    }

    public var isReady: Bool { step == .ready }
    public var releasePending: Bool { releasePendingSince != nil }

    /// Steps with a time limit, or a release to watch; the driver keeps its timer running while true.
    public var needsTimer: Bool {
        if releasePending { return true }
        switch step {
        case .connecting, .discoveringServices, .discoveringCharacteristics, .subscribing, .cancelling: return true
        default: return false
        }
    }

    /// A link is up (from `didConnect` until it drops or is cancelled).
    public var hasLink: Bool {
        switch step {
        case .discoveringServices, .discoveringCharacteristics, .subscribing, .ready: true
        default: false
        }
    }

    public var isCancelling: Bool {
        if case .cancelling = step { return true }
        return false
    }

    /// Only while characteristics are expected may the driver take write/notify handles from a callback.
    public var acceptsCharacteristics: Bool {
        if case .discoveringCharacteristics = step { return true }
        return false
    }

    public var failure: HandshakeFailure? {
        if case .failed(let failure) = step { return failure }
        return nil
    }

    private var connectedAt: Date? {
        switch step {
        case .discoveringServices(let since), .discoveringCharacteristics(let since), .subscribing(let since): since
        default: nil
        }
    }

    @discardableResult
    public mutating func handle(_ event: Event) -> Action {
        switch (event, step) {
        // Lifecycle
        case (.connectRequested(let now), _):
            guard let since = releasePendingSince else {
                step = .connecting(since: now)
                return .connectNow
            }
            if now.timeIntervalSince(since) < cancelAckTimeout {
                step = .cancelling(since: since, reconnect: true)
                return .none
            }
            // Still unproven after the limit: cancel again and give it one more window.
            releasePendingSince = now
            step = .cancelling(since: now, reconnect: true)
            return .retryCancel
        case (.reconnectScheduled, .idle) where !releasePending:
            step = .waitingForReconnect
        case (.connected(let now), .connecting) where !releasePending,
             (.connected(let now), .waitingForReconnect) where !releasePending:
            step = .discoveringServices(since: now)
        case (.connected, _):
            return .rejectConnection
        case (.connectFailed, .connecting), (.connectFailed, .waitingForReconnect):
            step = .idle
        case (.cancelRequested(let now), _):
            // Nothing to release when no link or request exists.
            guard step != .idle || releasePending else { break }
            releasePendingSince = now
            // A failure stays visible; the release is still tracked.
            if failure == nil { step = .cancelling(since: now, reconnect: false) }
        case (.disconnected(let now), _), (.released(let now), _):
            return linkGone(at: now, isDisconnectCallback: event == .disconnected(now))

        // Handshake chain
        case (.servicesDiscovered(let hasUART, let error), .discoveringServices(let since)):
            if let error { step = .failed(.serviceDiscoveryFailed(error)) }
            else if !hasUART { step = .failed(.noUARTService) }
            else { step = .discoveringCharacteristics(since: since) }
        case (.uartCharacteristics(let hasWrite, let hasNotify, let error), .discoveringCharacteristics(let since)):
            if let error { step = .failed(.characteristicDiscoveryFailed(error)) }
            else if !hasWrite { step = .failed(.missingWrite) }
            else if !hasNotify { step = .failed(.missingNotify) }
            else { step = .subscribing(since: since) }
        case (.notifyState(let isOn, let error), .subscribing):
            if let error { step = .failed(.notifyRejected(error)) }
            else if !isOn { step = .failed(.notifyRejected("aus")) }
            else { step = .ready }
        // Notify switched off or failing after the ring was ready: no more answers can arrive.
        case (.notifyState(let isOn, let error), .ready) where error != nil || !isOn:
            step = .failed(.notifyRejected(error ?? "aus"))

        // Time limits
        case (.tick(let now), .connecting(let since)):
            if now.timeIntervalSince(since) >= connectTimeout { step = .failed(.connectTimeout) }
        case (.tick(let now), .cancelling(let since, let reconnect)):
            guard now.timeIntervalSince(since) >= cancelAckTimeout else { break }
            // No proof of release: never connect blindly. A queued connect is aborted and explained;
            // the release stays pending, so the next request cannot skip it either.
            step = reconnect ? .failed(.releaseTimeout) : .idle
        case (.tick(let now), _):
            if let connectedAt, now.timeIntervalSince(connectedAt) >= handshakeTimeout { step = .failed(.handshakeTimeout) }

        default:
            // Late or out-of-order callbacks (e.g. a notify ack of an old link) change nothing.
            break
        }
        return .none
    }

    /// The ring's link is gone (callback or other evidence).
    private mutating func linkGone(at now: Date, isDisconnectCallback: Bool) -> Action {
        if releasePending {
            releasePendingSince = nil
            switch step {
            case .cancelling(_, reconnect: true):
                step = .connecting(since: now)
                return .connectNow
            case .cancelling:
                step = .idle
            default:
                break   // a failure (also `releaseTimeout`) stays visible until the next request
            }
            return .none
        }
        guard isDisconnectCallback else { return .none }
        switch step {
        case .discoveringServices, .discoveringCharacteristics, .subscribing, .ready:
            // An unexpected drop of the current link.
            step = .idle
        default:
            // Before `didConnect` CoreBluetooth reports `didFailToConnect`, not a disconnect: a disconnect
            // now (connecting, waiting for reconnect) is a stray callback of an older link and changes nothing.
            break
        }
        return .none
    }
}
