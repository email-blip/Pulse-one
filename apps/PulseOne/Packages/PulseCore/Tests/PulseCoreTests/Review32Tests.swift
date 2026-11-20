import Foundation
import Testing
@testable import PulseCore

// Architecture Review 3.2 §7: the ten regression cases, numbered as in the review.

private let personA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let personB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
private let nov1 = Date(timeIntervalSince1970: 1_793_491_200)   // 2026-11-01 00:00 UTC
private let day: TimeInterval = 86_400

private func at(_ dayOfNovember: Int, hour: Double = 12) -> Date {
    nov1.addingTimeInterval(Double(dayOfNovember - 1) * day + hour * 3_600)
}

private var berlin: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}

private func ring(_ bpm: Int, _ date: Date, _ source: MeasurementSource = .ringLive, device: String = "ring-1") -> RawObservation {
    RawObservation(reading: VitalReading(metric: .heartRate, value: bpm, timestamp: date, source: source,
                                         deviceName: "R03", deviceIdentifier: device, model: "R03", firmware: "3.00.10")!,
                   timeZoneIdentifier: "Europe/Berlin")
}

private func raw(_ kind: SampleKind, _ value: Double, _ unit: SampleUnit, _ start: Date, end: Date? = nil,
                 id: String, source: DataSourceKind, device: String, tz: String? = "Europe/Berlin",
                 flag: String? = nil) -> RawObservation {
    RawObservation(kind: kind, value: value, unit: unit, start: start, end: end, timeZoneIdentifier: tz,
                   source: source, deviceID: device, originalSampleID: id, method: .healthStore, deviceFlag: flag)
}

/// Applies plans like `SampleStore` does.
private struct Store {
    var rows: [String: HealthSample] = [:]

    @discardableResult
    mutating func sync(_ observations: [RawObservation], profiles: ProfileTimeline = .constant(personA),
                       now: Date = at(30)) -> SyncPlan {
        let plan = SyncCoordinator.plan(batch: SyncBatch(observations: observations), existing: rows,
                                        profiles: profiles, importedAt: now)
        for s in plan.inserts + plan.updates { rows[s.deduplicationKey] = s }
        return plan
    }

    var samples: [HealthSample] { rows.values.sorted { $0.start < $1.start } }
}

