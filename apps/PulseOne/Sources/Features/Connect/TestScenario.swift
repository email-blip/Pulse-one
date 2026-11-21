import Foundation
import PulseCore
import SwiftData

/// Fixed states for UI and screenshot tests (`-uiTestScenario <name>`). Only reachable with
/// `-uiTesting YES`; the screen then shows a "Testansicht" banner. These values are not
/// measurements and are never written to the real store (UI tests use an in-memory store).
enum TestScenario {
    static let all = ["start", "scanning", "connected", "live", "failed", "reconnecting", "heart", "devices"]
    /// Scenarios that show the ring screen on its own.
    static let ringScenarios: Set<String> = ["start", "scanning", "connected", "live", "failed", "reconnecting"]

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
        case "connected", "live", "failed", "reconnecting", "heart":
            s.deviceName = "R03_1A2B"
            s.deviceIdentifier = ringID.uuidString
            s.model = r03
            s.firmware = "3.00.10"
            s.battery = .init(level: 82, charging: false)
            s.capabilities.raise(.battery, to: .verified)
            s.capabilities.raise(.heartRate, to: .discovered)
            s.rememberedRing = "R03_1A2B"
            s.connection = .ready
            if name == "connected" {
                // Test view only: how the ring card looks after a history fetch.
                s.features = RingFeatureSupport(model: r03)
                for feature in [RingFeature.heartRate, .hrv, .steps, .sleep, .spo2] { s.features.markAnswered(feature) }
                s.features.markSilent(.stress)
                s.ringSettings[.heartRate] = RingSettingReport(feature: .heartRate, enabled: true, intervalMinutes: 5)
                s.ringSettings[.hrv] = RingSettingReport(feature: .hrv, enabled: true, intervalMinutes: nil)
                s.historySync = .finished(summary: "Testansicht: Puls 288 · HRV 48 · Schritte 96", at: fixedTime)
            }
            if name == "live" || name == "heart" {
                s.measurement = .receiving(value: 64, at: fixedTime, since: fixedTime.addingTimeInterval(-6))
                s.liveHeartRate = 64
                s.capabilities.raise(.heartRate, to: .verified)
            }
            if name == "failed" { s.measurement = .failed(.noValidValue, at: fixedTime) }
            if name == "reconnecting" { s.connection = .reconnecting(attempt: 2) }
        default:
            s.rememberedRing = nil
        }
        return s
    }

    /// Fixed clock for test states, so screenshots do not change between runs.
    static let fixedTime = Date(timeIntervalSince1970: 1_795_188_773)

    /// A short sample conversation for the diagnosis card (test view only).
    static func trace(for name: String) -> BLETrace {
        var trace = BLETrace()
        guard name == "failed" else { return trace }
        let t = fixedTime.addingTimeInterval(-40)
        trace.add(.event, "Messung gestartet (Echtzeit Puls)", at: t)
        trace.add(.sent, channel: ColmiProtocol.uartWrite, ColmiProtocol.hex(ColmiProtocol.realTimeStart(.heartRate)), at: t)
        let answer = (try? ColmiProtocol.makePacket(.realTimeStart, payload: [1, 0, 0])) ?? []
        trace.add(.received, channel: ColmiProtocol.uartNotify, ColmiProtocol.hex(answer), at: t.addingTimeInterval(2))
        return trace
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
            // A sync ran but Health returned nothing: shows the permission hint.
            try? registry.update(health.id) {
                $0.reach(.compatible)
                $0.lastSuccessfulSync = base
                $0.log("Sync: 0 neu, 0 geändert, 0 gelöscht, 0 abgelehnt")
            }
        }
        return registry
    }

    /// Scenarios of the tab app (TODAY, HEALTH, profile) that show five weeks of sample history.
    static let historyScenarios: Set<String> = ["today", "health", "healthDetail", "profile", "intelligence"]

    /// Five weeks of plausible values for the tab screenshots. Test view only, never in the real store.
    @MainActor
    static func insertTabHistory(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: fixedTime)
        func add(_ kind: SampleKind, _ value: Double, at start: Date, duration: TimeInterval = 0, source: DataSourceKind) {
            guard start <= fixedTime else { return }
            let sample = HealthSample(profileID: owner, kind: kind, value: value, unit: kind.canonicalUnit, start: start,
                                      end: start.addingTimeInterval(duration), timeZoneIdentifier: calendar.timeZone.identifier,
                                      source: source, deviceID: source == .colmiRing ? "test-ring" : "healthkit",
                                      originalSampleID: "test-\(kind.rawValue)-\(Int(start.timeIntervalSince1970))",
                                      importedAt: fixedTime, quality: .valid,
                                      method: source == .colmiRing ? .liveSensor : .healthStore)
            context.insert(StoredSample(sample))
        }
        for offset in 0...34 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let wave = sin(Double(offset) * 0.7)
            let hour = { (h: Double) in day.addingTimeInterval(h * 3600) }
            add(.restingHeartRate, 58 + 3 * wave, at: hour(6), source: .appleHealth)
            add(.ringHRV, 46 + 7 * cos(Double(offset) * 0.5), at: hour(6.5), source: .colmiRing)
            add(.oxygenSaturation, 97 + (offset % 3 == 0 ? -1 : 0), at: hour(3), source: .colmiRing)
            add(.sleepDuration, (7 + 0.6 * wave) * 3600, at: hour(-1), duration: (7 + 0.6 * wave) * 3600, source: .appleHealth)
            for (h, steps) in [(9.0, 1800.0), (12.0, 2600.0), (15.0, 1900.0 + 900 * wave), (18.0, 2200.0)] {
                add(.steps, steps, at: hour(h), duration: 3000, source: .appleHealth)
            }
            for (h, bpm) in [(8.0, 66.0), (11.0, 72.0), (14.0, 78.0 + 4 * wave), (15.0, 64.0)] {
                add(.heartRate, bpm, at: hour(h), source: .colmiRing)
            }
        }
    }

    @MainActor
    static func insertSampleHistory(for name: String, into context: ModelContext) {
        if historyScenarios.contains(name) { insertTabHistory(into: context) }
        if name == "intelligence" { IntelligenceTestData.insert(into: context) }
        if name == "coach" { CoachScenario.insert(into: context) }
        if name == "nutrition" { NutritionTestData.insert(into: context) }
        if name == "companion" || name == "companionWake" { CompanionTestData.insert(into: context) }
        guard name == "live" || name == "heart" || name == "devices" else { return }
        let base = Date(timeIntervalSince1970: 1_795_188_773)
        let device = name == "devices" ? "test-ring" : "test"
        for (offset, bpm) in [(0, 64), (-20, 66), (-40, 67)] {
            if let reading = VitalReading(metric: .heartRate, value: bpm, timestamp: base.addingTimeInterval(Double(offset)),
                                          source: .ringLive, deviceName: "R03_1A2B", deviceIdentifier: device,
                                          model: "R03", firmware: "3.00.10") {
                context.insert(StoredMeasurement(reading))
            }
        }
    }
}
