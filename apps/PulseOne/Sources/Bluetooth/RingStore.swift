import Foundation
import Observation
import PulseCore

/// Observable state of the ring connection for the UI. In normal use it is driven by
/// `ColmiCentral` (CoreBluetooth). UI tests use `preview(_:)`, which has no Bluetooth and
/// shows a visible "Testansicht" banner, so test states are never mistaken for ring data.
@MainActor
@Observable
final class RingStore {
    var snapshot: RingSnapshot
    /// Bluetooth diagnostic log of this app session (directive 4.0 §3), exportable by the user.
    var trace = BLETrace()
    let isTestScenario: Bool
    /// Show every named Bluetooth device, not only names that look like a Colmi ring.
    var showAllDevices = false

    @ObservationIgnored var onMeasurement: (@MainActor (VitalReading) -> Void)?
    /// Receives values read from the ring's stored history (already normalised observations).
    @ObservationIgnored var onHistory: (@MainActor ([RawObservation], String) -> Void)?
    /// Sleep phases of the nights the ring sent (`BC 27`), with ring id and firmware.
    @ObservationIgnored var onSleep: (@MainActor ([SleepSegment], String, String?) -> Void)?
    /// How often the ring measures on its own; applied on every connect.
    private(set) var measurementProfile: RingMeasurementProfile = RingStore.savedProfile()
    private static let profileKey = "ring.measurementProfile"
    /// When the ring's stored history was last fetched completely (nil in test scenarios).
    private(set) var lastHistorySync: Date?
    @ObservationIgnored private var central: ColmiCentral?

    private init(snapshot: RingSnapshot, isTestScenario: Bool) {
        self.snapshot = snapshot
        self.isTestScenario = isTestScenario
        self.lastHistorySync = isTestScenario ? nil : UserDefaults.standard.object(forKey: ColmiCentral.lastSyncKey) as? Date
    }

    static func live() -> RingStore {
        let store = RingStore(snapshot: RingSnapshot(), isTestScenario: false)
        store.central = ColmiCentral(store: store)
        return store
    }

    static func preview(_ snapshot: RingSnapshot, trace: BLETrace = BLETrace()) -> RingStore {
        let store = RingStore(snapshot: snapshot, isTestScenario: true)
        store.trace = trace
        return store
    }

    /// Plain-text diagnosis for the share sheet: no device identifier, ring suffix hidden.
    func diagnosticReport() -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        var text = trace.report(appVersion: version, systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                deviceName: snapshot.deviceName, firmware: snapshot.firmware)
        text += "\n\nMessung: \(snapshot.measurement.title) · \(snapshot.measurement.detail)"
        if !snapshot.unknownPackets.isEmpty {
            text += "\nUnbekannte Antworten (\(snapshot.unknownPackets.count)):\n" + snapshot.unknownPackets.joined(separator: "\n")
        }
        return text
    }

    func clearTrace() { trace.clear() }

    var visibleRings: [DiscoveredRing] {
        showAllDevices ? snapshot.discovered : snapshot.discovered.filter { $0.model != nil }
    }

    var hiddenDeviceCount: Int { snapshot.discovered.count - visibleRings.count }

    func startScan() { central?.startScan() }
    func stopScan() { central?.stopScan() }
    func connect(_ ring: DiscoveredRing) { central?.connect(ring.id) }
    func reconnectRemembered() { central?.reconnectRemembered() }
    /// Connects a ring from the device list; `identifier` is the CoreBluetooth peripheral UUID.
    func connect(identifier: String) {
        guard let id = UUID(uuidString: identifier) else { return }
        central?.connectKnown(id)
    }
    func disconnect() { central?.disconnect() }
    func startHeartRate(mode: ColmiProtocol.HeartRateStartMode = .realTime) { central?.startHeartRate(mode: mode) }
    func stopHeartRate() { central?.stopHeartRate() }
    func refreshBattery() { central?.refreshBattery() }

    func setMeasurementProfile(_ profile: RingMeasurementProfile) {
        measurementProfile = profile
        guard !isTestScenario else { return }
        UserDefaults.standard.set(profile.rawValue, forKey: Self.profileKey)
        central?.applyProfile(profile)
    }

    func syncHistoryNow() { central?.syncHistory(force: true) }
    /// Gadgetbridge "find device": the ring blinks.
    func findRing() { central?.findRing() }
    /// Switches the ring off until it is charged again.
    func powerOff() { central?.powerOff() }

    func noteHistorySynced(at date: Date) { lastHistorySync = date }

    /// Hint from day 4 without a history fetch; the ring keeps about 7 days.
    var syncReminder: String? {
        guard snapshot.rememberedRing != nil || snapshot.deviceName != nil else { return nil }
        return RingSyncSchedule().reminder(lastSync: lastHistorySync, now: .now, calendar: .current)
    }
    /// Foreground hook: fetches the history at most every few hours (`RingSyncSchedule`).
    func syncIfDue() { central?.syncIfDue() }

    func recordHistory(_ observations: [RawObservation], deviceIdentifier: String) {
        onHistory?(observations, deviceIdentifier)
    }

    func recordSleep(_ segments: [SleepSegment], deviceIdentifier: String) {
        onSleep?(segments, deviceIdentifier, snapshot.firmware)
    }

    private static func savedProfile() -> RingMeasurementProfile {
        UserDefaults.standard.string(forKey: profileKey).flatMap(RingMeasurementProfile.init(rawValue:)) ?? .standard
    }

    func record(_ reading: VitalReading) {
        onMeasurement?(reading)
    }
}
