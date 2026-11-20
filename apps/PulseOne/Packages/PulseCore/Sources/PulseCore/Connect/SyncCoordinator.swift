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

/// Where a sample came from: the source system and the device within it. Two rings of the same model
/// are two origins.
public struct SampleOrigin: Hashable, Sendable, Comparable {
    public let source: DataSourceKind
    public let deviceID: String

    public init(source: DataSourceKind, deviceID: String) {
        self.source = source
        self.deviceID = deviceID
    }

    public static func < (a: SampleOrigin, b: SampleOrigin) -> Bool {
        (a.source.rawValue, a.deviceID) < (b.source.rawValue, b.deviceID)
    }
}

extension HealthSample {
    public var origin: SampleOrigin { SampleOrigin(source: source, deviceID: deviceID) }
}

/// A period total and the one origin it was taken from, so the number stays traceable.
public struct ResolvedTotal: Equatable, Sendable {
    public let total: Double
    public let origin: SampleOrigin
    public let sampleCount: Int

    public var source: DataSourceKind { origin.source }
}

/// Chooses between overlapping sources without averaging them (directive Phase A, Directive 3.1 A).
/// Order: source priority, then device priority within a source, then device id (stable fallback).
public enum DataSourceResolver {
    /// Default order when several sources measured the same thing. Earlier wins.
    public static let defaultPriority: [DataSourceKind] = [.bluetoothStandard, .colmiRing, .ouraCloud, .appleHealth, .manual]

    /// Point values (pulse, SpO₂ …): within each time bucket, keep only samples of the best origin present.
    public static func resolvePoints(_ samples: [HealthSample], bucket: TimeInterval = 60,
                                     priority: [DataSourceKind] = defaultPriority,
                                     devicePriority: [String] = []) -> [HealthSample] {
        let usable = samples.filter { $0.quality == .plausible }
        let grouped = Dictionary(grouping: usable) { Int(($0.start.timeIntervalSince1970 / bucket).rounded(.down)) }
        return grouped.keys.sorted().flatMap { key -> [HealthSample] in
            let group = grouped[key] ?? []
            guard let best = bestOrigin(in: group, priority: priority, devicePriority: devicePriority) else { return [] }
            return group.filter { $0.origin == best }.sorted { $0.start < $1.start }
        }
    }

    /// Cumulative values (steps, energy …) for one period: the total of one origin only, never a sum across
    /// sources or devices.
    public static func resolveTotal(_ samples: [HealthSample], priority: [DataSourceKind] = defaultPriority,
                                    devicePriority: [String] = []) -> ResolvedTotal? {
        let usable = samples.filter { $0.quality == .plausible }
        guard let best = bestOrigin(in: usable, priority: priority, devicePriority: devicePriority) else { return nil }
        let chosen = usable.filter { $0.origin == best }
        return ResolvedTotal(total: chosen.reduce(0) { $0 + $1.value }, origin: best, sampleCount: chosen.count)
    }

    static func bestOrigin(in samples: [HealthSample], priority: [DataSourceKind],
                           devicePriority: [String]) -> SampleOrigin? {
        func rank(_ o: SampleOrigin) -> (Int, Int) {
            (priority.firstIndex(of: o.source) ?? Int.max, devicePriority.firstIndex(of: o.deviceID) ?? Int.max)
        }
        return Set(samples.map(\.origin)).min { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a < b
        }
    }
}
