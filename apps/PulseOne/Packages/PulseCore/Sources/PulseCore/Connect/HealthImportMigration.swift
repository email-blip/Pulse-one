import Foundation

/// Lossless repair of the Apple Health rows that import format 1 typed wrongly (Codex review P1-003 R2-1).
///
/// Format 1 stored the absolute sleeping wrist temperature as `skinTemperatureDeviation`, so it was graded
/// implausible. Nothing is deleted to fix it: each such row is retyped in place to `skinTemperature`
/// (same id, profile, value, time and origin), gets the new dedup key and is graded again. Only a row
/// whose corrected key already exists is removed, because that row is a proven duplicate. Rows older than
/// the 30-day re-import window are kept and repaired the same way. Ring, manual and other Health rows
/// are never selected. A second run finds nothing to do.
public enum HealthImportMigration {
    public struct Plan: Equatable, Sendable {
        /// Corrected rows, same `id` as before.
        public var retyped: [HealthSample] = []
        /// Old rows whose corrected key is already stored (same HealthKit sample twice).
        public var duplicates: [UUID] = []

        public init() {}
        public var isEmpty: Bool { retyped.isEmpty && duplicates.isEmpty }
    }

    /// Rows that format 1 typed wrongly.
    public static func affected(_ sample: HealthSample, healthDeviceID: String) -> Bool {
        sample.source == .appleHealth && sample.deviceID == healthDeviceID && sample.kind == .skinTemperatureDeviation
    }

    /// - Parameters:
    ///   - stored: candidate rows (others are ignored, so passing all rows of the device is fine).
    ///   - existingKeys: dedup keys already stored, at least those of `skinTemperature` rows of this device.
    public static func plan(stored: [HealthSample], existingKeys: Set<String>, healthDeviceID: String) -> Plan {
        var plan = Plan()
        var taken = existingKeys
        let candidates = stored.filter { affected($0, healthDeviceID: healthDeviceID) }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        for old in candidates {
            let fixed = retyped(old)
            if taken.contains(fixed.deduplicationKey) {
                plan.duplicates.append(old.id)
            } else {
                taken.insert(fixed.deduplicationKey)
                plan.retyped.append(fixed)
            }
        }
        return plan
    }

    /// The same row as absolute skin temperature, graded again with its original import time.
    static func retyped(_ old: HealthSample) -> HealthSample {
        let raw = RawObservation(kind: .skinTemperature, value: old.value, unit: .celsius, start: old.start,
                                 end: old.end, timeZoneIdentifier: old.timeZoneIdentifier, source: old.source,
                                 deviceID: old.deviceID, originalSampleID: old.originalSampleID, method: old.method,
                                 identity: old.identity, rawDataReference: old.rawDataReference,
                                 originDetail: old.originDetail)
        // Apple Health is not a hardware-confirmed source, as in the normal import.
        let (quality, reason) = MeasurementNormalizer.grade(raw, value: old.value, importedAt: old.importedAt,
                                                            sourceConfirmed: false)
        return HealthSample(id: old.id, profileID: old.profileID, kind: .skinTemperature, value: old.value,
                            unit: .celsius, start: old.start, end: old.end, timeZoneIdentifier: old.timeZoneIdentifier,
                            source: old.source, deviceID: old.deviceID, originalSampleID: old.originalSampleID,
                            importedAt: old.importedAt, quality: quality, qualityReason: reason, method: old.method,
                            identity: old.identity, rawDataReference: old.rawDataReference,
                            originDetail: old.originDetail, receivedAt: old.receivedAt)
    }
}

/// One Apple Health sync as a single unit of work (R2-1): migrate, ingest, save. If any step throws,
/// everything staged is rolled back and the stored cursor stays as it was, so the next start repeats
/// the same run. The cursor advances only after the save succeeded.
public enum HealthSyncTransaction {
    public struct Outcome: Equatable, Sendable {
        public let cursor: String?
        public let committed: Bool
        public let migratedRows: Int
        public let removedDuplicates: Int
        public let error: String?
    }

    /// - Parameters:
    ///   - storedCursor: cursor before this run.
    ///   - batchCursor: cursor the import produced; stored only on success.
    ///   - migrate: stages the migration (only when `migrating`), returns the applied plan.
    ///   - ingest: stages the batch.
    ///   - save: commits everything staged at once.
    ///   - rollback: discards everything staged.
    public static func run(storedCursor: String?, batchCursor: String?, migrating: Bool,
                           migrate: () throws -> HealthImportMigration.Plan,
                           ingest: () throws -> Void,
                           save: () throws -> Void,
                           rollback: () -> Void) -> Outcome {
        do {
            let plan = migrating ? try migrate() : HealthImportMigration.Plan()
            try ingest()
            try save()
            return Outcome(cursor: batchCursor, committed: true, migratedRows: plan.retyped.count,
                           removedDuplicates: plan.duplicates.count, error: nil)
        } catch {
            rollback()
            return Outcome(cursor: storedCursor, committed: false, migratedRows: 0, removedDuplicates: 0,
                           error: String(describing: error))
        }
    }
}
