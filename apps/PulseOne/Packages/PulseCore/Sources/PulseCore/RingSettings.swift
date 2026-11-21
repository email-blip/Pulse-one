import Foundation

/// Read/write selector of the Colmi preference commands (Gadgetbridge `PREF_READ` / `PREF_WRITE`).
public enum RingPreference {
    public static let read: UInt8 = 1
    public static let write: UInt8 = 2
}

/// Measurements a ring can take on its own during the day. Every feature is a capability:
/// the app only offers it when the ring model is expected to have it and only claims it
/// once the ring answered (`RingFeatureSupport`). Nothing here depends on a model name.
public enum RingFeature: String, CaseIterable, Codable, Sendable, Hashable {
    case heartRate
    case hrv
    case stress
    case spo2
    case steps
    case sleep
    /// Skin temperature (R09 and others). Kept as a type, but no command is sent until a
    /// real R09 test confirmed a documented command (owner decision 2026-11-21).
    case skinTemperature

    public var title: String {
        switch self {
        case .heartRate: "Puls"
        case .hrv: "HRV"
        case .stress: "Stresswert"
        case .spo2: "Sauerstoffsättigung"
        case .steps: "Schritte"
        case .sleep: "Schlaf"
        case .skinTemperature: "Hauttemperatur"
        }
    }

    /// The sample kinds this feature fills in the common store. Stress has no kind yet:
    /// it is read and counted, but only shown once a descriptive scale is agreed.
    public var sampleKinds: [SampleKind] {
        switch self {
        case .heartRate: [.heartRate]
        case .hrv: [.heartRateVariability]
        case .stress: []
        case .spo2: [.oxygenSaturation]
        case .steps: [.steps, .distance]
        case .sleep: [.sleepDuration]
        case .skinTemperature: [.skinTemperature]
        }
    }

    /// True when a documented command exists for this feature (Gadgetbridge / colmi_r02_client).
    public var hasDocumentedCommand: Bool { self != .skinTemperature }
}

/// One setting as the ring reported it.
public struct RingSettingReport: Equatable, Sendable {
    public let feature: RingFeature
    public let enabled: Bool
    /// Only the heart-rate setting carries an interval.
    public let intervalMinutes: Int?

    public init(feature: RingFeature, enabled: Bool, intervalMinutes: Int?) {
        self.feature = feature
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
    }

    static func feature(for command: ColmiProtocol.Command) -> RingFeature? {
        switch command {
        case .heartRateLogSettings: .heartRate
        case .autoSpO2Preference: .spo2
        case .autoStressPreference: .stress
        case .autoHRVPreference: .hrv
        default: nil
        }
    }
}

/// How often the ring measures on its own. Values follow konzept/RING-AUSWERTUNGEN.md
/// ("Standard": pulse every 5 minutes, HRV and stress every 30 minutes, SpO₂ hourly).
/// HRV, stress and SpO₂ have no interval on the ring, only on/off (Gadgetbridge); their rhythm
/// is fixed by the firmware.
public enum RingMeasurementProfile: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard
    case batterySaver
    case minimal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .batterySaver: "Akku sparen"
        case .minimal: "Minimal"
        }
    }

    /// Pulse interval in minutes; the ring accepts steps of 5 up to 60.
    public var heartRateIntervalMinutes: Int {
        switch self {
        case .standard: 5
        case .batterySaver: 15
        case .minimal: 30
        }
    }

    public func isEnabled(_ feature: RingFeature) -> Bool {
        switch feature {
        case .heartRate, .steps, .sleep: true
        case .hrv: self != .minimal
        case .stress, .spo2: self == .standard
        case .skinTemperature: false
        }
    }

    /// Plain description for the settings screen.
    public var summary: String {
        var parts = ["Puls alle \(heartRateIntervalMinutes) Minuten"]
        parts.append(isEnabled(.hrv) ? "HRV etwa alle 30 Minuten" : "keine HRV")
        parts.append(isEnabled(.stress) ? "Stresswert etwa alle 30 Minuten" : "kein Stresswert")
        parts.append(isEnabled(.spo2) ? "Sauerstoff stündlich" : "kein Sauerstoff")
        return parts.joined(separator: " · ") + " · Schritte und Schlaf immer"
    }

    /// Packets that apply this profile, only for features the ring may support.
    public func packets(for support: RingFeatureSupport) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        if support.mayUse(.heartRate) {
            packets.append(ColmiProtocol.heartRateIntervalWrite(minutes: heartRateIntervalMinutes))
        }
        for feature in [RingFeature.hrv, .stress, .spo2] where support.mayUse(feature) {
            if let packet = ColmiProtocol.toggleWrite(feature, enabled: isEnabled(feature)) { packets.append(packet) }
        }
        return packets
    }
}

