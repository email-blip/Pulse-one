import Foundation
import PulseCore
import SwiftData

/// Normalised sample on disk (General Directive 3.0 §5). One row per source sample: the unique
/// `dedupKey` makes repeated syncs idempotent. Stays on the device.
@Model
final class StoredSample {
    @Attribute(.unique) var dedupKey: String
    var sampleID: UUID
    /// nil = the device's owner at that time is unresolved (Review 3.2 §2).
    var profileID: UUID?
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
    var qualityReason: String?
    var methodRaw: String
    /// "source_id" or "derived" (Review 3.2 §3). Default keeps lightweight migration of older stores.
    var identityRaw: String = "source_id"
    var rawDataReference: String?
    /// HealthKit app, model and device hash (`HealthOrigin`); optional so older stores migrate lightweight.
    var originDetail: String?
    /// When the app first received the value (live readings); nil for older rows and history.
    var receivedAt: Date?

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
        qualityReason = s.qualityReason
        methodRaw = s.method.rawValue
        identityRaw = s.identity.rawValue
        rawDataReference = s.rawDataReference
        originDetail = s.originDetail
        receivedAt = s.receivedAt
    }

    func update(from s: HealthSample) {
        value = s.value
        unitRaw = s.unit.rawValue
        start = s.start
        end = s.end
        timeZoneIdentifier = s.timeZoneIdentifier
        importedAt = s.importedAt
        qualityRaw = s.quality.rawValue
        qualityReason = s.qualityReason
        methodRaw = s.method.rawValue
        rawDataReference = s.rawDataReference
        originDetail = s.originDetail
        // The first receipt stays; a later sync never moves it.
        if receivedAt == nil { receivedAt = s.receivedAt }
        // The profile is not touched here: only `reattribute` changes it, after a logged correction.
    }

    /// Import-format repair only (`HealthImportMigration`): new kind and key, same id, profile and value.
    func retype(to s: HealthSample) {
        dedupKey = s.deduplicationKey
        kindRaw = s.kind.rawValue
        unitRaw = s.unit.rawValue
        qualityRaw = s.quality.rawValue
        qualityReason = s.qualityReason
    }

    /// Ring history id repair only (`RingHistoryIDMigration`): new original id and key, everything else stays.
    func rekey(to s: HealthSample) {
        dedupKey = s.deduplicationKey
        originalSampleID = s.originalSampleID
    }

    /// Back to the core type; nil if the row holds a value this app version does not know.
    var sample: HealthSample? {
        guard let kind = SampleKind(rawValue: kindRaw), let unit = SampleUnit(rawValue: unitRaw),
              let source = DataSourceKind(rawValue: sourceRaw), let quality = SampleQuality(rawValue: qualityRaw),
              let method = MeasurementMethod(rawValue: methodRaw) else { return nil }
        let identity = SampleIdentity(rawValue: identityRaw) ?? .sourceID
        return HealthSample(id: sampleID, profileID: profileID, kind: kind, value: value, unit: unit, start: start,
                            end: end, timeZoneIdentifier: timeZoneIdentifier, source: source, deviceID: deviceID,
                            originalSampleID: originalSampleID, importedAt: importedAt, quality: quality,
                            qualityReason: qualityReason, method: method, identity: identity,
                            rawDataReference: rawDataReference, originDetail: originDetail, receivedAt: receivedAt)
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

    /// Stages a plan in the context without saving.
    func stage(_ plan: SyncPlan) throws {
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
    }

    func apply(_ plan: SyncPlan) throws {
        try stage(plan)
        try context.save()
    }

    /// Normalises, de-duplicates and stores one batch. Returns the applied plan for diagnostics.
    @discardableResult
    func ingest(_ batch: SyncBatch, deviceID: String, profiles: ProfileTimeline, now: Date = .now) throws -> SyncPlan {
        let plan = SyncCoordinator.plan(batch: batch, existing: existing(for: batch, deviceID: deviceID),
                                        profiles: profiles, importedAt: now)
        try apply(plan)
        return plan
    }

    /// Like `ingest`, but only stages; `overlay` holds rows already changed in this context (by dedup key)
    /// so the plan sees them regardless of how the fetch treats pending changes.
    func stageIngest(_ batch: SyncBatch, deviceID: String, profiles: ProfileTimeline,
                     overlay: [String: HealthSample] = [:], removed: Set<UUID> = [], now: Date = .now) throws -> SyncPlan {
        var existing = existing(for: batch, deviceID: deviceID).filter { !removed.contains($0.value.id) }
        let retypedIDs = Set(overlay.values.map(\.id))
        existing = existing.filter { !retypedIDs.contains($0.value.id) }
        existing.merge(overlay) { _, new in new }
        let plan = SyncCoordinator.plan(batch: batch, existing: existing, profiles: profiles, importedAt: now)
        try stage(plan)
        return plan
    }

    /// Health import format 1 → 2 (`HealthImportMigration`): retypes the wrongly typed rows in place and
    /// removes only proven duplicates. Stages without saving; the caller saves once or rolls back.
    func stageHealthMigration(deviceID: String) throws -> HealthImportMigration.Plan {
        let device = deviceID
        let oldKind = SampleKind.skinTemperatureDeviation.rawValue
        let newKind = SampleKind.skinTemperature.rawValue
        let oldRows = try context.fetch(FetchDescriptor<StoredSample>(predicate: #Predicate {
            $0.deviceID == device && $0.kindRaw == oldKind }))
        guard !oldRows.isEmpty else { return HealthImportMigration.Plan() }
        let present = try context.fetch(FetchDescriptor<StoredSample>(predicate: #Predicate {
            $0.deviceID == device && $0.kindRaw == newKind }))
        let plan = HealthImportMigration.plan(stored: oldRows.compactMap(\.sample),
                                              existingKeys: Set(present.map(\.dedupKey)), healthDeviceID: deviceID)
        let fixed = Dictionary(uniqueKeysWithValues: plan.retyped.map { ($0.id, $0) })
        let duplicates = Set(plan.duplicates)
        for row in oldRows {
            if let s = fixed[row.sampleID] { row.retype(to: s) }
            else if duplicates.contains(row.sampleID) { context.delete(row) }
        }
        return plan
    }

    /// Ring history ids with the value in them (test team R1) → slot ids. Removes only proven duplicates,
    /// then saves. Runs before every ring history ingest; after the first run it finds nothing.
    @discardableResult
    func migrateRingHistoryIDs(deviceID: String, fallbackZone: TimeZone = .current) throws -> RingHistoryIDMigration.Plan {
        let device = deviceID
        let ring = DataSourceKind.colmiRing.rawValue
        let history = MeasurementMethod.deviceHistory.rawValue
        let rows = try context.fetch(FetchDescriptor<StoredSample>(predicate: #Predicate {
            $0.deviceID == device && $0.sourceRaw == ring && $0.methodRaw == history }))
        let samples = rows.compactMap(\.sample)
        guard samples.contains(where: RingHistoryIDMigration.isLegacy) else { return RingHistoryIDMigration.Plan() }
        let keys = Set(samples.filter { !RingHistoryIDMigration.isLegacy($0) }.map(\.deduplicationKey))
        let plan = RingHistoryIDMigration.plan(stored: samples, existingKeys: keys, fallbackZone: fallbackZone)
        let fixed = Dictionary(uniqueKeysWithValues: plan.rekeyed.map { ($0.id, $0) })
        let duplicates = Set(plan.duplicates)
        // Delete first, so a kept row never meets a removed row's key.
        for row in rows where duplicates.contains(row.sampleID) { context.delete(row) }
        for row in rows { if let s = fixed[row.sampleID] { row.rekey(to: s) } }
        try context.save()
        return plan
    }

    /// One Apple Health sync as a single transaction (review R2-1): optional format migration, ingest,
    /// one save; on any error `context.rollback()` and the stored cursor stays. `save` is injectable so
    /// the integration test can make it fail; the app uses the context's own save.
    func syncHealth(_ batch: SyncBatch, deviceID: String, storedCursor: String?, profiles: ProfileTimeline,
                    now: Date = .now, save: (() throws -> Void)? = nil) -> (HealthSyncTransaction.Outcome, SyncPlan) {
        let migrating = storedCursor != nil && HealthImportCursor.decode(storedCursor).needsMigration
        var migration = HealthImportMigration.Plan()
        var plan = SyncPlan()
        let outcome = HealthSyncTransaction.run(
            storedCursor: storedCursor, batchCursor: batch.nextCursor, migrating: migrating,
            migrate: {
                migration = try stageHealthMigration(deviceID: deviceID)
                return migration
            },
            ingest: {
                plan = try stageIngest(
                    batch, deviceID: deviceID, profiles: profiles,
                    overlay: Dictionary(migration.retyped.map { ($0.deduplicationKey, $0) }) { first, _ in first },
                    removed: Set(migration.duplicates), now: now)
            },
            save: { if let save { try save() } else { try context.save() } },
            rollback: { context.rollback() })
        return (outcome, outcome.committed ? plan : SyncPlan())
    }

    /// After a logged assignment correction: moves the device's samples to the profile valid at their time.
    @discardableResult
    func reattribute(deviceID: String, profiles: ProfileTimeline) throws -> Int {
        let device = deviceID
        let rows = try context.fetch(FetchDescriptor<StoredSample>(predicate: #Predicate { $0.deviceID == device }))
        var changed = 0
        for row in rows {
            let target = profiles.profile(at: row.start)
            if row.profileID != target { row.profileID = target; changed += 1 }
        }
        try context.save()
        return changed
    }
}
