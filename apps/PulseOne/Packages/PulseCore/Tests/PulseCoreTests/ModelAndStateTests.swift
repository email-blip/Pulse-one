import Foundation
import Testing
@testable import PulseCore

@Suite("Colmi model detection")
struct ColmiModelTests {
    @Test(arguments: [
        ("R03_1A2B", "R03"), ("COLMI R09", "R09"), ("r02_abcd", "R02"), ("R12", "R12")
    ])
    func detectsModels(name: String, expected: String) {
        #expect(ColmiModel.detect(advertisedName: name)?.name == expected)
    }

    @Test(arguments: ["Polar H10", "R1", "R30_X", "", "AR03X", "R013"])
    func ignoresOtherDevices(name: String) {
        #expect(ColmiModel.detect(advertisedName: name) == nil)
    }

    @Test func temperatureOnlyWhereClaimed() {
        #expect(ColmiModel.detect(advertisedName: "R09_1")?.hasTemperature == true)
        #expect(ColmiModel.detect(advertisedName: "R03_1")?.hasTemperature == false)
    }

    /// Only the firmware that delivered real heart-rate values in PULSE ONE counts as tested.
    @Test func onlyTheVerifiedFirmwareIsTested() {
        #expect(TestedFirmware.isTested("RY03_3.00.28_250401"))
        #expect(!TestedFirmware.isTested("RY03_3.00.21_241028"))
        #expect(!TestedFirmware.isTested("RY03_3.00.10"))
        #expect(!TestedFirmware.isTested(nil))
    }
}

@Suite("Connection and reconnect")
struct ConnectionTests {
    @Test func labelsAreGerman() {
        #expect(ConnectionState.idle.label == "Nicht verbunden")
        #expect(ConnectionState.reconnecting(attempt: 2).label == "Verbindung verloren · neuer Versuch 2")
    }

    @Test func connectedStates() {
        #expect(ConnectionState.ready.isConnected)
        #expect(!ConnectionState.reconnecting(attempt: 1).isConnected)
        #expect(ConnectionState.scanning.isBusy)
    }

    @Test func backoffGrowsAndGivesUp() {
        let policy = ReconnectPolicy(maxAttempts: 4, baseDelay: 2, maxDelay: 10)
        #expect(policy.delay(forAttempt: 1) == 2)
        #expect(policy.delay(forAttempt: 2) == 4)
        #expect(policy.delay(forAttempt: 3) == 8)
        #expect(policy.delay(forAttempt: 4) == 10)
        #expect(policy.delay(forAttempt: 5) == nil)
        #expect(policy.delay(forAttempt: 0) == nil)
    }
}

@Suite("Measurements and capabilities")
struct MeasurementTests {
    private func make(_ metric: Metric, _ value: Int) -> VitalReading? {
        VitalReading(metric: metric, value: value, timestamp: .now, source: .ringLive,
                    deviceName: "R03_1A2B", deviceIdentifier: "id", model: "R03", firmware: nil)
    }

    @Test func implausibleValuesAreRejected() {
        #expect(make(.heartRate, 0) == nil)
        #expect(make(.heartRate, 300) == nil)
        #expect(make(.heartRate, 64)?.unit == "bpm")
        #expect(make(.battery, 101) == nil)
    }

    @Test func capabilityLevelsOnlyRise() {
        var tracker = CapabilityTracker(expected: [.heartRate])
        #expect(tracker.level(of: .heartRate) == .expected)
        tracker.raise(.heartRate, to: .verified)
        tracker.raise(.heartRate, to: .discovered)
        #expect(tracker.level(of: .heartRate) == .verified)
    }

    @Test func snapshotDeduplicatesAndSortsBySignal() {
        var snapshot = RingSnapshot()
        let id = UUID()
        snapshot.upsert(.init(id: id, name: "R03_A", rssi: -80, model: nil))
        snapshot.upsert(.init(id: UUID(), name: "R03_B", rssi: -50, model: nil))
        snapshot.upsert(.init(id: id, name: "R03_A", rssi: -40, model: nil))
        #expect(snapshot.discovered.map(\.name) == ["R03_A", "R03_B"])
    }

    @Test func untestedFirmwareIsFlagged() {
        var snapshot = RingSnapshot()
        snapshot.firmware = "3.00.10"
        #expect(snapshot.firmwareNote == "Firmware 3.00.10 · noch nicht getestet")
    }
}