/// What the connected ring can do, by evidence. A feature starts as expected (model list or
/// default), becomes `answered` when the ring replied to its command and `unsupported` when it
/// stayed silent. The UI shows values by feature, never by model name.
public struct RingFeatureSupport: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case expected
        case answered
        case unsupported
        /// Present on the model, but no documented command yet (skin temperature).
        case waitingForTest
    }

    public private(set) var states: [RingFeature: State]

    /// Colmi rings share the UART protocol; temperature only where the model list claims it.
    public init(model: ColmiModel?) {
        var states: [RingFeature: State] = [:]
        for feature in RingFeature.allCases where feature != .skinTemperature { states[feature] = .expected }
        if model?.hasTemperature == true { states[.skinTemperature] = .waitingForTest }
        self.states = states
    }

    public func state(of feature: RingFeature) -> State? { states[feature] }

    /// True unless the ring showed it lacks the feature or no command is documented.
    public func mayUse(_ feature: RingFeature) -> Bool {
        guard feature.hasDocumentedCommand, let state = states[feature] else { return false }
        return state != .unsupported
    }

    public mutating func markAnswered(_ feature: RingFeature) {
        guard states[feature] != nil else { return }
        states[feature] = .answered
    }

    /// Only an unanswered feature can be marked unsupported; one answer is proof enough.
    public mutating func markSilent(_ feature: RingFeature) {
        guard let state = states[feature], state == .expected else { return }
        states[feature] = .unsupported
    }

    /// Features to show in the UI, in a stable order.
    public var visibleFeatures: [RingFeature] {
        RingFeature.allCases.filter { states[$0] != nil && states[$0] != .unsupported }
    }
}

extension ColmiProtocol {
    /// Gadgetbridge `onSetHeartRateMeasurementInterval`: `16 02 01 mm` (on) or `16 02 02 00` (off).
    /// Minutes are rounded to 5 and capped at 60, as the ring requires.
    public static func heartRateIntervalWrite(minutes: Int) -> [UInt8] {
        let rounded = min(Int((Double(max(0, minutes)) / 5).rounded()) * 5, 60)
        let payload: [UInt8] = [RingPreference.write, rounded > 0 ? 1 : 2, UInt8(rounded)]
        return (try? makePacket(.heartRateLogSettings, payload: payload)) ?? []
    }

    /// Gadgetbridge `onSendConfiguration`: `<cmd> 02 01|00` for SpO₂, stress and HRV.
    public static func toggleWrite(_ feature: RingFeature, enabled: Bool) -> [UInt8]? {
        guard let command = preferenceCommand(feature) else { return nil }
        return try? makePacket(command, payload: [RingPreference.write, enabled ? 1 : 0])
    }

    /// Gadgetbridge `requestSettingsFromRing`: `<cmd> 01`.
    public static func preferenceRead(_ feature: RingFeature) -> [UInt8]? {
        guard let command = preferenceCommand(feature) else { return nil }
        return try? makePacket(command, payload: [RingPreference.read])
    }

    static func preferenceCommand(_ feature: RingFeature) -> Command? {
        switch feature {
        case .heartRate: .heartRateLogSettings
        case .spo2: .autoSpO2Preference
        case .stress: .autoStressPreference
        case .hrv: .autoHRVPreference
        case .steps, .sleep, .skinTemperature: nil
        }
    }
}
