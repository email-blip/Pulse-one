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
    let isTestScenario: Bool
    /// Show every named Bluetooth device, not only names that look like a Colmi ring.
    var showAllDevices = false

    @ObservationIgnored var onMeasurement: (@MainActor (VitalReading) -> Void)?
    @ObservationIgnored private var central: ColmiCentral?

    private init(snapshot: RingSnapshot, isTestScenario: Bool) {
        self.snapshot = snapshot
        self.isTestScenario = isTestScenario
    }

    static func live() -> RingStore {
        let store = RingStore(snapshot: RingSnapshot(), isTestScenario: false)
        store.central = ColmiCentral(store: store)
        return store
    }

    static func preview(_ snapshot: RingSnapshot) -> RingStore {
        RingStore(snapshot: snapshot, isTestScenario: true)
    }

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
    func startHeartRate() { central?.startHeartRate() }
    func stopHeartRate() { central?.stopHeartRate() }
    func refreshBattery() { central?.refreshBattery() }

    func record(_ reading: VitalReading) {
        onMeasurement?(reading)
    }
}
