import Foundation
import PulseCore
import SwiftData

/// Fixed states for UI and screenshot tests (`-uiTestScenario <name>`). Only reachable with
/// `-uiTesting YES`; the screen then shows a "Testansicht" banner. These values are not
/// measurements and are never written to the real store (UI tests use an in-memory store).
enum TestScenario {
    static let all = ["start", "scanning", "connected", "live", "reconnecting", "heart", "devices"]

    static func snapshot(for name: String) -> RingSnapshot {
        var s = RingSnapshot()
        s.bluetooth = .ready
        let ringID = UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID()
        let r03 = ColmiModel.detect(advertisedName: "R03_1A2B")
        switch name {
        case "scanning":
            s.connection = .scanning
            s.upsert(.init(id: ringID, name: "R03_1A2B", rssi: -52, model: r03))
            s.upsert(.init(id: UUID(), name: "Kopfhörer", rssi: -70, model: nil))
        case "connected", "live", "reconnecting", "heart":
            s.deviceName = "R03_1A2B"
            s.deviceIdentifier = ringID.uuidString
            s.model = r03
            s.firmware = "3.00.10"
            s.battery = .init(level: 82, charging: false)
            s.capabilities.raise(.battery, to: .verified)
            s.capabilities.raise(.heartRate, to: .discovered)
            s.rememberedRing = "R03_1A2B"
            s.connection = .ready
            if name == "live" || name == "heart" {
                s.connection = .measuring
                s.liveHeartRate = 64
                s.capabilities.raise(.heartRate, to: .verified)
            }
            if name == "reconnecting" { s.connection = .reconnecting(attempt: 2) }
        default:
            s.rememberedRing = nil
        }
        return s
    }

    static let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID()

    /// Registry for the devices screenshot: a ring that delivered data and Apple Health after a sync.
    static func registry(for name: String) -> DeviceRegistry {
        var registry = DeviceRegistry(ownerProfileID: owner)
        guard name == "devices" else { return registry }
        let base = Date(timeIntervalSince1970: 1_795_188_773)
        if let ring = try? registry.add(adapterID: AdapterCatalog.colmiR03.id, sourceIdentifier: "test-ring",
                                        name: "R03_1A2B", profileID: owner) {
            try? registry.update(ring.id) {
                $0.reach(.synced)
                $0.batteryPercent = 82
                $0.firmware = "3.00.10"
                $0.lastSuccessfulSync = base
                $0.lastSampleAt = base
            }
        }
        if let health = try? registry.add(adapterID: AdapterCatalog.appleHealth.id, sourceIdentifier: "healthkit",
                                          name: "Apple Health") {
            try? registry.update(health.id) {
                $0.reach(.connected)
                $0.log("Testansicht: noch nicht synchronisiert")
            }
        }
        return registry
    }

    @MainActor
    static func insertSampleHistory(for name: String, into context: ModelContext) {
        guard name == "live" || name == "heart" else { return }
        let base = Date(timeIntervalSince1970: 1_795_188_773)
        for (offset, bpm) in [(0, 64), (-20, 66), (-40, 67)] {
            if let reading = VitalReading(metric: .heartRate, value: bpm, timestamp: base.addingTimeInterval(Double(offset)),
                                          source: .ringLive, deviceName: "R03_1A2B", deviceIdentifier: "test",
                                          model: "R03", firmware: "3.00.10") {
                context.insert(StoredMeasurement(reading))
            }
        }
    }
}
