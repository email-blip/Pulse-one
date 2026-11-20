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
        // HealthKit stores the absolute wrist temperature; only the Health app shows it as a deviation
        // from the personal baseline. A deviation is derived later from our own baseline, never imported.
        .init(identifier: .appleSleepingWristTemperature, kind: .skinTemperature, unit: .degreeCelsius(), sampleUnit: .celsius),
        .init(identifier: .respiratoryRate, kind: .respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), sampleUnit: .breathsPerMinute),
        .init(identifier: .basalEnergyBurned, kind: .basalEnergy, unit: .kilocalorie(), sampleUnit: .kilocalories),
        .init(identifier: .vo2Max, kind: .vo2Max,
              unit: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())),
              sampleUnit: .millilitersPerKilogramMinute),
        .init(identifier: .bodyMass, kind: .bodyMass, unit: .gramUnit(with: .kilo), sampleUnit: .kilograms),
        .init(identifier: .height, kind: .height, unit: .meter(), sampleUnit: .meters)
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

    /// `cursor` is a `HealthImportCursor` (type identifier → archived `HKQueryAnchor`, plus format). A type that fails
    /// (for example while the device is locked) keeps its old anchor and is reported; the others
    /// are imported anyway, so one bad type never blocks the whole sync.
    func sync(deviceID: String, cursor: String?) async throws -> SyncBatch {
        guard Self.available else { throw AdapterError.notAvailable }
        var anchors = HealthImportCursor.decode(cursor)
        var batch = SyncBatch()
        let since = Date(timeIntervalSinceNow: -initialWindow)
        let timeZone = TimeZone.current.identifier

        func observation(_ kind: SampleKind, _ value: Double, _ unit: SampleUnit, _ sample: HKSample) -> RawObservation {
            RawObservation(
                kind: kind, value: value, unit: unit,
                start: sample.startDate, end: sample.endDate, timeZoneIdentifier: timeZone,
                source: .appleHealth, deviceID: deviceID, originalSampleID: sample.uuid.uuidString,
                method: .healthStore, rawDataReference: "healthkit:\(sample.sourceRevision.source.bundleIdentifier)",
                originDetail: Self.originDetail(of: sample))
        }
        func record(_ kind: SampleKind, added: Int, deleted: Int, error: Error? = nil) {
            batch.reports.append(SyncTypeReport(kind: kind, added: added, deleted: deleted, at: .now,
                                                error: error.map { String(describing: $0).prefix(120).description }))
        }

        for mapping in Self.quantities {
            let key = mapping.identifier.rawValue
            let anchor = anchors[key].flatMap(Self.unarchive)
            let predicate = anchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil
            let query = HKAnchoredObjectQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(mapping.identifier), predicate: predicate)],
                anchor: anchor)
            do {
                let result = try await query.result(for: store)
                for sample in result.addedSamples {
                    batch.observations.append(observation(
                        mapping.kind, sample.quantity.doubleValue(for: mapping.unit), mapping.sampleUnit, sample))
                }
                batch.deletedOriginalIDs += result.deletedObjects.map { $0.uuid.uuidString }
                anchors[key] = Self.archive(result.newAnchor)
                record(mapping.kind, added: result.addedSamples.count, deleted: result.deletedObjects.count)
            } catch {
                record(mapping.kind, added: 0, deleted: 0, error: error)
            }
        }

        // Sleep: one duration sample per "asleep" interval; in-bed and awake intervals are not sleep.
        let sleepKey = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        let sleepAnchor = anchors[sleepKey].flatMap(Self.unarchive)
        let sleepQuery = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: sleepAnchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil)],
            anchor: sleepAnchor)
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        do {
            let sleep = try await sleepQuery.result(for: store)
            let added = sleep.addedSamples.filter { asleep.contains($0.value) }
            for sample in added {
                batch.observations.append(observation(
                    .sleepDuration, sample.endDate.timeIntervalSince(sample.startDate), .seconds, sample))
            }
            batch.deletedOriginalIDs += sleep.deletedObjects.map { $0.uuid.uuidString }
            anchors[sleepKey] = Self.archive(sleep.newAnchor)
            record(.sleepDuration, added: added.count, deleted: sleep.deletedObjects.count)
        } catch {
            record(.sleepDuration, added: 0, deleted: 0, error: error)
        }

        // Workouts: one training-duration sample per workout. Sport type and route follow with the
        // movement recording (HEALTH-DATA-SPEC §0); here only the duration counts.
        let workoutKey = "HKWorkoutTypeIdentifier"
        let workoutAnchor = anchors[workoutKey].flatMap(Self.unarchive)
        let workoutQuery = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(workoutAnchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil)],
            anchor: workoutAnchor)
        do {
            let workouts = try await workoutQuery.result(for: store)
            for workout in workouts.addedSamples {
                batch.observations.append(observation(.trainingDuration, workout.duration, .seconds, workout))
            }
            batch.deletedOriginalIDs += workouts.deletedObjects.map { $0.uuid.uuidString }
            anchors[workoutKey] = Self.archive(workouts.newAnchor)
            record(.trainingDuration, added: workouts.addedSamples.count, deleted: workouts.deletedObjects.count)
        } catch {
            record(.trainingDuration, added: 0, deleted: 0, error: error)
        }

        batch.nextCursor = anchors.encode()
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

    /// Which app and which single device wrote the sample (`HealthOrigin`): bundle, model and a hash of
    /// `HKDevice.localIdentifier`. The device name ("Johannes' iPhone") is never stored; a missing
    /// identifier stays "unbekannt" instead of being guessed from the model.
    static func originDetail(of sample: HKSample) -> String {
        HealthOrigin.detail(bundle: sample.sourceRevision.source.bundleIdentifier,
                            model: sample.device?.model ?? sample.sourceRevision.productType,
                            localIdentifier: sample.device?.localIdentifier)
    }
}