@Suite("Review 3.2 regression")
struct Review32Tests {
    // 1. Historic samples after a profile switch
    @Test func historicSamplesStayWithTheirProfile() throws {
        var registry = DeviceRegistry(ownerProfileID: personA)
        let r03 = try registry.add(adapterID: AdapterCatalog.colmiR03.id, sourceIdentifier: "ring-1", name: "R03", profileID: personA)
        try registry.assign(r03.id, to: personB, from: at(16, hour: 0), reason: "Ring weitergegeben", now: at(16))
        let timeline = try #require(registry.device(r03.id)).timeline

        var store = Store()
        store.sync([ring(60, at(10)), ring(70, at(18))], profiles: timeline)
        #expect(store.samples.map(\.profileID) == [personA, personB])

        // A later sync of the same history changes nothing.
        let again = store.sync([ring(60, at(10)), ring(70, at(18))], profiles: timeline)
        #expect(again.isEmpty)
        #expect(store.samples.map(\.profileID) == [personA, personB])

        // A handover cannot start before the running period: that needs a logged correction.
        #expect(throws: RegistryError.invalidAssignment(.startsBeforeCurrent)) {
            try registry.assign(r03.id, to: personA, from: at(12), reason: "falsch", now: at(20))
        }
    }

    @Test func unclearPeriodsAreUnresolvedAndCorrectionsAreLogged() throws {
        var registry = DeviceRegistry(ownerProfileID: personA)
        let r03 = try registry.add(adapterID: AdapterCatalog.colmiR03.id, sourceIdentifier: "ring-1", name: "R03", profileID: personA)
        var store = Store()
        store.sync([ring(61, at(12)), ring(62, at(14)), ring(63, at(20))], profiles: try #require(registry.device(r03.id)).timeline)

        // The owner says: 13.–15.11. unclear who wore the ring.
        try registry.correctAssignment(r03.id, to: nil, from: at(13, hour: 0), until: at(16, hour: 0),
                                       reason: "Ring verliehen, Person unbekannt", now: at(21))
        let device = try #require(registry.device(r03.id))
        let moved = SyncCoordinator.reattribute(store.samples, with: device.timeline)
        #expect(moved.count == 1)
        #expect(moved.first?.value == 62 && moved.first?.profileID == nil)
        #expect(device.timeline.profile(at: at(12)) == personA)
        #expect(device.timeline.profile(at: at(20)) == personA)
        #expect(device.assignments.contains { $0.reason.hasPrefix("Korrektur: Ring verliehen") && $0.recordedAt == at(21) })
        #expect(device.diagnostics.last?.contains("Zuordnung korrigiert") == true)
    }

    // 2. Several samples with the same timestamp
    @Test func sameTimestampDifferentValuesAreBothKept() {
        var store = Store()
        let plan = store.sync([ring(60, at(5)), ring(64, at(5))])
        #expect(plan.inserts.count == 2)
        #expect(store.samples.allSatisfy { $0.identity == .derived })
        // A source id reused with another value inside one batch is reported, not silently merged.
        let health = store.sync([raw(.heartRate, 70, .beatsPerMinute, at(6), id: "hk-1", source: .appleHealth, device: "healthkit"),
                                 raw(.heartRate, 75, .beatsPerMinute, at(6), id: "hk-1", source: .appleHealth, device: "healthkit")])
        #expect(health.inserts.count == 1)
        #expect(health.conflicts == 1)
    }

    // 3. Repeated historic sync
    @Test func repeatedHistorySyncAddsNothing() {
        var store = Store()
        let history = (0..<12).map { ring(55 + $0, at(7, hour: Double($0) / 12), .ringHistory) }
        store.sync(history)
        for _ in 0..<3 {
            let plan = store.sync(history)
            #expect(plan.isEmpty && plan.unchanged == 12)
        }
        #expect(store.rows.count == 12)
    }

    // 4. Live and history overlap
    @Test func liveAndHistoryOfTheSameMinuteCountOnce() throws {
        var store = Store()
        store.sync([ring(64, at(8)), ring(64, at(8).addingTimeInterval(20), .ringHistory)])
        #expect(store.rows.count == 2)                        // both kept, nothing deleted
        let resolved = DataSourceResolver.resolvePoints(store.samples, policy: SourcePolicy())
        #expect(resolved.count == 1)
        #expect(resolved.first?.method == .liveSensor)
        let daily = try #require(DailySeries.build(store.samples, kind: .heartRate, calendar: berlin).first)
        #expect(daily.sampleCount == 1)
    }

    // 5. Different sources on the same day
    @Test func differentSourcesOnOneDayFillGapsWithoutDoubleCounting() throws {
        var store = Store()
        store.sync([ring(58, at(9, hour: 3)), ring(60, at(9, hour: 3.5)),
                    raw(.heartRate, 90, .beatsPerMinute, at(9, hour: 10), id: "hk-hr", source: .appleHealth, device: "healthkit"),
                    raw(.steps, 3_000, .count, at(9, hour: 8), id: "hk-s1", source: .appleHealth, device: "healthkit"),
                    raw(.steps, 1_200, .count, at(9, hour: 8.2), id: "ring-s1", source: .colmiRing, device: "ring-1"),
                    raw(.steps, 800, .count, at(9, hour: 14), id: "ring-s2", source: .colmiRing, device: "ring-1")])
        let pulse = try #require(DailySeries.build(store.samples, kind: .heartRate, calendar: berlin).first)
        #expect(pulse.value == (58 + 60 + 90) / 3)
        #expect(pulse.origins.count == 2)
        let steps = try #require(DailySeries.build(store.samples, kind: .steps, calendar: berlin).first)
        #expect(steps.value == 3_800)                          // 08:00 Health, 14:00 ring; ring 08:12 not added
        #expect(steps.origins.count == 2)
        #expect(Set(steps.sampleIDs).count == 2)
    }

    // 6. Manually chosen device priority
    @Test func manualPreferenceWins() {
        let a = SampleOrigin(source: .colmiRing, deviceID: "ring-a")
        let b = SampleOrigin(source: .colmiRing, deviceID: "ring-b")
        let health = SampleOrigin(source: .appleHealth, deviceID: "healthkit")
        var prefs = SourcePreferences()
        prefs.set(.device(b), for: .heartRate)
        prefs.set(.source(.appleHealth), for: .sleepDuration)
        let policy = SourcePolicy(preferences: prefs)
        #expect(policy.choose(kind: .heartRate, among: [a, b, health]) == ResolvedOrigin(origin: b, reason: .preferred))
        #expect(policy.choose(kind: .sleepDuration, among: [a, health]) == ResolvedOrigin(origin: health, reason: .preferred))
        // Automatic depends on kind and situation, and is stable (device id), never "last added".
        #expect(SourcePolicy().choose(kind: .heartRate, among: [b, a])?.origin == a)
        let strap = SampleOrigin(source: .bluetoothStandard, deviceID: "polar")
        #expect(SourcePolicy(context: .workout).choose(kind: .heartRate, among: [a, strap, health])?.origin == strap)
        #expect(SourcePolicy(context: .rest).choose(kind: .heartRate, among: [a, strap, health])?.origin == a)
        #expect(SourcePolicy().choose(kind: .steps, among: [a, health])?.origin == health)
        // Choosing "automatic" removes the stored preference.
        prefs.set(.automatic, for: .heartRate)
        #expect(prefs.choice(for: .heartRate) == .automatic)
    }

    // 7. Preferred source unavailable
    @Test func missingPreferredSourceFallsBackVisibly() {
        let a = SampleOrigin(source: .colmiRing, deviceID: "ring-a")
        let health = SampleOrigin(source: .appleHealth, deviceID: "healthkit")
        var prefs = SourcePreferences()
        prefs.set(.device(SampleOrigin(source: .colmiRing, deviceID: "ring-gone")), for: .heartRate)
        let resolved = SourcePolicy(preferences: prefs).choose(kind: .heartRate, among: [a, health])
        #expect(resolved?.origin == a)
        #expect(resolved?.reason == .fallback(preferredMissing: .device(SampleOrigin(source: .colmiRing, deviceID: "ring-gone"))))
        #expect(SourcePolicy(preferences: prefs).choose(kind: .heartRate, among: []) == nil)
    }

    // 8. Incomplete day coverage
    @Test func incompleteDaysShowTheirCoverage() throws {
        var store = Store()
        store.sync([ring(60, at(11, hour: 6)), ring(62, at(11, hour: 6.5)), ring(64, at(11, hour: 13))])
        let value = try #require(DailySeries.build(store.samples, kind: .heartRate, calendar: berlin).first)
        #expect(value.coveredHours == 2)
        #expect(value.sampleIDs.count == 3)
    }

    // 9. Faulty and time-uncertain values
    @Test func faultyAndUncertainValuesAreKeptButNeverAnalysed() throws {
        var store = Store()
        let plan = store.sync([
            raw(.heartRate, 61, .beatsPerMinute, at(12), id: "ok", source: .appleHealth, device: "healthkit"),
            raw(.heartRate, 61, .beatsPerMinute, at(12, hour: 13), id: "flag", source: .appleHealth, device: "healthkit",
                flag: "kein Hautkontakt"),
            raw(.heartRate, 61, .beatsPerMinute, at(12, hour: 14), id: "notz", source: .appleHealth, device: "healthkit", tz: nil),
            raw(.heartRate, 300, .beatsPerMinute, at(12, hour: 15), id: "wild", source: .appleHealth, device: "healthkit"),
            raw(.sleepDuration, 0, .seconds, at(12, hour: 1), id: "noend", source: .appleHealth, device: "healthkit"),
            raw(.heartRate, 61, .beatsPerMinute, at(30).addingTimeInterval(120), id: "ahead", source: .appleHealth, device: "healthkit")
        ])
        let byID = Dictionary(uniqueKeysWithValues: plan.inserts.map { ($0.originalSampleID, $0) })
        #expect(byID["ok"]?.quality == .plausible)
        #expect(byID["flag"]?.quality == .technicalError)
        #expect(byID["notz"]?.quality == .timeUncertain)
        #expect(byID["wild"]?.quality == .implausible)
        #expect(byID["noend"]?.quality == .incomplete)
        #expect(byID["ahead"]?.quality == .timeUncertain)
        #expect(plan.inserts.allSatisfy { $0.qualityReason?.isEmpty == false })
        let days = DailySeries.build(store.samples, kind: .heartRate, calendar: berlin)
        #expect(days.count == 1 && days.first?.sampleCount == 1)
        #expect(DailySeries.build(store.samples, kind: .sleepDuration, calendar: berlin).isEmpty)
        // A confirmed source upgrades plausible to valid.
        let confirmed = try MeasurementNormalizer.normalize(ring(60, at(12)), profileID: personA, importedAt: at(30),
                                                            sourceConfirmed: true)
        #expect(confirmed.quality == .valid)
    }

    // 10. Migration and resume after a crash, with historic profiles
    @Test func migrationResumesAndUsesTheTimeline() {
        let timeline = ProfileTimeline([
            DeviceAssignment(profileID: personA, from: .distantPast, until: at(16, hour: 0), reason: "Erstzuordnung", recordedAt: at(1)),
            DeviceAssignment(profileID: personB, from: at(16, hour: 0), reason: "Weitergabe", recordedAt: at(16))
        ])
        let legacy = (0..<20).map { ring(60 + $0 % 5, at(10 + $0 / 2, hour: Double($0 % 2) * 6)) }
        var store = Store()
        store.sync(Array(legacy.prefix(7)), profiles: timeline)       // crash after the first chunk
        let resumed = store.sync(legacy, profiles: timeline)
        #expect(resumed.inserts.count == 13 && resumed.unchanged == 7)
        #expect(store.rows.count == 20)
        #expect(store.samples.filter { $0.start < at(16, hour: 0) }.allSatisfy { $0.profileID == personA })
        #expect(store.samples.filter { $0.start >= at(16, hour: 0) }.allSatisfy { $0.profileID == personB })
    }

    // Supporting checks
    @Test func overlappingSleepIsMergedNotAdded() throws {
        var store = Store()
        store.sync([raw(.sleepDuration, 7_200, .seconds, at(3, hour: 0), end: at(3, hour: 2), id: "s1", source: .appleHealth, device: "healthkit"),
                    raw(.sleepDuration, 7_200, .seconds, at(3, hour: 1), end: at(3, hour: 3), id: "s2", source: .appleHealth, device: "healthkit")])
        let night = try #require(DailySeries.build(store.samples, kind: .sleepDuration, calendar: berlin).first)
        #expect(night.value == 3 * 3_600)
    }

    @Test func registriesWithoutHistoryStillLoad() throws {
        let json = """
        {"devices":[{"id":"00000000-0000-0000-0000-000000000001","adapterID":"colmi.r03","sourceIdentifier":"ring-1",
        "name":"R03","profileID":"00000000-0000-0000-0000-00000000000A","stage":4,"diagnostics":[]}],
        "ownerProfileID":"00000000-0000-0000-0000-00000000000A"}
        """
        let registry = try JSONDecoder().decode(DeviceRegistry.self, from: Data(json.utf8))
        let device = try #require(registry.devices.first)
        #expect(device.timeline.profile(at: at(5)) == personA)
        #expect(device.assignments.first?.reason.contains("Übernommen") == true)
        #expect(registry.preferences(for: personA) == SourcePreferences())
        // Round trip keeps history and preferences.
        var copy = registry
        copy.setPreference(.source(.appleHealth), for: .steps, profile: personA)
        let decoded = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(copy))
        #expect(decoded.preferences(for: personA).choice(for: .steps) == .source(.appleHealth))
        #expect(decoded.devices.first?.assignments == device.assignments)
    }

    @Test func temperaturesKeepTheirSite() {
        #expect(SampleKind.skinTemperature.measurementSite != SampleKind.bodyTemperature.measurementSite)
        #expect(SampleKind.skinTemperatureDeviation.aggregation == .derived)
        #expect(SampleKind.restingHeartRate.aggregation == .derived)
    }
}
