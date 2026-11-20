import Foundation
import PulseCore
import SwiftData

/// Normalised sample on disk (General Directive 3.0 §5). One row per source sample: the unique
/// `dedupKey` makes repeated syncs idempotent. Stays on the device.
@Model
final class StoredSample {
    @Attribute(.unique) var dedupKey: String
    var sampleID: UUID
    var profileID: UUID
    var kindRaw: String
    var value: Double
    var unitRaw: String
    var start: Date
    var end: Date
    var timeZoneIdentifier: String?
    var sourceRaw: String
    var deviceID: String
    var originalSampleID: String
    var importedAt: Date
    var qualityRaw: String
    var methodRaw: String
    var rawDataReference: String?

    init(_ s: HealthSample) {
        dedupKey = s.deduplicationKey
        sampleID = s.id
        profileID = s.profileID
        kindRaw = s.kind.rawValue
        value = s.value
        unitRaw = s.unit.rawValue
        start = s.start
        end = s.end
        timeZoneIdentifier = s.timeZoneIdentifier
        sourceRaw = s.source.rawValue
        deviceID = s.deviceID
        originalSampleID = s.originalSampleID
        importedAt = s.importedAt
        qualityRaw = s.quality.rawValue
        methodRaw = s.method.rawValue
        rawDataReference = s.rawDataReference
    }

    func update(from s: HealthSample) {
        value = s.value
        unitRaw = s.unit.rawValue
        start = s.start
        end = s.end
        timeZoneIdentifier = s.timeZoneIdentifier
        importedAt = s.importedAt
        qualityRaw = s.quality.rawValue
        methodRaw = s.method.rawValue
        rawDataReference = s.rawDataReference
        profileID = s.profileID
    }

    /// Back to the core type; nil if the row holds a value this app version does not know.
    var sample: HealthSample? {
        guard let kind = SampleKind(rawValue: kindRaw), let unit = SampleUnit(rawValue: unitRaw),
              let source = DataSourceKind(rawValue: sourceRaw), let quality = SampleQuality(rawValue: qualityRaw),
              let method = MeasurementMethod(rawValue: methodRaw) else { return nil }
        return HealthSample(id: sampleID, profileID: profileID, kind: kind, value: value, unit: unit, start: start,
                            end: end, timeZoneIdentifier: timeZoneIdentifier, source: source, deviceID: deviceID,
                            originalSampleID: originalSampleID, importedAt: importedAt, quality: quality,
                            method: method, rawDataReference: rawDataReference)
    }
}

/// Applies sync plans to SwiftData.
@MainActor
struct SampleStore {
    let context: ModelContext

    /// Stored samples that a batch could touch: same keys, or deleted by original id on this device.
    func existing(for batch: SyncBatch, deviceID: String) -> [String: HealthSample] {
        let keys = Set(batch.observations.map(\.deduplicationKey))
        let deleted = Set(batch.deletedOriginalIDs)
        var result: [String: HealthSample] = [:]
        if !keys.isEmpty {
            let keyList = Array(keys)
            let descriptor = FetchDescriptor<StoredSample>(predicate: #Predicate { keyList.contains($0.dedupKey) })
            for row in (try? context.fetch(descriptor)) ?? [] {
                if let s = row.sample { result[row.dedupKey] = s }
            }
        }
        if !deleted.isEmpty {
            let ids = Array(deleted)
            let device = deviceID
            let descriptor = FetchDescriptor<StoredSample>(predicate: #Predicate {
                $0.deviceID == device && ids.contains($0.originalSampleID)
            })
            for row in (try? context.fetch(descriptor)) ?? [] {
                if let s = row.sample { result[row.dedupKey] = s }
            }
        }
        return result
    }

    func apply(_ plan: SyncPlan) throws {
        for s in plan.inserts { context.insert(StoredSample(s)) }
        if !plan.updates.isEmpty {
            let byID = Dictionary(uniqueKeysWithValues: plan.updates.map { ($0.id, $0) })
            let ids = Array(byID.keys)
            let rows = try context.fetch(FetchDescriptor<StoredSample>(predicate: #Predicate { ids.contains($0.sampleID) }))
            for row in rows { if let s = byID[row.sampleID] { row.update(from: s) } }
        }
        if !plan.deletions.isEmpty {
            let ids = plan.deletions
            let rows = try context.fetch(FetchDescriptor<StoredSample>(predicate: #Predicate { ids.contains($0.sampleID) }))
            for row in rows { context.delete(row) }
        }
        try context.save()
    }

    /// Normalises, de-duplicates and stores one batch. Returns the applied plan for diagnostics.
    @discardableResult
    func ingest(_ batch: SyncBatch, deviceID: String, profileID: UUID, now: Date = .now) throws -> SyncPlan {
        let plan = SyncCoordinator.plan(batch: batch, existing: existing(for: batch, deviceID: deviceID),
                                        profileID: profileID, importedAt: now)
        try apply(plan)
        return plan
    }
}
