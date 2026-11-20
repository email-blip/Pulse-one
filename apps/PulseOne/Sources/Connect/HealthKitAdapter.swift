import Foundation
import HealthKit
import PulseCore

/// Apple Health as a data source (General Directive 3.0 Phase A). Read-only, per-type permissions,
/// incremental import with one anchor per type (`HKAnchoredObjectQueryDescriptor`), including deletions.
/// The first import is limited to `initialWindow` so a long Health history does not block the app.
final class HealthKitAdapter: DeviceAdapter, @unchecked Sendable {
    // @unchecked: HKHealthStore is thread-safe per Apple's documentation; nothing else is mutable.
    static let deviceID = "healthkit"
    let descriptor = AdapterCatalog.appleHealth
    private let store = HKHealthStore()
    private let initialWindow: TimeInterval = 30 * 24 * 3600

    struct QuantityMapping {
        let identifier: HKQuantityTypeIdentifier
        let kind: SampleKind
        let unit: HKUnit
        let sampleUnit: SampleUnit
    }

    static var quantities: [QuantityMapping] { [
        .init(identifier: .heartRate, kind: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), sampleUnit: .beatsPerMinute),
        .init(identifier: .restingHeartRate, kind: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), sampleUnit: .beatsPerMinute),
        .init(identifier: .heartRateVariabilitySDNN, kind: .heartRateVariability, unit: .secondUnit(with: .milli), sampleUnit: .milliseconds),
        .init(identifier: .oxygenSaturation, kind: .oxygenSaturation, unit: .percent(), sampleUnit: .fraction),
        .init(identifier: .stepCount, kind: .steps, unit: .count(), sampleUnit: .count),
        .init(identifier: .activeEnergyBurned, kind: .activeEnergy, unit: .kilocalorie(), sampleUnit: .kilocalories),
        .init(identifier: .distanceWalkingRunning, kind: .distance, unit: .meter(), sampleUnit: .meters),
        .init(identifier: .bodyTemperature, kind: .bodyTemperature, unit: .degreeCelsius(), sampleUnit: .celsius),
        .init(identifier: .appleSleepingWristTemperature, kind: .skinTemperatureDeviation, unit: .degreeCelsius(), sampleUnit: .celsius)
    ] }

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Types we ask to read (workouts already, for the coming training features).
    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(quantities.map { HKQuantityType($0.identifier) as HKObjectType })
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async throws {
        guard Self.available else { throw AdapterError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// `cursor` is a JSON map of type identifier → archived `HKQueryAnchor`.
    func sync(deviceID: String, cursor: String?) async throws -> SyncBatch {
        guard Self.available else { throw AdapterError.notAvailable }
        var anchors = Self.decodeAnchors(cursor)
        var batch = SyncBatch()
        let since = Date(timeIntervalSinceNow: -initialWindow)
        let timeZone = TimeZone.current.identifier

        for mapping in Self.quantities {
            let key = mapping.identifier.rawValue
            let anchor = anchors[key].flatMap(Self.unarchive)
            let predicate = anchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil
            let query = HKAnchoredObjectQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(mapping.identifier), predicate: predicate)],
                anchor: anchor)
            let result = try await query.result(for: store)
            for sample in result.addedSamples {
                batch.observations.append(RawObservation(
                    kind: mapping.kind, value: sample.quantity.doubleValue(for: mapping.unit), unit: mapping.sampleUnit,
                    start: sample.startDate, end: sample.endDate, timeZoneIdentifier: timeZone,
                    source: .appleHealth, deviceID: deviceID, originalSampleID: sample.uuid.uuidString,
                    method: .healthStore, rawDataReference: "healthkit:\(sample.sourceRevision.source.bundleIdentifier)"))
            }
            batch.deletedOriginalIDs += result.deletedObjects.map { $0.uuid.uuidString }
            anchors[key] = Self.archive(result.newAnchor)
        }

        // Sleep: one duration sample per "asleep" interval; in-bed and awake intervals are not sleep.
        let sleepKey = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        let sleepAnchor = anchors[sleepKey].flatMap(Self.unarchive)
        let sleepQuery = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: sleepAnchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil)],
            anchor: sleepAnchor)
        let sleep = try await sleepQuery.result(for: store)
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        for sample in sleep.addedSamples where asleep.contains(sample.value) {
            batch.observations.append(RawObservation(
                kind: .sleepDuration, value: sample.endDate.timeIntervalSince(sample.startDate), unit: .seconds,
                start: sample.startDate, end: sample.endDate, timeZoneIdentifier: timeZone,
                source: .appleHealth, deviceID: deviceID, originalSampleID: sample.uuid.uuidString,
                method: .healthStore, rawDataReference: "healthkit:\(sample.sourceRevision.source.bundleIdentifier)"))
        }
        batch.deletedOriginalIDs += sleep.deletedObjects.map { $0.uuid.uuidString }
        anchors[sleepKey] = Self.archive(sleep.newAnchor)

        batch.nextCursor = Self.encodeAnchors(anchors)
        return batch
    }

    // MARK: Anchor persistence

    private static func archive(_ anchor: HKQueryAnchor) -> String? {
        (try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true))?.base64EncodedString()
    }

    private static func unarchive(_ text: String) -> HKQueryAnchor? {
        guard let data = Data(base64Encoded: text) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func decodeAnchors(_ cursor: String?) -> [String: String] {
        guard let data = cursor?.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private static func encodeAnchors(_ anchors: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(anchors) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
