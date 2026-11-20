import Foundation

/// What a sync run changes in the store. Applying the same batch twice yields an empty plan the second time.
public struct SyncPlan: Equatable, Sendable {
    public var inserts: [HealthSample] = []
    /// Existing samples whose source changed the value or time; keeps the stored `id`.
    public var updates: [HealthSample] = []
    /// Stored sample ids the source reported as deleted.
    public var deletions: [UUID] = []
    public var unchanged = 0
    public var rejected: [NormalizationError] = []

    public init() {}

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletions.isEmpty }
}

/// Idempotent merge of incoming source data into the store (directive §5: no double counting).
public enum SyncCoordinator {
    /// - Parameters:
    ///   - existing: stored samples of this device, keyed by `deduplicationKey`.
    ///   - batch: what the adapter delivered.
    public static func plan(batch: SyncBatch, existing: [String: HealthSample], profileID: UUID,
                            importedAt: Date) -> SyncPlan {
        var plan = SyncPlan()
        var seen = Set<String>()
        for raw in batch.observations {
            let sample: HealthSample
            do {
                sample = try MeasurementNormalizer.normalize(raw, profileID: profileID, importedAt: importedAt)
            } catch let error as NormalizationError {
                plan.rejected.append(error)
                continue
            } catch {
                continue
            }
            let key = sample.deduplicationKey
            guard seen.insert(key).inserted else { continue }   // duplicate inside one batch
            if let stored = existing[key] {
                if sameContent(stored, sample) {
                    plan.unchanged += 1
                } else {
                    plan.updates.append(replacing(stored, with: sample))
                }
            } else {
                plan.inserts.append(sample)
            }
        }
        let deletedKeys = Set(batch.deletedOriginalIDs)
        if !deletedKeys.isEmpty {
            plan.deletions = existing.values
                .filter { deletedKeys.contains($0.originalSampleID) && !seen.contains($0.deduplicationKey) }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
        }
        return plan
    }

    static func sameContent(_ a: HealthSample, _ b: HealthSample) -> Bool {
        a.value == b.value && a.unit == b.unit && a.start == b.start && a.end == b.end
            && a.quality == b.quality && a.profileID == b.profileID
    }

    static func replacing(_ stored: HealthSample, with new: HealthSample) -> HealthSample {
        HealthSample(id: stored.id, profileID: new.profileID, kind: new.kind, value: new.value, unit: new.unit,
                     start: new.start, end: new.end, timeZoneIdentifier: new.timeZoneIdentifier, source: new.source,
                     deviceID: new.deviceID, originalSampleID: new.originalSampleID, importedAt: new.importedAt,
                     quality: new.quality, method: new.method, rawDataReference: new.rawDataReference)
    }
}

/// Chooses between overlapping sources without averaging them (directive Phase A).
public enum DataSourceResolver {
    /// Default order when several sources measured the same thing. Earlier wins.
    public static let defaultPriority: [DataSourceKind] = [.bluetoothStandard, .colmiRing, .ouraCloud, .appleHealth, .manual]

    /// Point values (pulse, SpO₂ …): within each time bucket, keep only samples of the best source present.
    public static func resolvePoints(_ samples: [HealthSample], bucket: TimeInterval = 60,
                                     priority: [DataSourceKind] = defaultPriority) -> [HealthSample] {
        let usable = samples.filter { $0.quality == .plausible }
        let grouped = Dictionary(grouping: usable) { Int(($0.start.timeIntervalSince1970 / bucket).rounded(.down)) }
        return grouped.keys.sorted().flatMap { key -> [HealthSample] in
            let group = grouped[key] ?? []
            guard let best = bestSource(in: group, priority: priority) else { return [] }
            return group.filter { $0.source == best }.sorted { $0.start < $1.start }
        }
    }

    /// Cumulative values (steps, energy …) for one period: the total of one source only, never a sum across sources.
    public static func resolveTotal(_ samples: [HealthSample],
                                    priority: [DataSourceKind] = defaultPriority) -> (total: Double, source: DataSourceKind)? {
        let usable = samples.filter { $0.quality == .plausible }
        guard let best = bestSource(in: usable, priority: priority) else { return nil }
        let total = usable.filter { $0.source == best }.reduce(0) { $0 + $1.value }
        return (total, best)
    }

    static func bestSource(in samples: [HealthSample], priority: [DataSourceKind]) -> DataSourceKind? {
        let present = Set(samples.map(\.source))
        return priority.first { present.contains($0) } ?? present.sorted { $0.rawValue < $1.rawValue }.first
    }
}
